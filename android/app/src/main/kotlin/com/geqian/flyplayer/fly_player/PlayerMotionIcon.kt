package com.geqian.flyplayer.fly_player

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.view.animation.LinearInterpolator
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/** 图标语义一览：PLAY_PAUSE..VOLUME 与桌面一一对应，其余为安卓特有（同风格补绘）。 */
enum class PlayerMotionKind {
    PLAY_PAUSE,
    PREVIOUS,
    NEXT,
    DANMAKU,
    SPEED,
    EPISODES,
    EPISODE_GRID,
    QUALITY,
    SUBTITLE,
    AUDIO,
    LISTEN,
    FULLSCREEN,
    SPLIT,
    ROTATE,
    REPEAT,
    BOOKMARK,
    SCREENSHOT,
    SETTINGS,
    VOLUME,
    BACK,
    LOCK,
    LOCK_OPEN,
    PIP,
    DANMAKU_SETTINGS,
}

/**
 * 播放器动态图标：几何与动效同步自 lib/desktop/playback/desktop_player_motion_icon.dart
 * （200×200 坐标系、圆头笔画、420ms 进场 / 300ms 退场、easeOutCubic + sin(qπ) 波动、
 * 播放暂停形变从当前轮廓继续）。修改几何需双端同步。
 *
 * 透明图标只绘制笔画；状态切换时运行一次动画，静止时不保留动画帧回调。
 * 墨色自绘（常态 idleColor / 激活 selectedColor），外层 setColorFilter 对其无效。
 */
class PlayerMotionIconDrawable constructor(
    kind: PlayerMotionKind,
    label: String,
    selected: Boolean,
    private val idleColor: Int,
    private val selectedColor: Int,
    private val iconHeightPx: Int,
) : Drawable() {
    private var kind: PlayerMotionKind = kind
    private var label: String = label
    private var selected: Boolean = selected

    private var q = 1f
    private var entering = true
    private var playPauseFrom = if (label == "pause") 1f else 0f
    private var animator: ValueAnimator? = null

    private val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        strokeWidth = 6f
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
        fontFeatureSettings = "tnum"
    }
    private val linear = LinearInterpolator()

    /** 状态切换入口：任一字段变化才重启动画，运行中从当前轮廓继续（与桌面 didUpdateWidget 一致）。 */
    fun setIconState(
        kind: PlayerMotionKind = this.kind,
        label: String = this.label,
        selected: Boolean = this.selected,
    ) {
        val changed = kind != this.kind || label != this.label || selected != this.selected
        if (!changed) return
        if (this.kind == PlayerMotionKind.PLAY_PAUSE) {
            val oldTarget = if (this.label == "pause") 1f else 0f
            playPauseFrom += (oldTarget - playPauseFrom) * easeOutCubic(q)
        }
        entering = if (selected != this.selected) selected else true
        this.kind = kind
        this.label = label
        this.selected = selected
        runMotion()
    }

    /** 激活态切换（对应桌面 selected）：墨色变化并运行一次进/出场动画。 */
    fun setActive(selected: Boolean) = setIconState(selected = selected)

    private fun runMotion() {
        animator?.cancel()
        val next = ValueAnimator.ofFloat(0f, 1f)
        next.duration = if (entering) 420L else 300L
        next.interpolator = linear
        next.addUpdateListener { animation ->
            q = animation.animatedValue as Float
            invalidateSelf()
        }
        next.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                q = 1f
                invalidateSelf()
                if (animator === animation) animator = null
            }
        })
        animator = next
        next.start()
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return
        val ink = if (selected) selectedColor else idleColor
        pen.color = ink
        fillPaint.color = ink
        textPaint.color = ink
        val height = bounds.height().toFloat()
        val width = bounds.width().toFloat()
        val scale = height / 130f
        canvas.save()
        canvas.scale(scale, scale)
        canvas.translate((width * 130f / height - 200f) / 2f, -35f)
        paintIcon(canvas)
        canvas.restore()
    }

    private fun paintIcon(canvas: Canvas) {
        val wave = sin(q * PI).toFloat()
        val direction = if (entering) 1f else -1f
        when (kind) {
            PlayerMotionKind.PLAY_PAUSE -> paintPlayPause(canvas, wave)
            PlayerMotionKind.PREVIOUS, PlayerMotionKind.NEXT -> paintStep(canvas, wave, direction)
            PlayerMotionKind.BOOKMARK -> paintBookmark(canvas, wave)
            PlayerMotionKind.SCREENSHOT -> paintScreenshot(canvas, wave)
            PlayerMotionKind.SETTINGS -> paintSettings(canvas, direction)
            PlayerMotionKind.VOLUME -> paintVolume(canvas, wave)
            PlayerMotionKind.DANMAKU -> paintDanmaku(canvas, direction)
            PlayerMotionKind.SPEED -> paintSpeed(canvas, direction)
            PlayerMotionKind.EPISODES -> paintEpisodes(canvas, direction)
            PlayerMotionKind.EPISODE_GRID -> paintEpisodeGrid(canvas, direction)
            PlayerMotionKind.QUALITY -> paintQuality(canvas, wave)
            PlayerMotionKind.SUBTITLE -> paintSubtitle(canvas, direction)
            PlayerMotionKind.AUDIO, PlayerMotionKind.LISTEN -> paintAudioOrListen(canvas, wave, direction)
            PlayerMotionKind.FULLSCREEN -> paintFullscreen(canvas, wave)
            PlayerMotionKind.SPLIT -> paintSplit(canvas, wave, direction)
            PlayerMotionKind.ROTATE -> paintRotate(canvas, wave, direction)
            PlayerMotionKind.REPEAT -> paintRepeat(canvas, wave, direction)
            PlayerMotionKind.BACK -> paintBack(canvas, wave, direction)
            PlayerMotionKind.LOCK, PlayerMotionKind.LOCK_OPEN -> paintLock(canvas, wave, direction)
            PlayerMotionKind.PIP -> paintPip(canvas, direction)
            PlayerMotionKind.DANMAKU_SETTINGS -> paintDanmakuSettings(canvas, direction)
        }
    }

    // ---- 桌面移植（几何逐行对应 _MotionPainter，勿单独改动）----

    private fun paintPlayPause(canvas: Canvas, wave: Float) {
        val target = if (label == "pause") 1f else 0f
        val progress = playPauseFrom + (target - playPauseFrom) * easeOutCubic(q)
        canvas.save()
        canvas.translate(100f, 100f)
        val grow = 1f + 0.04f * wave
        canvas.scale(grow, grow)
        canvas.translate(-100f, -100f)
        for (half in 0..1) {
            val path = Path()
            for (point in 0..3) {
                val x = lerp(PLAY_POINTS[half][point][0], PAUSE_POINTS[half][point][0], progress)
                val y = lerp(PLAY_POINTS[half][point][1], PAUSE_POINTS[half][point][1], progress)
                if (point == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            path.close()
            canvas.drawPath(path, fillPaint)
        }
        canvas.restore()
    }

    private fun paintStep(canvas: Canvas, wave: Float, direction: Float) {
        canvas.save()
        if (kind == PlayerMotionKind.NEXT) {
            canvas.translate(200f, 0f)
            canvas.scale(-1f, 1f)
        }
        val shift = -direction * 9f * wave
        canvas.drawRoundRect(53f, 62f, 63f, 138f, 3f, 3f, fillPaint)
        val triangle = Path().apply {
            moveTo(77f + shift, 100f)
            lineTo(140f + shift, 62f)
            lineTo(140f + shift, 138f)
            close()
        }
        canvas.drawPath(triangle, fillPaint)
        canvas.restore()
    }

    private fun paintBookmark(canvas: Canvas, wave: Float) {
        val lift = 7f * wave
        val bookmark = Path().apply {
            moveTo(61f, 55f - lift)
            lineTo(113f, 55f - lift)
            lineTo(113f, 146f - lift)
            lineTo(87f, 130f - lift)
            lineTo(61f, 146f - lift)
            close()
        }
        canvas.drawPath(bookmark, pen)
        val arm = 12f + 6f * wave
        line(canvas, 140f - arm, 75f, 140f + arm, 75f)
        line(canvas, 140f, 75f - arm, 140f, 75f + arm)
    }

    private fun paintScreenshot(canvas: Canvas, wave: Float) {
        val body = Path().apply {
            moveTo(49f, 67f)
            lineTo(73f, 67f)
            lineTo(82f, 52f)
            lineTo(118f, 52f)
            lineTo(127f, 67f)
            lineTo(151f, 67f)
            quadTo(157f, 67f, 157f, 74f)
            lineTo(157f, 140f)
            quadTo(157f, 146f, 150f, 146f)
            lineTo(50f, 146f)
            quadTo(43f, 146f, 43f, 140f)
            lineTo(43f, 74f)
            quadTo(43f, 67f, 49f, 67f)
            close()
        }
        canvas.drawPath(body, pen)
        canvas.drawCircle(100f, 105f, 25f - 10f * wave, pen)
        canvas.drawCircle(139f, 80f, 3f, fillPaint)
    }

    private fun paintSettings(canvas: Canvas, direction: Float) {
        canvas.save()
        canvas.translate(100f, 100f)
        // 八齿齿轮转过一个齿距，终点与静止轮廓重合，退出时反转。
        canvas.rotate(direction * easeOutCubic(q) * 45f)
        val gear = Path()
        for (tooth in 0 until 8) {
            for (point in 0 until 4) {
                val angle = (tooth + point / 4.0) * PI / 4
                val radius = if (point == 1 || point == 2) 50.0 else 39.0
                val x = radius * cos(angle)
                val y = radius * sin(angle)
                if (tooth == 0 && point == 0) gear.moveTo(x.toFloat(), y.toFloat()) else gear.lineTo(x.toFloat(), y.toFloat())
            }
        }
        gear.close()
        canvas.drawPath(gear, pen)
        canvas.drawCircle(0f, 0f, 17f, pen)
        canvas.restore()
    }

    private fun paintVolume(canvas: Canvas, wave: Float) {
        val speaker = Path().apply {
            moveTo(47f, 85f)
            lineTo(69f, 85f)
            lineTo(96f, 63f)
            lineTo(96f, 137f)
            lineTo(69f, 115f)
            lineTo(47f, 115f)
            close()
        }
        canvas.drawPath(speaker, pen)
        if (label == "muted") {
            val arm = 12f + 4f * wave
            line(canvas, 132f - arm, 100f - arm, 132f + arm, 100f + arm)
            line(canvas, 132f - arm, 100f + arm, 132f + arm, 100f - arm)
        } else {
            val arcs = if (label == "low") 1 else 2
            val start = Math.toDegrees((-0.75 - 0.15 * wave).toDouble()).toFloat()
            val sweep = Math.toDegrees((1.5 + 0.3 * wave).toDouble()).toFloat()
            for (i in 0 until arcs) {
                val radius = 30f + i * 22f + (i + 1) * 3f * wave
                canvas.drawArc(96f - radius, 100f - radius, 96f + radius, 100f + radius, start, sweep, false, pen)
            }
        }
    }

    private fun paintDanmaku(canvas: Canvas, direction: Float) {
        screen(canvas)
        canvas.save()
        canvas.clipRect(54f, 65f, 146f, 134f)
        val origins = floatArrayOf(59f, 99f, 62f)
        val lengths = floatArrayOf(39f, 38f, 51f)
        for (j in 0 until 3) {
            val raw = (origins[j] - 53f - direction * q * 120f) % 120f
            val x = 53f + (if (raw < 0f) raw + 120f else raw)
            for (offset in floatArrayOf(-120f, 0f, 120f)) {
                line(canvas, x + offset, 79f + j * 22f, x + offset + lengths[j], 79f + j * 22f)
            }
        }
        canvas.restore()
    }

    private fun paintSpeed(canvas: Canvas, direction: Float) {
        canvas.save()
        canvas.clipRect(10f, 65f, 190f, 133f)
        val dy = direction * easeOutCubic(q) * 72f
        // 桌面用 50 号字（28px 图标），20dp 下照搬只有约 8dp 高、比原 13sp 文字小一截，
        // 安卓端放大到 72 号使数字约 11dp，滚动间距 72 单位仍够两行错位。
        text(canvas, label, 99f - dy, 72f)
        text(canvas, label, 99f - dy + direction * 72f, 72f)
        canvas.restore()
    }

    private fun paintEpisodes(canvas: Canvas, direction: Float) {
        for (j in 0 until 3) {
            val local = ((q - j * 0.12f) / 0.76f).coerceIn(0f, 1f)
            val offset = -direction * sin(local * PI).toFloat() * 27f
            val x = 50f + offset
            val y = 59f + j * 36f
            pen.strokeWidth = 4f
            canvas.drawRoundRect(x, y, x + 15f, y + 15f, 3f, 3f, pen)
            line(canvas, x + 33f, y + 7f, x + 95f - abs(offset) * 0.45f, y + 7f)
        }
    }

    /** 行→宫格切换钮用：2×3 方格，随动画逐格弹现。 */
    private fun paintEpisodeGrid(canvas: Canvas, direction: Float) {
        for (row in 0 until 2) {
            for (col in 0 until 3) {
                val index = row * 3 + col
                val local = ((q - index * 0.06f) / 0.7f).coerceIn(0f, 1f)
                val factor = if (entering) {
                    0.2f + 0.8f * easeOutCubic(local)
                } else {
                    1f - 0.8f * sin(local * PI).toFloat()
                }
                val x = 52f + col * 34f
                val y = 70f + row * 38f
                val half = 14f * factor
                pen.strokeWidth = 5f
                canvas.drawRoundRect(x + 14f - half, y + 14f - half, x + 14f + half, y + 14f + half, 4f, 4f, pen)
            }
        }
    }

    private fun paintQuality(canvas: Canvas, wave: Float) {
        screen(canvas, 9f * wave)
        text(canvas, "HD", 99f, 45f + 4f * wave)
    }

    private fun paintSubtitle(canvas: Canvas, direction: Float) {
        screen(canvas)
        val strokes = arrayOf(
            floatArrayOf(60f, 76f, 26f),
            floatArrayOf(98f, 76f, 28f),
            floatArrayOf(60f, 101f, 78f),
            floatArrayOf(60f, 121f, 59f),
        )
        for (j in strokes.indices) {
            val stroke = strokes[j]
            val local = ((q - j * 0.075f) / 0.7f).coerceIn(0f, 1f)
            val factor = if (entering) {
                0.15f + 0.85f * easeOutCubic(local)
            } else {
                1f - 0.85f * sin(local * PI).toFloat()
            }
            line(canvas, stroke[0], stroke[1], stroke[0] + stroke[2] * factor, stroke[1], 5f)
        }
    }

    private fun paintAudioOrListen(canvas: Canvas, wave: Float, direction: Float) {
        if (kind == PlayerMotionKind.LISTEN) {
            screen(canvas)
            canvas.save()
            canvas.translate(100f, 100f)
            canvas.scale(0.55f, 0.55f)
            canvas.translate(-100f, -100f)
            paintHeadphones(canvas, wave, direction)
            canvas.restore()
        } else {
            paintHeadphones(canvas, wave, direction)
        }
    }

    private fun paintHeadphones(canvas: Canvas, wave: Float, direction: Float) {
        val tilt = direction * wave * 9f
        val left = 132f - wave * 19f
        val right = 118f + wave * 13f
        canvas.drawOval(49f, left - 12f, 77f, left + 9f, fillPaint)
        canvas.drawOval(117f, right - 12f, 145f, right + 9f, fillPaint)
        pen.strokeWidth = 7f
        val band = Path().apply {
            moveTo(74f, left)
            lineTo(74f, 66f + tilt)
            lineTo(141f, 51f - tilt)
            lineTo(141f, right)
        }
        canvas.drawPath(band, pen)
        line(canvas, 76f, 79f + tilt, 140f, 64f - tilt, 8f)
    }

    private fun paintFullscreen(canvas: Canvas, wave: Float) {
        val amount = if (selected) 12f else 0f
        val gap = amount + 7f * wave
        pen.strokeWidth = 7f
        for (sx in intArrayOf(-1, 1)) {
            for (sy in intArrayOf(-1, 1)) {
                val x = 100f + sx * (40f + gap)
                val y = 100f + sy * (35f + gap)
                val corner = Path().apply {
                    moveTo(x - sx * 23f, y)
                    lineTo(x, y)
                    lineTo(x, y - sy * 23f)
                }
                canvas.drawPath(corner, pen)
            }
        }
    }

    /**
     * AB 循环：双弧 + 实心箭头 + 大号 A/AB 字样。
     * 桌面同款几何在 20dp 下弧线与 35 号文字糊成一片，此处按手机尺寸加重设计
     * （笔画 8、字号 52、实心三角箭头），桌面端如需对齐可反向同步。
     */
    private fun paintRepeat(canvas: Canvas, wave: Float, direction: Float) {
        canvas.save()
        canvas.translate(100f, 99f)
        canvas.rotate(direction * wave * 10f)
        canvas.translate(-100f, -99f)
        pen.strokeWidth = 8f
        canvas.drawPath(
            Path().apply {
                moveTo(42f, 96f)
                cubicTo(42f, 62f, 70f, 50f, 100f, 50f)
                lineTo(138f, 50f)
            },
            pen,
        )
        canvas.drawPath(
            Path().apply { moveTo(136f, 36f); lineTo(156f, 50f); lineTo(136f, 64f); close() },
            fillPaint,
        )
        canvas.drawPath(
            Path().apply {
                moveTo(158f, 102f)
                cubicTo(158f, 136f, 130f, 150f, 100f, 150f)
                lineTo(62f, 150f)
            },
            pen,
        )
        canvas.drawPath(
            Path().apply { moveTo(64f, 136f); lineTo(44f, 150f); lineTo(64f, 164f); close() },
            fillPaint,
        )
        text(canvas, if (label == "A") "A" else "AB", 99f, 52f)
        canvas.restore()
    }

    // ---- 安卓特有（同风格新绘：200 坐标系、同笔画参数）----

    private fun paintBack(canvas: Canvas, wave: Float, direction: Float) {
        val shift = -direction * 10f * wave
        line(canvas, 114f + shift, 62f, 74f + shift, 100f)
        line(canvas, 74f + shift, 100f, 114f + shift, 138f)
        line(canvas, 74f + shift, 100f, 150f + shift, 100f, 7f)
    }

    private fun paintLock(canvas: Canvas, wave: Float, direction: Float) {
        val shackleY = -direction * wave * 6f
        canvas.drawRoundRect(66f, 97f, 134f, 148f, 10f, 10f, pen)
        pen.strokeWidth = 6f
        if (kind == PlayerMotionKind.LOCK) {
            canvas.drawArc(78f, 51f + shackleY, 122f, 95f + shackleY, 180f, 180f, false, pen)
        } else {
            // 开锁：锁环右端悬空（弧止于 315°）。
            canvas.drawArc(78f, 51f + shackleY, 122f, 95f + shackleY, 180f, 135f, false, pen)
        }
        canvas.drawCircle(100f, 122f, 6f, fillPaint)
    }

    private fun paintPip(canvas: Canvas, direction: Float) {
        screen(canvas)
        val slide = direction * (1f - easeOutCubic(q))
        canvas.drawRoundRect(101f - 44f * slide, 99f - 26f * slide, 145f - 44f * slide, 129f - 26f * slide, 5f, 5f, fillPaint)
    }

    private fun paintSplit(canvas: Canvas, wave: Float, direction: Float) {
        val gap = direction * wave * 6f
        canvas.drawRoundRect(46f - gap, 62f, 96f - gap, 138f, 11f, 11f, pen)
        canvas.drawRoundRect(104f + gap, 62f, 154f + gap, 138f, 11f, 11f, pen)
        canvas.drawRoundRect(67f - gap, 90f, 76f - gap, 110f, 2f, 2f, fillPaint)
        canvas.drawRoundRect(125f + gap, 90f, 134f + gap, 110f, 2f, 2f, fillPaint)
    }

    private fun paintRotate(canvas: Canvas, wave: Float, direction: Float) {
        canvas.save()
        canvas.translate(100f, 100f)
        canvas.rotate(direction * wave * 17f)
        canvas.translate(-100f, -100f)
        val phone = Path().apply {
            moveTo(100f, 62f)
            lineTo(138f, 100f)
            lineTo(100f, 138f)
            lineTo(62f, 100f)
            close()
        }
        canvas.drawPath(phone, pen)
        pen.strokeWidth = 6f
        canvas.drawArc(36f, 36f, 164f, 164f, -90f, 55f, false, pen)
        canvas.drawArc(36f, 36f, 164f, 164f, 90f, 55f, false, pen)
        line(canvas, 152f, 63f, 141f, 61f, 6f)
        line(canvas, 152f, 63f, 150f, 74f, 6f)
        line(canvas, 48f, 137f, 59f, 139f, 6f)
        line(canvas, 48f, 137f, 50f, 126f, 6f)
        canvas.restore()
    }

    private fun paintDanmakuSettings(canvas: Canvas, direction: Float) {
        canvas.drawRoundRect(45f, 60f, 155f, 128f, 12f, 12f, pen)
        val tail = Path().apply {
            moveTo(70f, 127f)
            lineTo(62f, 143f)
            lineTo(90f, 127f)
        }
        canvas.drawPath(tail, pen)
        for (j in 0 until 3) {
            val local = ((q - j * 0.12f) / 0.76f).coerceIn(0f, 1f)
            val rise = sin(local * PI).toFloat() * 8f * direction
            canvas.drawCircle(75f + j * 25f, 94f - rise, 5.5f, fillPaint)
        }
    }

    // ---- 公共笔画 ----

    private fun line(canvas: Canvas, x: Float, y: Float, endX: Float, endY: Float, width: Float = 6f) {
        pen.strokeWidth = width
        canvas.drawLine(x, y, endX, endY, pen)
    }

    /** 桌面 `screen()`：圆角屏框，可选内缩。 */
    private fun screen(canvas: Canvas, inset: Float = 0f) {
        pen.strokeWidth = 6f
        canvas.drawRoundRect(43f + inset, 54f + inset, 157f - inset, 143f - inset, 11f, 11f, pen)
    }

    /** 桌面 `text()`：以 (100, y) 为中心绘制粗体表格数字。 */
    private fun text(canvas: Canvas, value: String, y: Float, fontSize: Float) {
        textPaint.textSize = fontSize
        val metrics = textPaint.fontMetrics
        canvas.drawText(value, 100f, y - (metrics.ascent + metrics.descent) / 2f, textPaint)
    }

    override fun getIntrinsicWidth(): Int =
        (iconHeightPx * (if (kind == PlayerMotionKind.SPEED) 44f / 28f else 1f)).toInt().coerceAtLeast(1)

    override fun getIntrinsicHeight(): Int = iconHeightPx.coerceAtLeast(1)

    // 墨色自绘：外部 alpha/filter 不介入（视图级透明度仍由 View.alpha 生效）。
    override fun setAlpha(alpha: Int) = Unit

    override fun setColorFilter(colorFilter: ColorFilter?) = Unit

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    private companion object {
        // 播放/暂停形变端点，同步自桌面 play/pause 数组。
        val PLAY_POINTS = arrayOf(
            arrayOf(floatArrayOf(68f, 58f), floatArrayOf(106f, 80f), floatArrayOf(106f, 120f), floatArrayOf(68f, 142f)),
            arrayOf(floatArrayOf(106f, 80f), floatArrayOf(145f, 100f), floatArrayOf(145f, 100f), floatArrayOf(106f, 120f)),
        )
        val PAUSE_POINTS = arrayOf(
            arrayOf(floatArrayOf(68f, 58f), floatArrayOf(88f, 58f), floatArrayOf(88f, 142f), floatArrayOf(68f, 142f)),
            arrayOf(floatArrayOf(116f, 58f), floatArrayOf(138f, 58f), floatArrayOf(138f, 142f), floatArrayOf(116f, 142f)),
        )

        fun easeOutCubic(t: Float): Float {
            val remain = 1f - t
            return 1f - remain * remain * remain
        }

        fun lerp(from: Float, to: Float, progress: Float): Float = from + (to - from) * progress
    }
}

/** 按密度生成图标 drawable；heightDp 控制渲染尺寸（20dp 常规 / 24dp 播放暂停）。 */
fun playerMotionIcon(
    context: Context,
    kind: PlayerMotionKind,
    label: String = "",
    selected: Boolean = false,
    idleColor: Int = Color.WHITE,
    selectedColor: Int = Color.WHITE,
    heightDp: Float = 20f,
): PlayerMotionIconDrawable = PlayerMotionIconDrawable(
    kind = kind,
    label = label,
    selected = selected,
    idleColor = idleColor,
    selectedColor = selectedColor,
    iconHeightPx = (heightDp * context.resources.displayMetrics.density).toInt().coerceAtLeast(1),
)
