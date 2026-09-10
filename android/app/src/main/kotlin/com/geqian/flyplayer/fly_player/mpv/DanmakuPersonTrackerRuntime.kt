package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val PERSON_TRACKER_SAMPLE_WIDTH = 96
private const val PERSON_TRACKER_SAMPLE_HEIGHT = 54
private const val PERSON_TRACKER_TEMPLATE_WIDTH = 18
private const val PERSON_TRACKER_TEMPLATE_HEIGHT = 24
private const val PERSON_TRACKER_MIN_RECT_AREA = 0.012f
private const val PERSON_TRACKER_MIN_CONFIDENCE = 0.72f
private const val PERSON_TRACKER_TEMPLATE_BLEND_ALPHA = 0.18f
private const val PERSON_TRACKER_MAX_FAILURES = 2
private val PERSON_TRACKER_SCALE_STEPS = floatArrayOf(0.94f, 1f, 1.06f)

data class PersonTrackingResult(
    val success: Boolean,
    val rect: DanmakuNormalizedRect?,
    val confidence: Float,
    val source: String,
)

interface PersonTrackerRuntime : AutoCloseable {
    fun init(
        frameBitmap: Bitmap,
        normalizedRect: DanmakuNormalizedRect,
    ): Boolean

    fun update(frameBitmap: Bitmap): PersonTrackingResult

    fun reset()
}

class LumaTemplatePersonTrackerRuntime : PersonTrackerRuntime {
    private var template: FloatArray? = null
    private var lastRect: DanmakuNormalizedRect? = null
    private var consecutiveFailures = 0

    override fun init(
        frameBitmap: Bitmap,
        normalizedRect: DanmakuNormalizedRect,
    ): Boolean {
        val sanitizedRect = sanitizeRect(normalizedRect) ?: return false
        val luma = sampleBitmapLuma(frameBitmap)
        val nextTemplate =
            extractPatch(
                luma = luma,
                sourceWidth = PERSON_TRACKER_SAMPLE_WIDTH,
                sourceHeight = PERSON_TRACKER_SAMPLE_HEIGHT,
                rect = sanitizedRect,
            ) ?: return false
        template = nextTemplate
        lastRect = sanitizedRect
        consecutiveFailures = 0
        return true
    }

    override fun update(frameBitmap: Bitmap): PersonTrackingResult {
        val currentTemplate = template
        val previousRect = lastRect
        if (currentTemplate == null || previousRect == null) {
            return PersonTrackingResult(
                success = false,
                rect = null,
                confidence = 0f,
                source = "tracker_uninitialized",
            )
        }
        val luma = sampleBitmapLuma(frameBitmap)
        val previousRectInSamples =
            rectToSampleSpace(
                rect = previousRect,
                sampleWidth = PERSON_TRACKER_SAMPLE_WIDTH,
                sampleHeight = PERSON_TRACKER_SAMPLE_HEIGHT,
            )
        val halfSearchRadiusX =
            max(3, min(12, (previousRectInSamples.width * 0.42f).roundToInt()))
        val halfSearchRadiusY =
            max(3, min(10, (previousRectInSamples.height * 0.30f).roundToInt()))
        var bestRect: DanmakuNormalizedRect? = null
        var bestPatch: FloatArray? = null
        var bestConfidence = 0f

        for (scale in PERSON_TRACKER_SCALE_STEPS) {
            val scaledRect =
                rectFromCenter(
                    centerX = previousRect.centerX,
                    centerY = previousRect.centerY,
                    width = previousRect.width * scale,
                    height = previousRect.height * scale,
                ) ?: continue
            val scaledRectInSamples =
                rectToSampleSpace(
                    rect = scaledRect,
                    sampleWidth = PERSON_TRACKER_SAMPLE_WIDTH,
                    sampleHeight = PERSON_TRACKER_SAMPLE_HEIGHT,
                )
            for (dy in -halfSearchRadiusY..halfSearchRadiusY) {
                for (dx in -halfSearchRadiusX..halfSearchRadiusX) {
                    val candidateRect =
                        rectFromCenter(
                            centerX =
                                scaledRect.centerX +
                                    (dx.toFloat() / PERSON_TRACKER_SAMPLE_WIDTH.toFloat()),
                            centerY =
                                scaledRect.centerY +
                                    (dy.toFloat() / PERSON_TRACKER_SAMPLE_HEIGHT.toFloat()),
                            width = scaledRect.width,
                            height = scaledRect.height,
                        ) ?: continue
                    val candidatePatch =
                        extractPatch(
                            luma = luma,
                            sourceWidth = PERSON_TRACKER_SAMPLE_WIDTH,
                            sourceHeight = PERSON_TRACKER_SAMPLE_HEIGHT,
                            rect = candidateRect,
                        ) ?: continue
                    val confidence = computeConfidence(currentTemplate, candidatePatch)
                    if (confidence <= bestConfidence) {
                        continue
                    }
                    bestConfidence = confidence
                    bestRect = candidateRect
                    bestPatch = candidatePatch
                }
            }
        }

        val acceptedRect = bestRect?.takeIf { bestConfidence >= PERSON_TRACKER_MIN_CONFIDENCE }
        val acceptedPatch = bestPatch?.takeIf { acceptedRect != null }
        if (acceptedRect == null || acceptedPatch == null) {
            consecutiveFailures += 1
            if (consecutiveFailures >= PERSON_TRACKER_MAX_FAILURES) {
                reset()
            }
            return PersonTrackingResult(
                success = false,
                rect = bestRect,
                confidence = bestConfidence,
                source = "tracker_low_confidence",
            )
        }
        blendTemplate(currentTemplate, acceptedPatch)
        lastRect = acceptedRect
        consecutiveFailures = 0
        return PersonTrackingResult(
            success = true,
            rect = acceptedRect,
            confidence = bestConfidence,
            source = "tracker",
        )
    }

    override fun reset() {
        template = null
        lastRect = null
        consecutiveFailures = 0
    }

    override fun close() {
        reset()
    }

    private fun blendTemplate(
        target: FloatArray,
        patch: FloatArray,
    ) {
        val previousWeight = 1f - PERSON_TRACKER_TEMPLATE_BLEND_ALPHA
        for (index in target.indices) {
            target[index] =
                (target[index] * previousWeight) +
                    (patch[index] * PERSON_TRACKER_TEMPLATE_BLEND_ALPHA)
        }
    }

    private fun computeConfidence(
        baseline: FloatArray,
        candidate: FloatArray,
    ): Float {
        var totalDiff = 0f
        for (index in baseline.indices) {
            totalDiff += abs(baseline[index] - candidate[index])
        }
        val normalizedDiff =
            (totalDiff / baseline.size.toFloat())
                .coerceIn(0f, 255f) / 255f
        return (1f - normalizedDiff).coerceIn(0f, 1f)
    }

    private fun sampleBitmapLuma(bitmap: Bitmap): IntArray {
        val luma = IntArray(PERSON_TRACKER_SAMPLE_WIDTH * PERSON_TRACKER_SAMPLE_HEIGHT)
        val stepX = bitmap.width.toFloat() / PERSON_TRACKER_SAMPLE_WIDTH.toFloat()
        val stepY = bitmap.height.toFloat() / PERSON_TRACKER_SAMPLE_HEIGHT.toFloat()
        var index = 0
        for (sampleY in 0 until PERSON_TRACKER_SAMPLE_HEIGHT) {
            val bitmapY =
                ((sampleY + 0.5f) * stepY).toInt().coerceIn(0, bitmap.height - 1)
            for (sampleX in 0 until PERSON_TRACKER_SAMPLE_WIDTH) {
                val bitmapX =
                    ((sampleX + 0.5f) * stepX).toInt().coerceIn(0, bitmap.width - 1)
                val color = bitmap.getPixel(bitmapX, bitmapY)
                val red = android.graphics.Color.red(color)
                val green = android.graphics.Color.green(color)
                val blue = android.graphics.Color.blue(color)
                luma[index++] = ((red * 77) + (green * 150) + (blue * 29)) shr 8
            }
        }
        return luma
    }

    private fun extractPatch(
        luma: IntArray,
        sourceWidth: Int,
        sourceHeight: Int,
        rect: DanmakuNormalizedRect,
    ): FloatArray? {
        if (rect.area() < PERSON_TRACKER_MIN_RECT_AREA) {
            return null
        }
        val left = rect.left.coerceIn(0f, 1f) * (sourceWidth - 1).toFloat()
        val top = rect.top.coerceIn(0f, 1f) * (sourceHeight - 1).toFloat()
        val right = rect.right.coerceIn(0f, 1f) * (sourceWidth - 1).toFloat()
        val bottom = rect.bottom.coerceIn(0f, 1f) * (sourceHeight - 1).toFloat()
        if (right <= left || bottom <= top) {
            return null
        }
        val patch = FloatArray(PERSON_TRACKER_TEMPLATE_WIDTH * PERSON_TRACKER_TEMPLATE_HEIGHT)
        var index = 0
        for (y in 0 until PERSON_TRACKER_TEMPLATE_HEIGHT) {
            val sourceY =
                top + (((y + 0.5f) / PERSON_TRACKER_TEMPLATE_HEIGHT.toFloat()) * (bottom - top))
            for (x in 0 until PERSON_TRACKER_TEMPLATE_WIDTH) {
                val sourceX =
                    left + (((x + 0.5f) / PERSON_TRACKER_TEMPLATE_WIDTH.toFloat()) * (right - left))
                patch[index++] = sampleLuma(luma, sourceWidth, sourceHeight, sourceX, sourceY)
            }
        }
        return patch
    }

    private fun sampleLuma(
        values: IntArray,
        width: Int,
        height: Int,
        x: Float,
        y: Float,
    ): Float {
        val x0 = x.toInt().coerceIn(0, width - 1)
        val y0 = y.toInt().coerceIn(0, height - 1)
        val x1 = min(x0 + 1, width - 1)
        val y1 = min(y0 + 1, height - 1)
        val fx = (x - x0.toFloat()).coerceIn(0f, 1f)
        val fy = (y - y0.toFloat()).coerceIn(0f, 1f)
        val topLeft = values[(y0 * width) + x0].toFloat()
        val topRight = values[(y0 * width) + x1].toFloat()
        val bottomLeft = values[(y1 * width) + x0].toFloat()
        val bottomRight = values[(y1 * width) + x1].toFloat()
        val top = topLeft + ((topRight - topLeft) * fx)
        val bottom = bottomLeft + ((bottomRight - bottomLeft) * fx)
        return top + ((bottom - top) * fy)
    }

    private fun rectToSampleSpace(
        rect: DanmakuNormalizedRect,
        sampleWidth: Int,
        sampleHeight: Int,
    ): SampleRect =
        SampleRect(
            width = rect.width * sampleWidth.toFloat(),
            height = rect.height * sampleHeight.toFloat(),
        )

    private fun sanitizeRect(rect: DanmakuNormalizedRect): DanmakuNormalizedRect? {
        if (rect.area() < PERSON_TRACKER_MIN_RECT_AREA) {
            return null
        }
        return rectFromCenter(
            centerX = rect.centerX,
            centerY = rect.centerY,
            width = rect.width,
            height = rect.height,
        )
    }

    private fun rectFromCenter(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
    ): DanmakuNormalizedRect? {
        val safeWidth = width.coerceIn(0.04f, 0.92f)
        val safeHeight = height.coerceIn(0.08f, 0.96f)
        if (safeWidth <= 0f || safeHeight <= 0f) {
            return null
        }
        val maxLeft = (1f - safeWidth).coerceAtLeast(0f)
        val maxTop = (1f - safeHeight).coerceAtLeast(0f)
        return DanmakuNormalizedRect(
            x = (centerX - (safeWidth / 2f)).coerceIn(0f, maxLeft),
            y = (centerY - (safeHeight / 2f)).coerceIn(0f, maxTop),
            width = safeWidth,
            height = safeHeight,
        )
    }

    private data class SampleRect(
        val width: Float,
        val height: Float,
    )
}
