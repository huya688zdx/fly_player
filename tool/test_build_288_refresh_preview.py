from __future__ import annotations

import inspect
import struct
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tool import build_288_refresh_preview as animation_builder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ANIMATION_ASSET = PROJECT_ROOT / "assets" / "refresh" / "shoujo_bird_loading.webp"


def alpha_area(frame: Image.Image) -> int:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3]
    return int(np.count_nonzero(alpha > 24))


def alpha_bbox_center_y(frame: Image.Image) -> float:
    bbox = frame.convert("RGBA").getchannel("A").getbbox()
    if bbox is None:
        raise AssertionError("检测到空白动画帧")
    return (bbox[1] + bbox[3]) / 2


def maximum_upper_vertical_edge(frame: Image.Image) -> int:
    alpha = np.asarray(frame.convert("RGBA"))[:, :, 3] > 24
    vertical_edges = np.logical_xor(alpha[:260, :-1], alpha[:260, 1:])
    return int(vertical_edges.sum(axis=0).max())


def webp_frame_durations(path: Path) -> list[int]:
    data = path.read_bytes()
    durations: list[int] = []
    offset = 12
    while offset + 8 <= len(data):
        chunk_type = data[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        chunk = data[offset + 8 : offset + 8 + chunk_size]
        if chunk_type == b"ANMF":
            durations.append(int.from_bytes(chunk[12:15], "little"))
        offset += 8 + chunk_size + (chunk_size & 1)
    return durations


class RefreshAnimationSequenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.frames = animation_builder.build_frames()

    def test_uses_only_drawn_and_original_video_frames(self) -> None:
        source = inspect.getsource(animation_builder)
        self.assertNotIn("calcOpticalFlowFarneback", source)
        self.assertNotIn("interpolate_poses", source)

    def test_output_keeps_near_340_frames(self) -> None:
        self.assertGreaterEqual(len(self.frames), 320)
        self.assertLessEqual(len(self.frames), 360)
        self.assertTrue(all(frame.size == (512, 512) for frame in self.frames))

    def test_no_frame_is_blank_or_cut_by_the_canvas(self) -> None:
        for index, frame in enumerate(self.frames):
            self.assertGreater(alpha_area(frame), 20, f"第 {index + 1} 帧为空")
            left, top, right, bottom = frame.getchannel("A").getbbox()
            self.assertGreater(left, 0, f"第 {index + 1} 帧碰到左边界")
            self.assertGreater(top, 0, f"第 {index + 1} 帧碰到上边界")
            self.assertLess(right, 512, f"第 {index + 1} 帧碰到右边界")
            self.assertLess(bottom, 512, f"第 {index + 1} 帧碰到下边界")

    def test_winged_ball_is_not_sliced_by_a_rectangular_mask(self) -> None:
        human_frame_count = len(self.frames) - animation_builder.SOURCE_VIDEO_FRAME_COUNT
        first_winged_ball_frames = self.frames[
            human_frame_count : human_frame_count + 30
        ]
        self.assertLessEqual(
            max(maximum_upper_vertical_edge(frame) for frame in first_winged_ball_frames),
            70,
        )

    def test_ring_collapses_to_a_point_then_reopens_as_a_bird(self) -> None:
        second_video_frame_count = 360 - animation_builder.SOURCE_VIDEO_2_FIRST_FRAME
        second_video_start = len(self.frames) - second_video_frame_count
        point_area = min(
            alpha_area(frame)
            for frame in self.frames[second_video_start + 5 : second_video_start + 33]
        )
        reopened_area = max(
            alpha_area(frame)
            for frame in self.frames[second_video_start + 33 : second_video_start + 60]
        )
        self.assertLessEqual(point_area, 700)
        self.assertGreaterEqual(reopened_area, 3000)

    def test_final_bird_flies_up_and_away(self) -> None:
        second_video_frame_count = 360 - animation_builder.SOURCE_VIDEO_2_FIRST_FRAME
        second_video_start = len(self.frames) - second_video_frame_count
        self.assertLessEqual(alpha_area(self.frames[-1]), 200)
        self.assertLessEqual(
            alpha_bbox_center_y(self.frames[-1]),
            alpha_bbox_center_y(self.frames[second_video_start + 75]) - 120,
        )

    def test_timing_keeps_25_fps_for_original_video_frames(self) -> None:
        durations = animation_builder.frame_durations(self.frames)
        human_frame_count = len(self.frames) - animation_builder.SOURCE_VIDEO_FRAME_COUNT
        self.assertTrue(all(value == 80 for value in durations[1:human_frame_count]))
        self.assertTrue(all(value == 40 for value in durations[human_frame_count:-1]))

    def test_exported_webp_keeps_the_complete_sequence(self) -> None:
        with Image.open(ANIMATION_ASSET) as animation:
            # WebP 会把完全相同的持帧合并；总时间轴仍有约 340 帧，
            # 编码后保留约 270 个有效画面且总时长必须完整。
            self.assertGreaterEqual(animation.n_frames, 260)
            self.assertLessEqual(animation.n_frames, 300)
            self.assertEqual(animation.size, (512, 512))
        self.assertEqual(
            sum(webp_frame_durations(ANIMATION_ASSET)),
            sum(animation_builder.frame_durations(self.frames)),
        )


if __name__ == "__main__":
    unittest.main()
