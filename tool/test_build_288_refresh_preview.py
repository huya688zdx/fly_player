from __future__ import annotations

import math
import statistics
import unittest
from pathlib import Path

import numpy as np
from PIL import Image


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


class RefreshAnimationStabilityTest(unittest.TestCase):
    def test_cocoon_body_stays_stable_while_wings_flap(self) -> None:
        animation = Image.open(ANIMATION_ASSET)
        centers: list[tuple[float, float]] = []
        for frame_index in range(96, 160):
            animation.seek(frame_index)
            centers.append(pale_body_center(animation.copy()))

        stage_ranges = ((0, 32), (32, 64))
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
        animation = Image.open(ANIMATION_ASSET)
        anchors: list[tuple[float, float]] = []
        for frame_index in range(224, 288):
            animation.seek(frame_index)
            anchors.append(central_body_bottom(animation.copy()))

        for start, end in ((0, 32), (32, 64)):
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
        animation = Image.open(ANIMATION_ASSET)
        frames: list[Image.Image] = []
        for frame_index in range(288):
            animation.seek(frame_index)
            frames.append(animation.copy())

        # 96/128/192/256 处只是翅膀姿势页切换，外框会随翼展自然变化；
        # 这里检查人物、茧身、变鸟和成鸟四个真正的语义边界。
        for boundary in (32, 64, 160, 224):
            step = math.dist(
                alpha_bbox_center(frames[boundary - 1]),
                alpha_bbox_center(frames[boundary]),
            )
            self.assertLessEqual(
                step,
                25.0,
                f"第 {boundary}→{boundary + 1} 帧边界跳动 {step:.1f}px",
            )

    def test_early_stages_do_not_pump_the_character_size(self) -> None:
        animation = Image.open(ANIMATION_ASSET)
        areas: list[int] = []
        for frame_index in range(160):
            animation.seek(frame_index)
            areas.append(alpha_area(animation.copy()))

        for stage_index in range(5):
            stage_areas = areas[stage_index * 32 : (stage_index + 1) * 32]
            coefficient_of_variation = statistics.pstdev(stage_areas) / statistics.mean(
                stage_areas
            )
            self.assertLessEqual(
                coefficient_of_variation,
                0.16,
                f"第 {stage_index + 1} 段尺寸波动达到 {coefficient_of_variation:.1%}",
            )


if __name__ == "__main__":
    unittest.main()
