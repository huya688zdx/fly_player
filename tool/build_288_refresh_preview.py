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


def render_intermediate(
    subject: Image.Image,
    current: Image.Image,
    following: Image.Image,
    progress: float,
) -> Image.Image:
    current_area = alpha_area(current)
    following_area = alpha_area(following)
    target_area = current_area + (following_area - current_area) * progress
    source_area = max(alpha_area(subject), 1)
    scale = float(np.sqrt(target_area / source_area))
    scale = min(max(scale, 0.72), 1.35)

    maximum_extent = max(subject.size)
    scale = min(scale, 472 / maximum_extent)
    resized = subject.resize(
        (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
        Image.Resampling.LANCZOS,
    )

    current_center = bbox_center(current)
    following_center = bbox_center(following)
    target_x = current_center[0] + (following_center[0] - current_center[0]) * progress
    target_y = current_center[1] + (following_center[1] - current_center[1]) * progress

    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    left = round(target_x - resized.width / 2)
    top = round(target_y - resized.height / 2)
    canvas.alpha_composite(resized, (left, top))
    return canvas


def render_to_reference(subject: Image.Image, reference: Image.Image) -> Image.Image:
    reference_area = alpha_area(reference)
    source_area = max(alpha_area(subject), 1)
    scale = float(np.sqrt(reference_area / source_area))
    scale = min(max(scale, 0.72), 1.35)
    scale = min(scale, 472 / max(subject.size))
    resized = subject.resize(
        (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
        Image.Resampling.LANCZOS,
    )
    target_x, target_y = bbox_center(reference)
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        (round(target_x - resized.width / 2), round(target_y - resized.height / 2)),
    )
    return canvas


def pose_feature(frame: Image.Image) -> np.ndarray:
    cropped = frame.crop(alpha_bbox(frame))
    alpha = np.asarray(cropped.getchannel("A"), dtype=np.float32) / 255.0
    scale = min(44 / alpha.shape[1], 44 / alpha.shape[0])
    resized = cv2.resize(
        alpha,
        (max(1, round(alpha.shape[1] * scale)), max(1, round(alpha.shape[0] * scale))),
        interpolation=cv2.INTER_AREA,
    )
    normalized = np.zeros((48, 48), dtype=np.float32)
    top = (48 - resized.shape[0]) // 2
    left = (48 - resized.shape[1]) // 2
    normalized[top : top + resized.shape[0], left : left + resized.shape[1]] = resized
    return normalized.reshape(-1)


def merge_ordered_pose_sequences(sequences: list[list[Image.Image]]) -> list[Image.Image]:
    """在保留每套序列内部顺序的前提下，按轮廓平滑度合并四套姿势。"""
    sequence_count = len(sequences)
    sequence_length = len(sequences[0])
    features = [[pose_feature(frame) for frame in sequence] for sequence in sequences]

    def transition_cost(previous: np.ndarray, current: np.ndarray) -> float:
        return float(np.mean(np.abs(previous - current)))

    costs: dict[tuple[tuple[int, ...], int], float] = {}
    parents: dict[
        tuple[tuple[int, ...], int], tuple[tuple[int, ...], int] | None
    ] = {}
    for sequence_index in range(sequence_count):
        counts = tuple(1 if index == sequence_index else 0 for index in range(sequence_count))
        state = (counts, sequence_index)
        costs[state] = 0.0
        parents[state] = None

    total_frames = sequence_count * sequence_length
    for consumed in range(1, total_frames):
        states = [state for state in list(costs) if sum(state[0]) == consumed]
        for counts, last_sequence in states:
            state = (counts, last_sequence)
            previous_feature = features[last_sequence][counts[last_sequence] - 1]
            for next_sequence in range(sequence_count):
                next_local_index = counts[next_sequence]
                if next_local_index >= sequence_length:
                    continue
                next_counts = list(counts)
                next_counts[next_sequence] += 1
                next_counts_tuple = tuple(next_counts)
                current_feature = features[next_sequence][next_local_index]
                expected_progress = consumed / max(total_frames - 1, 1)
                local_progress = next_local_index / max(sequence_length - 1, 1)
                progress_penalty = abs(expected_progress - local_progress) * 0.20
                candidate_cost = (
                    costs[state]
                    + transition_cost(previous_feature, current_feature)
                    + progress_penalty
                )
                next_state = (next_counts_tuple, next_sequence)
                if candidate_cost < costs.get(next_state, float("inf")):
                    costs[next_state] = candidate_cost
                    parents[next_state] = state

    final_counts = tuple(sequence_length for _ in range(sequence_count))
    final_state = min(
        ((final_counts, sequence_index) for sequence_index in range(sequence_count)),
        key=lambda state: costs[state],
    )
    ordered_positions: list[tuple[int, int]] = []
    state: tuple[tuple[int, ...], int] | None = final_state
    while state is not None:
        counts, sequence_index = state
        ordered_positions.append((sequence_index, counts[sequence_index] - 1))
        state = parents[state]
    ordered_positions.reverse()
    return [sequences[sequence_index][local_index] for sequence_index, local_index in ordered_positions]


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
    generated_pages = [
        [extract_page_subjects(path) for path in stage_pages]
        for stage_pages in INBETWEEN_PAGES
    ]

    frames: list[Image.Image] = []
    for stage_index in range(9):
        first_base_index = stage_index * 8
        stage_base_frames = base_frames[first_base_index : first_base_index + 8]
        stage_sequences = [stage_base_frames, *generated_pages[stage_index]]
        ordered_stage_frames = merge_ordered_pose_sequences(stage_sequences)
        frames.extend(
            render_on_stage_curve(
                frame,
                stage_base_frames,
                index / max(len(ordered_stage_frames) - 1, 1),
            )
            for index, frame in enumerate(ordered_stage_frames)
        )

    if len(frames) != 288:
        raise ValueError(f"输出姿势数量应为 288，实际为 {len(frames)}")
    return frames


def save_contact_sheet(frames: list[Image.Image]) -> None:
    columns = 24
    rows = 12
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
    durations = [50] * len(frames)
    durations[0] = 400
    durations[-1] = 800
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


def main() -> None:
    frames = build_frames()
    save_contact_sheet(frames)
    save_animation(frames)
    print(f"frames={len(frames)}")
    print(f"duration_ms={400 + 800 + (len(frames) - 2) * 50}")
    print(OUTPUT_ANIMATION)
    print(OUTPUT_CONTACT)


if __name__ == "__main__":
    main()
