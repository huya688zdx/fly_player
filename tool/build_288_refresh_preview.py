from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path

ASSET_ROOT = Path(__file__).resolve().parents[1] / "assets" / "refresh"
GENERATED_ROOT = Path(os.environ.get("FLY_REFRESH_OUTPUT_DIR", "build/refresh-preview"))
OUTPUT_ANIMATION = GENERATED_ROOT / "refresh_reworked_preview.png"
OUTPUT_CONTACT = GENERATED_ROOT / "refresh_reworked_contact.png"
OUTPUT_VIDEO = GENERATED_ROOT / "refresh_reworked_preview.mp4"
ASSET_ANIMATION = GENERATED_ROOT / "shoujo_bird_loading_reworked.webp"
ASSET_STATIC = GENERATED_ROOT / "shoujo_bird_loading_reworked_static.png"
SOURCE_VIDEO = Path(os.environ["FLY_REFRESH_SOURCE_VIDEO"]) if "FLY_REFRESH_SOURCE_VIDEO" in os.environ else None
SOURCE_VIDEO_2 = Path(os.environ["FLY_REFRESH_SOURCE_VIDEO_2"]) if "FLY_REFRESH_SOURCE_VIDEO_2" in os.environ else None
SOURCE_VIDEO_FIRST_FRAME = 472
SOURCE_VIDEO_2_FIRST_FRAME = 247
SOURCE_CROP = (510, 0, 1410, 900)

FRAME_SIZE = 512


def input_paths() -> list[Path]:
    paths = [ASSET_ROOT / name for name in (
        "shoujo_bird_human_performance_00_25.png",
        "shoujo_bird_closure_08_reworked.png",
        "shoujo_bird_wing_unfold_00_04.png",
    )]
    for label, path in (("--source-video", SOURCE_VIDEO), ("--source-video-2", SOURCE_VIDEO_2)):
        if path is None:
            raise ValueError(f"Missing input: supply {label} (or FLY_REFRESH_SOURCE_VIDEO[_2])")
        paths.append(path)
    for path in paths:
        if not path.is_file():
            raise ValueError(f"Missing input: {path}")
    return paths


def load_render_dependencies() -> None:
    global cv2, np, Image, ImageDraw
    try:
        import cv2
        import numpy as np
        from PIL import Image, ImageDraw
    except ImportError as error:
        raise RuntimeError("Rendering requires opencv-python, numpy and Pillow; see tool/REFRESH_BUILD.md. "
                           f"Unavailable dependency: {error.name}") from error


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("检测到空白姿势帧")
    return bbox


def alpha_area(image: Image.Image) -> int:
    alpha = np.asarray(image.getchannel("A"))
    return int(np.count_nonzero(alpha > 24))


def extract_grid_subjects(
    path: Path,
    columns: int,
    rows: int,
    minimum_component_area: int = 20,
) -> list[Image.Image]:
    source = Image.open(path).convert("RGBA")
    source_rgba = np.asarray(source)
    mask = (source_rgba[:, :, 3] > 24).astype(np.uint8)
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)

    width, height = source.size
    centers = [
        ((column + 0.5) * width / columns, (row + 0.5) * height / rows)
        for row in range(rows)
        for column in range(columns)
    ]
    grouped_masks = [np.zeros((height, width), dtype=np.uint8) for _ in centers]

    for label in range(1, count):
        area = stats[label, cv2.CC_STAT_AREA]
        if area < minimum_component_area:
            continue
        component_center = centroids[label]
        target_index = min(
            range(len(centers)),
            key=lambda index: (
                (component_center[0] - centers[index][0]) ** 2
                + (component_center[1] - centers[index][1]) ** 2
            ),
        )
        grouped_masks[target_index][labels == label] = 255

    rgba = source_rgba.copy()
    subjects: list[Image.Image] = []
    for index, subject_mask in enumerate(grouped_masks):
        rgba[:, :, 3] = np.where(subject_mask > 0, source_rgba[:, :, 3], 0)
        subject = Image.fromarray(rgba.copy(), "RGBA")
        bbox = alpha_bbox(subject)
        cropped = subject.crop(bbox)
        if cropped.width < 24 or cropped.height < 24:
            raise ValueError(f"姿势 {index + 1} 提取异常：{path}")
        subjects.append(cropped)
    return subjects


def ball_geometry(subject: Image.Image) -> tuple[float, float, float]:
    red, green, blue, alpha = np.moveaxis(np.asarray(subject).astype(np.int16), 2, 0)
    # 只测量浅色球体，羽翼张合不能影响主体的比例和锚点。
    chroma = np.maximum.reduce([red, green, blue]) - np.minimum.reduce([red, green, blue])
    mask = (alpha > 220) & (red > 185) & (green > 200) & (chroma < 45)
    _, _, stats, centers = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    label = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (*centers[label], float(stats[label, cv2.CC_STAT_WIDTH]))


def place_subject(
    subject: Image.Image,
    scale: tuple[float, float],
    anchor: tuple[float, float],
    target: tuple[float, float],
) -> Image.Image:
    resized = subject.resize(
        (round(subject.width * scale[0]), round(subject.height * scale[1])),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE))
    canvas.alpha_composite(resized, (
        round(target[0] - anchor[0] * scale[0]),
        round(target[1] - anchor[1] * scale[1]),
    ))
    return canvas


def original_video_subject(
    frame_bgr: np.ndarray,
) -> Image.Image:
    left, top, right, bottom = SOURCE_CROP
    crop = frame_bgr[top:bottom, left:right]
    blue, green, red = cv2.split(crop)
    blue_delta = blue.astype(np.int16) - red.astype(np.int16)
    green_delta = green.astype(np.int16) - red.astype(np.int16)

    # 蓝青色与暖色只用于定位角色，不能直接充当完整轮廓：
    # 球体变色期间的近白身体、浅色翼尖和线稿不一定满足色差阈值。
    blue_seed = (blue_delta > 7) & (green_delta > 1) & (blue > 120)
    warm_body_seed = (
        (red.astype(np.int16) - blue.astype(np.int16) > 10)
        & (green.astype(np.int16) - blue.astype(np.int16) > 5)
        & (red > 150)
    )
    color_seed = blue_seed | warm_body_seed
    seed = (color_seed | (np.min(crop, axis=2) < 246)).astype(np.uint8)

    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        seed,
        8,
    )
    crop_center = np.array([crop.shape[1] / 2, crop.shape[0] / 2])
    selected = np.zeros(seed.shape, dtype=np.uint8)
    for label in range(1, component_count):
        x, y, width, height, area = stats[label]
        if area < 2:
            continue
        # 变形初段的人形轮廓会落到裁切底边，不能因此整帧丢弃；
        # 左右/顶边仍视为远处背景色块。
        if x == 0 or y == 0 or x + width == crop.shape[1]:
            continue
        if np.linalg.norm(centroids[label] - crop_center) > 500:
            continue
        if area / max(width * height, 1) < 0.025:
            continue
        # 沿原画的连通轮廓保留浅色身体，排除没有角色色块的背景压缩噪点。
        if not np.any(color_seed[labels == label]):
            continue
        selected[labels == label] = 255

    if np.count_nonzero(selected) < 20:
        # 第二段结尾的远景鸟只有几十个浅色像素，蓝色饱和度不足；
        # 此处改用与纯白背景的亮度差，并限制在画面上半部排除字幕噪点。
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB).astype(np.int16)
        distant_seed = (np.max(255 - rgb, axis=2) > 6).astype(np.uint8)
        count, distant_labels, distant_stats, distant_centroids = (
            cv2.connectedComponentsWithStats(distant_seed, 8)
        )
        for label in range(1, count):
            x, y, width, height, area = distant_stats[label]
            center_x, center_y = distant_centroids[label]
            if area < 2 or center_y >= crop.shape[0] / 2:
                continue
            if x == 0 or x + width == crop.shape[1]:
                continue
            if area / max(width * height, 1) < 0.015:
                continue
            selected[distant_labels == label] = 255

    if np.count_nonzero(selected) < 2:
        raise ValueError("原视频主体蒙版为空")

    # 连续细线仍保留，孤立的单点毛刺不作为主体轮廓。
    kernel = np.ones((3, 3), np.uint8)
    support = (cv2.GaussianBlur(selected, (5, 5), 1.0) > 72).astype(np.uint8)
    support = cv2.morphologyEx(support, cv2.MORPH_CLOSE, kernel)
    core = cv2.erode(support, kernel, iterations=2)
    if not np.any(core):
        core = support.copy()

    # 内部保持不透明；边缘用邻近主体颜色估计覆盖率，避免二值阈值咬掉细节。
    _, nearest = cv2.distanceTransformWithLabels(
        1 - core, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL,
    )
    palette = np.zeros((int(nearest.max()) + 1, 3), np.float32)
    reference = cv2.erode(crop, kernel).astype(np.float32)
    palette[nearest[core > 0]] = reference[core > 0]
    foreground = palette[nearest]
    background = np.median(crop.reshape(-1, 3), axis=0).astype(np.float32)
    delta = crop.astype(np.float32) - background
    color_delta = foreground - background
    alpha = np.clip(
        np.sum(delta * color_delta, axis=2)
        / np.maximum(np.sum(color_delta**2, axis=2), 1), 0, 1,
    )
    alpha[cv2.dilate(support, kernel) == 0] = 0
    alpha[core > 0] = 1
    alpha[alpha < 0.10] = 0

    # 从半透明边缘颜色中扣除原片白底，叠到深色页面时才不会出现白色毛边。
    rgb = np.clip(
        (crop.astype(np.float32) - (1 - alpha[:, :, None]) * background)
        / np.maximum(alpha[:, :, None], 0.01), 0, 255,
    ).astype(np.uint8)
    rgba = cv2.cvtColor(rgb, cv2.COLOR_BGR2RGBA)
    rgba[:, :, 3] = np.round(alpha * 255).astype(np.uint8)
    subject = Image.fromarray(rgba, "RGBA")
    return subject.resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.LANCZOS)



def load_video_range(
    path: Path,
    first_frame: int,
    last_frame_exclusive: int | None = None,
) -> list[Image.Image]:
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise ValueError(f"无法打开原视频：{path}")

    decoded_frames: list[Image.Image] = []
    source_index = 0
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            if last_frame_exclusive is not None and source_index >= last_frame_exclusive:
                break
            if source_index >= first_frame:
                decoded_frames.append(
                    original_video_subject(frame)
                )
            source_index += 1
    finally:
        capture.release()

    return decoded_frames


def apply_human_arm_revisions(
    original_atlas: Image.Image,
    revisions: dict[int, tuple[Image.Image, Image.Image]],
) -> Image.Image:
    """在原稿坐标接收 B/C 局部稿；端点及蒙版外像素直接沿用原稿。"""
    import numpy as np

    if original_atlas.mode != "RGBA" or original_atlas.size != (6 * FRAME_SIZE, 5 * FRAME_SIZE):
        raise ValueError("收臂基准必须是原尺寸 RGBA 图集")
    if set(revisions) - {8, 9}:
        raise ValueError("本轮只允许修改 B/C，不能替换 A/D 端点")
    result = original_atlas.copy()
    for index, (revised, mask) in revisions.items():
        if revised.mode != "RGBA" or revised.size != (FRAME_SIZE, FRAME_SIZE):
            raise ValueError("局部稿必须保持原始 512×512 RGBA 坐标，不能自动缩放或重新定位")
        if mask.mode != "L" or mask.size != revised.size:
            raise ValueError("局部蒙版必须是同尺寸灰度图")
        selected = np.asarray(mask)
        if not np.isin(selected, (0, 255)).all():
            raise ValueError("修稿范围必须用黑白蒙版明确标记，不通过混合两张画稿补动作")
        # 当前收臂连接区均在腰部以上，下摆和靴子不属于此次修订范围。
        if np.any(selected[320:]):
            raise ValueError("本次局部蒙版不能覆盖下摆或靴子区域（y≥320）")
        x, y = index % 6 * FRAME_SIZE, index // 6 * FRAME_SIZE
        frame = original_atlas.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE))
        # 直接替换选区内 RGBA，包括应被清掉的旧轮廓；范围外不重新采样。
        frame.paste(revised, (0, 0), mask)
        result.paste(frame, (x, y))
    return result


def build_frames() -> tuple[list[Image.Image], list[str]]:
    input_paths()
    load_render_dependencies()
    human_atlas = Image.open(ASSET_ROOT / "shoujo_bird_human_performance_00_25.png").convert("RGBA")
    closure = extract_grid_subjects(ASSET_ROOT / "shoujo_bird_closure_08_reworked.png", 4, 2, 80)
    growth_atlas = Image.open(ASSET_ROOT / "shoujo_bird_wing_unfold_00_04.png").convert("RGBA")
    first_video = load_video_range(SOURCE_VIDEO, SOURCE_VIDEO_FIRST_FRAME, 547)
    second_video = load_video_range(SOURCE_VIDEO_2, SOURCE_VIDEO_2_FIRST_FRAME, 360)
    frames: list[Image.Image] = []
    phases: list[str] = []

    def hold(frame: Image.Image, ticks: int, phase: str) -> None:
        # 重复条目只表达有意持帧；姿势均来自已绘制图或原视频。
        frames.extend([frame] * ticks)
        phases.extend([phase] * ticks)

    # 后撤阶段的母版误按两只靴子的共同范围居中，抬脚会带偏支撑脚。
    # 按逐稿核对的画面右侧靴筒锚点定位，只作整数平移，不重采样画稿。
    support_ankle_x = {
        "human_0": 266, "human_1": 265, "human_backstep": 265,
        "human_2": 275, "human_3": 279, "human_4": 276, "human_5": 275,
    }
    # 双脚并拢后保留现有重心与下蹲轨迹，不把弯曲中的脚踝强行锁住。
    # 注视、后撤、看手、抱拢、下蹲依次发生，闭眼只在抱拢后出现。
    human_holds = [
        ("human_0", 7), ("human_1", 4), ("human_backstep", 3),
        ("human_2", 3), ("human_3", 3), ("human_4", 3), ("human_5", 3),
        ("human_6", 3), ("human_hands_separate", 3), ("human_arms_cross", 3),
        ("human_7", 4), ("human_8", 4), ("human_9", 3), ("human_knees_bend", 3),
        ("human_10", 3), ("human_11", 3), ("human_12", 3),
        ("human_crouch_lower", 3), ("human_13", 3), ("human_crouch_tuck", 3),
        ("human_14", 4), ("closure_0", 3), ("closure_1", 3),
        ("closure_2", 3), ("closure_3", 3), ("closure_4", 4),
    ]
    for index, (phase, ticks) in enumerate(human_holds):
        left, top = index % 6 * FRAME_SIZE, index // 6 * FRAME_SIZE
        frame = human_atlas.crop((left, top, left + FRAME_SIZE, top + FRAME_SIZE))
        if phase in support_ankle_x:
            registered = Image.new("RGBA", frame.size)
            registered.paste(frame, (266 - support_ankle_x[phase], 0))
            frame = registered
        hold(frame, ticks, phase)

    # 人物完全包入后接回已有茧稿；入口高度接住新画稿，随后沿用收小位置。
    for index, height, bottom in ((5, 166, 440), (6, 130, 403), (7, 94, 376)):
        subject = closure[index]
        scale = height / subject.height
        frame = place_subject(subject, (scale, scale), (subject.width / 2, subject.height), (252, bottom))
        hold(frame, 6 if index == 5 else 4, f"closure_{index}")
    # 裸茧和四张展开姿势已在共同画布中定位，保留画出的折翼和身体反应。
    # 不再逐帧拟合身体宽高，也不按翼展重缩放。
    for index, ticks in enumerate([2, 3, 2, 2, 2]):
        frame = growth_atlas.crop((index * FRAME_SIZE, 0, (index + 1) * FRAME_SIZE, FRAME_SIZE))
        hold(frame, ticks, f"growth_{index}")

    # 连续原片只播放一次；60FPS源时间按30FPS取样，入口不额外持帧。
    for offset in range(0, len(first_video), 2):
        hold(first_video[offset], 1, f"video1_{SOURCE_VIDEO_FIRST_FRAME + offset}")
    for source_index in [*range(247, 277, 2), 276]:
        phase = "ring" if source_index < 262 else "point"
        hold(second_video[source_index - 247], 1, phase)

    # 展开到飞远完整沿用原片，以30FPS慢放原始60FPS帧序。
    # 保留原片的小身体、翼形和远去轨迹，不额外放大或重绘鸟的轮廓。
    for source_index in range(277, 360):
        hold(second_video[source_index - 247], 1, f"video2_{source_index}")
    return frames, phases


def save_contact_sheet(frames: list[Image.Image]) -> None:
    columns = 24
    rows = (len(frames) + columns - 1) // columns
    cell_size = 64
    contact = Image.new("RGB", (columns * cell_size, rows * cell_size), (22, 24, 30))
    draw = ImageDraw.Draw(contact)
    for index, frame in enumerate(frames):
        thumbnail = frame.copy()
        thumbnail.thumbnail((cell_size - 4, cell_size - 4), Image.Resampling.LANCZOS)
        x = (index % columns) * cell_size + (cell_size - thumbnail.width) // 2
        y = (index // columns) * cell_size + (cell_size - thumbnail.height) // 2
        contact.paste(thumbnail, (x, y), thumbnail)
        draw.text((index % columns * cell_size + 2, index // columns * cell_size + 1), str(index + 1), fill=(150, 155, 168))
    contact.save(OUTPUT_CONTACT)


def frame_durations(frames: list[Image.Image]) -> list[int]:
    # 累计量化到33/34毫秒，避免固定33毫秒产生总时长漂移。
    boundaries = [round(index * 1000 / 30) for index in range(len(frames) + 1)]
    return [end - start for start, end in zip(boundaries, boundaries[1:])]


def save_animation(frames: list[Image.Image]) -> None:
    durations = frame_durations(frames)
    frames[0].save(
        OUTPUT_ANIMATION,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        # 保留上一帧，再以 SOURCE 覆盖差分区域；回退到更早画面会丢失主体。
        disposal=0,
        blend=0,
        optimize=False,
    )
    frames[0].save(
        ASSET_ANIMATION,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        lossless=True,
        method=6,
    )
    frames[-45].save(ASSET_STATIC, optimize=True)


def save_mp4_preview(frames: list[Image.Image]) -> None:
    # 通用MP4预览采用浅灰底；透明WebP仍作为App素材输出。
    writer = cv2.VideoWriter(
        str(OUTPUT_VIDEO), cv2.VideoWriter_fourcc(*"mp4v"), 30,
        (FRAME_SIZE, FRAME_SIZE),
    )
    if not writer.isOpened():
        raise RuntimeError(f"无法创建MP4预览：{OUTPUT_VIDEO}")
    background = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (244, 246, 249, 255))
    try:
        for frame in frames:
            rgb = np.asarray(Image.alpha_composite(background, frame).convert("RGB"))
            writer.write(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
    finally:
        writer.release()


def main(argv: list[str] | None = None) -> None:
    global ASSET_ROOT, SOURCE_VIDEO, SOURCE_VIDEO_2, GENERATED_ROOT
    global OUTPUT_ANIMATION, OUTPUT_CONTACT, OUTPUT_VIDEO, ASSET_ANIMATION, ASSET_STATIC
    parser = argparse.ArgumentParser(description="Build the refresh preview from explicitly supplied original videos.")
    parser.add_argument("--asset-root", type=Path, default=ASSET_ROOT, help="Directory containing the three committed PNG atlases")
    parser.add_argument("--source-video", type=Path, required=True, help="Original video 1; frames 472..546")
    parser.add_argument("--source-video-2", type=Path, required=True, help="Original video 2; frames 247..359")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory for all six generated outputs")
    parser.add_argument("--check-inputs", action="store_true", help="Read and hash inputs only; does not decode media or create output")
    args = parser.parse_args(argv)
    ASSET_ROOT = args.asset_root.resolve()
    SOURCE_VIDEO, SOURCE_VIDEO_2 = args.source_video.resolve(), args.source_video_2.resolve()
    GENERATED_ROOT = args.output_dir.resolve()
    OUTPUT_ANIMATION = GENERATED_ROOT / "refresh_reworked_preview.png"
    OUTPUT_CONTACT = GENERATED_ROOT / "refresh_reworked_contact.png"
    OUTPUT_VIDEO = GENERATED_ROOT / "refresh_reworked_preview.mp4"
    ASSET_ANIMATION = GENERATED_ROOT / "shoujo_bird_loading_reworked.webp"
    ASSET_STATIC = GENERATED_ROOT / "shoujo_bird_loading_reworked_static.png"
    try:
        inputs = []
        for path in input_paths():
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            inputs.append({"path": str(path), "sha256": digest, "bytes": path.stat().st_size})
        if args.check_inputs:
            print(json.dumps({"inputs": inputs, "media_decode_verified": False}))
            return
        load_render_dependencies()
        GENERATED_ROOT.mkdir(parents=True, exist_ok=True)
    except (ValueError, OSError, RuntimeError) as error:
        parser.exit(2, f"{error}\n")
    frames, phases = build_frames()
    save_contact_sheet(frames)
    save_animation(frames)
    save_mp4_preview(frames)
    print(f"frames={len(frames)}")
    print(f"duration_ms={sum(frame_durations(frames))}")
    print(OUTPUT_ANIMATION)
    print(OUTPUT_CONTACT)
    print(ASSET_ANIMATION)
    print(ASSET_STATIC)
    print(OUTPUT_VIDEO)
    with (GENERATED_ROOT / "refresh_reworked_timeline.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(["时间轴序号_从1开始", "开始毫秒", "时长毫秒", "动作来源"])
        elapsed = 0
        for index, (phase, duration) in enumerate(zip(phases, frame_durations(frames))):
            writer.writerow([index + 1, elapsed, duration, phase])
            elapsed += duration


if __name__ == "__main__":
    main()
