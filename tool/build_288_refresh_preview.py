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
OFFICIAL_TRANSITION_ATLAS = (
    PROJECT_ROOT
    / "assets"
    / "refresh"
    / "shoujo_bird_official_transition_01_16.png"
)

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


def central_body_mask(frame: Image.Image) -> np.ndarray:
    alpha = np.asarray(frame.getchannel("A"))
    opaque = alpha > 24
    y_coordinates, x_coordinates = np.where(opaque)
    left = int(x_coordinates.min())
    right = int(x_coordinates.max())
    horizontal_center = (left + right) / 2
    half_band = max(8, min(28, round((right - left + 1) * 0.1)))
    x_grid = np.indices(alpha.shape)[1]
    return (
        opaque
        & (x_grid >= horizontal_center - half_band)
        & (x_grid <= horizontal_center + half_band)
    ).astype(np.uint8)


def source_body_anchor(
    frame: Image.Image,
    stage_index: int,
) -> tuple[float, float]:
    if stage_index in (7, 8):
        mask = central_body_mask(frame)
        y_coordinates, x_coordinates = np.where(mask)
        return (
            float(np.median(x_coordinates)),
            float(np.quantile(y_coordinates, 0.94)),
        )
    return bbox_center(frame)


def linear_anchor_segment(
    anchors: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    start = anchors[0]
    end = anchors[-1]
    last_index = max(len(anchors) - 1, 1)
    return [
        (
            start[0] + (end[0] - start[0]) * index / last_index,
            start[1] + (end[1] - start[1]) * index / last_index,
        )
        for index in range(len(anchors))
    ]


def stabilize_body_motion(
    frames: list[Image.Image],
    stage_indices: list[int],
    semantic_ranges: list[tuple[int, int]],
) -> list[Image.Image]:
    anchors = [
        source_body_anchor(frame, stage_index)
        for frame, stage_index in zip(frames, stage_indices)
    ]
    # 每个语义段首尾完全沿用原关键帧位置，仅平滑中间轨迹；既不吞掉
    # 人物深弯等主动位移，也不会在翅膀张合时反复搬动身体。
    target_anchors: list[tuple[float, float]] = []
    for start, end in semantic_ranges:
        target_anchors.extend(linear_anchor_segment(anchors[start:end]))

    stabilized: list[Image.Image] = []
    for frame, source_anchor, target_anchor in zip(frames, anchors, target_anchors):
        offset = (
            round(target_anchor[0] - source_anchor[0]),
            round(target_anchor[1] - source_anchor[1]),
        )
        canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        canvas.alpha_composite(frame, offset)
        stabilized.append(canvas)
    return stabilized


def flight_cycle_sources(base_frames: list[Image.Image]) -> list[Image.Image]:
    flight_cycle = [
        base_frames[56],
        base_frames[58],
        base_frames[59],
        base_frames[60],
        base_frames[59],
        base_frames[56],
        base_frames[57],
        base_frames[57],
    ]
    return [pose for pose in flight_cycle * 3 for _ in range(2)]


def to_premultiplied(image: Image.Image) -> np.ndarray:
    array = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    array[:, :, :3] *= array[:, :, 3:4]
    return array


def from_premultiplied(array: np.ndarray) -> Image.Image:
    alpha = np.clip(array[:, :, 3:4], 0.0, 1.0)
    rgb = np.zeros_like(array[:, :, :3])
    np.divide(
        np.clip(array[:, :, :3], 0.0, 1.0),
        np.maximum(alpha, 1e-6),
        out=rgb,
        where=alpha > 1e-6,
    )
    rgba = np.concatenate((rgb, alpha), axis=2)
    return Image.fromarray(np.round(rgba * 255).astype(np.uint8), "RGBA")


def optical_flow_pair(
    first: Image.Image,
    second: Image.Image,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    first_array = np.asarray(first.convert("RGBA"))
    second_array = np.asarray(second.convert("RGBA"))
    forward = cv2.calcOpticalFlowFarneback(
        first_array[:, :, 3],
        second_array[:, :, 3],
        None,
        0.5,
        4,
        31,
        4,
        7,
        1.5,
        cv2.OPTFLOW_FARNEBACK_GAUSSIAN,
    )
    backward = cv2.calcOpticalFlowFarneback(
        second_array[:, :, 3],
        first_array[:, :, 3],
        None,
        0.5,
        4,
        31,
        4,
        7,
        1.5,
        cv2.OPTFLOW_FARNEBACK_GAUSSIAN,
    )
    return to_premultiplied(first), to_premultiplied(second), forward, backward


FLOW_GRID_X, FLOW_GRID_Y = np.meshgrid(
    np.arange(FRAME_SIZE, dtype=np.float32),
    np.arange(FRAME_SIZE, dtype=np.float32),
)


def smootherstep(value: float) -> float:
    return value**3 * (value * (value * 6 - 15) + 10)


def morph_pair(
    pair: tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray],
    progress: float,
) -> Image.Image:
    first, second, forward, backward = pair
    warped_first = cv2.remap(
        first,
        FLOW_GRID_X - forward[:, :, 0] * progress,
        FLOW_GRID_Y - forward[:, :, 1] * progress,
        cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )
    warped_second = cv2.remap(
        second,
        FLOW_GRID_X - backward[:, :, 0] * (1.0 - progress),
        FLOW_GRID_Y - backward[:, :, 1] * (1.0 - progress),
        cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )
    return from_premultiplied(
        warped_first * (1.0 - progress) + warped_second * progress
    )


def interpolate_poses(
    keyframes: list[Image.Image],
    frame_count: int,
) -> list[Image.Image]:
    pairs = [
        optical_flow_pair(keyframes[index], keyframes[index + 1])
        for index in range(len(keyframes) - 1)
    ]
    frames: list[Image.Image] = []
    for output_index in range(frame_count):
        position = output_index * (len(keyframes) - 1) / max(frame_count - 1, 1)
        lower_index = min(int(position), len(keyframes) - 2)
        local_progress = smootherstep(position - lower_index)
        frames.append(morph_pair(pairs[lower_index], local_progress))
    return frames


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


def apply_flight_departure(
    frames: list[Image.Image],
) -> list[Image.Image]:
    departing: list[Image.Image] = []
    for index, frame in enumerate(frames):
        progress = smootherstep(index / max(len(frames) - 1, 1))
        scale = 1.0 - progress * 0.40
        cropped = frame.crop(alpha_bbox(frame))
        resized = cropped.resize(
            (
                max(1, round(cropped.width * scale)),
                max(1, round(cropped.height * scale)),
            ),
            Image.Resampling.LANCZOS,
        )
        center_x, center_y = bbox_center(frame)
        canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        canvas.alpha_composite(
            resized,
            (
                round(center_x - resized.width / 2),
                round(center_y - progress * 20 - resized.height / 2),
            ),
        )
        departing.append(canvas)
    return stabilize_body_motion(
        departing,
        [8] * len(departing),
        [(0, len(departing))],
    )


def render_on_stage_curve(
    subject: Image.Image,
    stage_base_frames: list[Image.Image],
    progress: float,
) -> Image.Image:
    position = progress * (len(stage_base_frames) - 1)
    lower_index = min(int(position), len(stage_base_frames) - 1)
    upper_index = min(lower_index + 1, len(stage_base_frames) - 1)
    fraction = position - lower_index
    lower = stage_base_frames[lower_index]
    upper = stage_base_frames[upper_index]

    target_area = alpha_area(lower) + (alpha_area(upper) - alpha_area(lower)) * fraction
    lower_center = bbox_center(lower)
    upper_center = bbox_center(upper)
    target_center = (
        lower_center[0] + (upper_center[0] - lower_center[0]) * fraction,
        lower_center[1] + (upper_center[1] - lower_center[1]) * fraction,
    )

    source_area = max(alpha_area(subject), 1)
    scale = float(np.sqrt(target_area / source_area))
    scale = min(max(scale, 0.68), 1.42)
    cropped = subject.crop(alpha_bbox(subject))
    scale = min(scale, 472 / max(cropped.size))
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


def build_frames() -> list[Image.Image]:
    base_frames = load_base_frames()
    transition_poses = extract_grid_subjects(
        OFFICIAL_TRANSITION_ATLAS,
        columns=4,
        rows=4,
        minimum_component_area=80,
    )
    # 第 5 格仍偏封闭椭圆，不符合官方参考中的轮廓消解过程；跳过它，
    # 由光流在相邻人体姿势之间生成连续收拢，不再经过“蛋”状态。
    transition_sources = [
        *base_frames[:8],
        *transition_poses[:4],
        transition_poses[5],
        *transition_poses[6:13],
    ]
    rendered_transition_sources = [
        render_transition_pose(
            frame,
            index / max(len(transition_sources) - 1, 1),
        )
        for index, frame in enumerate(transition_sources)
    ]
    transformation_frames = interpolate_poses(
        rendered_transition_sources,
        frame_count=192,
    )
    transformation_frames = stabilize_body_motion(
        transformation_frames,
        [0] * len(transformation_frames),
        [(0, len(transformation_frames))],
    )

    flight_frames: list[Image.Image] = []
    flight_stage_indices: list[int] = []
    flight_sources = flight_cycle_sources(base_frames)
    for stage_index in (7, 8):
        first_base_index = stage_index * 8
        stage_base_frames = base_frames[first_base_index : first_base_index + 8]
        rendered_stage = [
            render_on_stage_curve(
                frame,
                stage_base_frames,
                index / max(len(flight_sources) - 1, 1),
            )
            for index, frame in enumerate(flight_sources)
        ]
        flight_frames.extend(rendered_stage)
        flight_stage_indices.extend([stage_index] * len(rendered_stage))

    flight_frames = stabilize_body_motion(
        flight_frames,
        flight_stage_indices,
        [(0, len(flight_frames))],
    )
    frames = [
        *transformation_frames,
        *apply_flight_departure(flight_frames),
    ]

    if len(frames) != 288:
        raise ValueError(f"输出姿势数量应为 288，实际为 {len(frames)}")
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


def save_animation(frames: list[Image.Image]) -> None:
    # 25 FPS；首尾仅做短暂停留，不降低中段动作帧率。
    durations = [40] * len(frames)
    durations[0] = 160
    durations[-1] = 320
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
    frames[216].save(ASSET_STATIC, optimize=True)


def main() -> None:
    frames = build_frames()
    save_contact_sheet(frames)
    save_animation(frames)
    print(f"frames={len(frames)}")
    print(f"duration_ms={160 + 320 + (len(frames) - 2) * 40}")
    print(OUTPUT_ANIMATION)
    print(OUTPUT_CONTACT)
    print(ASSET_ANIMATION)
    print(ASSET_STATIC)


if __name__ == "__main__":
    main()
