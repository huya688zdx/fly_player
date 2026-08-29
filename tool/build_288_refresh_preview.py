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

BASE_ATLASES = [
    PROJECT_ROOT / "assets" / "refresh" / f"shoujo_bird_frames_{start:02d}_{start + 7:02d}.png"
    for start in range(1, 73, 8)
]

HUMAN_DIR = Path(
    r"C:\Users\25131.GUOJUN.000\.codex\generated_images"
    r"\01a048cd-6793-7223-820f-70b53f7ea979"
)
COCOON_DIR = Path(
    r"C:\Users\25131.GUOJUN.000\.codex\generated_images"
    r"\01a048d2-8695-7310-9131-6e3f6b36f16a"
)
BIRD_DIR = Path(
    r"C:\Users\25131.GUOJUN.000\.codex\generated_images"
    r"\01a048d4-8886-7de2-ad30-058e3fb5c9c1"
)

# 每个阶段依次为 1/4、1/2、3/4 姿势页。
INBETWEEN_PAGES = [
    [
        HUMAN_DIR / "exec-678e6432-39e0-4c39-aaf2-8c67c28f073b.png",
        HUMAN_DIR / "exec-834b2322-266d-459e-bbac-ecc632a62673.png",
        HUMAN_DIR / "exec-1d263d3c-aab2-4d8f-9ac4-fd8510b08f23.png",
    ],
    [
        HUMAN_DIR / "exec-a75448e2-27a8-40ad-a869-f4f1e1fcc0c1.png",
        HUMAN_DIR / "exec-26e3ff5a-2e32-4e0c-9fb9-7097c1aec056.png",
        HUMAN_DIR / "exec-84af17ad-21dd-4f9a-a2d8-b33c59024cb1.png",
    ],
    [
        HUMAN_DIR / "exec-81d8b7be-7779-4bc2-9d74-ada5787c4134.png",
        HUMAN_DIR / "exec-ef41a7c1-5716-4058-a760-05a2723c1b83.png",
        HUMAN_DIR / "exec-5011be26-2e78-4ed4-831b-a1061bf3dcca.png",
    ],
    [
        COCOON_DIR / "exec-0e505d14-740a-40af-b5ea-72b72ec1d95e.png",
        COCOON_DIR / "exec-6fc67bc2-9847-4809-9518-45e656a3accd.png",
        COCOON_DIR / "exec-85e129ad-5830-42f0-a4c6-aca67409bad8.png",
    ],
    [
        COCOON_DIR / "exec-c4b920c8-8c54-4fff-a893-4fd305aa9d80.png",
        COCOON_DIR / "exec-1a98645c-7a43-4c24-9954-bf53a64767f2.png",
        COCOON_DIR / "exec-0e443879-3595-4791-8664-1244c8dc8a07.png",
    ],
    [
        COCOON_DIR / "exec-336a0da4-2ac9-4611-b199-f4a55989eea8.png",
        COCOON_DIR / "exec-046e42cf-3698-438f-b5ec-4b50812d503c.png",
        COCOON_DIR / "exec-60c882e0-c42c-42f6-a133-6a5b7723ced5.png",
    ],
    [
        BIRD_DIR / "exec-5b010462-48ea-4768-904f-3f966ef2eb9e.png",
        BIRD_DIR / "exec-be0b3c7b-b244-4d18-a352-38f8bfeca858.png",
        BIRD_DIR / "exec-b77bfaae-d915-4e62-882d-f1810aac9650.png",
    ],
    [
        BIRD_DIR / "exec-4a07fd1d-510e-4121-bea0-e3f3f35e2ac8.png",
        BIRD_DIR / "exec-5991408a-9ef5-447d-a5f9-59998de99261.png",
        BIRD_DIR / "exec-619cb7d5-baf7-46c7-959c-8aa993e5358b.png",
    ],
    [
        BIRD_DIR / "exec-1ccead77-4961-48ea-a482-168cdf838fd3.png",
        BIRD_DIR / "exec-03e6c789-3116-4e5d-89cc-d33f753acd8c.png",
        BIRD_DIR / "exec-1967d081-10b1-4086-b724-c371452cf42a.png",
    ],
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


def extract_page_subjects(path: Path) -> list[Image.Image]:
    source = Image.open(path).convert("RGB")
    rgb = np.asarray(source)
    mask = external_foreground_mask(rgb)
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)

    width, height = source.size
    centers = [
        ((column + 0.5) * width / GRID_COLUMNS, (row + 0.5) * height / GRID_ROWS)
        for row in range(GRID_ROWS)
        for column in range(GRID_COLUMNS)
    ]
    grouped_masks = [np.zeros((height, width), dtype=np.uint8) for _ in centers]

    for label in range(1, count):
        area = stats[label, cv2.CC_STAT_AREA]
        if area < 20:
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


def pale_body_mask(frame: Image.Image) -> np.ndarray:
    pixels = np.asarray(frame.convert("RGBA"))
    rgb = pixels[:, :, :3]
    return (
        (pixels[:, :, 3] > 24)
        & (rgb[:, :, 0] > 145)
        & (rgb[:, :, 1] > 165)
        & (rgb[:, :, 2] > 165)
    ).astype(np.uint8)


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
    if stage_index in (0, 1):
        return bbox_center(frame)

    if stage_index in (2, 3, 4):
        mask = pale_body_mask(frame)
        y_coordinates, x_coordinates = np.where(mask)
        if len(x_coordinates) >= 50:
            return (
                float(np.median(x_coordinates)),
                float(np.median(y_coordinates)),
            )

    if stage_index in (7, 8):
        mask = central_body_mask(frame)
        y_coordinates, x_coordinates = np.where(mask)
        return (
            float(np.median(x_coordinates)),
            float(np.quantile(y_coordinates, 0.94)),
        )

    alpha = (np.asarray(frame.getchannel("A")) > 24).astype(np.uint8)
    central_mask = central_body_mask(frame)
    distance = cv2.distanceTransform(alpha, cv2.DIST_L2, 5)
    weights = np.square(distance) * central_mask
    weight_sum = float(weights.sum())
    if weight_sum <= 0:
        return bbox_center(frame)
    y_grid, x_grid = np.indices(alpha.shape)
    return (
        float((x_grid * weights).sum() / weight_sum),
        float((y_grid * weights).sum() / weight_sum),
    )


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


def hold_poses(poses: list[Image.Image], repeat_count: int) -> list[Image.Image]:
    return [pose for pose in poses for _ in range(repeat_count)]


def curated_stage_sources(
    stage_index: int,
    base_frames: list[Image.Image],
    generated_stage_frames: dict[int, list[Image.Image]],
) -> list[Image.Image]:
    first_base_index = stage_index * 8
    stage_base_frames = base_frames[first_base_index : first_base_index + 8]
    if stage_index <= 2:
        return hold_poses(stage_base_frames, 4)
    if stage_index in (3, 4):
        return hold_poses(generated_stage_frames[stage_index], 3)
    if stage_index in (5, 6):
        return hold_poses(stage_base_frames, 3)

    flight_cycle = [
        base_frames[57],
        base_frames[56],
        base_frames[58],
        base_frames[59],
        base_frames[60],
        base_frames[59],
        base_frames[56],
        base_frames[57],
    ]
    return hold_poses(flight_cycle * 3, 2)


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
    generated_stage_frames = {
        3: extract_page_subjects(INBETWEEN_PAGES[3][1]),
        4: extract_page_subjects(INBETWEEN_PAGES[4][0]),
    }

    frames: list[Image.Image] = []
    stage_indices: list[int] = []
    stage_ranges: list[tuple[int, int]] = []
    for stage_index in range(9):
        first_base_index = stage_index * 8
        stage_base_frames = base_frames[first_base_index : first_base_index + 8]
        stage_sources = curated_stage_sources(
            stage_index,
            base_frames,
            generated_stage_frames,
        )
        stage_start = len(frames)
        rendered_stage = [
            render_on_stage_curve(
                frame,
                stage_base_frames,
                index / max(len(stage_sources) - 1, 1),
            )
            for index, frame in enumerate(stage_sources)
        ]
        frames.extend(rendered_stage)
        stage_indices.extend([stage_index] * len(rendered_stage))
        stage_ranges.append((stage_start, len(frames)))

    if len(frames) != 288:
        raise ValueError(f"输出姿势数量应为 288，实际为 {len(frames)}")
    semantic_ranges = [
        stage_ranges[0],
        stage_ranges[1],
        (stage_ranges[2][0], stage_ranges[4][1]),
        (stage_ranges[5][0], stage_ranges[6][1]),
        (stage_ranges[7][0], stage_ranges[8][1]),
    ]
    return stabilize_body_motion(frames, stage_indices, semantic_ranges)


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
