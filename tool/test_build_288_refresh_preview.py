from __future__ import annotations

import inspect
import struct
import unittest
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from tool import build_288_refresh_preview as animation_builder


ANIMATION_ASSET = animation_builder.ASSET_ANIMATION


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
        cls.frames, cls.phases = animation_builder.build_frames()

    def test_uses_only_drawn_and_original_video_frames(self) -> None:
        source = inspect.getsource(animation_builder)
        self.assertNotIn("calcOpticalFlowFarneback", source)
        self.assertNotIn("interpolate_poses", source)

    def test_output_has_a_complete_readable_story(self) -> None:
        self.assertEqual(len(self.frames), len(self.phases))
        for phase in ("human_0", "closure_5", "growth_0", "video1_472", "ring", "point", "video2_284", "video2_359"):
            self.assertIn(phase, self.phases)
        self.assertTrue(all(frame.size == (512, 512) for frame in self.frames))

    def test_human_bridges_show_new_poses_between_their_endpoints(self) -> None:
        # 锁定这次接受的六处动作过程，不能退回重复端点或长时间空等。
        for before, bridge, after in (
            ("human_1", "human_backstep", "human_2"),
            ("human_6", "human_hands_separate", "human_arms_cross"),
            ("human_hands_separate", "human_arms_cross", "human_7"),
            ("human_9", "human_knees_bend", "human_10"),
            ("human_12", "human_crouch_lower", "human_13"),
            ("human_13", "human_crouch_tuck", "human_14"),
        ):
            left, middle, right = (self.phases.index(phase) for phase in (before, bridge, after))
            self.assertTrue(left < middle < right)
            for neighbor in (left, right):
                self.assertFalse(np.array_equal(np.asarray(self.frames[middle]), np.asarray(self.frames[neighbor])))
        self.assertLessEqual(self.phases.count("human_0") + self.phases.count("human_1"), 12)

    def test_no_frame_is_blank_or_cut_by_the_canvas(self) -> None:
        for index, frame in enumerate(self.frames):
            self.assertGreater(alpha_area(frame), 20, f"第 {index + 1} 帧为空")
            left, top, right, bottom = frame.getchannel("A").getbbox()
            self.assertGreater(left, 0, f"第 {index + 1} 帧碰到左边界")
            self.assertGreater(top, 0, f"第 {index + 1} 帧碰到上边界")
            self.assertLess(right, 512, f"第 {index + 1} 帧碰到右边界")
            self.assertLess(bottom, 512, f"第 {index + 1} 帧碰到下边界")

    def test_winged_ball_is_not_sliced_by_a_rectangular_mask(self) -> None:
        first_winged_ball_frames = [frame for frame, phase in zip(self.frames, self.phases) if phase.startswith("video1_")]
        self.assertEqual(
            [phase for phase in self.phases if phase.startswith("video1_")],
            [f"video1_{index}" for index in range(472, 547, 2)],
        )
        original = animation_builder.load_video_range(animation_builder.SOURCE_VIDEO, 472, 547)[::2]
        for actual, expected in zip(first_winged_ball_frames, original):
            np.testing.assert_array_equal(np.asarray(actual), np.asarray(expected))
        self.assertLessEqual(
            max(maximum_upper_vertical_edge(frame) for frame in first_winged_ball_frames),
            70,
        )

    def test_ring_collapses_to_a_point_then_reopens_as_a_bird(self) -> None:
        point_area = min(
            alpha_area(frame) for frame, phase in zip(self.frames, self.phases) if phase == "point"
        )
        reopened_area = max(
            alpha_area(frame) for frame, phase in zip(self.frames, self.phases) if phase.startswith("video2_")
        )
        self.assertLessEqual(point_area, 700)
        self.assertGreaterEqual(reopened_area, 3000)

    def test_pale_ball_body_remains_opaque(self) -> None:
        frame = animation_builder.load_video_range(animation_builder.SOURCE_VIDEO, 420, 421)[0]
        # 原片第 420 帧球体内部；浅色身体不能因不属于蓝色或暖色种子而丢失。
        alpha = np.asarray(frame.getchannel("A"))
        self.assertGreaterEqual(int(alpha[325:345, 245:260].min()), 250)

    def test_point_keeps_its_body_without_the_detached_noise(self) -> None:
        frame = animation_builder.load_video_range(animation_builder.SOURCE_VIDEO_2, 275, 276)[0]
        alpha = np.asarray(frame.getchannel("A"))
        self.assertLessEqual(int(alpha[291:299, 248:255].max()), 24)
        self.assertGreaterEqual(int(alpha[310:316, 240:247].min()), 250)

    def test_final_bird_flies_up_and_away(self) -> None:
        # 飞远段必须逐帧保留原片，不强制远景鸟具有近景的大轮廓。
        start = self.phases.index("video2_277")
        original = animation_builder.load_video_range(animation_builder.SOURCE_VIDEO_2, 277, 360)
        self.assertEqual(self.phases[start:], [f"video2_{index}" for index in range(277, 360)])
        for actual, expected in zip(self.frames[start:], original):
            np.testing.assert_array_equal(np.asarray(actual), np.asarray(expected))
        stable = self.frames[self.phases.index("video2_296")]
        self.assertGreater(alpha_area(self.frames[-1]), 20)
        self.assertLess(alpha_area(self.frames[-1]), alpha_area(stable) * .7)
        self.assertLessEqual(
            alpha_bbox_center_y(self.frames[-1]),
            alpha_bbox_center_y(stable) - 80,
        )

    def test_timing_uses_30_fps_without_accumulated_rounding_drift(self) -> None:
        durations = animation_builder.frame_durations(self.frames)
        self.assertEqual(set(durations), {33, 34})
        self.assertEqual(sum(durations), round(len(self.frames) * 1000 / 30))

    def test_exported_webp_keeps_the_complete_sequence(self) -> None:
        with Image.open(ANIMATION_ASSET) as animation:
            # 持帧合并不应改变整个故事的时长，也不要求凑到固定画面数。
            self.assertGreater(animation.n_frames, 24)
            self.assertEqual(animation.size, (512, 512))
        self.assertEqual(
            sum(webp_frame_durations(ANIMATION_ASSET)),
            sum(animation_builder.frame_durations(self.frames)),
        )

    def test_mp4_preview_preserves_timing_and_frame_count(self) -> None:
        video = cv2.VideoCapture(str(animation_builder.OUTPUT_VIDEO))
        try:
            self.assertTrue(video.isOpened())
            self.assertAlmostEqual(video.get(cv2.CAP_PROP_FPS), 30)
            self.assertEqual(int(video.get(cv2.CAP_PROP_FRAME_COUNT)), len(self.frames))
            for _ in self.frames:
                ok, actual = video.read()
                self.assertTrue(ok)
                self.assertEqual(actual.shape[:2], (512, 512))
            self.assertFalse(video.read()[0])
        finally:
            video.release()

    def test_preview_preserves_pixels_outside_the_updated_rectangle(self) -> None:
        # 按时间定位，避免原片持帧合并后编码帧号与时间轴帧号不一致。
        target_time = sum(animation_builder.frame_durations(self.frames)[:40])
        with Image.open(animation_builder.OUTPUT_ANIMATION) as preview:
            elapsed = 0
            for index in range(preview.n_frames):
                preview.seek(index)
                elapsed += preview.info["duration"]
                if elapsed > target_time:
                    break
            np.testing.assert_array_equal(
                np.asarray(preview.convert("RGBA").getchannel("A")),
                np.asarray(self.frames[40].getchannel("A")),
            )

    def test_transition_keeps_feet_and_ball_stable(self) -> None:
        bottoms = [frame.getchannel("A").getbbox()[3] for frame, phase in zip(self.frames, self.phases) if phase.startswith("human_")]
        self.assertLessEqual(max(bottoms) - min(bottoms), 1)
        # 后撤时画面右脚持续支撑；只测靴筒，抬起的另一只脚不能影响定位。
        support_x = []
        for phase in ("human_0", "human_1", "human_backstep", "human_2", "human_3", "human_4", "human_5"):
            rgba = np.asarray(self.frames[self.phases.index(phase)]).astype(np.int16)[426:436, 252:304]
            red, green, blue, alpha = np.moveaxis(rgba, 2, 0)
            _, xs = np.where((red - green > 35) & (green - blue > 25) & (alpha > 200))
            self.assertGreater(len(xs), 30, phase)
            support_x.append(float(np.median(xs)) + 252)
        self.assertLessEqual(np.ptp(support_x), 1, support_x)
        geometry = np.array([animation_builder.ball_geometry(frame) for frame, phase in zip(self.frames, self.phases) if phase.startswith("growth_")])
        # 稳定尺度允许出翼时有意轻沉，不能重新锁死成完全不动的身体。
        self.assertTrue(np.all(np.ptp(geometry, axis=0) <= [2, 10, 6]), geometry)
        self.assertTrue(np.all((np.diff(geometry[:, 1]) >= 0) & (np.diff(geometry[:, 1]) <= 3)), geometry)


class HumanArmRevisionBoundaryTest(unittest.TestCase):
    def test_only_masked_bc_pixels_change_and_endpoints_stay_exact(self) -> None:
        original = Image.new("RGBA", (3072, 2560), (20, 40, 60, 150))
        original.putpixel((0, 0), (20, 40, 60, 0))
        patch = Image.new("RGBA", (512, 512), (80, 100, 120, 0))
        mask = Image.new("L", (512, 512))
        mask.putpixel((260, 220), 255)
        actual = animation_builder.apply_human_arm_revisions(original, {8: (patch, mask), 9: (patch, mask)})
        expected = original.copy()
        for index in (8, 9):
            expected.putpixel((index % 6 * 512 + 260, index // 6 * 512 + 220), patch.getpixel((260, 220)))
        # 全图相等同时覆盖端点、下摆、透明像素RGB以及旧轮廓清除。
        np.testing.assert_array_equal(np.asarray(actual), np.asarray(expected))

    def test_rejects_endpoint_or_rescaled_full_figure_import(self) -> None:
        original = Image.new("RGBA", (3072, 2560))
        patch = Image.new("RGBA", (512, 512))
        mask = Image.new("L", (512, 512))
        with self.assertRaisesRegex(ValueError, "A/D"):
            animation_builder.apply_human_arm_revisions(original, {7: (patch, mask)})
        with self.assertRaisesRegex(ValueError, "512×512"):
            animation_builder.apply_human_arm_revisions(original, {8: (patch.resize((627, 660)), mask)})


if __name__ == "__main__":
    unittest.main()
