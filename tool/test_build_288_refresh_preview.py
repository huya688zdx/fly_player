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


def pale_body_center(frame: Image.Image) -> tuple[float, float]:
    pixels = np.asarray(frame.convert("RGBA"))
    rgb = pixels[:, :, :3]
    mask = (
        (pixels[:, :, 3] > 24)
        & (rgb[:, :, 0] > 145)
        & (rgb[:, :, 1] > 165)
        & (rgb[:, :, 2] > 165)
    )
    y_coordinates, x_coordinates = np.where(mask)
    if len(x_coordinates) < 50:
        raise AssertionError("未检测到足够的浅色身体像素")
    return float(np.median(x_coordinates)), float(np.median(y_coordinates))


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


def normalized_silhouette(frame: Image.Image) -> np.ndarray:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3]
    y_coordinates, x_coordinates = np.where(alpha > 24)
    cropped = alpha[
        y_coordinates.min() : y_coordinates.max() + 1,
        x_coordinates.min() : x_coordinates.max() + 1,
    ]
    return cv2.resize(cropped, (64, 64), interpolation=cv2.INTER_AREA) / 255.0


def cocoon_state(frame: Image.Image) -> str:
    pixels = np.asarray(frame.convert("RGBA"))
    alpha_mask = pixels[:, :, 3] > 24
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
    y_coordinates, _ = np.where(alpha_mask)
    height = int(y_coordinates.max() - y_coordinates.min() + 1)
    if pale_ratio < 0.65:
        return "compact"
    if pale_ratio > 0.69 and height > 200:
        return "winged"
    return "transition"


class RefreshAnimationStabilityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.frames = animation_builder.build_frames()

    def test_cocoon_body_stays_stable_while_wings_flap(self) -> None:
        centers = [pale_body_center(frame) for frame in self.frames[96:144]]

        stage_ranges = ((0, 24), (24, 48))
        for start, end in stage_ranges:
            maximum_step = max(
                math.dist(centers[index - 1], centers[index])
                for index in range(start + 1, end)
            )
            self.assertLessEqual(
                maximum_step,
                6.0,
                f"茧身核心发生 {maximum_step:.1f}px 的相邻帧跳动",
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
        # 96 处只是翅膀姿势页切换，外框会随翼展自然变化；
        # 这里检查人物、茧身、变鸟和成鸟四个真正的语义边界。
        for boundary in (32, 64, 144, 192):
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

    def test_cocoon_does_not_reopen_after_contraction_starts(self) -> None:
        states = [cocoon_state(frame) for frame in self.frames[96:120]]

        first_compact = states.index("compact")
        self.assertNotIn(
            "winged",
            states[first_compact + 1 :],
            "茧体开始收拢后又退回完整有翼状态",
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


if __name__ == "__main__":
    unittest.main()
