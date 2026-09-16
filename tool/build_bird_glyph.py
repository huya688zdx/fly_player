"""从正式故事动画取青鸟原姿势，导出行内扑翼循环。"""

from __future__ import annotations

from pathlib import Path

from PIL import Image


ASSET_ROOT = Path(__file__).resolve().parents[1] / "assets" / "refresh"
# 固定画布覆盖整轮翼展，不随每张图的外框重新定位或缩放。
CROP = (128, 120, 384, 376)
POSE_TICKS = (185, 190, 195, 200, 195, 190)


def build_frames() -> list[Image.Image]:
    ticks = []
    elapsed = 0
    with Image.open(ASSET_ROOT / "shoujo_bird_loading.webp") as source:
        for index in range(source.n_frames):
            source.seek(index)
            frame = source.convert("RGBA").copy()
            end = elapsed + source.info["duration"]
            ticks.extend([frame] * (round(end * 30 / 1000) - round(elapsed * 30 / 1000)))
            elapsed = end
    if elapsed != 8700 or len(ticks) != 261:
        raise ValueError("正式动画时间轴已变更，请重新确认青鸟姿势位置")
    # 上举→展开→平翼→下拍→平翼→展开；回程复用原姿势，不生成中间图。
    return [ticks[index].crop(CROP).resize((128, 128), Image.Resampling.LANCZOS) for index in POSE_TICKS]


def main() -> None:
    frames = build_frames()
    frames[0].save(
        ASSET_ROOT / "bluebird_glyph.webp",
        save_all=True,
        append_images=frames[1:],
        duration=100,
        loop=0,
        lossless=True,
        method=6,
    )
    frames[1].save(ASSET_ROOT / "bluebird_glyph_static.png", optimize=True)
    print("行内青鸟：128×128透明，4张原姿势组成6格播放序列，600毫秒无限循环")


if __name__ == "__main__":
    main()
