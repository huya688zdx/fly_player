"""把生成的图标状态图合成为工具栏动效预览，不接入播放器。"""

from pathlib import Path
import math
import shutil

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
SOURCE = Path(r"C:/Users/25131.GUOJUN.000/.codex/generated_images/01a08b2a-8e74-7650-bd16-4e5aced5aec9/exec-a8965c67-9be5-4721-89bd-66a6c03c2b98.png")
NAMES = ["弹幕", "倍速", "选集", "画质", "字幕", "音轨", "全屏"]
FONT = "C:/Windows/Fonts/msyh.ttc"
BOLD = "C:/Windows/Fonts/msyhbd.ttc"
WIDTH, HEIGHT = 960, 540
FPS, SECONDS = 30, 7.2


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


def ease(value):
    value = max(0, min(1, value))
    return 1 - (1 - value) ** 3


def state(t, index):
    start = 0.8 + index * 0.18
    end = 4.5 + index * 0.14
    if t < start:
        return 0, "静止", 0
    if t < start + 0.60:
        q = (t - start) / 0.60
        return ease(q), "进入", q
    if t < end:
        return 1, "静止", 0
    if t < end + 0.45:
        q = (t - end) / 0.45
        return 1 - ease(q), "退出", q
    return 0, "静止", 0


def draw_icon(index, amount=0, phase="静止", q=0):
    # 按状态图的造型拆开图形笔画，每帧绘制运动部件，文字不做叠帧混合。
    image = Image.new("RGBA", (200, 200))
    draw = ImageDraw.Draw(image)
    ink = "#edf4ff"
    draw.rounded_rectangle((8, 8, 192, 192), 40, fill="#1c2633", outline="#34465d", width=2)
    moving = phase != "静止"
    wave = math.sin(q * math.pi) if moving else 0
    sign = 1 if phase == "进入" else -1

    def line(points, color=ink, width=7):
        draw.line(points, fill=color, width=width, joint="curve")
        radius = width / 2
        for x, y in (points[0], points[-1]):
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)

    if index == 0:
        draw.rounded_rectangle((43, 54, 157, 143), 12, outline=ink, width=6)
        streaks = Image.new("RGBA", (200, 200))
        pen = ImageDraw.Draw(streaks)
        for j, (x, length) in enumerate([(59, 39), (99, 38), (62, 51)]):
            if moving:
                travel = sign * (q * 120)
                x = 53 + ((x - 53 - travel) % 120)
                if x > 147:
                    x -= 120
            y = 76 + j * 22
            pen.rounded_rectangle((x, y, x + length, y + 6), 3, fill=ink)
            if moving:
                pen.rounded_rectangle((x + 120, y, x + 120 + length, y + 6), 3, fill=ink)
        mask = Image.new("L", (200, 200))
        ImageDraw.Draw(mask).rectangle((54, 65, 146, 134), fill=255)
        image.alpha_composite(Image.composite(streaks, Image.new("RGBA", (200, 200)), mask))
    elif index == 1:
        # 数值沿纵向滚入，原字退出后才进入新字，没有两套文字残影。
        layer = Image.new("RGBA", (200, 200))
        pen = ImageDraw.Draw(layer)
        dy = 0
        if moving:
            dy = sign * (ease(q) * 60)
        pen.text((100, 98 - dy), "1.0×", font=font(43, True), fill=ink, anchor="mm")
        if moving:
            pen.text((100, 98 - dy + sign * 60), "1.0×", font=font(43, True), fill=ink, anchor="mm")
        mask = Image.new("L", (200, 200))
        ImageDraw.Draw(mask).rectangle((37, 69, 165, 125), fill=255)
        image.alpha_composite(Image.composite(layer, Image.new("RGBA", (200, 200)), mask))
        draw.arc((64, 131, 136, 147), 5, 175, fill="#8cbcff", width=3)
    elif index == 2:
        for j in range(3):
            row_q = max(0, min(1, (q - j * 0.12) / 0.76))
            offset = -sign * math.sin(row_q * math.pi) * 27 if moving else 0
            x, y = 50 + offset, 59 + j * 36
            draw.rounded_rectangle((x, y, x + 15, y + 15), 3, outline=ink, width=4)
            line([(x + 33, y + 7), (x + 95 - abs(offset) * 0.45, y + 7)])
    elif index == 3:
        inset = 9 * wave
        draw.rounded_rectangle((42 + inset, 56 + inset, 158 - inset, 142 - inset), 10, outline=ink, width=6)
        glyph = Image.new("RGBA", (200, 200))
        pen = ImageDraw.Draw(glyph)
        pen.text((100, 99), "HD", font=font(round(42 + 4 * wave), True), fill=ink, anchor="mm")
        image.alpha_composite(glyph)
    elif index == 4:
        draw.rounded_rectangle((43, 54, 157, 143), 11, outline=ink, width=6)
        for j, (x, y, length) in enumerate([(60, 76, 26), (98, 76, 28), (60, 101, 78), (60, 121, 59)]):
            factor = 1
            if moving:
                local = max(0, min(1, (q - j * 0.075) / 0.7))
                # 进入时笔画从短到长展开，退出时缩回后恢复默认标识。
                factor = (0.15 + 0.85 * ease(local)) if phase == "进入" else (1 - 0.85 * math.sin(local * math.pi))
            line([(x, y), (x + length * factor, y)], width=5)
    elif index == 5:
        tilt = sign * wave * 9
        left_y = 132 - wave * 19
        right_y = 118 + wave * 13
        draw.ellipse((49, left_y - 12, 77, left_y + 9), fill=ink)
        draw.ellipse((117, right_y - 12, 145, right_y + 9), fill=ink)
        line([(74, left_y), (74, 66 + tilt), (141, 51 - tilt), (141, right_y)], width=7)
        line([(76, 79 + tilt), (140, 64 - tilt)], width=8)
    else:
        gap = 12 * amount + 7 * wave
        for sx, sy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
            x, y = 100 + sx * (40 + gap), 100 + sy * (35 + gap)
            line([(x - sx * 23, y), (x, y), (x, y - sy * 23)], width=7)
    if amount > 0:
        color = (140, 190, 255, round(255 * amount))
        draw.rounded_rectangle((87, 170, 113, 174), 2, fill=color)
    return image


def centered(draw, text, x, y, size, color, bold=False):
    draw.text((x, y), text, font=font(size, bold), fill=color, anchor="mt")


def backdrop():
    image = Image.new("RGBA", (WIDTH, HEIGHT), "#10151d")
    draw = ImageDraw.Draw(image)
    draw.text((42, 30), "播放器图标 · 状态动效", font=font(26, True), fill="#eef3fa")
    draw.text((43, 72), "动的是图形本身：穿行、滚动、展开、聚焦、书写、跳动、扩展。", font=font(14), fill="#93a2b6")
    draw.rounded_rectangle((28, 130, 932, 304), 24, fill="#161e29", outline="#293647")
    draw.text((43, 329), "实际工具栏尺寸", font=font(15, True), fill="#bdc9d9")
    draw.rounded_rectangle((28, 362, 932, 448), 18, fill="#090d12", outline="#263241")
    draw.line((53, 380, 908, 380), fill="#334252", width=3)
    draw.line((53, 380, 344, 380), fill="#81b8f8", width=3)
    draw.text((44, 478), "弹幕：开启 / 关闭    ·    菜单：展开 / 收起    ·    全屏：进入 / 退出", font=font(14), fill="#a2b0c2")
    draw.text((44, 504), "动效方案预览 · 尚未接入播放器", font=font(12), fill="#65778e")
    return image


def render(t, sprites=None, all_state=None):
    image = backdrop()
    draw = ImageDraw.Draw(image)
    phase = "等待操作" if t < 0.8 else "图形展开" if t < 2.6 else "保持选中" if t < 4.5 else "图形收回" if t < 6.0 else "回到默认"
    draw.text((710, 48), phase, font=font(14), fill="#85baff")
    for i in range(7):
        amount, motion, q = state(t, i) if all_state is None else (all_state, "静止", 0)
        sprite = draw_icon(i, amount, motion, q)
        cx = 105 + i * 125
        size = 100
        image.alpha_composite(sprite.resize((size, size), Image.Resampling.LANCZOS), (cx - size // 2, 194 - size // 2))
        centered(draw, NAMES[i], cx, 263, 15, "#dae6f7" if amount > 0.5 else "#8d9aaf")
        if amount > 0:
            color = tuple(round(a + (b - a) * amount) for a, b in zip((22, 30, 41), (126, 184, 255)))
            draw.ellipse((cx - 2, 286, cx + 2, 290), fill=color)
        small_size = 42
        small_x = 493 + i * 64
        image.alpha_composite(sprite.resize((small_size, small_size), Image.Resampling.LANCZOS), (small_x - small_size // 2, 414 - small_size // 2))
    draw.polygon([(58, 402), (58, 426), (76, 414)], fill="#eaf2fc")
    draw.text((97, 403), "14:24 / 23:40", font=font(15), fill="#c5d2e3")
    return image.convert("RGB")


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    if SOURCE.exists():
        shutil.copyfile(SOURCE, ROOT / "source-atlas.png")
    sprites = None
    for i in range(7):
        for row in range(2):
            draw_icon(i, row).save(ROOT / f"icon-{i}-{'on' if row else 'off'}.png")
    # 先输出逐帧关键图，再把同一套绘制结果合成为循环动图。
    keyframes = Image.new("RGB", (1400, 800), "#10151d")
    for row, q in enumerate([0, 0.22, 0.5, 1]):
        for i in range(7):
            icon = draw_icon(i, ease(q), "进入", q)
            keyframes.paste(icon, (i * 200, row * 200), icon)
    keyframes.save(ROOT / "keyframes.png")
    comparison = Image.new("RGB", (WIDTH, HEIGHT * 2), "#10151d")
    comparison.paste(render(0, sprites, 0), (0, 0))
    comparison.paste(render(3.4, sprites, 1), (0, HEIGHT))
    comparison.save(ROOT / "states.png")
    frames = [render(i / FPS, sprites) for i in range(round(FPS * SECONDS))]
    frames[0].save(ROOT / "preview.webp", save_all=True, append_images=frames[1:], duration=[33, 33, 34] * (len(frames) // 3), loop=0, quality=85, method=4)
    gif_frames = [frame.quantize(colors=128) for frame in frames[::2]]
    gif_frames[0].save(ROOT / "preview.gif", save_all=True, append_images=gif_frames[1:], duration=[60, 70, 70] * (len(gif_frames) // 3), loop=0, disposal=2, optimize=False)
    render(1.72, sprites).save(ROOT / "motion-check.png")
    print(f"已生成 {len(frames)} 帧，{SECONDS} 秒，{FPS} fps。输出：{ROOT}")


if __name__ == "__main__":
    main()
