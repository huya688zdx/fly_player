from __future__ import annotations

import math
import statistics
import unittest
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from tool import build_288_refresh_preview as animation_builder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ANIMATION_ASSET = PROJECT_ROOT / "assets" / "refresh" / "shoujo_bird_loading.webp"


def central_body_bottom(frame: Image.Image) -> tuple[float, float]:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3]
    y_coordinates, x_coordinates = np.where(alpha > 24)
    left = int(x_coordinates.min())
    right = int(x_coordinates.max())
    horizontal_center = (left + right) / 2
    half_band = max(8, min(28, round((right - left + 1) * 0.1)))
    central_mask = (
        (alpha > 24)
        & (np.indices(alpha.shape)[1] >= horizontal_center - half_band)
        & (np.indices(alpha.shape)[1] <= horizontal_center + half_band)
    )
    central_y, central_x = np.where(central_mask)
    return float(np.median(central_x)), float(np.quantile(central_y, 0.94))


def alpha_bbox_center(frame: Image.Image) -> tuple[float, float]:
    bbox = frame.convert("RGBA").getchannel("A").getbbox()
    if bbox is None:
        raise AssertionError("检测到空白动画帧")
    left, top, right, bottom = bbox
    return (left + right) / 2, (top + bottom) / 2


def alpha_area(frame: Image.Image) -> int:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3]
    return int(np.count_nonzero(alpha > 24))


def silhouette_metrics(frame: Image.Image) -> tuple[float, float, float]:
    pixels = np.asarray(frame.convert("RGBA"))
    alpha_mask = pixels[:, :, 3] > 24
    y_coordinates, x_coordinates = np.where(alpha_mask)
    width = int(x_coordinates.max() - x_coordinates.min() + 1)
    height = int(y_coordinates.max() - y_coordinates.min() + 1)
    cropped_alpha = alpha_mask[
        y_coordinates.min() : y_coordinates.max() + 1,
        x_coordinates.min() : x_coordinates.max() + 1,
    ]
    rgb = pixels[:, :, :3]
    pale_mask = (
        alpha_mask
        & (rgb[:, :, 0] > 145)
        & (rgb[:, :, 1] > 165)
        & (rgb[:, :, 2] > 165)
    )
    pale_ratio = float(np.count_nonzero(pale_mask)) / max(
        int(np.count_nonzero(alpha_mask)), 1
    )
    return width / height, float(np.mean(cropped_alpha)), pale_ratio


def normalized_silhouette(frame: Image.Image) -> np.ndarray:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3]
    y_coordinates, x_coordinates = np.where(alpha > 24)
    cropped = alpha[
        y_coordinates.min() : y_coordinates.max() + 1,
        x_coordinates.min() : x_coordinates.max() + 1,
    ]
    return cv2.resize(cropped, (64, 64), interpolation=cv2.INTER_AREA) / 255.0


class RefreshAnimationStabilityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.frames = animation_builder.build_frames()

    def test_transition_center_moves_continuously(self) -> None:
        centers = [alpha_bbox_center(frame) for frame in self.frames[:192]]
        maximum_step = max(
            math.dist(previous, current)
            for previous, current in zip(centers, centers[1:])
        )
        self.assertLessEqual(
            maximum_step,
            4.0,
            f"变形主体发生 {maximum_step:.1f}px 的相邻帧跳动",
        )

    def test_bird_body_follows_a_smooth_flight_path(self) -> None:
        anchors = [central_body_bottom(frame) for frame in self.frames[192:288]]

        for start, end in ((0, 48), (48, 96)):
            maximum_acceleration = max(
                math.dist(
                    anchors[index],
                    (
                        anchors[index - 1][0] * 2 - anchors[index - 2][0],
                        anchors[index - 1][1] * 2 - anchors[index - 2][1],
                    ),
                )
                for index in range(start + 2, end)
            )
            self.assertLessEqual(
                maximum_acceleration,
                8.0,
                f"鸟身运动轨迹出现 {maximum_acceleration:.1f}px 的速度突变",
            )

    def test_semantic_stage_boundaries_keep_the_original_continuity(self) -> None:
        # 光流段没有硬切阶段；每 32 帧抽查一次，并检查变形转飞行的边界。
        for boundary in (32, 64, 96, 128, 160, 192):
            step = math.dist(
                alpha_bbox_center(self.frames[boundary - 1]),
                alpha_bbox_center(self.frames[boundary]),
            )
            self.assertLessEqual(
                step,
                25.0,
                f"第 {boundary}→{boundary + 1} 帧边界跳动 {step:.1f}px",
            )

    def test_early_stages_do_not_pump_the_character_size(self) -> None:
        early_stage_ranges = ((0, 32), (32, 64), (64, 96), (96, 120), (120, 144))
        for stage_index, (start, end) in enumerate(early_stage_ranges):
            stage_areas = [alpha_area(frame) for frame in self.frames[start:end]]
            coefficient_of_variation = statistics.pstdev(stage_areas) / statistics.mean(
                stage_areas
            )
            self.assertLessEqual(
                coefficient_of_variation,
                0.16,
                f"第 {stage_index + 1} 段尺寸波动达到 {coefficient_of_variation:.1%}",
            )

    def test_flight_uses_a_repeatable_silhouette_cycle(self) -> None:
        silhouettes = [normalized_silhouette(frame) for frame in self.frames[192:288]]

        cycle_errors = [
            float(np.mean(np.abs(silhouettes[index] - silhouettes[index + 16])))
            for index in range(len(silhouettes) - 16)
        ]
        self.assertLessEqual(
            max(cycle_errors),
            0.12,
            f"飞鸟循环轮廓最大偏差达到 {max(cycle_errors):.3f}",
        )

    def test_exported_webp_keeps_near_300_frames(self) -> None:
        with Image.open(ANIMATION_ASSET) as animation:
            self.assertGreaterEqual(animation.n_frames, 270)
            self.assertLessEqual(animation.n_frames, 288)
            self.assertEqual(animation.size, (512, 512))

    def test_transition_does_not_hold_an_egg_silhouette(self) -> None:
        longest_egg_hold = 0
        current_egg_hold = 0
        for frame in self.frames[32:192]:
            aspect, fill_ratio, pale_ratio = silhouette_metrics(frame)
            is_egg = (
                0.48 <= aspect <= 0.72
                and fill_ratio >= 0.78
                and pale_ratio >= 0.83
            )
            current_egg_hold = current_egg_hold + 1 if is_egg else 0
            longest_egg_hold = max(longest_egg_hold, current_egg_hold)

        self.assertLessEqual(
            longest_egg_hold,
            3,
            f"蛋状封闭轮廓连续停留了 {longest_egg_hold} 帧",
        )

    def test_transition_has_no_large_aspect_reset(self) -> None:
        aspects = [silhouette_metrics(frame)[0] for frame in self.frames[96:192]]
        largest_ratio = max(
            max(previous, current) / max(min(previous, current), 0.01)
            for previous, current in zip(aspects, aspects[1:])
        )
        self.assertLessEqual(
            largest_ratio,
            1.60,
            f"变鸟阶段相邻轮廓宽高比突变达到 {largest_ratio:.2f} 倍",
        )

    def test_bird_finishes_by_flying_farther_away(self) -> None:
        first_frame = self.frames[192]
        final_frame = self.frames[-1]
        first_area = alpha_area(first_frame)
        final_area = alpha_area(final_frame)
        first_y = alpha_bbox_center(first_frame)[1]
        final_y = alpha_bbox_center(final_frame)[1]

        self.assertLessEqual(final_area, first_area * 0.40)
        self.assertLessEqual(final_y, first_y - 35.0)


if __name__ == "__main__":
    unittest.main()
