from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


PROJECT_ROOT = Path(r"F:\fly_play_recovered")
GENERATED_ROOT = Path(
    r"C:\Users\25131.GUOJUN.000\.codex\generated_images"
    r"\01a042f6-5aef-7ee2-b59a-80c14ef74a8e"
)
OUTPUT_ANIMATION = GENERATED_ROOT / "refresh_story_single_character_288poses_preview.png"
OUTPUT_CONTACT = GENERATED_ROOT / "refresh_story_single_character_288poses_contact.png"
ASSET_ANIMATION = PROJECT_ROOT / "assets" / "refresh" / "shoujo_bird_loading.webp"
ASSET_STATIC = PROJECT_ROOT / "assets" / "refresh" / "shoujo_bird_loading_static.png"
HUMAN_TO_BALL_ATLAS = (
    PROJECT_ROOT
    / "assets"
    / "refresh"
    / "shoujo_bird_human_to_ball_01_16.png"
)
HUMAN_TO_BALL_INBETWEEN_ATLAS = (
    PROJECT_ROOT
    / "assets"
    / "refresh"
    / "shoujo_bird_human_to_ball_inbetweens_01_16.png"
)
SOURCE_VIDEO = Path(r"F:\mp\bili_video_d_1787919698203.mp4")
SOURCE_VIDEO_2 = Path(r"F:\mp\bili_video_d_1787920057392.mp4")
SOURCE_VIDEO_FIRST_FRAME = 360
SOURCE_VIDEO_2_FIRST_FRAME = 247
SOURCE_VIDEO_FRAME_COUNT = 300
SOURCE_CROP = (510, 0, 1410, 900)

BASE_ATLASES = [
    PROJECT_ROOT / "assets" / "refresh" / f"shoujo_bird_frames_{start:02d}_{start + 7:02d}.png"
    for start in range(1, 73, 8)
]

FRAME_SIZE = 512
GRID_COLUMNS = 4
GRID_ROWS = 2


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("检测到空白姿势帧")
    return bbox


def alpha_area(image: Image.Image) -> int:
    alpha = np.asarray(image.getchannel("A"))
    return int(np.count_nonzero(alpha > 24))


def load_base_frames() -> list[Image.Image]:
    frames: list[Image.Image] = []
    for atlas_path in BASE_ATLASES:
        atlas = Image.open(atlas_path).convert("RGBA")
        if atlas.size != (FRAME_SIZE * GRID_COLUMNS, FRAME_SIZE * GRID_ROWS):
            raise ValueError(f"基础图集尺寸异常：{atlas_path} {atlas.size}")
        for row in range(GRID_ROWS):
            for column in range(GRID_COLUMNS):
                left = column * FRAME_SIZE
                top = row * FRAME_SIZE
                frames.append(atlas.crop((left, top, left + FRAME_SIZE, top + FRAME_SIZE)))
    if len(frames) != 72:
        raise ValueError(f"基础姿势数量应为 72，实际为 {len(frames)}")
    return frames


def external_foreground_mask(rgb: np.ndarray) -> np.ndarray:
    minimum = rgb.min(axis=2)
    maximum = rgb.max(axis=2)
    neutral_light = (minimum > 226) & ((maximum - minimum) < 32)

    traversable = neutral_light.astype(np.uint8)
    padded = cv2.copyMakeBorder(traversable, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=1)
    flood = np.zeros((padded.shape[0] + 2, padded.shape[1] + 2), dtype=np.uint8)
    cv2.floodFill(padded, flood, (0, 0), 2)
    outside = padded[1:-1, 1:-1] == 2

    foreground = (~outside).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(foreground, 8)
    cleaned = np.zeros_like(foreground)
    for label in range(1, count):
        if stats[label, cv2.CC_STAT_AREA] >= 20:
            cleaned[labels == label] = 1
    return cleaned


def extract_grid_subjects(
    path: Path,
    columns: int,
    rows: int,
    minimum_component_area: int = 20,
) -> list[Image.Image]:
    source = Image.open(path).convert("RGB")
    rgb = np.asarray(source)
    mask = external_foreground_mask(rgb)
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

    rgba = np.dstack((rgb, np.zeros((height, width), dtype=np.uint8)))
    subjects: list[Image.Image] = []
    for index, subject_mask in enumerate(grouped_masks):
        rgba[:, :, 3] = subject_mask
        subject = Image.fromarray(rgba.copy(), "RGBA")
        bbox = alpha_bbox(subject)
        cropped = subject.crop(bbox)
        if cropped.width < 24 or cropped.height < 24:
            raise ValueError(f"姿势 {index + 1} 提取异常：{path}")
        subjects.append(cropped)
    return subjects


def bbox_center(frame: Image.Image) -> tuple[float, float]:
    left, top, right, bottom = alpha_bbox(frame)
    return ((left + right) / 2, (top + bottom) / 2)


def smootherstep(value: float) -> float:
    return value**3 * (value * (value * 6 - 15) + 10)


def render_transition_pose(subject: Image.Image, progress: float) -> Image.Image:
    target_area = 28600 + (19700 - 28600) * smootherstep(progress)
    target_center = (256.0, 300.0 + (243.5 - 300.0) * smootherstep(progress))
    cropped = subject.crop(alpha_bbox(subject))
    scale = float(np.sqrt(target_area / max(alpha_area(cropped), 1)))
    scale = min(scale, 448 / max(cropped.size))
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        (
            round(target_center[0] - resized.width / 2),
            round(target_center[1] - resized.height / 2),
        ),
    )
    return canvas


def original_video_subject(
    frame_bgr: np.ndarray,
) -> Image.Image:
    left, top, right, bottom = SOURCE_CROP
    crop = frame_bgr[top:bottom, left:right]
    blue, green, red = cv2.split(crop)
    blue_delta = blue.astype(np.int16) - red.astype(np.int16)
    green_delta = green.astype(np.int16) - red.astype(np.int16)

    # 只保留原画中的蓝青色角色/翅膀，以及成鸟后偏暖的身体；
    # 白色背景与上方白色人形不会进入种子蒙版。
    blue_seed = (blue_delta > 7) & (green_delta > 1) & (blue > 120)
    warm_body_seed = (
        (red.astype(np.int16) - blue.astype(np.int16) > 10)
        & (green.astype(np.int16) - blue.astype(np.int16) > 5)
        & (red > 150)
    )
    seed = (blue_seed | warm_body_seed).astype(np.uint8)

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

    # 将紧邻色块的深色线稿一并收进蒙版，不扩张到远处背景。
    near_subject = cv2.dilate(selected, np.ones((3, 3), np.uint8), iterations=2)
    not_white = np.min(crop, axis=2) < 244
    alpha = np.where((selected > 0) | ((near_subject > 0) & not_white), 255, 0)

    alpha = cv2.GaussianBlur(alpha.astype(np.uint8), (3, 3), 0)

    rgba = cv2.cvtColor(crop, cv2.COLOR_BGR2RGBA)
    rgba[:, :, 3] = alpha
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


def load_original_video_frames() -> list[Image.Image]:
    first_video = load_video_range(
        SOURCE_VIDEO,
        SOURCE_VIDEO_FIRST_FRAME,
    )
    second_video = load_video_range(
        SOURCE_VIDEO_2,
        SOURCE_VIDEO_2_FIRST_FRAME,
        last_frame_exclusive=360,
    )
    frames = [*first_video, *second_video]
    if len(frames) != SOURCE_VIDEO_FRAME_COUNT:
        raise ValueError(
            f"两段原视频连续帧应为 {SOURCE_VIDEO_FRAME_COUNT}，实际为 {len(frames)}"
        )
    return frames


def build_frames() -> list[Image.Image]:
    base_frames = load_base_frames()
    human_to_ball = extract_grid_subjects(
        HUMAN_TO_BALL_ATLAS,
        columns=4,
        rows=4,
        minimum_component_area=80,
    )
    human_inbetweens = extract_grid_subjects(
        HUMAN_TO_BALL_INBETWEEN_ATLAS,
        columns=4,
        rows=4,
        minimum_component_area=80,
    )

    # 前段只使用真实绘制姿势；前 12 个中割姿势与主姿势交错，
    # 后四格按主姿势单向压成圆球，不再经过光流或液体溶解效果。
    human_sources = [*base_frames[:10]]
    for index, pose in enumerate(human_to_ball):
        human_sources.append(pose)
        if index < 12:
            human_sources.append(human_inbetweens[index])

    human_frames = [
        render_transition_pose(
            frame,
            index / max(len(human_sources) - 1, 1),
        )
        for index, frame in enumerate(human_sources)
    ]
    frames = [*human_frames, *load_original_video_frames()]

    if not 320 <= len(frames) <= 360:
        raise ValueError(f"输出姿势数量应约为 340，实际为 {len(frames)}")
    return frames


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
    human_frame_count = len(frames) - SOURCE_VIDEO_FRAME_COUNT
    # 手绘人物段按 12.5 张有效画/秒展示；原视频连续帧按 25 FPS 展示，
    # 整体比 60 FPS 原片更慢，但不制造任何补间帧。
    durations = [80] * human_frame_count + [40] * SOURCE_VIDEO_FRAME_COUNT
    durations[0] = 160
    durations[-1] = 320
    return durations


def save_animation(frames: list[Image.Image]) -> None:
    durations = frame_durations(frames)
    frames[0].save(
        OUTPUT_ANIMATION,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        disposal=2,
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
    frames[-40].save(ASSET_STATIC, optimize=True)


def main() -> None:
    frames = build_frames()
    save_contact_sheet(frames)
    save_animation(frames)
    print(f"frames={len(frames)}")
    print(f"duration_ms={sum(frame_durations(frames))}")
    print(OUTPUT_ANIMATION)
    print(OUTPUT_CONTACT)
    print(ASSET_ANIMATION)
    print(ASSET_STATIC)


if __name__ == "__main__":
    main()
