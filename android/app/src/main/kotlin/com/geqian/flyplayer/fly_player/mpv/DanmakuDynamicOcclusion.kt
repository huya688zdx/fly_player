package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.TextureView
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

private const val DANMAKU_AI_TAG = "FlyPlayerDanmakuAI"
private const val DANMAKU_AI_PADDLE_MODEL_ASSET_DIR = "models/pp_humansegv2_lite"
private const val DANMAKU_AI_DEFAULT_SAMPLE_INTERVAL_MS = 500L
private const val DANMAKU_AI_DEFAULT_INPUT_WIDTH = 256
private const val DANMAKU_AI_DEFAULT_INPUT_HEIGHT = 144
private const val DANMAKU_AI_DEFAULT_SAMPLE_AREA_RATIO = 1.0f
private const val DANMAKU_AI_MASK_THRESHOLD = 0.18f
private const val DANMAKU_AI_RECT_HELPER_THRESHOLD = 0.30f
private const val DANMAKU_AI_MASK_SOFT_EDGE_START = 0.08f
private const val DANMAKU_AI_MASK_SOLID_CORE_START = 0.42f
private const val DANMAKU_AI_OUTPUT_MASK_HARD_THRESHOLD = 0.58f
private const val DANMAKU_AI_OUTPUT_MASK_KEEP_THRESHOLD = 0.44f
private const val DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS = 1
private const val DANMAKU_AI_MIN_FOREGROUND_RATIO = 0.010f
private const val DANMAKU_AI_SUBJECT_MIN_FILL_RATIO = 0.18f
private const val DANMAKU_AI_SUBJECT_MIN_ASPECT_RATIO = 0.22f
private const val DANMAKU_AI_SUBJECT_MAX_SPARSE_AREA_RATIO = 0.55f
private const val DANMAKU_AI_SUBJECT_MAX_SPARSE_HEIGHT_RATIO = 0.72f
private const val DANMAKU_AI_MASK_SHAPE_MIN_CORE_FILL_RATIO = 0.24f
private const val DANMAKU_AI_MASK_SHAPE_MIN_ERODED_RATIO = 0.30f
private const val DANMAKU_AI_MASK_SHAPE_EROSION_RADIUS = 1
private const val DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_WIDTH_RATIO = 0.20f
private const val DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_HEIGHT_RATIO = 0.52f
private const val DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO = 2.35f
private const val DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_AREA_RATIO = 0.12f
private const val DANMAKU_AI_MASK_SHAPE_MAX_TAPERED_SIDE_RATIO = 0.42f
private const val DANMAKU_AI_AMBIGUOUS_COMPONENT_MIN_PIXELS = 96
private const val DANMAKU_AI_AMBIGUOUS_SECOND_COMPONENT_RATIO = 0.42f
private const val DANMAKU_AI_AMBIGUOUS_MULTI_COMPONENT_COUNT = 3
private const val DANMAKU_AI_AMBIGUOUS_LARGEST_FOREGROUND_SHARE = 0.68f
private const val DANMAKU_AI_MAX_EMPTY_FRAMES = 1
private const val DANMAKU_AI_EMPTY_RESULT_HOLD_FRAMES = 1
private const val DANMAKU_AI_OVER_BUDGET_LIMIT = 3
private const val DANMAKU_AI_MASK_SMOOTHING_ALPHA = 0.55f
private const val DANMAKU_AI_RECT_SMOOTHING_ALPHA = 0.38f
private const val DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU = 0.18f
private const val DANMAKU_AI_SCENE_CUT_SAMPLE_WIDTH = 32
private const val DANMAKU_AI_SCENE_CUT_SAMPLE_HEIGHT = 18
private const val DANMAKU_AI_SCENE_CUT_AVERAGE_DELTA_THRESHOLD = 22.0
private const val DANMAKU_AI_SCENE_CUT_CHANGED_PIXEL_DELTA = 32
private const val DANMAKU_AI_SCENE_CUT_CHANGED_RATIO_THRESHOLD = 0.32
private const val DANMAKU_AI_SCENE_CUT_BURST_INTERVAL_MS = 180L
private const val DANMAKU_AI_SCENE_CUT_BURST_SAMPLE_COUNT = 3
private const val DANMAKU_AI_SCENE_CUT_STABLE_MASK_FRAMES = 2
private const val DANMAKU_AI_MOTION_SAMPLE_WIDTH = 48
private const val DANMAKU_AI_MOTION_SAMPLE_HEIGHT = 27
private const val DANMAKU_AI_MOTION_ROI_EXPAND_HORIZONTAL_RATIO = 0.45f
private const val DANMAKU_AI_MOTION_ROI_EXPAND_VERTICAL_RATIO = 0.40f
private const val DANMAKU_AI_MOTION_FALLBACK_CENTER_WIDTH_RATIO = 0.34f
private const val DANMAKU_AI_MOTION_FALLBACK_CENTER_HEIGHT_RATIO = 0.34f
private const val DANMAKU_AI_MOTION_MIN_RECT_AREA = 0.018f
private const val DANMAKU_AI_MOTION_SEARCH_RADIUS_PX = 4
private const val DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO = 0.22f
private const val DANMAKU_AI_MOTION_MAX_AVERAGE_DELTA = 22.0
private const val DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES = 48
private const val DANMAKU_AI_MOTION_MAX_FAILURES = 3
private const val DANMAKU_AI_MOTION_GATE_MIN_IOU = 0.45f
private const val DANMAKU_AI_MOTION_GATE_MAX_DX_NORMALIZED = 0.06f
private const val DANMAKU_AI_MOTION_GATE_MAX_DY_NORMALIZED = 0.04f
private const val DANMAKU_AI_MOTION_GATE_MIN_AREA_RATIO = 0.85f
private const val DANMAKU_AI_MOTION_GATE_MAX_AREA_RATIO = 1.15f
private const val DANMAKU_AI_MOTION_GATE_MAX_AVERAGE_DELTA = 18.0
private const val DANMAKU_AI_MOTION_MAX_CONSECUTIVE_COMPENSATED_FRAMES = 2
private const val DANMAKU_AI_CACHE_DIR_NAME = "danmaku_ai_cache"
private const val DANMAKU_AI_CACHE_VERSION = 5
private const val DANMAKU_AI_CACHE_STATE_FILE_NAME = "state.json"
private const val DANMAKU_AI_CACHE_FRAME_FILE_NAME = "frame.webp"
private const val DANMAKU_AI_CACHE_MASK_FILE_NAME = "mask.webp"
private const val DANMAKU_AI_CACHE_FRAME_WRITE_INTERVAL_MS = 4000L
private const val DANMAKU_AI_CACHE_WARM_START_DELAY_MS = 2500L
private const val DANMAKU_AI_CAPTURE_SLOW_LOG_THRESHOLD_MS = 24L
private const val DANMAKU_AI_INFERENCE_SLOW_LOG_THRESHOLD_MS = 90L
private const val DANMAKU_AI_TOTAL_SLOW_LOG_THRESHOLD_MS = 120L

enum class DanmakuAiBackend(val wireValue: String) {
    PADDLE("paddle"),
    GPU("gpu"),
    CPU("cpu"),
    DISABLED("disabled"),
    ;

    companion object {
        fun fromValue(raw: String?): DanmakuAiBackend? {
            val normalized = raw?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it.wireValue == normalized }
        }
    }
}

data class DanmakuNormalizedRect(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
) {
    val left: Float
        get() = x

    val top: Float
        get() = y

    val right: Float
        get() = (x + width).coerceIn(0f, 1f)

    val bottom: Float
        get() = (y + height).coerceIn(0f, 1f)

    fun area(): Float = width.coerceAtLeast(0f) * height.coerceAtLeast(0f)

    fun iou(other: DanmakuNormalizedRect): Float {
        val intersectLeft = maxOf(left, other.left)
        val intersectTop = maxOf(top, other.top)
        val intersectRight = minOf(right, other.right)
        val intersectBottom = minOf(bottom, other.bottom)
        val intersectWidth = (intersectRight - intersectLeft).coerceAtLeast(0f)
        val intersectHeight = (intersectBottom - intersectTop).coerceAtLeast(0f)
        val intersection = intersectWidth * intersectHeight
        if (intersection <= 0f) {
            return 0f
        }
        val union = area() + other.area() - intersection
        return if (union <= 0f) 0f else (intersection / union).coerceIn(0f, 1f)
    }

    fun expanded(horizontalRatio: Float, verticalRatio: Float): DanmakuNormalizedRect {
        val expandX = width * horizontalRatio
        val expandY = height * verticalRatio
        val left = (x - (expandX / 2f)).coerceIn(0f, 1f)
        val top = (y - (expandY / 2f)).coerceIn(0f, 1f)
        val right = (x + width + (expandX / 2f)).coerceIn(0f, 1f)
        val bottom = (y + height + (expandY / 2f)).coerceIn(0f, 1f)
        return DanmakuNormalizedRect(
            x = left,
            y = top,
            width = (right - left).coerceAtLeast(0f),
            height = (bottom - top).coerceAtLeast(0f),
        )
    }

    fun lerp(target: DanmakuNormalizedRect, alpha: Float): DanmakuNormalizedRect {
        val clampedAlpha = alpha.coerceIn(0f, 1f)

        fun mix(start: Float, end: Float): Float = start + ((end - start) * clampedAlpha)

        return DanmakuNormalizedRect(
            x = mix(x, target.x).coerceIn(0f, 1f),
            y = mix(y, target.y).coerceIn(0f, 1f),
            width = mix(width, target.width).coerceIn(0f, 1f),
            height = mix(height, target.height).coerceIn(0f, 1f),
        )
    }

    fun toMap(): Map<String, Double> {
        return mapOf(
            "x" to x.toDouble(),
            "y" to y.toDouble(),
            "width" to width.toDouble(),
            "height" to height.toDouble(),
        )
    }
}

data class DanmakuDynamicOcclusionState(
    val enabled: Boolean,
    val available: Boolean,
    val backend: String,
    val updatedAtMs: Long,
    val maskPath: String?,
    val maskWidth: Int,
    val maskHeight: Int,
    val framePath: String?,
    val cacheHit: Boolean,
    val normalizedRect: DanmakuNormalizedRect?,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "enabled" to enabled,
            "available" to available,
            "backend" to backend,
            "updatedAtMs" to updatedAtMs,
            "maskPath" to maskPath,
            "maskWidth" to maskWidth,
            "maskHeight" to maskHeight,
            "framePath" to framePath,
            "cacheHit" to cacheHit,
            "normalizedRect" to normalizedRect?.toMap(),
        )
    }

    companion object {
        fun disabled(): DanmakuDynamicOcclusionState {
            return DanmakuDynamicOcclusionState(
                enabled = false,
                available = false,
                backend = DanmakuAiBackend.DISABLED.wireValue,
                updatedAtMs = 0L,
                maskPath = null,
                maskWidth = 0,
                maskHeight = 0,
                framePath = null,
                cacheHit = false,
                normalizedRect = null,
            )
        }
    }
}

data class DanmakuDynamicOcclusionConfig(
    val enabled: Boolean,
    val sampleIntervalMs: Long,
    val preferredBackendOrder: List<DanmakuAiBackend>,
    val inputWidth: Int,
    val inputHeight: Int,
    val sampleAreaRatio: Float,
) {
    companion object {
        val defaults =
            DanmakuDynamicOcclusionConfig(
                enabled = false,
                sampleIntervalMs = DANMAKU_AI_DEFAULT_SAMPLE_INTERVAL_MS,
                preferredBackendOrder =
                    listOf(
                        DanmakuAiBackend.PADDLE,
                    ),
                inputWidth = DANMAKU_AI_DEFAULT_INPUT_WIDTH,
                inputHeight = DANMAKU_AI_DEFAULT_INPUT_HEIGHT,
                sampleAreaRatio = DANMAKU_AI_DEFAULT_SAMPLE_AREA_RATIO,
            )

        fun fromMap(raw: Map<String, Any?>): DanmakuDynamicOcclusionConfig {
            val preferredBackendOrder =
                (raw["preferredBackendOrder"] as? List<*>)
                    ?.mapNotNull { DanmakuAiBackend.fromValue(it?.toString()) }
                    ?.filter { it == DanmakuAiBackend.PADDLE }
                    ?.distinct()
                    ?.takeIf { it.isNotEmpty() }
                    ?: defaults.preferredBackendOrder
            return DanmakuDynamicOcclusionConfig(
                enabled = raw["enabled"] == true,
                sampleIntervalMs =
                    (raw["sampleIntervalMs"]?.toLongValue() ?: defaults.sampleIntervalMs)
                        .coerceIn(200L, 500L),
                preferredBackendOrder = preferredBackendOrder,
                inputWidth =
                    (raw["inputWidth"]?.toIntValue() ?: defaults.inputWidth).coerceIn(64, 512),
                inputHeight =
                    (raw["inputHeight"]?.toIntValue() ?: defaults.inputHeight).coerceIn(64, 512),
                sampleAreaRatio =
                    ((raw["sampleAreaRatio"]?.toDoubleValue()?.toFloat())
                        ?: defaults.sampleAreaRatio)
                        .coerceIn(0.1f, 1.0f),
            )
        }
    }
}

private data class DanmakuMaskResult(
    val maskValues: FloatArray,
    val maskWidth: Int,
    val maskHeight: Int,
    val normalizedRect: DanmakuNormalizedRect?,
)

private data class DanmakuFrameContinuity(
    val sceneCut: Boolean,
    val signature: IntArray,
)

private data class DanmakuMotionRoi(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int
        get() = (right - left + 1).coerceAtLeast(0)

    val height: Int
        get() = (bottom - top + 1).coerceAtLeast(0)

    val area: Int
        get() = width * height
}

private data class DanmakuMotionReferenceFrame(
    val lumaSamples: IntArray,
    val sampleWidth: Int,
    val sampleHeight: Int,
    val normalizedRect: DanmakuNormalizedRect,
    val timestampMs: Long,
)

private data class DanmakuMotionCompensation(
    val dxSamplePx: Int,
    val dySamplePx: Int,
    val dxMaskPx: Int,
    val dyMaskPx: Int,
    val dxNormalized: Float,
    val dyNormalized: Float,
    val score: Double,
)

private data class InferenceOutcome(
    val maskResult: DanmakuMaskResult?,
    val motionLumaSamples: IntArray,
    val motionSampleWidth: Int,
    val motionSampleHeight: Int,
    val motionCompensation: DanmakuMotionCompensation?,
    val motionCompensationAttempted: Boolean,
)

private data class DanmakuCapturedFrame(
    val bitmap: Bitmap,
    val sampleAreaRatio: Float,
)

private data class DanmakuMaskExtraction(
    val maskResult: DanmakuMaskResult,
    val appliedMotionCompensation: DanmakuMotionCompensation?,
)

private data class DanmakuPrimaryComponent(
    val rect: DanmakuNormalizedRect,
    val pixelCount: Int,
    val fillRatio: Float,
)

private data class DanmakuPrimaryMaskComponent(
    val maskValues: FloatArray,
    val component: DanmakuPrimaryComponent,
)

private data class DanmakuForegroundComplexity(
    val significantComponentCount: Int,
    val largestPixelCount: Int,
    val secondLargestPixelCount: Int,
    val totalForegroundPixels: Int,
)

private data class DanmakuOcclusionCacheEntry(
    val backend: String,
    val updatedAtMs: Long,
    val maskPath: String,
    val maskWidth: Int,
    val maskHeight: Int,
    val framePath: String?,
    val normalizedRect: DanmakuNormalizedRect?,
)

private class DanmakuOcclusionCacheStore(
    private val context: Context,
) {
    fun load(source: MpvSource): DanmakuOcclusionCacheEntry? {
        val directory = entryDirectory(source)
        val stateFile = File(directory, DANMAKU_AI_CACHE_STATE_FILE_NAME)
        if (!stateFile.isFile) {
            return null
        }
        return runCatching {
            val json = JSONObject(stateFile.readText())
            if (json.optInt("cacheVersion", 0) != DANMAKU_AI_CACHE_VERSION) {
                return null
            }
            val maskFile = File(directory, DANMAKU_AI_CACHE_MASK_FILE_NAME)
            if (!maskFile.isFile || maskFile.length() <= 0L) {
                return null
            }
            val frameFile = File(directory, DANMAKU_AI_CACHE_FRAME_FILE_NAME)
            val rect =
                if (json.has("x") && json.has("y") && json.has("width") && json.has("height")) {
                    DanmakuNormalizedRect(
                        x = json.optDouble("x", 0.0).toFloat(),
                        y = json.optDouble("y", 0.0).toFloat(),
                        width = json.optDouble("width", 0.0).toFloat(),
                        height = json.optDouble("height", 0.0).toFloat(),
                    )
                } else {
                    null
                }
            DanmakuOcclusionCacheEntry(
                backend = json.optString("backend", DanmakuAiBackend.PADDLE.wireValue),
                updatedAtMs = json.optLong("updatedAtMs", 0L),
                maskPath = maskFile.absolutePath,
                maskWidth = json.optInt("maskWidth", 0),
                maskHeight = json.optInt("maskHeight", 0),
                framePath = frameFile.takeIf { it.isFile && it.length() > 0L }?.absolutePath,
                normalizedRect = rect,
            )
        }.getOrNull()
    }

    fun save(
        source: MpvSource,
        backend: String,
        updatedAtMs: Long,
        normalizedRect: DanmakuNormalizedRect?,
        frameBitmap: Bitmap?,
        maskWidth: Int,
        maskHeight: Int,
        maskValues: FloatArray,
    ): DanmakuOcclusionCacheEntry? {
        val directory = entryDirectory(source)
        if (!directory.exists() && !directory.mkdirs()) {
            return null
        }
        return runCatching {
            val frameFile = File(directory, DANMAKU_AI_CACHE_FRAME_FILE_NAME)
            if (frameBitmap != null) {
                frameFile.outputStream().use { output ->
                    frameBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 82, output)
                }
            }

            val maskFile = File(directory, DANMAKU_AI_CACHE_MASK_FILE_NAME)
            createMaskBitmap(maskWidth, maskHeight, maskValues).use { maskBitmap ->
                maskFile.outputStream().use { output ->
                    maskBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, output)
                }
            }

            val stateFile = File(directory, DANMAKU_AI_CACHE_STATE_FILE_NAME)
            val json =
                JSONObject()
                    .put("cacheVersion", DANMAKU_AI_CACHE_VERSION)
                    .put("backend", backend)
                    .put("updatedAtMs", updatedAtMs)
                    .put("maskWidth", maskWidth)
                    .put("maskHeight", maskHeight)
            if (normalizedRect != null) {
                json
                    .put("x", normalizedRect.x.toDouble())
                    .put("y", normalizedRect.y.toDouble())
                    .put("width", normalizedRect.width.toDouble())
                    .put("height", normalizedRect.height.toDouble())
            }
            stateFile.writeText(json.toString())

            DanmakuOcclusionCacheEntry(
                backend = backend,
                updatedAtMs = updatedAtMs,
                maskPath = maskFile.absolutePath,
                maskWidth = maskWidth,
                maskHeight = maskHeight,
                framePath = frameFile.takeIf { it.isFile && it.length() > 0L }?.absolutePath,
                normalizedRect = normalizedRect,
            )
        }.getOrNull()
    }

    private fun entryDirectory(source: MpvSource): File {
        return File(File(context.cacheDir, DANMAKU_AI_CACHE_DIR_NAME), cacheKey(source))
    }

    private fun cacheKey(source: MpvSource): String {
        val stableIdentity =
            listOf(
                source.itemGuid.trim(),
                source.mediaGuid.trim(),
                source.videoGuid.trim(),
                source.url.trim(),
                source.title.trim(),
            ).joinToString("|")
        val digest = MessageDigest.getInstance("SHA-256").digest(stableIdentity.toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(Locale.US, byte) }
    }

    private fun createMaskBitmap(
        width: Int,
        height: Int,
        maskValues: FloatArray,
    ): Bitmap {
        val pixels = IntArray(width * height)
        for (index in pixels.indices) {
            val alpha = (maskValues[index].coerceIn(0f, 1f) * 255f).toInt().coerceIn(0, 255)
            pixels[index] = Color.argb(alpha, 255, 255, 255)
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}

private inline fun <T : Bitmap?, R> T.use(block: (T) -> R): R {
    return try {
        block(this)
    } finally {
        this?.recycle()
    }
}

class DanmakuDynamicOcclusionController(
    private val context: Context,
    private val videoOutputTarget: VideoOutputTarget,
    private val stateListener: (DanmakuDynamicOcclusionState) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inferenceThread = HandlerThread("FlyPlayerDanmakuOcclusion").apply { start() }
    private val inferenceHandler = Handler(inferenceThread.looper)
    private val cacheStore = DanmakuOcclusionCacheStore(context)
    private val runtimeFactory =
        DanmakuSegmentationRuntimeFactory(
            context = context,
            paddleModelAssetDir = DANMAKU_AI_PADDLE_MODEL_ASSET_DIR,
        )

    @Volatile
    private var disposed = false

    @Volatile
    private var config = DanmakuDynamicOcclusionConfig.defaults

    @Volatile
    private var paused = true

    @Volatile
    private var sourceLoaded = false

    @Volatile
    private var surfaceReady = false

    @Volatile
    private var videoOutputReady = false

    @Volatile
    private var processing = false

    @Volatile
    private var capturePending = false

    @Volatile
    private var samplingScheduled = false

    @Volatile
    private var warmStartDelayUntilUptimeMs = 0L

    private var latestState = DanmakuDynamicOcclusionState.disabled()
    private var latestRect: DanmakuNormalizedRect? = null
    private var latestMaskValues: FloatArray? = null
    private var latestMaskWidth = 0
    private var latestMaskHeight = 0
    private var latestMaskPath: String? = null
    private var latestFramePath: String? = null
    private var latestMaskTimestampMs = 0L
    private var currentSource: MpvSource? = null
    private var consecutiveEmptyFrames = 0
    private var activeBackendIndex = 0
    private var activeRuntime: DanmakuSegmentationRuntime? = null
    private var averageLatencyMs = 0.0
    private var overBudgetCount = 0
    private var reusableBitmap: Bitmap? = null
    private var reusableFocusedBitmap: Bitmap? = null
    private var previousFrameLumaSignature: IntArray? = null
    private var lastFrameCacheWriteAtMs = 0L
    private var sampleSequence = 0L
    private var cacheRestoreEligible = true
    private var latestMotionReferenceFrame: DanmakuMotionReferenceFrame? = null
    private var lastMotionCompensation: DanmakuMotionCompensation? = null
    private var consecutiveMotionCompensationFailures = 0
    private var consecutiveCompensatedFrames = 0

    @Volatile
    private var sceneCutRecoveryActive = false

    @Volatile
    private var sceneCutBurstSamplesRemaining = 0

    @Volatile
    private var stableMaskFramesSinceSceneCut = 0

    private val sampleRunnable =
        Runnable {
            samplingScheduled = false
            if (disposed || !shouldSample()) {
                return@Runnable
            }
            if (processing) {
                capturePending = true
                scheduleNextSample()
                return@Runnable
            }
            captureFrameAndInfer()
            scheduleNextSample()
        }

    fun updateConfig(raw: Map<String, Any?>) {
        if (disposed) return
        val next = DanmakuDynamicOcclusionConfig.fromMap(raw)
        val backendOrderChanged = next.preferredBackendOrder != config.preferredBackendOrder
        val inputSizeChanged =
            next.inputWidth != config.inputWidth || next.inputHeight != config.inputHeight
        config = next
        if (!next.enabled) {
            stopSampling(clearPending = true)
            releaseRuntime()
            clearRuntimeMaskState()
            emitState(DanmakuDynamicOcclusionState.disabled())
            return
        }
        if (backendOrderChanged || inputSizeChanged) {
            activeBackendIndex = 0
            averageLatencyMs = 0.0
            overBudgetCount = 0
            releaseRuntime()
            clearReusableBitmap()
        }
        evaluateSamplingState(resetStaleMask = false)
    }

    fun updatePlaybackState(
        paused: Boolean,
        sourceLoaded: Boolean,
        surfaceReady: Boolean,
        videoOutputReady: Boolean,
    ) {
        if (disposed) return
        this.paused = paused
        this.sourceLoaded = sourceLoaded
        this.surfaceReady = surfaceReady
        this.videoOutputReady = videoOutputReady
        evaluateSamplingState(resetStaleMask = !sourceLoaded || !surfaceReady)
    }

    fun onSourceChanged(source: MpvSource) {
        if (disposed) return
        currentSource = source
        cacheRestoreEligible = true
        clearRuntimeMaskState()
        capturePending = false
        activeBackendIndex = 0
        averageLatencyMs = 0.0
        overBudgetCount = 0
        lastFrameCacheWriteAtMs = 0L
        restoreCachedState()
        if (latestMaskPath == null) {
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = config.enabled)
        }
    }

    fun currentStateMap(): Map<String, Any?> = latestState.toMap()

    fun dispose() {
        if (disposed) return
        disposed = true
        stopSampling(clearPending = true)
        mainHandler.removeCallbacksAndMessages(null)
        inferenceHandler.removeCallbacksAndMessages(null)
        releaseRuntime()
        clearReusableBitmap()
        inferenceThread.quitSafely()
    }

    private fun clearRuntimeMaskState() {
        latestRect = null
        latestMaskValues = null
        latestMaskWidth = 0
        latestMaskHeight = 0
        latestMaskPath = null
        latestFramePath = null
        latestMaskTimestampMs = 0L
        consecutiveEmptyFrames = 0
        previousFrameLumaSignature = null
        sceneCutRecoveryActive = false
        sceneCutBurstSamplesRemaining = 0
        stableMaskFramesSinceSceneCut = 0
        latestMotionReferenceFrame = null
        lastMotionCompensation = null
        consecutiveMotionCompensationFailures = 0
        consecutiveCompensatedFrames = 0
    }

    private fun evaluateSamplingState(resetStaleMask: Boolean) {
        if (!config.enabled) {
            return
        }
        if (!sourceLoaded || !surfaceReady || !videoOutputReady) {
            stopSampling(clearPending = true)
            if (resetStaleMask) {
                clearRuntimeMaskState()
            }
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = true)
            return
        }
        if (paused) {
            stopSampling(clearPending = false)
            emitLatestMaskStateIfAvailable()
            return
        }
        if (!samplingScheduled) {
            samplingScheduled = true
            val delayMs = (warmStartDelayUntilUptimeMs - SystemClock.uptimeMillis()).coerceAtLeast(0L)
            if (delayMs > 0L) {
                mainHandler.postDelayed(sampleRunnable, delayMs)
            } else {
                mainHandler.post(sampleRunnable)
            }
        }
    }

    private fun shouldSample(): Boolean {
        return config.enabled && sourceLoaded && surfaceReady && videoOutputReady && !paused
    }

    private fun scheduleNextSample() {
        if (disposed || !shouldSample() || samplingScheduled) {
            return
        }
        samplingScheduled = true
        mainHandler.postDelayed(sampleRunnable, currentSampleIntervalMs())
    }

    private fun stopSampling(clearPending: Boolean) {
        mainHandler.removeCallbacks(sampleRunnable)
        samplingScheduled = false
        if (clearPending) {
            capturePending = false
        }
    }

    private fun captureFrameAndInfer() {
        val textureView = videoOutputTarget.view as? TextureView
        if (textureView == null || !textureView.isAvailable) {
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = config.enabled)
            return
        }
        val runtime =
            ensureRuntime()
                ?: run {
                    stopSampling(clearPending = true)
                    emitUnavailableState(
                        backend = DanmakuAiBackend.DISABLED,
                        keepEnabled = config.enabled,
                    )
                    return
                }
        val sampleId = ++sampleSequence
        val captureStartedAt = SystemClock.elapsedRealtime()
        val capturedFrame =
            captureBitmap(
                textureView = textureView,
                width = runtime.inputWidth,
                height = runtime.inputHeight,
                sampleAreaRatio = config.sampleAreaRatio,
            )
        val captureLatencyMs = SystemClock.elapsedRealtime() - captureStartedAt
        val bitmap = capturedFrame?.bitmap
        if (bitmap == null) {
            Log.w(
                DANMAKU_AI_TAG,
                "sample=$sampleId backend=${runtime.backend.wireValue} capture failed size=${runtime.inputWidth}x${runtime.inputHeight}",
            )
            emitUnavailableState(backend = runtime.backend, keepEnabled = config.enabled)
            return
        }
        maybeLogSamplingSlowPath(
            sampleId = sampleId,
            backend = runtime.backend,
            captureLatencyMs = captureLatencyMs,
            inferenceLatencyMs = null,
            totalLatencyMs = captureLatencyMs,
            reason = "capture",
        )
        processing = true
        inferenceHandler.post {
            runInference(
                runtime = runtime,
                bitmap = bitmap,
                sampleId = sampleId,
                captureLatencyMs = captureLatencyMs,
                sampleAreaRatio = capturedFrame.sampleAreaRatio,
            )
        }
    }

    private fun captureBitmap(
        textureView: TextureView,
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
    ): DanmakuCapturedFrame? {
        val current = reusableBitmap
        val reusable =
            if (
                current != null &&
                    current.width == width &&
                    current.height == height &&
                    !current.isRecycled
            ) {
                current
            } else {
                current?.recycle()
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    reusableBitmap = it
                }
            }
        val captured = runCatching { textureView.getBitmap(reusable) }.getOrNull() ?: return null
        val clampedRatio = sampleAreaRatio.coerceIn(0.1f, 1.0f)
        if (clampedRatio >= 0.999f) {
            return DanmakuCapturedFrame(bitmap = captured, sampleAreaRatio = 1.0f)
        }
        val focusedCurrent = reusableFocusedBitmap
        val focused =
            if (
                focusedCurrent != null &&
                    focusedCurrent.width == width &&
                    focusedCurrent.height == height &&
                    !focusedCurrent.isRecycled
            ) {
                focusedCurrent
            } else {
                focusedCurrent?.recycle()
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    reusableFocusedBitmap = it
                }
            }
        val sourceHeight = max(1, (height.toFloat() * clampedRatio).roundToInt()).coerceAtMost(height)
        val canvas = Canvas(focused)
        canvas.drawColor(Color.BLACK)
        canvas.drawBitmap(
            captured,
            Rect(0, 0, width, sourceHeight),
            Rect(0, 0, width, height),
            Paint(Paint.FILTER_BITMAP_FLAG),
        )
        return DanmakuCapturedFrame(bitmap = focused, sampleAreaRatio = clampedRatio)
    }

    private fun runInference(
        runtime: DanmakuSegmentationRuntime,
        bitmap: Bitmap,
        sampleId: Long,
        captureLatencyMs: Long,
        sampleAreaRatio: Float,
    ) {
        val startedAt = SystemClock.elapsedRealtime()
        val result =
            runCatching {
                val frameContinuity = analyzeFrameContinuity(bitmap)
                previousFrameLumaSignature = frameContinuity.signature
                val motionSampleWidth =
                    minOf(DANMAKU_AI_MOTION_SAMPLE_WIDTH, bitmap.width.coerceAtLeast(1))
                val motionSampleHeight =
                    minOf(DANMAKU_AI_MOTION_SAMPLE_HEIGHT, bitmap.height.coerceAtLeast(1))
                val motionLumaSamples =
                    sampleBitmapLuma(bitmap, motionSampleWidth, motionSampleHeight)
                val motionCompensationAttempted =
                    !frameContinuity.sceneCut &&
                        !sceneCutRecoveryActive &&
                        latestMotionReferenceFrame != null &&
                        latestRect != null &&
                        latestMaskValues != null
                val motionCompensation =
                    if (motionCompensationAttempted) {
                        estimateMotionCompensation(
                            currentLumaSamples = motionLumaSamples,
                            sampleWidth = motionSampleWidth,
                            sampleHeight = motionSampleHeight,
                            maskWidth = runtime.outputWidth,
                            maskHeight = runtime.outputHeight,
                        )
                    } else {
                        null
                    }
                if (frameContinuity.sceneCut && !sceneCutRecoveryActive) {
                    mainHandler.post {
                        if (!disposed && activeRuntime?.backend == runtime.backend) {
                            beginSceneCutRecovery(runtime.backend)
                        }
                    }
                }
                val outputValues = runtime.run(bitmap)
                extractMaskResult(
                    outputValues = outputValues,
                    outputWidth = runtime.outputWidth,
                    outputHeight = runtime.outputHeight,
                    allowTemporalSmoothing =
                        !frameContinuity.sceneCut && !sceneCutRecoveryActive,
                    motionCompensation = motionCompensation,
                    motionCompensationAttempted = motionCompensationAttempted,
                )?.let { extraction ->
                    if (sampleAreaRatio < 0.999f) {
                        remapMaskResultToFullFrame(extraction.maskResult, sampleAreaRatio)
                    } else {
                        extraction.maskResult
                    }
                        .let { mappedResult ->
                            InferenceOutcome(
                                maskResult = mappedResult,
                                motionLumaSamples = motionLumaSamples,
                                motionSampleWidth = motionSampleWidth,
                                motionSampleHeight = motionSampleHeight,
                                motionCompensation = extraction.appliedMotionCompensation,
                                motionCompensationAttempted = motionCompensationAttempted,
                            )
                        }
                }.let { mappedOutcome ->
                    mappedOutcome
                }
            }.getOrElse { error ->
                Log.w(DANMAKU_AI_TAG, "backend=${runtime.backend.wireValue} inference failed", error)
                handleBackendFailure(runtime.backend)
                null
            }
        val inferenceLatencyMs = SystemClock.elapsedRealtime() - startedAt
        val cacheEntry =
            if (result?.maskResult != null) {
                persistMaskCache(
                    source = currentSource,
                    backend = runtime.backend,
                    result = result.maskResult,
                    frameBitmap = bitmap,
                    updatedAtMs = System.currentTimeMillis(),
                )
            } else {
                null
            }
        val totalLatencyMs = captureLatencyMs + inferenceLatencyMs
        maybeLogSamplingSlowPath(
            sampleId = sampleId,
            backend = runtime.backend,
            captureLatencyMs = captureLatencyMs,
            inferenceLatencyMs = inferenceLatencyMs,
            totalLatencyMs = totalLatencyMs,
            reason = if (result?.maskResult == null) "empty" else "ok",
        )
        mainHandler.post {
            processing = false
            if (disposed) {
                return@post
            }
            if (result?.maskResult != null) {
                applyMaskResult(
                    backend = runtime.backend,
                    result = result.maskResult,
                    cacheEntry = cacheEntry,
                    latencyMs = totalLatencyMs,
                    motionLumaSamples = result.motionLumaSamples,
                    motionSampleWidth = result.motionSampleWidth,
                    motionSampleHeight = result.motionSampleHeight,
                    motionCompensation = result.motionCompensation,
                )
            } else if (activeRuntime?.backend == runtime.backend) {
                applyEmptyResult(
                    backend = runtime.backend,
                    motionCompensationAttempted = result?.motionCompensationAttempted == true,
                )
            }
            if (capturePending && shouldSample()) {
                capturePending = false
                mainHandler.removeCallbacks(sampleRunnable)
                samplingScheduled = false
                mainHandler.post(sampleRunnable)
            }
        }
    }

    private fun extractMaskResult(
        outputValues: FloatArray,
        outputWidth: Int,
        outputHeight: Int,
        allowTemporalSmoothing: Boolean,
        motionCompensation: DanmakuMotionCompensation?,
        motionCompensationAttempted: Boolean,
    ): DanmakuMaskExtraction? {
        val width = outputWidth
        val height = outputHeight
        val total = width * height

        val dilated = FloatArray(total)
        dilateMask(outputValues, dilated, width, height)
        val blurred = FloatArray(total)
        blurMask(dilated, blurred, width, height)
        val normalized = normalizeMask(blurred)
        val baseComponent = extractPrimaryComponent(normalized, width, height) ?: return null
        if (!isLikelyForegroundSubject(baseComponent)) {
            return null
        }
        val baseRect = baseComponent.rect
        val appliedMotionCompensation =
            motionCompensation?.takeIf {
                shouldApplyMotionCompensation(
                    nextRect = baseRect,
                    motionCompensation = it,
                )
            }
        val compensatedPreviousMask =
            buildCompensatedPreviousMask(appliedMotionCompensation, width, height)
        val compensatedPreviousRect = buildCompensatedPreviousRect(appliedMotionCompensation)
        val bypassTemporalSmoothing =
            motionCompensationAttempted && appliedMotionCompensation == null
        val shouldSmoothTemporally =
            allowTemporalSmoothing &&
                !bypassTemporalSmoothing &&
                shouldUseTemporalSmoothing(
                    nextRect = baseRect,
                    previousRectOverride = compensatedPreviousRect,
                )
        val smoothed =
            if (shouldSmoothTemporally) {
                smoothMaskOverTime(
                    nextMask = normalized,
                    width = width,
                    height = height,
                    previousMaskOverride = compensatedPreviousMask,
                )
            } else {
                normalized.copyOf()
            }
        val refined = refineMaskAlpha(smoothed)
        if (shouldRejectAmbiguousForeground(refined, width, height)) {
            return null
        }
        val hardened = hardenMaskForOcclusion(refined, width, height)
        val primaryMaskComponent =
            retainPrimaryMaskComponent(hardened, width, height) ?: return null
        if (shouldRejectWeirdPrimaryMask(primaryMaskComponent.maskValues, width, height)) {
            return null
        }
        val helperComponent =
            primaryMaskComponent.component.takeIf(::isLikelyForegroundSubject)
                ?: extractPrimaryComponent(refined, width, height)
                ?: baseComponent
        val helperRect =
            if (isLikelyForegroundSubject(helperComponent)) {
                helperComponent.rect
            } else {
                baseRect
            }
        val finalRect =
            if (shouldSmoothTemporally) {
                smoothRectOverTime(
                    nextRect = helperRect,
                    previousRectOverride = compensatedPreviousRect,
                )
            } else {
                helperRect
            }
        return DanmakuMaskExtraction(
            maskResult =
                DanmakuMaskResult(
                    maskValues = primaryMaskComponent.maskValues,
                    maskWidth = width,
                    maskHeight = height,
                    normalizedRect = finalRect,
                ),
            appliedMotionCompensation = appliedMotionCompensation,
        )
    }

    private fun dilateMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 0f
                val top = max(0, y - 1)
                val bottom = minOf(height - 1, y + 1)
                val left = max(0, x - 1)
                val right = minOf(width - 1, x + 1)
                for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        val sample = input[(sampleY * width) + sampleX]
                        if (sample > value) {
                            value = sample
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun blurMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var total = 0f
                var samples = 0
                val top = max(0, y - 1)
                val bottom = minOf(height - 1, y + 1)
                val left = max(0, x - 1)
                val right = minOf(width - 1, x + 1)
                for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        total += input[(sampleY * width) + sampleX]
                        samples += 1
                    }
                }
                output[(y * width) + x] = total / samples.toFloat()
            }
        }
    }

    private fun normalizeMask(values: FloatArray): FloatArray {
        val normalized = FloatArray(values.size)
        var foregroundPixels = 0
        for (index in values.indices) {
            val value =
                ((values[index] - DANMAKU_AI_MASK_THRESHOLD) / (1f - DANMAKU_AI_MASK_THRESHOLD))
                    .coerceIn(0f, 1f)
            normalized[index] = value
            if (value >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                foregroundPixels += 1
            }
        }
        val minForegroundPixels =
            max(32, (values.size * DANMAKU_AI_MIN_FOREGROUND_RATIO).toInt())
        return if (foregroundPixels >= minForegroundPixels) normalized else FloatArray(values.size)
    }

    private fun smoothMaskOverTime(
        nextMask: FloatArray,
        width: Int,
        height: Int,
        previousMaskOverride: FloatArray? = null,
    ): FloatArray {
        val previousMask = previousMaskOverride ?: latestMaskValues
        if (previousMask == null || latestMaskWidth != width || latestMaskHeight != height) {
            return nextMask.copyOf()
        }
        val smoothed = FloatArray(nextMask.size)
        val previousWeight = 1f - DANMAKU_AI_MASK_SMOOTHING_ALPHA
        for (index in nextMask.indices) {
            smoothed[index] =
                ((previousMask[index] * previousWeight) +
                    (nextMask[index] * DANMAKU_AI_MASK_SMOOTHING_ALPHA))
                    .coerceIn(0f, 1f)
        }
        return smoothed
    }

    private fun shouldUseTemporalSmoothing(
        nextRect: DanmakuNormalizedRect,
        previousRectOverride: DanmakuNormalizedRect? = null,
    ): Boolean {
        val previousRect = previousRectOverride ?: latestRect ?: return false
        return previousRect.iou(nextRect) >= DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU
    }

    private fun smoothRectOverTime(
        nextRect: DanmakuNormalizedRect,
        previousRectOverride: DanmakuNormalizedRect? = null,
    ): DanmakuNormalizedRect {
        val previousRect = previousRectOverride ?: latestRect ?: return nextRect
        return if (previousRect.iou(nextRect) >= DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU) {
            previousRect.lerp(nextRect, DANMAKU_AI_RECT_SMOOTHING_ALPHA)
        } else {
            nextRect
        }
    }

    private fun analyzeFrameContinuity(bitmap: Bitmap): DanmakuFrameContinuity {
        val sampleWidth = DANMAKU_AI_SCENE_CUT_SAMPLE_WIDTH.coerceAtMost(bitmap.width)
        val sampleHeight = DANMAKU_AI_SCENE_CUT_SAMPLE_HEIGHT.coerceAtMost(bitmap.height)
        val signature = sampleBitmapLuma(bitmap, sampleWidth, sampleHeight)
        val previous = previousFrameLumaSignature
        if (previous == null || previous.size != signature.size) {
            return DanmakuFrameContinuity(sceneCut = false, signature = signature)
        }
        var totalDelta = 0L
        var changedPixels = 0
        for (i in signature.indices) {
            val delta = kotlin.math.abs(signature[i] - previous[i])
            totalDelta += delta.toLong()
            if (delta >= DANMAKU_AI_SCENE_CUT_CHANGED_PIXEL_DELTA) {
                changedPixels += 1
            }
        }
        val averageDelta = totalDelta.toDouble() / signature.size.toDouble()
        val changedRatio = changedPixels.toDouble() / signature.size.toDouble()
        return DanmakuFrameContinuity(
            sceneCut =
                averageDelta >= DANMAKU_AI_SCENE_CUT_AVERAGE_DELTA_THRESHOLD ||
                    changedRatio >= DANMAKU_AI_SCENE_CUT_CHANGED_RATIO_THRESHOLD,
            signature = signature,
        )
    }

    private fun sampleBitmapLuma(
        bitmap: Bitmap,
        sampleWidth: Int,
        sampleHeight: Int,
    ): IntArray {
        val signature = IntArray(sampleWidth * sampleHeight)
        val stepX = bitmap.width.toFloat() / sampleWidth.toFloat()
        val stepY = bitmap.height.toFloat() / sampleHeight.toFloat()
        var index = 0
        for (sampleY in 0 until sampleHeight) {
            val bitmapY =
                ((sampleY + 0.5f) * stepY).toInt().coerceIn(0, bitmap.height - 1)
            for (sampleX in 0 until sampleWidth) {
                val bitmapX =
                    ((sampleX + 0.5f) * stepX).toInt().coerceIn(0, bitmap.width - 1)
                val color = bitmap.getPixel(bitmapX, bitmapY)
                val red = Color.red(color)
                val green = Color.green(color)
                val blue = Color.blue(color)
                signature[index++] = ((red * 77) + (green * 150) + (blue * 29)) shr 8
            }
        }
        return signature
    }

    private fun estimateMotionCompensation(
        currentLumaSamples: IntArray,
        sampleWidth: Int,
        sampleHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
    ): DanmakuMotionCompensation? {
        if (sceneCutRecoveryActive) {
            return null
        }
        val reference = latestMotionReferenceFrame ?: return null
        val previousRect = latestRect ?: return null
        val previousMask = latestMaskValues ?: return null
        if (previousMask.isEmpty() || previousRect.area() < DANMAKU_AI_MOTION_MIN_RECT_AREA) {
            return null
        }
        if (
            reference.sampleWidth != sampleWidth ||
                reference.sampleHeight != sampleHeight ||
                latestMaskWidth != maskWidth ||
                latestMaskHeight != maskHeight
        ) {
            return null
        }
        val roi = resolveMotionRoi(reference.normalizedRect, sampleWidth, sampleHeight) ?: return null
        val maxShiftX =
            minOf(
                DANMAKU_AI_MOTION_SEARCH_RADIUS_PX,
                max(1, (sampleWidth * DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO).roundToInt()),
            )
        val maxShiftY =
            minOf(
                DANMAKU_AI_MOTION_SEARCH_RADIUS_PX,
                max(1, (sampleHeight * DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO).roundToInt()),
            )
        var bestDx = 0
        var bestDy = 0
        var bestScore = Double.MAX_VALUE
        for (dy in -maxShiftY..maxShiftY) {
            for (dx in -maxShiftX..maxShiftX) {
                var totalDelta = 0L
                var overlapSamples = 0
                for (y in roi.top..roi.bottom) {
                    val shiftedY = y + dy
                    if (shiftedY !in 0 until sampleHeight) {
                        continue
                    }
                    val previousRow = y * sampleWidth
                    val currentRow = shiftedY * sampleWidth
                    for (x in roi.left..roi.right) {
                        val shiftedX = x + dx
                        if (shiftedX !in 0 until sampleWidth) {
                            continue
                        }
                        totalDelta +=
                            abs(reference.lumaSamples[previousRow + x] - currentLumaSamples[currentRow + shiftedX]).toLong()
                        overlapSamples += 1
                    }
                }
                if (overlapSamples < DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES) {
                    continue
                }
                val averageDelta = totalDelta.toDouble() / overlapSamples.toDouble()
                if (averageDelta < bestScore) {
                    bestScore = averageDelta
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        if (bestScore == Double.MAX_VALUE || bestScore > DANMAKU_AI_MOTION_MAX_AVERAGE_DELTA) {
            return null
        }
        val dxMaskPx =
            ((bestDx.toFloat() / sampleWidth.toFloat()) * maskWidth.toFloat()).roundToInt()
        val dyMaskPx =
            ((bestDy.toFloat() / sampleHeight.toFloat()) * maskHeight.toFloat()).roundToInt()
        return DanmakuMotionCompensation(
            dxSamplePx = bestDx,
            dySamplePx = bestDy,
            dxMaskPx = dxMaskPx,
            dyMaskPx = dyMaskPx,
            dxNormalized = dxMaskPx.toFloat() / maskWidth.toFloat(),
            dyNormalized = dyMaskPx.toFloat() / maskHeight.toFloat(),
            score = bestScore,
        )
    }

    private fun shouldApplyMotionCompensation(
        nextRect: DanmakuNormalizedRect,
        motionCompensation: DanmakuMotionCompensation,
    ): Boolean {
        if (sceneCutRecoveryActive) {
            return false
        }
        if (consecutiveCompensatedFrames >= DANMAKU_AI_MOTION_MAX_CONSECUTIVE_COMPENSATED_FRAMES) {
            return false
        }
        val previousRect = latestRect ?: return false
        val previousArea = previousRect.area()
        val nextArea = nextRect.area()
        if (previousArea <= 0f || nextArea <= 0f) {
            return false
        }
        if (motionCompensation.score > DANMAKU_AI_MOTION_GATE_MAX_AVERAGE_DELTA) {
            return false
        }
        if (abs(motionCompensation.dxNormalized) > DANMAKU_AI_MOTION_GATE_MAX_DX_NORMALIZED) {
            return false
        }
        if (abs(motionCompensation.dyNormalized) > DANMAKU_AI_MOTION_GATE_MAX_DY_NORMALIZED) {
            return false
        }
        val areaRatio = nextArea / previousArea
        if (
            areaRatio < DANMAKU_AI_MOTION_GATE_MIN_AREA_RATIO ||
                areaRatio > DANMAKU_AI_MOTION_GATE_MAX_AREA_RATIO
        ) {
            return false
        }
        val compensatedPreviousRect = buildCompensatedPreviousRect(motionCompensation) ?: return false
        return compensatedPreviousRect.iou(nextRect) >= DANMAKU_AI_MOTION_GATE_MIN_IOU
    }

    private fun resolveMotionRoi(
        rect: DanmakuNormalizedRect,
        sampleWidth: Int,
        sampleHeight: Int,
    ): DanmakuMotionRoi? {
        val expandedRect =
            rect.expanded(
                horizontalRatio = DANMAKU_AI_MOTION_ROI_EXPAND_HORIZONTAL_RATIO,
                verticalRatio = DANMAKU_AI_MOTION_ROI_EXPAND_VERTICAL_RATIO,
            )
        val expandedRoi = normalizedRectToMotionRoi(expandedRect, sampleWidth, sampleHeight)
        if (expandedRoi != null && expandedRoi.area >= DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES) {
            return expandedRoi
        }
        val fallbackWidth =
            max(4, (sampleWidth * DANMAKU_AI_MOTION_FALLBACK_CENTER_WIDTH_RATIO).roundToInt())
        val fallbackHeight =
            max(4, (sampleHeight * DANMAKU_AI_MOTION_FALLBACK_CENTER_HEIGHT_RATIO).roundToInt())
        val left = ((sampleWidth - fallbackWidth) / 2).coerceIn(0, sampleWidth - 1)
        val top = ((sampleHeight - fallbackHeight) / 2).coerceIn(0, sampleHeight - 1)
        val right = (left + fallbackWidth - 1).coerceIn(left, sampleWidth - 1)
        val bottom = (top + fallbackHeight - 1).coerceIn(top, sampleHeight - 1)
        return DanmakuMotionRoi(left = left, top = top, right = right, bottom = bottom)
    }

    private fun normalizedRectToMotionRoi(
        rect: DanmakuNormalizedRect,
        sampleWidth: Int,
        sampleHeight: Int,
    ): DanmakuMotionRoi? {
        val width = rect.width.coerceIn(0f, 1f)
        val height = rect.height.coerceIn(0f, 1f)
        if (width <= 0f || height <= 0f) {
            return null
        }
        val left =
            (rect.left.coerceIn(0f, 1f) * sampleWidth.toFloat())
                .toInt()
                .coerceIn(0, sampleWidth - 1)
        val top =
            (rect.top.coerceIn(0f, 1f) * sampleHeight.toFloat())
                .toInt()
                .coerceIn(0, sampleHeight - 1)
        val right =
            ((rect.right.coerceIn(0f, 1f) * sampleWidth.toFloat()).roundToInt() - 1)
                .coerceIn(left, sampleWidth - 1)
        val bottom =
            ((rect.bottom.coerceIn(0f, 1f) * sampleHeight.toFloat()).roundToInt() - 1)
                .coerceIn(top, sampleHeight - 1)
        return DanmakuMotionRoi(left = left, top = top, right = right, bottom = bottom)
    }

    private fun buildCompensatedPreviousMask(
        motionCompensation: DanmakuMotionCompensation?,
        width: Int,
        height: Int,
    ): FloatArray? {
        val previousMask = latestMaskValues ?: return null
        if (latestMaskWidth != width || latestMaskHeight != height) {
            return null
        }
        val compensation = motionCompensation ?: return previousMask
        return shiftMaskValues(
            values = previousMask,
            width = width,
            height = height,
            dxPx = compensation.dxMaskPx,
            dyPx = compensation.dyMaskPx,
        )
    }

    private fun shiftMaskValues(
        values: FloatArray,
        width: Int,
        height: Int,
        dxPx: Int,
        dyPx: Int,
    ): FloatArray {
        if (dxPx == 0 && dyPx == 0) {
            return values.copyOf()
        }
        val shifted = FloatArray(values.size)
        for (y in 0 until height) {
            val sourceY = y - dyPx
            if (sourceY !in 0 until height) {
                continue
            }
            val destinationRow = y * width
            val sourceRow = sourceY * width
            for (x in 0 until width) {
                val sourceX = x - dxPx
                if (sourceX !in 0 until width) {
                    continue
                }
                shifted[destinationRow + x] = values[sourceRow + sourceX]
            }
        }
        return shifted
    }

    private fun buildCompensatedPreviousRect(
        motionCompensation: DanmakuMotionCompensation?,
    ): DanmakuNormalizedRect? {
        val previousRect = latestRect ?: return null
        val compensation = motionCompensation ?: return previousRect
        return translateRect(
            rect = previousRect,
            dxNormalized = compensation.dxNormalized,
            dyNormalized = compensation.dyNormalized,
        )
    }

    private fun translateRect(
        rect: DanmakuNormalizedRect,
        dxNormalized: Float,
        dyNormalized: Float,
    ): DanmakuNormalizedRect {
        val safeWidth = rect.width.coerceIn(0f, 1f)
        val safeHeight = rect.height.coerceIn(0f, 1f)
        val maxLeft = (1f - safeWidth).coerceAtLeast(0f)
        val maxTop = (1f - safeHeight).coerceAtLeast(0f)
        return DanmakuNormalizedRect(
            x = (rect.x + dxNormalized).coerceIn(0f, maxLeft),
            y = (rect.y + dyNormalized).coerceIn(0f, maxTop),
            width = safeWidth,
            height = safeHeight,
        )
    }

    private fun remapMaskResultToFullFrame(
        result: DanmakuMaskResult,
        sampleAreaRatio: Float,
    ): DanmakuMaskResult {
        val clampedRatio = sampleAreaRatio.coerceIn(0.1f, 1.0f)
        if (clampedRatio >= 0.999f) {
            return result
        }
        val rect =
            result.normalizedRect?.let {
                DanmakuNormalizedRect(
                    x = it.x,
                    y = (it.y * clampedRatio).coerceIn(0f, 1f),
                    width = it.width,
                    height = (it.height * clampedRatio).coerceIn(0f, 1f),
                )
            }
        return DanmakuMaskResult(
            maskValues = result.maskValues,
            maskWidth = result.maskWidth,
            maskHeight = result.maskHeight,
            normalizedRect = rect,
        )
    }

    private fun refineMaskAlpha(values: FloatArray): FloatArray {
        val refined = FloatArray(values.size)
        for (index in values.indices) {
            val value = values[index].coerceIn(0f, 1f)
            refined[index] =
                when {
                    value <= DANMAKU_AI_MASK_SOFT_EDGE_START -> 0f
                    value >= DANMAKU_AI_MASK_SOLID_CORE_START -> 1f
                    else -> {
                        val t =
                            ((value - DANMAKU_AI_MASK_SOFT_EDGE_START) /
                                (DANMAKU_AI_MASK_SOLID_CORE_START -
                                    DANMAKU_AI_MASK_SOFT_EDGE_START))
                                .coerceIn(0f, 1f)
                        t * t * (3f - (2f * t))
                    }
                }
        }
        return refined
    }

    private fun hardenMaskForOcclusion(
        values: FloatArray,
        width: Int,
        height: Int,
    ): FloatArray {
        val previousMask =
            latestMaskValues?.takeIf { latestMaskWidth == width && latestMaskHeight == height }
        val binary = FloatArray(values.size)
        for (index in values.indices) {
            val threshold =
                if (previousMask?.get(index)?.let { it >= 0.5f } == true) {
                    DANMAKU_AI_OUTPUT_MASK_KEEP_THRESHOLD
                } else {
                    DANMAKU_AI_OUTPUT_MASK_HARD_THRESHOLD
                }
            binary[index] =
                if (values[index] >= threshold) {
                    1f
                } else {
                    0f
                }
        }
        val stabilized =
            if (DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS > 0) {
                FloatArray(values.size).also { dilated ->
                    dilateBinaryMask(
                        input = binary,
                        output = dilated,
                        width = width,
                        height = height,
                        radius = DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS,
                    )
                }
            } else {
                binary
            }
        return FloatArray(values.size).also { filled ->
            fillEnclosedBinaryMaskHoles(
                input = stabilized,
                output = filled,
                width = width,
                height = height,
            )
        }
    }

    private fun dilateBinaryMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 0f
                val top = max(0, y - radius)
                val bottom = minOf(height - 1, y + radius)
                val left = max(0, x - radius)
                val right = minOf(width - 1, x + radius)
                loop@ for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        if (input[(sampleY * width) + sampleX] > 0.5f) {
                            value = 1f
                            break@loop
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun fillEnclosedBinaryMaskHoles(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        val total = width * height
        val visited = BooleanArray(total)
        val queue = IntArray(total)
        var head = 0
        var tail = 0

        fun enqueueIfBackground(index: Int) {
            if (index < 0 || index >= total || visited[index] || input[index] > 0.5f) {
                return
            }
            visited[index] = true
            queue[tail++] = index
        }

        for (x in 0 until width) {
            enqueueIfBackground(x)
            enqueueIfBackground(((height - 1) * width) + x)
        }
        for (y in 1 until (height - 1).coerceAtLeast(1)) {
            enqueueIfBackground(y * width)
            enqueueIfBackground((y * width) + width - 1)
        }

        while (head < tail) {
            val current = queue[head++]
            val x = current % width
            val y = current / width
            if (x > 0) {
                enqueueIfBackground(current - 1)
            }
            if (x < width - 1) {
                enqueueIfBackground(current + 1)
            }
            if (y > 0) {
                enqueueIfBackground(current - width)
            }
            if (y < height - 1) {
                enqueueIfBackground(current + width)
            }
        }

        for (index in 0 until total) {
            output[index] =
                if (input[index] > 0.5f || !visited[index]) {
                    1f
                } else {
                    0f
                }
        }
    }

    private fun retainPrimaryMaskComponent(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuPrimaryMaskComponent? {
        val totalPixels = width * height
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        val componentPixels = IntArray(totalPixels)
        val bestPixels = IntArray(totalPixels)
        var bestCount = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] <= 0.5f) {
                continue
            }
            var count = 0
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                componentPixels[count++] = current
                val x = current % width
                val y = current / width
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] > 0.5f) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] > 0.5f) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] > 0.5f) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] > 0.5f) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
            }
            if (count > bestCount) {
                bestCount = count
                componentPixels.copyInto(bestPixels, destinationOffset = 0, startIndex = 0, endIndex = count)
            }
        }

        if (bestCount <= 0) {
            return null
        }
        val output = FloatArray(totalPixels)
        for (i in 0 until bestCount) {
            output[bestPixels[i]] = 1f
        }
        val component = extractPrimaryComponent(output, width, height) ?: return null
        return DanmakuPrimaryMaskComponent(
            maskValues = output,
            component = component,
        )
    }

    private fun shouldRejectAmbiguousForeground(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): Boolean {
        val complexity = analyzeForegroundComplexity(maskValues, width, height)
        if (complexity.significantComponentCount <= 1) {
            return false
        }
        val secondRatio =
            if (complexity.largestPixelCount > 0) {
                complexity.secondLargestPixelCount.toFloat() / complexity.largestPixelCount.toFloat()
            } else {
                0f
            }
        val largestShare =
            if (complexity.totalForegroundPixels > 0) {
                complexity.largestPixelCount.toFloat() / complexity.totalForegroundPixels.toFloat()
            } else {
                1f
            }
        if (secondRatio >= DANMAKU_AI_AMBIGUOUS_SECOND_COMPONENT_RATIO) {
            return true
        }
        if (
            complexity.significantComponentCount >= DANMAKU_AI_AMBIGUOUS_MULTI_COMPONENT_COUNT &&
                largestShare <= DANMAKU_AI_AMBIGUOUS_LARGEST_FOREGROUND_SHARE
        ) {
            return true
        }
        return false
    }

    private fun analyzeForegroundComplexity(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuForegroundComplexity {
        val totalPixels = width * height
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        var significantComponentCount = 0
        var totalForegroundPixels = 0
        var largestPixelCount = 0
        var secondLargestPixelCount = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] < DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                continue
            }
            var count = 0
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                count += 1
                val x = current % width
                val y = current / width
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
            }
            if (count < DANMAKU_AI_AMBIGUOUS_COMPONENT_MIN_PIXELS) {
                continue
            }
            significantComponentCount += 1
            totalForegroundPixels += count
            if (count > largestPixelCount) {
                secondLargestPixelCount = largestPixelCount
                largestPixelCount = count
            } else if (count > secondLargestPixelCount) {
                secondLargestPixelCount = count
            }
        }

        return DanmakuForegroundComplexity(
            significantComponentCount = significantComponentCount,
            largestPixelCount = largestPixelCount,
            secondLargestPixelCount = secondLargestPixelCount,
            totalForegroundPixels = totalForegroundPixels,
        )
    }

    private fun shouldRejectWeirdPrimaryMask(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): Boolean {
        val bounds = findMaskBounds(maskValues, width, height) ?: return true
        val boxWidth = bounds.right - bounds.left + 1
        val boxHeight = bounds.bottom - bounds.top + 1
        if (boxWidth <= 0 || boxHeight <= 0) {
            return true
        }
        val boxWidthRatio = boxWidth.toFloat() / width.toFloat()
        val boxHeightRatio = boxHeight.toFloat() / height.toFloat()
        val boxAspectRatio = boxHeight.toFloat() / boxWidth.toFloat()

        val coreLeft = bounds.left + max(1, (boxWidth * 0.22f).roundToInt())
        val coreRight = bounds.right - max(1, (boxWidth * 0.22f).roundToInt())
        val coreTop = bounds.top + max(1, (boxHeight * 0.18f).roundToInt())
        val coreBottom = bounds.bottom - max(1, (boxHeight * 0.18f).roundToInt())
        var corePixels = 0
        var coreForegroundPixels = 0
        for (y in coreTop..coreBottom.coerceAtLeast(coreTop)) {
            for (x in coreLeft..coreRight.coerceAtLeast(coreLeft)) {
                if (x < 0 || x >= width || y < 0 || y >= height) {
                    continue
                }
                corePixels += 1
                if (maskValues[(y * width) + x] > 0.5f) {
                    coreForegroundPixels += 1
                }
            }
        }
        if (corePixels > 0) {
            val coreFillRatio = coreForegroundPixels.toFloat() / corePixels.toFloat()
            if (coreFillRatio < DANMAKU_AI_MASK_SHAPE_MIN_CORE_FILL_RATIO) {
                return true
            }
        }

        val originalForegroundPixels = maskValues.count { it > 0.5f }
        if (originalForegroundPixels <= 0) {
            return true
        }
        val totalPixels = (width * height).coerceAtLeast(1)
        val overallAreaRatio = originalForegroundPixels.toFloat() / totalPixels.toFloat()
        if (
            boxWidthRatio <= DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_WIDTH_RATIO &&
            boxHeightRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_HEIGHT_RATIO &&
            boxAspectRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO &&
            overallAreaRatio <= DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_AREA_RATIO
        ) {
            return true
        }
        val topBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = bounds.top,
                bottom = bounds.top + max(0, (boxHeight * 0.24f).roundToInt()),
            )
        val middleBandCenter = bounds.top + (boxHeight / 2)
        val middleBandHalfHeight = max(1, (boxHeight * 0.12f).roundToInt())
        val middleBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = (middleBandCenter - middleBandHalfHeight).coerceAtLeast(bounds.top),
                bottom = (middleBandCenter + middleBandHalfHeight).coerceAtMost(bounds.bottom),
            )
        val bottomBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = (bounds.bottom - max(0, (boxHeight * 0.24f).roundToInt())).coerceAtLeast(bounds.top),
                bottom = bounds.bottom,
            )
        if (middleBandWidth > 0) {
            val taperedSideRatio =
                minOf(topBandWidth, bottomBandWidth).toFloat() / middleBandWidth.toFloat()
            if (
                boxAspectRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO &&
                taperedSideRatio <= DANMAKU_AI_MASK_SHAPE_MAX_TAPERED_SIDE_RATIO
            ) {
                return true
            }
        }
        val eroded = FloatArray(maskValues.size)
        erodeBinaryMask(
            input = maskValues,
            output = eroded,
            width = width,
            height = height,
            radius = DANMAKU_AI_MASK_SHAPE_EROSION_RADIUS,
        )
        val erodedForegroundPixels = eroded.count { it > 0.5f }
        val erodedRatio = erodedForegroundPixels.toFloat() / originalForegroundPixels.toFloat()
        return erodedRatio < DANMAKU_AI_MASK_SHAPE_MIN_ERODED_RATIO
    }

    private data class MaskBounds(
        val left: Int,
        val top: Int,
        val right: Int,
        val bottom: Int,
    )

    private fun findMaskBounds(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): MaskBounds? {
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (maskValues[(y * width) + x] <= 0.5f) {
                    continue
                }
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
            }
        }
        if (right < left || bottom < top) {
            return null
        }
        return MaskBounds(left = left, top = top, right = right, bottom = bottom)
    }

    private fun measureMaskBandWidth(
        maskValues: FloatArray,
        width: Int,
        left: Int,
        right: Int,
        top: Int,
        bottom: Int,
    ): Int {
        var bandLeft = right
        var bandRight = left
        for (y in top..bottom.coerceAtLeast(top)) {
            for (x in left..right.coerceAtLeast(left)) {
                if (maskValues[(y * width) + x] <= 0.5f) {
                    continue
                }
                if (x < bandLeft) bandLeft = x
                if (x > bandRight) bandRight = x
            }
        }
        if (bandRight < bandLeft) {
            return 0
        }
        return bandRight - bandLeft + 1
    }

    private fun erodeBinaryMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 1f
                val top = max(0, y - radius)
                val bottom = minOf(height - 1, y + radius)
                val left = max(0, x - radius)
                val right = minOf(width - 1, x + radius)
                loop@ for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        if (input[(sampleY * width) + sampleX] <= 0.5f) {
                            value = 0f
                            break@loop
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun extractPrimaryComponent(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuPrimaryComponent? {
        val totalPixels = width * height
        val minForegroundPixels = max(32, (totalPixels * DANMAKU_AI_MIN_FOREGROUND_RATIO).toInt())
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        var largestCount = 0
        var bestLeft = 0
        var bestTop = 0
        var bestRight = 0
        var bestBottom = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] < DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                continue
            }
            var count = 0
            var left = index % width
            var right = left
            var top = index / width
            var bottom = top
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                val x = current % width
                val y = current / width
                count += 1
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
            }
            if (count > largestCount) {
                largestCount = count
                bestLeft = left
                bestTop = top
                bestRight = right
                bestBottom = bottom
            }
        }

        if (largestCount < minForegroundPixels) {
            return null
        }
        val candidateRect =
            DanmakuNormalizedRect(
                x = bestLeft.toFloat() / width.toFloat(),
                y = bestTop.toFloat() / height.toFloat(),
                width = (bestRight - bestLeft + 1).toFloat() / width.toFloat(),
                height = (bestBottom - bestTop + 1).toFloat() / height.toFloat(),
            ).expanded(horizontalRatio = 0.10f, verticalRatio = 0.12f)
        val bboxPixelCount = (bestRight - bestLeft + 1) * (bestBottom - bestTop + 1)
        val fillRatio =
            if (bboxPixelCount > 0) {
                largestCount.toFloat() / bboxPixelCount.toFloat()
            } else {
                0f
            }
        return DanmakuPrimaryComponent(
            rect = candidateRect,
            pixelCount = largestCount,
            fillRatio = fillRatio,
        )
    }

    private fun extractPrimaryRect(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuNormalizedRect? {
        return extractPrimaryComponent(maskValues, width, height)?.rect
    }

    private fun isLikelyForegroundSubject(component: DanmakuPrimaryComponent): Boolean {
        val rect = component.rect
        val aspectRatio =
            if (rect.height > 0f) {
                rect.width / rect.height
            } else {
                0f
            }
        if (component.fillRatio < DANMAKU_AI_SUBJECT_MIN_FILL_RATIO) {
            return false
        }
        if (aspectRatio < DANMAKU_AI_SUBJECT_MIN_ASPECT_RATIO &&
            rect.area() >= DANMAKU_AI_SUBJECT_MAX_SPARSE_AREA_RATIO &&
            rect.height >= DANMAKU_AI_SUBJECT_MAX_SPARSE_HEIGHT_RATIO
        ) {
            return false
        }
        return true
    }

    private fun applyMaskResult(
        backend: DanmakuAiBackend,
        result: DanmakuMaskResult,
        cacheEntry: DanmakuOcclusionCacheEntry?,
        latencyMs: Long,
        motionLumaSamples: IntArray,
        motionSampleWidth: Int,
        motionSampleHeight: Int,
        motionCompensation: DanmakuMotionCompensation?,
    ) {
        warmStartDelayUntilUptimeMs = 0L
        val now = cacheEntry?.updatedAtMs ?: System.currentTimeMillis()
        latestRect = result.normalizedRect
        latestMaskValues = result.maskValues.copyOf()
        latestMaskWidth = result.maskWidth
        latestMaskHeight = result.maskHeight
        latestMaskTimestampMs = now
        consecutiveEmptyFrames = 0
        averageLatencyMs =
            if (averageLatencyMs <= 0.0) {
                latencyMs.toDouble()
            } else {
                (averageLatencyMs * 0.72) + (latencyMs.toDouble() * 0.28)
            }
        overBudgetCount =
            if (latencyMs > config.sampleIntervalMs) {
                overBudgetCount + 1
            } else {
                max(0, overBudgetCount - 1)
            }
        if (sceneCutRecoveryActive) {
            stableMaskFramesSinceSceneCut += 1
            if (sceneCutBurstSamplesRemaining > 0) {
                sceneCutBurstSamplesRemaining -= 1
            }
            if (stableMaskFramesSinceSceneCut >= DANMAKU_AI_SCENE_CUT_STABLE_MASK_FRAMES) {
                sceneCutRecoveryActive = false
                sceneCutBurstSamplesRemaining = 0
                stableMaskFramesSinceSceneCut = 0
            }
        }
        latestMaskPath = cacheEntry?.maskPath
        latestFramePath = cacheEntry?.framePath
        latestMotionReferenceFrame =
            result.normalizedRect?.let { rect ->
                DanmakuMotionReferenceFrame(
                    lumaSamples = motionLumaSamples.copyOf(),
                    sampleWidth = motionSampleWidth,
                    sampleHeight = motionSampleHeight,
                    normalizedRect = rect,
                    timestampMs = now,
                )
            }
        lastMotionCompensation = motionCompensation
        consecutiveMotionCompensationFailures = 0
        consecutiveCompensatedFrames =
            if (motionCompensation != null) {
                consecutiveCompensatedFrames + 1
            } else {
                0
            }
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = true,
                available = cacheEntry != null,
                backend = backend.wireValue,
                updatedAtMs = now,
                maskPath = cacheEntry?.maskPath,
                maskWidth = cacheEntry?.maskWidth ?: result.maskWidth,
                maskHeight = cacheEntry?.maskHeight ?: result.maskHeight,
                framePath = cacheEntry?.framePath,
                cacheHit = false,
                normalizedRect = result.normalizedRect,
            ),
        )
        if (overBudgetCount >= DANMAKU_AI_OVER_BUDGET_LIMIT) {
            handleBackendFailure(backend)
        }
    }

    private fun applyEmptyResult(
        backend: DanmakuAiBackend,
        motionCompensationAttempted: Boolean,
    ) {
        consecutiveEmptyFrames += 1
        if (motionCompensationAttempted) {
            lastMotionCompensation = null
            consecutiveMotionCompensationFailures += 1
            if (consecutiveMotionCompensationFailures >= DANMAKU_AI_MOTION_MAX_FAILURES) {
                latestMotionReferenceFrame = null
                consecutiveMotionCompensationFailures = 0
            }
        } else {
            lastMotionCompensation = null
        }
        consecutiveCompensatedFrames = 0
        if (sceneCutRecoveryActive) {
            stableMaskFramesSinceSceneCut = 0
            if (sceneCutBurstSamplesRemaining > 0) {
                sceneCutBurstSamplesRemaining -= 1
            }
        }
        if (shouldHoldPreviousMaskAfterEmptyResult()) {
            return
        }
        if (consecutiveEmptyFrames >= DANMAKU_AI_MAX_EMPTY_FRAMES) {
            clearRuntimeMaskState()
        }
        emitUnavailableState(backend = backend, keepEnabled = true)
    }

    private fun shouldHoldPreviousMaskAfterEmptyResult(): Boolean {
        if (sceneCutRecoveryActive) {
            return false
        }
        if (consecutiveEmptyFrames > DANMAKU_AI_EMPTY_RESULT_HOLD_FRAMES) {
            return false
        }
        if (latestMaskValues == null || latestMaskWidth <= 0 || latestMaskHeight <= 0) {
            return false
        }
        return latestState.enabled && latestState.available
    }

    private fun handleBackendFailure(backend: DanmakuAiBackend) {
        if (activeRuntime?.backend == backend) {
            releaseRuntime()
        }
        overBudgetCount = 0
        averageLatencyMs = 0.0
        while (activeBackendIndex < config.preferredBackendOrder.size) {
            if (config.preferredBackendOrder[activeBackendIndex] == backend) {
                activeBackendIndex += 1
                break
            }
            activeBackendIndex += 1
        }
        if (activeBackendIndex >= config.preferredBackendOrder.size) {
            stopSampling(clearPending = true)
            emitUnavailableState(backend = DanmakuAiBackend.DISABLED, keepEnabled = true)
        }
    }

    private fun emitUnavailableState(
        backend: DanmakuAiBackend,
        keepEnabled: Boolean,
    ) {
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = keepEnabled,
                available = false,
                backend = backend.wireValue,
                updatedAtMs = latestMaskTimestampMs,
                maskPath = null,
                maskWidth = 0,
                maskHeight = 0,
                framePath = null,
                cacheHit = false,
                normalizedRect = latestRect,
            ),
        )
    }

    private fun emitLatestMaskStateIfAvailable() {
        val maskPath = latestMaskPath ?: return
        if (latestMaskWidth <= 0 || latestMaskHeight <= 0) {
            return
        }
        val backendWireValue =
            latestState.backend.takeIf { it.isNotBlank() } ?: currentBackendOrFallback().wireValue
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = config.enabled,
                available = true,
                backend = backendWireValue,
                updatedAtMs = latestMaskTimestampMs,
                maskPath = maskPath,
                maskWidth = latestMaskWidth,
                maskHeight = latestMaskHeight,
                framePath = latestFramePath,
                cacheHit = latestState.cacheHit,
                normalizedRect = latestRect,
            ),
        )
    }

    private fun emitState(next: DanmakuDynamicOcclusionState) {
        if (disposed) {
            return
        }
        if (latestState == next) {
            return
        }
        latestState = next
        stateListener(next)
    }

    private fun ensureRuntime(): DanmakuSegmentationRuntime? {
        activeRuntime?.let { return it }
        while (activeBackendIndex < config.preferredBackendOrder.size) {
            val backend = config.preferredBackendOrder[activeBackendIndex]
            if (!runtimeFactory.shouldAttempt(backend)) {
                Log.d(
                    DANMAKU_AI_TAG,
                    "backend=${backend.wireValue} skipped device=${runtimeFactory.deviceSummary()}",
                )
                activeBackendIndex += 1
                continue
            }
            val runtime =
                runCatching { runtimeFactory.create(backend, config) }.getOrElse { error ->
                    Log.w(DANMAKU_AI_TAG, "backend=${backend.wireValue} init failed", error)
                    activeBackendIndex += 1
                    null
                }
            if (runtime != null) {
                activeRuntime = runtime
                Log.d(
                    DANMAKU_AI_TAG,
                    "backend=${backend.wireValue} init success device=${runtimeFactory.deviceSummary()}",
                )
                return runtime
            }
        }
        return null
    }

    private fun releaseRuntime() {
        activeRuntime?.close()
        activeRuntime = null
    }

    private fun restoreCachedState() {
        cacheRestoreEligible = false
        val source = currentSource ?: return
        val cached = cacheStore.load(source) ?: return
        if (!config.enabled) {
            return
        }
        latestRect = cached.normalizedRect
        latestMaskValues = null
        latestMaskWidth = cached.maskWidth
        latestMaskHeight = cached.maskHeight
        latestMaskPath = cached.maskPath
        latestFramePath = cached.framePath
        latestMaskTimestampMs = cached.updatedAtMs
        warmStartDelayUntilUptimeMs = SystemClock.uptimeMillis() + DANMAKU_AI_CACHE_WARM_START_DELAY_MS
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = true,
                available = true,
                backend = cached.backend,
                updatedAtMs = cached.updatedAtMs,
                maskPath = cached.maskPath,
                maskWidth = cached.maskWidth,
                maskHeight = cached.maskHeight,
                framePath = cached.framePath,
                cacheHit = true,
                normalizedRect = cached.normalizedRect,
            ),
        )
    }

    private fun persistMaskCache(
        source: MpvSource?,
        backend: DanmakuAiBackend,
        result: DanmakuMaskResult,
        frameBitmap: Bitmap,
        updatedAtMs: Long,
    ): DanmakuOcclusionCacheEntry? {
        val safeSource = source ?: return null
        val includeFrameBitmap =
            updatedAtMs - lastFrameCacheWriteAtMs >= DANMAKU_AI_CACHE_FRAME_WRITE_INTERVAL_MS
        if (includeFrameBitmap) {
            lastFrameCacheWriteAtMs = updatedAtMs
        }
        return runCatching {
            cacheStore.save(
                source = safeSource,
                backend = backend.wireValue,
                updatedAtMs = updatedAtMs,
                normalizedRect = result.normalizedRect,
                frameBitmap = if (includeFrameBitmap) frameBitmap else null,
                maskWidth = result.maskWidth,
                maskHeight = result.maskHeight,
                maskValues = result.maskValues,
            )
        }.getOrElse { error ->
            Log.w(DANMAKU_AI_TAG, "cache persist failed", error)
            null
        }
    }

    private fun clearReusableBitmap() {
        reusableBitmap?.recycle()
        reusableBitmap = null
        reusableFocusedBitmap?.recycle()
        reusableFocusedBitmap = null
    }

    private fun maybeLogSamplingSlowPath(
        sampleId: Long,
        backend: DanmakuAiBackend,
        captureLatencyMs: Long,
        inferenceLatencyMs: Long?,
        totalLatencyMs: Long,
        reason: String,
    ) {
        val inferenceMs = inferenceLatencyMs ?: -1L
        val shouldLog =
            captureLatencyMs >= DANMAKU_AI_CAPTURE_SLOW_LOG_THRESHOLD_MS ||
                (inferenceLatencyMs != null &&
                    inferenceLatencyMs >= DANMAKU_AI_INFERENCE_SLOW_LOG_THRESHOLD_MS) ||
                totalLatencyMs >= DANMAKU_AI_TOTAL_SLOW_LOG_THRESHOLD_MS
        if (!shouldLog) {
            return
        }
        Log.d(
            DANMAKU_AI_TAG,
            "sample=$sampleId backend=${backend.wireValue} captureMs=$captureLatencyMs inferenceMs=$inferenceMs totalMs=$totalLatencyMs intervalMs=${config.sampleIntervalMs} reason=$reason",
        )
    }

    private fun currentBackendOrFallback(): DanmakuAiBackend {
        return activeRuntime?.backend
            ?: config.preferredBackendOrder.getOrNull(activeBackendIndex)
            ?: DanmakuAiBackend.DISABLED
    }

    private fun currentSampleIntervalMs(): Long {
        return if (sceneCutRecoveryActive && sceneCutBurstSamplesRemaining > 0) {
            DANMAKU_AI_SCENE_CUT_BURST_INTERVAL_MS
        } else {
            config.sampleIntervalMs
        }
    }

    private fun beginSceneCutRecovery(backend: DanmakuAiBackend) {
        sceneCutRecoveryActive = true
        sceneCutBurstSamplesRemaining =
            max(sceneCutBurstSamplesRemaining, DANMAKU_AI_SCENE_CUT_BURST_SAMPLE_COUNT)
        stableMaskFramesSinceSceneCut = 0
        latestRect = null
        latestMaskValues = null
        latestMaskWidth = 0
        latestMaskHeight = 0
        latestMaskPath = null
        latestFramePath = null
        latestMaskTimestampMs = 0L
        consecutiveEmptyFrames = 0
        latestMotionReferenceFrame = null
        lastMotionCompensation = null
        consecutiveMotionCompensationFailures = 0
        consecutiveCompensatedFrames = 0
        emitUnavailableState(backend = backend, keepEnabled = true)
        if (shouldSample()) {
            mainHandler.removeCallbacks(sampleRunnable)
            samplingScheduled = false
            scheduleNextSample()
        }
    }
}
