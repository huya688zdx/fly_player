package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextPaint
import android.util.AttributeSet
import android.util.LruCache
import android.util.Log
import android.view.Choreographer
import android.view.View
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private enum class NativeDanmakuType {
    SCROLL,
    TOP,
    BOTTOM,
}

private enum class NativeDanmakuAdmissionResult {
    ADMITTED,
    QUEUED,
    BLOCKED,
    DROPPED,
    SKIPPED,
}

private enum class NativeDanmakuOverloadLevel {
    NORMAL,
    SOFT,
    HARD,
}

private data class NativeDanmakuComment(
    val id: String,
    val timeMs: Int,
    val text: String,
    val type: NativeDanmakuType,
    val color: Int,
)

private data class NativeDanmakuSettings(
    val enabled: Boolean = false,
    val opacity: Float = 0.85f,
    val density: Float = 1.0f,
    val fontScale: Float = 1.0f,
    val fontThickness: Float = 1.0f,
    val speed: Float = 0.85f,
    val displayAreaRatio: Float = 0.5f,
    val targetFrameRateHz: Int = 60,
    val scrollEnabled: Boolean = true,
    val topEnabled: Boolean = true,
    val bottomEnabled: Boolean = false,
    val colorEnabled: Boolean = true,
    val hideDuplicate: Boolean = true,
    val avoidSubtitleArea: Boolean = true,
    val playbackSpeed: Float = 1.0f,
    val sourceKey: String = "",
) {
    val effectiveOpacity: Int
        get() = (opacity.coerceIn(0.2f, 1.0f) * 255f).toInt().coerceIn(0, 255)
}

private data class NativeDanmakuBitmap(
    val bitmap: Bitmap,
    val drawWidth: Float,
    val drawHeight: Float,
)

private data class NativeDanmakuLaneLayout(
    val topTracks: FloatArray,
    val bottomOffsets: FloatArray,
)

private data class NativeDanmakuPayload(
    val settings: NativeDanmakuSettings,
    val comments: List<NativeDanmakuComment>?,
    val initialPositionMs: Float?,
)

internal object NativeDanmakuLaneScheduler {
    fun findReleasedLane(availableAtMs: FloatArray, targetTimeMs: Float): Int? {
        if (availableAtMs.isEmpty()) return null
        for (index in availableAtMs.indices) {
            if (availableAtMs[index] <= targetTimeMs) {
                return index
            }
        }
        return null
    }
}

private data class PendingNativeScrollDanmaku(
    val comment: NativeDanmakuComment,
    val eligibleAtMs: Float,
    val enqueuedAtMs: Float,
    val delayBudgetMs: Float,
    val normalizedText: String,
    val timeBucket: Int,
) {
    var displayText: String = comment.text
        private set
    var mergedCount: Int = 1
        private set

    fun mergeWith() {
        mergedCount += 1
        displayText = "${comment.text} x$mergedCount"
    }
}

private enum class NativeDanmakuOcclusionMode {
    DISABLED,
    MASK,
    BBOX,
    ;

    companion object {
        fun fromValue(raw: String?): NativeDanmakuOcclusionMode {
            return when (raw?.trim()?.lowercase()) {
                "mask" -> MASK
                "bbox" -> BBOX
                else -> DISABLED
            }
        }
    }
}

private data class NativeDanmakuOcclusionRect(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
) {
    val hasArea: Boolean
        get() = width > 0f && height > 0f
}

private data class NativeDanmakuOcclusionPayload(
    val enabled: Boolean = false,
    val available: Boolean = false,
    val backend: String = "disabled",
    val occlusionMode: String = "disabled",
    val maskPath: String? = null,
    val maskSignature: String? = null,
    val maskWidth: Int = 0,
    val maskHeight: Int = 0,
    val captureAreaRatio: Float = 1.0f,
    val normalizedRect: NativeDanmakuOcclusionRect? = null,
    val runtimeMaskBitmap: Bitmap? = null,
    val runtimeMaskVersion: Long = 0L,
) {
    val mode: NativeDanmakuOcclusionMode
        get() = NativeDanmakuOcclusionMode.fromValue(occlusionMode)

    val hasUsableMask: Boolean
        get() = available &&
            ((runtimeMaskBitmap != null && !runtimeMaskBitmap.isRecycled) ||
                !maskPath.isNullOrBlank()) &&
            maskWidth > 0 &&
            maskHeight > 0

    val hasUsableRect: Boolean
        get() = available && normalizedRect?.hasArea == true

    val shouldDelayMaskClear: Boolean
        get() = enabled && backend.trim().lowercase() != "disabled"

    val maskKey: String
        get() {
            if (!hasUsableMask) return ""
            if (runtimeMaskBitmap != null && !runtimeMaskBitmap.isRecycled) {
                val versionToken =
                    runtimeMaskVersion.takeIf { it > 0L }?.toString()
                        ?: (maskSignature?.trim()?.takeIf { it.isNotEmpty() } ?: "runtime")
                return "runtime|$versionToken|${maskWidth}x${maskHeight}"
            }
            val versionToken =
                maskSignature?.trim()?.takeIf { it.isNotEmpty() } ?: "$maskWidth:$maskHeight"
            return "${maskPath.orEmpty()}|$versionToken|${maskWidth}x${maskHeight}"
        }
}

private data class ActiveDanmakuItem(
    val id: String,
    val type: NativeDanmakuType,
    val bitmap: NativeDanmakuBitmap,
    val laneIndex: Int,
    var top: Float,
    val startMs: Float,
    val endMs: Float,
    val laneReleaseMs: Float,
    val speedPxPerMs: Float,
) {
    fun isExpired(timelineMs: Float): Boolean = timelineMs >= endMs

    fun left(viewportWidth: Float, timelineMs: Float): Float {
        return when (type) {
            NativeDanmakuType.SCROLL -> {
                val elapsedMs = (timelineMs - startMs).coerceAtLeast(0f)
                viewportWidth - (elapsedMs * speedPxPerMs)
            }
            else -> (viewportWidth - bitmap.drawWidth) / 2f
        }
    }
}

class NativeDanmakuOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    companion object {
        private const val TAG = "FlyPlayerDanmaku"
        // Plan B v2 occlusion debug logging (planb2 ...). Rate-limited in the draw path.
        private const val OCCLUSION_DEBUG_LOG = true
        private const val DEFAULT_TARGET_FPS = 60
        private const val MIN_TARGET_FPS = 24
        private const val MAX_TARGET_FPS = 120
        private const val BASE_TEXT_SIZE_SP = 22f
        private const val STROKE_WIDTH_DP = 1f
        private const val TRACK_VERTICAL_PADDING_DP = 2.5f
        private const val VIEWPORT_FONT_SCALE_REFERENCE_DP = 420f
        private const val MIN_VIEWPORT_FONT_SCALE = 0.76f
        private const val MOTION_DURATION_REFERENCE_SHORT_SIDE_DP = 420f
        private const val MIN_MOTION_DURATION_SCALE = 0.90f
        private const val MAX_MOTION_DURATION_SCALE = 1.40f
        private const val EDGE_PADDING_MIN_DP = 3f
        private const val EDGE_PADDING_MAX_DP = 10f
        private const val SUBTITLE_RESERVED_AREA_RATIO = 0.16f
        private const val SCROLL_BASE_TRAVEL_MS = 4600f
        private const val STATIC_BASE_DURATION_MS = 3200f
        // 滚动速度下限（px/ms），兼作时间线软同步增益；防止超窄视口/异常时长把速度算成 ~0。
        private const val DANMAKU_SPEED_MIN = 0.70f
        private const val DANMAKU_SPEED_MAX = 1.55f
        private const val DANMAKU_SPEED_STEP = (DANMAKU_SPEED_MAX - DANMAKU_SPEED_MIN) / 4f
        private const val DUPLICATE_WINDOW_MS = 2500
        private const val DENSITY_BUCKET_SCALE = 1000
        private const val TIMELINE_RESYNC_THRESHOLD_MS = 160f
        private const val TIMELINE_SOFT_SYNC_DEAD_ZONE_MS = 12f
        private const val TIMELINE_SOFT_SYNC_GAIN = 0.12f
        private const val TIMELINE_SOFT_SYNC_MAX_STEP_MS = 1.5f
        private const val TIMELINE_SOFT_SYNC_MIN_INTERVAL_MS = 110L
        private const val TIMELINE_SOFT_SYNC_FORCE_DRIFT_MS = 28f
        private const val TIMELINE_FORWARD_REBUILD_THRESHOLD_MS = 2500f
        private const val TIMELINE_CONTINUITY_REBUILD_GUARD_MS = 1800L
        private const val TIMELINE_CONTINUITY_SOFT_SYNC_SUPPRESS_MS = 360L
        private const val POSITION_ROLLBACK_TOLERANCE_MS = 48f
        private const val MAX_POSITION_SAMPLE_PROJECTION_MS = 50f
        private const val POSITION_SAMPLE_FULL_RELIABILITY_LATENCY_MS = 12f
        private const val POSITION_SAMPLE_ZERO_RELIABILITY_LATENCY_MS = 42f
        private const val SEEK_SETTLE_TOLERANCE_MS = 3000f
        private const val SEEK_GUARD_WINDOW_MS = 4200L
        private const val PLAYBACK_TRANSITION_GUARD_WINDOW_MS = 1400L
        private const val PAUSE_TRANSITION_SETTLE_WINDOW_MS = 220L
        private const val MAX_LOOKBACK_MS = 10_000f
        private const val FRAME_LOOKAHEAD_MS = 20f
        private const val TEXT_CACHE_SIZE = 384
        private const val VIEWPORT_REBUILD_WIDTH_DELTA_RATIO = 0.04f
        private const val VIEWPORT_REBUILD_HEIGHT_DELTA_RATIO = 0.08f
        private const val VIEWPORT_REBUILD_SCALE_DELTA = 0.015f
        private const val MASK_CLEAR_GRACE_MS = 350L
        private const val PARTIAL_MASK_BOUNDARY_BLEED_DP = 4f
        private const val PARTIAL_MASK_BOUNDARY_MAX_BLEED_RATIO = 0.035f
        private const val FPS_LOG_WINDOW_NS = 3_000_000_000L
        private const val SLOW_FRAME_THRESHOLD_MULTIPLIER = 1.35f
        private const val FRAME_SCHEDULER_TOLERANCE_NS = 250_000L
        private const val MAX_FRAME_BUDGET_MULTIPLIER = 2L
        private const val MIN_VISIBLE_SCROLL_ITEMS = 8
        private const val MAX_VISIBLE_SCROLL_ITEMS = 96
        private const val MAX_PENDING_VISIBLE_SCROLL_ITEMS = 160
        private const val PER_TRACK_VISIBLE_SCROLL_MULTIPLIER = 3.2f
        private const val PENDING_QUEUE_MINIMUM_SIZE = 360
        private const val PENDING_QUEUE_CAPACITY_MULTIPLIER = 12
        private const val PENDING_DRAIN_MINIMUM_BUDGET = 8
        private const val MAX_PENDING_DELAY_MS = 1800f
        private const val MERGE_TIME_BUCKET_MS = 1000
        private const val DRAW_SAMPLE_WINDOW_SIZE = 12
        private const val DRAW_SOFT_THRESHOLD_NS = 7_000_000L
        private const val DRAW_HARD_THRESHOLD_NS = 12_000_000L
        private const val DRAW_PRESSURE_SAMPLES = 6
        private const val RECOVERY_SAMPLES = 20
        private const val QUEUE_PRESSURE_WINDOW_MS = 2000f

        private val enablePerfLogs: Boolean
            get() = Log.isLoggable(TAG, Log.VERBOSE)
    }

    private val density = resources.displayMetrics.density
    private val strokeWidthPx = density * STROKE_WIDTH_DP
    private val edgePaddingMinPx = density * EDGE_PADDING_MIN_DP
    private val edgePaddingMaxPx = density * EDGE_PADDING_MAX_DP
    private val trackVerticalPaddingPx = density * TRACK_VERTICAL_PADDING_DP
    private val mainHandler = Handler(Looper.getMainLooper())
    private val payloadExecutor =
        java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "NativeDanmakuPayload").apply {
                isDaemon = true
            }
        }
    private val maskExecutor =
        java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "NativeDanmakuMask").apply {
                isDaemon = true
            }
        }
    private val fillPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
            textAlign = Paint.Align.LEFT
            isSubpixelText = true
        }
    private val strokePaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            style = Paint.Style.STROKE
            textAlign = Paint.Align.LEFT
            strokeJoin = Paint.Join.ROUND
            strokeMiter = 10f
            strokeWidth = strokeWidthPx
            isSubpixelText = true
        }
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val maskPaint =
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
        }
    private val maskPaintCrisp =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
        }
    private val layerPaint = Paint()
    private val maskSrcRect = Rect()
    private val maskDstRect = RectF()
    private val bboxDstRect = RectF()
    private val textCache =
        object : LruCache<String, NativeDanmakuBitmap>(TEXT_CACHE_SIZE) {
            override fun entryRemoved(
                evicted: Boolean,
                key: String,
                oldValue: NativeDanmakuBitmap,
                newValue: NativeDanmakuBitmap?,
            ) {
                if (oldValue !== newValue && !oldValue.bitmap.isRecycled) {
                    oldValue.bitmap.recycle()
                }
            }
        }

    private val frameCallback =
        object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                frameScheduled = false
                if (!shouldAnimate()) {
                    return
                }
                val throttledByScheduler = shouldThrottleFrame(frameTimeNanos)
                recordFrameStats(
                    frameTimeNanos = frameTimeNanos,
                    throttledByScheduler = throttledByScheduler,
                )
                if (throttledByScheduler) {
                    scheduleFrame()
                    return
                }
                renderFrameTimeNs = frameTimeNanos
                invalidate()
                scheduleFrame()
            }
        }

    private var attachedToHost = false
    private var frameScheduled = false
    private var frameBudgetAccumulatorNs = 0L
    private var frameBudgetLastCallbackNs = 0L
    private var renderFrameTimeNs = 0L
    private var payloadGeneration = 0
    private var maskGeneration = 0
    private var fpsWindowStartNs = 0L
    private var rawCallbackLastFrameNs = 0L
    private var rawCallbackFrameCount = 0
    private var rawCallbackAccumulatedDeltaNs = 0L
    private var rawCallbackMaxDeltaNs = 0L
    private var throttledCallbackCount = 0
    private var acceptedFrameLastNs = 0L
    private var acceptedFrameCount = 0
    private var acceptedSlowFrameCount = 0
    private var acceptedAccumulatedDeltaNs = 0L
    private var acceptedMaxDeltaNs = 0L
    private var drawWindowStartNs = 0L
    private var drawFrameCount = 0
    private var drawAccumulatedTotalNs = 0L
    private var drawAccumulatedTimelineNs = 0L
    private var drawAccumulatedBitmapNs = 0L
    private var drawAccumulatedMaskNs = 0L
    private var drawAccumulatedItems = 0
    private var drawMaxNs = 0L
    private var playbackSyncWindowStartNs = 0L
    private var playbackSyncSampleCount = 0
    private var playbackSyncAccumulatedSampleLatencyMs = 0f
    private var playbackSyncMaxSampleLatencyMs = 0f
    private var playbackSyncAccumulatedProjectionMs = 0f
    private var playbackSyncMaxProjectionMs = 0f
    private var playbackSyncAccumulatedRawDriftAbsMs = 0f
    private var playbackSyncAccumulatedStabilizedDriftAbsMs = 0f
    private var playbackSyncMaxRawDriftAbsMs = 0f
    private var playbackSyncMaxStabilizedDriftAbsMs = 0f
    private var playbackSyncRebuildCount = 0
    private var playbackSyncReanchorCount = 0
    private var playbackSyncSoftSyncPathCount = 0
    private var playbackSyncSoftSyncAppliedCount = 0
    private var playbackSyncLatencyFilteredCount = 0

    private var settings = NativeDanmakuSettings()
    private var comments: List<NativeDanmakuComment> = emptyList()
    private var occlusion = NativeDanmakuOcclusionPayload()

    // Between-sample mask motion extrapolation. The controller estimates global
    // frame velocity (normalized units per ms); each draw we offset the mask by
    // velocity * (time since the mask was anchored), so the mask follows motion
    // instead of freezing until the next ~0.7s sample.
    private var maskVelocityX = 0.0
    private var maskVelocityY = 0.0
    private var maskAnchorUptimeMs = 0L
    // Gentler than before (was 900ms / 0.18): the old extrapolation over-slid the whole
    // mask and felt "too strong". Capped tighter so motion tracking (when enabled) only
    // nudges the mask forward to offset live-capture lag, without flying off.
    private val maskExtrapMaxMs = 600L
    private val maskExtrapMaxFraction = 0.08f

    // Plan B: masks are precomputed AHEAD of playback and tagged with the video PTS
    // (ms) they belong to. We buffer recent masks and, each draw, pick the one whose
    // PTS matches the current playback time → the mask is synced to the frame, not
    // lagging behind it. Bitmaps are copied (the controller recycles its own).
    // Plan B v2: each buffered mask carries its OWN per-step velocity + sceneCut flag +
    // the producer step it belongs to, so the renderer extrapolates with the velocity
    // measured at that mask's moment (not a single controller-pushed global velocity)
    // and never extrapolates across a scene cut.
    private class MaskFrame(
        val ptsMs: Long,
        val bitmap: Bitmap,
        val vxPerMs: Double,
        val vyPerMs: Double,
        val sceneCut: Boolean,
        val stepMs: Long,
    )

    private val maskPtsBuffer = ArrayDeque<MaskFrame>()
    private val maskPtsBufferCap = 12

    // If the floor-selected mask is older than this, the mask is for the wrong moment —
    // drawing it would occlude the wrong spot. Better to show nothing briefly. Plan B v2:
    // tightened to ~1.5x the producer step (dynamic, updated on each push) since masks now
    // arrive ~every 280ms; until the first PTS mask arrives it stays at the legacy 1100ms.
    private var maskStaleMaxMs = 1100L

    // Plan B (PTS-synced) is active once we've received a mask tagged with a video PTS.
    // In this mode the draw path relies solely on the PTS buffer and must NOT fall back
    // to the single latest mask (which would re-introduce the stale wrong-spot draw the
    // staleness guard exists to prevent).
    private var ptsMaskMode = false

    // Phase 3 — 逐条弹幕防碎片 (per-comment draw-whole). DISABLED by default: real-device
    // feedback showed "draw whole over the subject" reads as 压脸 (covers the face) and the
    // per-frame classification flicker made comments blink. With the crisp carve (mask alpha
    // aligned to the foreground threshold) the subject already shows through cleanly
    // (穿透), so pure carving is preferred. >0 re-enables: comments overlapping the subject
    // by ≥ this ratio are drawn AFTER the mask (uncarved) instead of carved. Tunable.
    private val occlusionDrawWholeRatio = 0f
    private val occlusionCoverageAlphaThreshold = 110 // mask alpha (0-255) counted as "subject"
    private val occlusionCoverageSamplesX = 6
    private val occlusionCoverageSamplesY = 3
    private val drawWholeItems = ArrayList<ActiveDanmakuItem>()
    private val occlusionContentRect = RectF()
    // Cached ARGB pixels of the mask currently used for coverage sampling (extracted once
    // per mask bitmap change, not per frame).
    private var coverageMaskRef: Bitmap? = null
    private var coveragePixels: IntArray? = null
    private var coverageMaskW = 0
    private var coverageMaskH = 0

    // Plan B only: display aspect (w/h) of the raw video frame the mask came from. Used
    // to map the full-frame mask onto the letterboxed video rect inside the view. 0 =
    // unknown / live-capture path (mask already matches the rendered surface → full view).
    private var occlusionVideoAspect = 0f

    private fun pushMaskFrame(
        ptsMs: Long,
        vxPerMs: Double,
        vyPerMs: Double,
        sceneCut: Boolean,
        stepMs: Long,
        source: Bitmap,
    ) {
        if (source.isRecycled) return
        val copy = runCatching { source.copy(Bitmap.Config.ARGB_8888, false) }.getOrNull() ?: return
        maskPtsBuffer.addLast(MaskFrame(ptsMs, copy, vxPerMs, vyPerMs, sceneCut, stepMs))
        while (maskPtsBuffer.size > maskPtsBufferCap) {
            maskPtsBuffer.removeFirst().bitmap.takeIf { !it.isRecycled }?.recycle()
        }
        if (stepMs > 0L) {
            maskStaleMaxMs = (stepMs * 3L / 2L).coerceAtLeast(360L)
        }
    }

    // Plan B v2: FLOOR selection — the newest mask whose PTS is <= the current timeline.
    // Picking the absolute-nearest could grab a FUTURE mask and occlude a spot the video
    // hasn't reached yet. A future-only buffer (all PTS > t, e.g. right after a seek)
    // yields null → draw nothing until the matching mask lands.
    private fun selectMaskForTimeline(timelineMs: Long): MaskFrame? {
        var best: MaskFrame? = null
        for (frame in maskPtsBuffer) {
            if (frame.bitmap.isRecycled) continue
            if (frame.ptsMs > timelineMs) continue
            if (best == null || frame.ptsMs > best.ptsMs) {
                best = frame
            }
        }
        // Too stale → wrong moment; skip rather than occlude the wrong spot.
        if (best != null && timelineMs - best.ptsMs > maskStaleMaxMs) return null
        return best
    }

    // E1: the current time t is bracketed by the buffered floor mask (PTS <= t) and the
    // next mask (smallest PTS > floor). Drawing both at full alpha covers the subject's
    // swept path t0→t1 → no "mask lags the moving person" feel, independent of velocity.
    private class MaskBracket(val floor: MaskFrame, val next: MaskFrame?)

    private fun selectMaskBracket(timelineMs: Long): MaskBracket? {
        var floor: MaskFrame? = null
        for (frame in maskPtsBuffer) {
            if (frame.bitmap.isRecycled) continue
            if (frame.ptsMs > timelineMs) continue
            if (floor == null || frame.ptsMs > floor.ptsMs) floor = frame
        }
        val f = floor ?: return null
        if (timelineMs - f.ptsMs > maskStaleMaxMs) return null
        var next: MaskFrame? = null
        for (frame in maskPtsBuffer) {
            if (frame.bitmap.isRecycled) continue
            if (frame.ptsMs <= f.ptsMs) continue
            if (next == null || frame.ptsMs < next.ptsMs) next = frame
        }
        return MaskBracket(f, next)
    }

    private fun clearMaskPtsBuffer() {
        for (frame in maskPtsBuffer) {
            frame.bitmap.takeIf { !it.isRecycled }?.recycle()
        }
        maskPtsBuffer.clear()
        // Drop the coverage cache; it may reference a now-recycled buffered mask.
        coverageMaskRef = null
    }

    // E0 diagnostic: dErr (t - floorPts) is the floor-selection lag (expect 0..step);
    // tMinusPos (danmaku timeline vs last pushed mpv position) reveals any constant
    // soft-sync bias that would systematically offset selection (>80ms ⇒ add a constant
    // compensation at selection). Rate-limited to ~1/s.
    private var lastMaskBiasLogMs = 0L

    private fun maybeLogMaskBias(timelineMs: Long, floor: MaskFrame?, next: MaskFrame?, unionDrawn: Boolean) {
        if (!OCCLUSION_DEBUG_LOG) return
        val now = SystemClock.uptimeMillis()
        if (now - lastMaskBiasLogMs < 1000L) return
        lastMaskBiasLogMs = now
        var newest = Long.MIN_VALUE
        for (f in maskPtsBuffer) {
            if (!f.bitmap.isRecycled && f.ptsMs > newest) newest = f.ptsMs
        }
        val pos = lastKnownPositionMs.toLong()
        Log.d(
            TAG,
            "planb2 draw t=$timelineMs pos=$pos tMinusPos=${timelineMs - pos} " +
                "floorPts=${floor?.ptsMs ?: -1} nextPts=${next?.ptsMs ?: -1} " +
                "dErr=${if (floor != null) timelineMs - floor.ptsMs else -1} union=$unionDrawn " +
                "bufferAhead=${if (newest > Long.MIN_VALUE) newest - timelineMs else -1} buf=${maskPtsBuffer.size}",
        )
    }
    private var laneLayout = NativeDanmakuLaneLayout(FloatArray(0), FloatArray(0))
    private var effectiveDensityRatio = 1.0f
    private var topLaneAvailableAtMs = FloatArray(0)
    private var bottomLaneAvailableAtMs = FloatArray(0)
    // 滚动弹幕「追及碰撞」检测的每轨道前车状态：上一条滚动弹幕的速度 / 起始时间 / 绘制宽度。
    // 变速下后车可能追上前车，需用前车这些量判断本条进场后会不会追尾（见 findScrollLaneAntiCollision）。
    private var topLaneLastSpeedPxPerMs = FloatArray(0)
    private var topLaneLastStartMs = FloatArray(0)
    private var topLaneLastDrawWidthPx = FloatArray(0)
    private var activeItems = ArrayList<ActiveDanmakuItem>()
    private var pendingScrollItems = ArrayList<PendingNativeScrollDanmaku>()
    private var pendingScrollIds = HashSet<String>()
    private var duplicateWindow = HashMap<String, Int>()
    private var nextCommentIndex = 0
    private var currentMaskBitmap: Bitmap? = null
    private var currentMaskKey: String? = null
    private var pendingMaskClear: Runnable? = null
    private var appliedRequestedFrameRateHint = Float.NaN

    private var lastKnownPositionMs = 0f
    private var timelineAnchorPositionMs = 0f
    private var timelineAnchorTimeNs = 0L
    private var lastSoftSyncAppliedNs = 0L
    private var paused = true
    private var pendingSeekTargetMs: Float? = null
    private var pendingSeekGuardUntilNs = 0L
    private var playbackFloorGuardMs: Float? = null
    private var playbackFloorGuardUntilNs = 0L
    private var pausedAnchorGuardMs: Float? = null
    private var pausedAnchorGuardUntilNs = 0L
    private var timelineContinuityRebuildGuardUntilNs = 0L
    private var timelineContinuitySoftSyncSuppressUntilNs = 0L
    private var overloadLevel = NativeDanmakuOverloadLevel.NORMAL
    private val recentDrawElapsedNs = ArrayList<Long>(DRAW_SAMPLE_WINDOW_SIZE)
    private var paintSoftStreak = 0
    private var paintHardStreak = 0
    private var recoveryStreak = 0
    private var queuePressureStreak = 0
    private var queueHealthyForRecovery = true
    private var lastQueuePressureEvaluationMs = 0f
    private var schedulerQueuedByCapacityCount = 0
    private var schedulerQueuedByTrackCount = 0
    private var schedulerBlockedByCapacityCount = 0
    private var schedulerBlockedByTrackCount = 0
    private var schedulerDrainedFromQueueCount = 0
    private var schedulerDroppedFromQueueCount = 0
    private var schedulerDroppedByTrimCount = 0
    private var schedulerMergedCount = 0
    private var lastWindowPendingCount = 0
    private var lastWindowDrainedCount = 0
    private var lastWindowBlockedCount = 0

    init {
        isClickable = false
        isFocusable = false
        alpha = 1f
        applyRequestedFrameRateVote(reason = "init")
    }

    fun updatePlaybackState(state: MpvPlayerState) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { updatePlaybackState(state) }
            return
        }
        val nowNs = currentAnimationClockNs(System.nanoTime())
        val previousPaused = paused
        val nextPaused = state.playbackPhase != MpvPlaybackPhase.PLAYING.wireValue
        val sampleTimeNs =
            state.positionSampleTimeNs
                .takeIf { it > 0L }
                ?.coerceAtMost(nowNs)
                ?: nowNs
        val sampledPositionMs = state.positionMs.toFloat().coerceAtLeast(0f)
        val rawNextPositionMs =
            projectIncomingPositionMs(
                sampledPositionMs = sampledPositionMs,
                sampleTimeNs = sampleTimeNs,
                nowNs = nowNs,
                nextPaused = nextPaused,
                playbackPhase = state.playbackPhase,
            )
        val predictedMs = currentTimelineMs(nowNs)
        val sampleLatencyMs = ((nowNs - sampleTimeNs).coerceAtLeast(0L) / 1_000_000f)
        val projectionMs = rawNextPositionMs - sampledPositionMs
        val rawTimelineDriftMs = rawNextPositionMs - predictedMs
        val latencyAdjustedPositionMs =
            applyPositionSampleLatencyFilter(
                rawPositionMs = rawNextPositionMs,
                predictedMs = predictedMs,
                sampleLatencyMs = sampleLatencyMs,
                nextPaused = nextPaused,
                playbackPhase = state.playbackPhase,
            )
        expirePlaybackStateGuards(nowNs)
        if (state.playbackPhase == MpvPlaybackPhase.SEEKING.wireValue) {
            armSeekGuard(sampledPositionMs, nowNs)
        }
        val pauseTransition = !previousPaused && nextPaused
        val resumeTransition = previousPaused && !nextPaused
        if (pauseTransition) {
            armPausedAnchorGuard(predictedMs, nowNs)
        } else if (resumeTransition) {
            clearPausedAnchorGuard()
            armTimelineContinuityGuard(nowNs)
        }
        if (previousPaused != nextPaused && !nextPaused) {
            armPlaybackFloorGuard(
                max(lastKnownPositionMs, predictedMs),
                nowNs,
            )
        }
        if (nextPaused) {
            clearPlaybackFloorGuard()
        }
        val nextPositionMs =
            stabilizeIncomingPosition(
                rawPositionMs = latencyAdjustedPositionMs,
                predictedMs = predictedMs,
                nextPaused = nextPaused,
                playbackPhase = state.playbackPhase,
                nowNs = nowNs,
            )
        val isSeekingState = state.playbackPhase == MpvPlaybackPhase.SEEKING.wireValue
        val stabilizedTimelineDriftMs = nextPositionMs - predictedMs
        paused = nextPaused
        lastKnownPositionMs = nextPositionMs
        var softSyncApplied = false
        var shouldResetTimeline = false
        var reanchorSelected = false
        var softSyncSelected = false
        if (comments.isEmpty() || isSeekingState) {
            shouldResetTimeline = true
            rebuildTimeline(nextPositionMs, nowNs)
        } else if (pauseTransition || resumeTransition) {
            reanchorSelected = true
            reanchorTimeline(predictedMs, nowNs)
        } else if (nextPaused) {
            // Paused mpv state can be resent when controls appear/disappear. Keep
            // the danmaku frame frozen unless an explicit seek is being reported.
        } else {
            val playbackTransitionGuardActive =
                playbackFloorGuardUntilNs > nowNs && pendingSeekTargetMs == null
            val timelineRebuildGuardActive =
                timelineContinuityRebuildGuardUntilNs > nowNs &&
                    pendingSeekTargetMs == null
            val softSyncSuppressed =
                timelineContinuitySoftSyncSuppressUntilNs > nowNs &&
                    pendingSeekTargetMs == null
            val negativeDriftRequiresRebuild =
                stabilizedTimelineDriftMs < -TIMELINE_RESYNC_THRESHOLD_MS
            val forwardDriftRequiresRebuild =
                stabilizedTimelineDriftMs > TIMELINE_FORWARD_REBUILD_THRESHOLD_MS
            shouldResetTimeline =
                (negativeDriftRequiresRebuild || forwardDriftRequiresRebuild) &&
                    !playbackTransitionGuardActive &&
                    !timelineRebuildGuardActive
            if (shouldResetTimeline) {
                rebuildTimeline(nextPositionMs, nowNs)
            } else if (!softSyncSuppressed) {
                softSyncSelected = true
                softSyncApplied =
                    softSyncTimeline(
                        predictedMs = predictedMs,
                        targetMs = nextPositionMs,
                        nowNs = nowNs,
                    )
            }
        }
        recordPlaybackSyncStats(
            nowNs = nowNs,
            sampleLatencyMs = sampleLatencyMs,
            projectionMs = projectionMs,
            rawDriftMs = rawTimelineDriftMs,
            stabilizedDriftMs = stabilizedTimelineDriftMs,
            rebuildTimeline = shouldResetTimeline,
            reanchorTimeline = reanchorSelected,
            softSyncSelected = softSyncSelected,
            softSyncApplied = softSyncApplied,
            latencyFiltered = abs(latencyAdjustedPositionMs - rawNextPositionMs) >= 0.5f,
        )
        invalidate()
        if (shouldAnimate()) {
            scheduleFrame()
        } else {
            cancelFrame()
        }
    }

    fun hintSeek(positionMs: Long) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { hintSeek(positionMs) }
            return
        }
        val targetMs = positionMs.toFloat().coerceAtLeast(0f)
        val nowNs = currentAnimationClockNs(System.nanoTime())
        armSeekGuard(targetMs, nowNs)
        // Buffered Plan B masks belong to the old timeline; drop them after a seek.
        clearMaskPtsBuffer()
        lastKnownPositionMs = targetMs
        if (settings.enabled && comments.isNotEmpty()) {
            rebuildTimeline(targetMs, nowNs)
        } else {
            reanchorTimeline(targetMs, nowNs)
            activeItems.clear()
            clearPendingScrollQueue()
            duplicateWindow.clear()
        }
        invalidate()
        if (shouldAnimate()) {
            scheduleFrame()
        } else {
            cancelFrame()
        }
    }

    fun setPayload(payload: Map<String, Any?>) {
        val generation = ++payloadGeneration
        payloadExecutor.execute {
            val nextPayload = preprocessPayload(payload)
            mainHandler.post {
                if (generation != payloadGeneration) {
                    return@post
                }
                applyPayload(nextPayload)
            }
        }
    }

    fun clear() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { clear() }
            return
        }
        payloadGeneration += 1
        maskGeneration += 1
        settings = NativeDanmakuSettings()
        comments = emptyList()
        occlusion = NativeDanmakuOcclusionPayload()
        activeItems.clear()
        pendingScrollItems.clear()
        pendingScrollIds.clear()
        duplicateWindow.clear()
        resetDynamicDanmakuState(clearOverload = true)
        nextCommentIndex = 0
        laneLayout = NativeDanmakuLaneLayout(FloatArray(0), FloatArray(0))
        topLaneAvailableAtMs = FloatArray(0)
        bottomLaneAvailableAtMs = FloatArray(0)
        topLaneLastSpeedPxPerMs = FloatArray(0)
        topLaneLastStartMs = FloatArray(0)
        topLaneLastDrawWidthPx = FloatArray(0)
        lastKnownPositionMs = 0f
        timelineAnchorPositionMs = 0f
        timelineAnchorTimeNs = System.nanoTime()
        lastSoftSyncAppliedNs = 0L
        clearSeekGuard()
        clearPlaybackFloorGuard()
        clearTimelineContinuityGuard()
        clearMaskState()
        resetPlaybackSyncStats()
        cancelFrame()
        applyRequestedFrameRateVote(reason = "clear")
        invalidate()
    }

    fun setOcclusionState(payload: Map<String, Any?>) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { setOcclusionState(payload) }
            return
        }
        applyOcclusionState(
            NativeDanmakuOcclusionPayload(
                enabled = payload["enabled"] as? Boolean ?: false,
                available = payload["available"] as? Boolean ?: false,
                backend = payload["backend"]?.toString()?.trim().orEmpty().ifBlank { "disabled" },
                occlusionMode =
                    payload["occlusionMode"]?.toString()?.trim().orEmpty().ifBlank { "disabled" },
                maskPath = payload["maskPath"]?.toString()?.trim()?.takeIf { it.isNotEmpty() },
                maskSignature = payload["maskSignature"]?.toString()?.trim()?.takeIf { it.isNotEmpty() },
                maskWidth = payload["maskWidth"].toIntValue() ?: 0,
                maskHeight = payload["maskHeight"].toIntValue() ?: 0,
                captureAreaRatio =
                    ((payload["captureAreaRatio"].toDoubleValue() ?: 1.0).toFloat()).coerceIn(0.1f, 1.0f),
                normalizedRect =
                    (payload["normalizedRect"] as? Map<*, *>)?.let { rawRect ->
                        NativeDanmakuOcclusionRect(
                            x = ((rawRect["x"].toDoubleValue() ?: 0.0).toFloat()).coerceIn(0f, 1f),
                            y = ((rawRect["y"].toDoubleValue() ?: 0.0).toFloat()).coerceIn(0f, 1f),
                            width =
                                ((rawRect["width"].toDoubleValue() ?: 0.0).toFloat()).coerceIn(0f, 1f),
                            height =
                                ((rawRect["height"].toDoubleValue() ?: 0.0).toFloat()).coerceIn(0f, 1f),
                        )
                    },
            ),
        )
    }

    fun setOcclusionState(
        state: DanmakuDynamicOcclusionState,
        runtimeMaskBitmap: Bitmap?,
    ) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { setOcclusionState(state, runtimeMaskBitmap) }
            return
        }
        // Anchor mask motion extrapolation to this sample.
        maskVelocityX = state.maskVelocityX
        maskVelocityY = state.maskVelocityY
        maskAnchorUptimeMs = SystemClock.uptimeMillis()
        // Plan B: buffer the precomputed mask under its video PTS for PTS-synced draw.
        // PTS mode tracks the CURRENT source: a mask carrying a PTS (>0) means Plan B
        // (local); a mask without one means the live-capture path (network). Only flip
        // when an actual mask is present so empty/cleared states don't toggle it.
        if (runtimeMaskBitmap != null && !runtimeMaskBitmap.isRecycled) {
            if (state.maskPtsMs > 0L) {
                ptsMaskMode = true
                occlusionVideoAspect = state.videoAspect.toFloat()
                pushMaskFrame(
                    ptsMs = state.maskPtsMs,
                    vxPerMs = state.maskVelocityX,
                    vyPerMs = state.maskVelocityY,
                    sceneCut = state.maskSceneCut,
                    stepMs = state.effectiveSampleIntervalMs,
                    source = runtimeMaskBitmap,
                )
            } else {
                ptsMaskMode = false
                occlusionVideoAspect = 0f
            }
        }
        applyOcclusionState(
            NativeDanmakuOcclusionPayload(
                enabled = state.enabled,
                available = state.available,
                backend = state.backend.trim().ifEmpty { "disabled" },
                occlusionMode = state.occlusionMode.trim().ifEmpty { "disabled" },
                maskPath = state.maskPath?.trim()?.takeIf { it.isNotEmpty() },
                maskSignature = state.maskSignature?.trim()?.takeIf { it.isNotEmpty() },
                maskWidth = state.maskWidth,
                maskHeight = state.maskHeight,
                captureAreaRatio = state.captureAreaRatio.coerceIn(0.1f, 1.0f),
                normalizedRect =
                    state.normalizedRect?.let { rect ->
                        NativeDanmakuOcclusionRect(
                            x = rect.x.toFloat().coerceIn(0f, 1f),
                            y = rect.y.toFloat().coerceIn(0f, 1f),
                            width = rect.width.toFloat().coerceIn(0f, 1f),
                            height = rect.height.toFloat().coerceIn(0f, 1f),
                        )
                    },
                runtimeMaskBitmap = runtimeMaskBitmap?.takeIf { !it.isRecycled },
                runtimeMaskVersion = state.updatedAtMs,
            ),
        )
    }

    private fun applyOcclusionState(next: NativeDanmakuOcclusionPayload) {
        val incomingRuntimeMask = next.runtimeMaskBitmap?.takeIf { !it.isRecycled }
        if (
            next == occlusion &&
                (
                    next.mode != NativeDanmakuOcclusionMode.MASK ||
                        (next.maskKey == currentMaskKey &&
                            (incomingRuntimeMask == null || incomingRuntimeMask === currentMaskBitmap))
                )
        ) {
            return
        }
        occlusion = next
        maskGeneration += 1
        if (next.mode == NativeDanmakuOcclusionMode.MASK && next.hasUsableMask) {
            cancelPendingMaskClear()
            val nextMaskKey = next.maskKey
            val currentMask = currentMaskBitmap
            if (
                nextMaskKey == currentMaskKey &&
                    currentMask != null &&
                    !currentMask.isRecycled &&
                    (incomingRuntimeMask == null || incomingRuntimeMask === currentMask)
            ) {
                return
            }
            incomingRuntimeMask?.let { runtimeMask ->
                replaceMaskBitmap(runtimeMask, nextMaskKey)
                invalidate()
                return
            }
            loadMaskAsync(next, nextMaskKey)
            return
        }
        cancelPendingMaskClear()
        if (next.mode != NativeDanmakuOcclusionMode.MASK) {
            clearLoadedMaskBitmap()
        }
        if (next.mode == NativeDanmakuOcclusionMode.BBOX && next.hasUsableRect) {
            invalidate()
            return
        }
        if (next.shouldDelayMaskClear) {
            scheduleMaskClear()
        } else {
            clearMaskState()
        }
        invalidate()
    }

    private fun stabilizeIncomingPosition(
        rawPositionMs: Float,
        predictedMs: Float,
        nextPaused: Boolean,
        playbackPhase: String,
        nowNs: Long,
    ): Float {
        var stabilizedMs = rawPositionMs
        if (!nextPaused &&
            playbackPhase != MpvPlaybackPhase.SEEKING.wireValue &&
            stabilizedMs + POSITION_ROLLBACK_TOLERANCE_MS < predictedMs
        ) {
            stabilizedMs = predictedMs
        }
        val pendingSeekTargetMs = pendingSeekTargetMs
        if (pendingSeekTargetMs != null) {
            val targetDeltaMs = abs(stabilizedMs - pendingSeekTargetMs)
            if (targetDeltaMs <= SEEK_SETTLE_TOLERANCE_MS) {
                clearSeekGuard()
            } else if (pendingSeekGuardUntilNs > nowNs) {
                val predictedDeltaMs = abs(predictedMs - pendingSeekTargetMs)
                if (targetDeltaMs > predictedDeltaMs + POSITION_ROLLBACK_TOLERANCE_MS) {
                    stabilizedMs = max(stabilizedMs, predictedMs)
                }
            } else {
                clearSeekGuard()
            }
        }
        val playbackFloorGuardMs = playbackFloorGuardMs
        if (playbackFloorGuardMs != null) {
            if (playbackFloorGuardUntilNs > nowNs) {
                if (stabilizedMs + POSITION_ROLLBACK_TOLERANCE_MS < playbackFloorGuardMs) {
                    stabilizedMs = playbackFloorGuardMs
                } else if (stabilizedMs >= playbackFloorGuardMs - POSITION_ROLLBACK_TOLERANCE_MS) {
                    clearPlaybackFloorGuard()
                }
            } else {
                clearPlaybackFloorGuard()
            }
        }
        val pausedAnchorGuardMs = pausedAnchorGuardMs
        if (nextPaused && pausedAnchorGuardMs != null) {
            if (pausedAnchorGuardUntilNs > nowNs) {
                stabilizedMs = pausedAnchorGuardMs
            } else {
                clearPausedAnchorGuard()
            }
        } else if (!nextPaused && pausedAnchorGuardUntilNs != 0L) {
            clearPausedAnchorGuard()
        }
        return stabilizedMs
    }

    private fun projectIncomingPositionMs(
        sampledPositionMs: Float,
        sampleTimeNs: Long,
        nowNs: Long,
        nextPaused: Boolean,
        playbackPhase: String,
    ): Float {
        if (nextPaused || playbackPhase == MpvPlaybackPhase.SEEKING.wireValue) {
            return sampledPositionMs
        }
        if (sampleTimeNs <= 0L || nowNs <= sampleTimeNs) {
            return sampledPositionMs
        }
        val projectedElapsedMs =
            ((nowNs - sampleTimeNs).coerceAtLeast(0L) / 1_000_000f)
                .coerceAtMost(MAX_POSITION_SAMPLE_PROJECTION_MS)
        return sampledPositionMs +
            (projectedElapsedMs * settings.playbackSpeed.coerceAtLeast(0.1f))
    }

    private fun applyPositionSampleLatencyFilter(
        rawPositionMs: Float,
        predictedMs: Float,
        sampleLatencyMs: Float,
        nextPaused: Boolean,
        playbackPhase: String,
    ): Float {
        if (nextPaused || playbackPhase == MpvPlaybackPhase.SEEKING.wireValue) {
            return rawPositionMs
        }
        val reliability =
            when {
                sampleLatencyMs <= POSITION_SAMPLE_FULL_RELIABILITY_LATENCY_MS -> 1f
                sampleLatencyMs >= POSITION_SAMPLE_ZERO_RELIABILITY_LATENCY_MS -> 0f
                else -> {
                    val span =
                        POSITION_SAMPLE_ZERO_RELIABILITY_LATENCY_MS -
                            POSITION_SAMPLE_FULL_RELIABILITY_LATENCY_MS
                    1f - ((sampleLatencyMs - POSITION_SAMPLE_FULL_RELIABILITY_LATENCY_MS) / span)
                }
            }.coerceIn(0f, 1f)
        if (reliability >= 0.999f) {
            return rawPositionMs
        }
        return predictedMs + ((rawPositionMs - predictedMs) * reliability)
    }

    private fun armSeekGuard(targetMs: Float, nowNs: Long) {
        pendingSeekTargetMs = targetMs.coerceAtLeast(0f)
        pendingSeekGuardUntilNs = nowNs + (SEEK_GUARD_WINDOW_MS * 1_000_000L)
        clearPlaybackFloorGuard()
        clearTimelineContinuityGuard()
    }

    private fun clearSeekGuard() {
        pendingSeekTargetMs = null
        pendingSeekGuardUntilNs = 0L
    }

    private fun armPlaybackFloorGuard(positionMs: Float, nowNs: Long) {
        if (pendingSeekTargetMs != null) {
            return
        }
        playbackFloorGuardMs = positionMs.coerceAtLeast(0f)
        playbackFloorGuardUntilNs =
            nowNs + (PLAYBACK_TRANSITION_GUARD_WINDOW_MS * 1_000_000L)
    }

    private fun clearPlaybackFloorGuard() {
        playbackFloorGuardMs = null
        playbackFloorGuardUntilNs = 0L
    }

    private fun armTimelineContinuityGuard(nowNs: Long) {
        timelineContinuityRebuildGuardUntilNs =
            nowNs + (TIMELINE_CONTINUITY_REBUILD_GUARD_MS * 1_000_000L)
        timelineContinuitySoftSyncSuppressUntilNs =
            nowNs + (TIMELINE_CONTINUITY_SOFT_SYNC_SUPPRESS_MS * 1_000_000L)
    }

    private fun clearTimelineContinuityGuard() {
        timelineContinuityRebuildGuardUntilNs = 0L
        timelineContinuitySoftSyncSuppressUntilNs = 0L
    }

    private fun armPausedAnchorGuard(positionMs: Float, nowNs: Long) {
        pausedAnchorGuardMs = positionMs.coerceAtLeast(0f)
        pausedAnchorGuardUntilNs =
            nowNs + (PAUSE_TRANSITION_SETTLE_WINDOW_MS * 1_000_000L)
    }

    private fun clearPausedAnchorGuard() {
        pausedAnchorGuardMs = null
        pausedAnchorGuardUntilNs = 0L
    }

    private fun reanchorTimeline(positionMs: Float, nowNs: Long) {
        timelineAnchorPositionMs = positionMs.coerceAtLeast(0f)
        timelineAnchorTimeNs = nowNs
    }

    private fun softSyncTimeline(
        predictedMs: Float,
        targetMs: Float,
        nowNs: Long,
    ): Boolean {
        val driftMs = targetMs - predictedMs
        // Avoid pulling the visible danmaku timeline backward during normal
        // playback. Small negative drifts are common around UI wake/layout
        // interactions and are more noticeable than a slight forward bias.
        // Large backward jumps still go through the rebuild / pause / seek
        // paths before reaching soft sync.
        if (driftMs < 0f) {
            return false
        }
        if (abs(driftMs) <= TIMELINE_SOFT_SYNC_DEAD_ZONE_MS) {
            return false
        }
        val sinceLastSoftSyncNs =
            if (lastSoftSyncAppliedNs == 0L) {
                Long.MAX_VALUE
            } else {
                (nowNs - lastSoftSyncAppliedNs).coerceAtLeast(0L)
            }
        if (sinceLastSoftSyncNs < (TIMELINE_SOFT_SYNC_MIN_INTERVAL_MS * 1_000_000L) &&
            abs(driftMs) < TIMELINE_SOFT_SYNC_FORCE_DRIFT_MS
        ) {
            return false
        }
        val deltaMs =
            (driftMs * TIMELINE_SOFT_SYNC_GAIN)
                .coerceIn(
                    -TIMELINE_SOFT_SYNC_MAX_STEP_MS,
                    TIMELINE_SOFT_SYNC_MAX_STEP_MS,
                )
        val correctedTimelineMs = predictedMs + deltaMs
        lastSoftSyncAppliedNs = nowNs
        reanchorTimeline(correctedTimelineMs, nowNs)
        return true
    }

    private fun expirePlaybackStateGuards(nowNs: Long) {
        if (pendingSeekGuardUntilNs != 0L && pendingSeekGuardUntilNs <= nowNs) {
            clearSeekGuard()
        }
        if (playbackFloorGuardUntilNs != 0L && playbackFloorGuardUntilNs <= nowNs) {
            clearPlaybackFloorGuard()
        }
        if (pausedAnchorGuardUntilNs != 0L && pausedAnchorGuardUntilNs <= nowNs) {
            clearPausedAnchorGuard()
        }
        if (timelineContinuityRebuildGuardUntilNs != 0L &&
            timelineContinuityRebuildGuardUntilNs <= nowNs
        ) {
            timelineContinuityRebuildGuardUntilNs = 0L
        }
        if (timelineContinuitySoftSyncSuppressUntilNs != 0L &&
            timelineContinuitySoftSyncSuppressUntilNs <= nowNs
        ) {
            timelineContinuitySoftSyncSuppressUntilNs = 0L
        }
    }

    fun release() {
        payloadGeneration += 1
        maskGeneration += 1
        cancelFrame()
        payloadExecutor.shutdownNow()
        maskExecutor.shutdownNow()
        textCache.evictAll()
        activeItems.clear()
        pendingScrollItems.clear()
        pendingScrollIds.clear()
        duplicateWindow.clear()
        resetDynamicDanmakuState(clearOverload = true)
        clearSeekGuard()
        clearPlaybackFloorGuard()
        clearTimelineContinuityGuard()
        clearMaskState()
        resetFrameStats()
        resetPlaybackSyncStats()
        clearRequestedFrameRateVote(reason = "release")
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attachedToHost = true
        applyRequestedFrameRateVote(reason = "attach")
        if (shouldAnimate()) {
            scheduleFrame()
        }
    }

    override fun onDetachedFromWindow() {
        attachedToHost = false
        clearRequestedFrameRateVote(reason = "detach")
        cancelFrame()
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == oldw && h == oldh) return
        val nowNs = currentAnimationClockNs(System.nanoTime())
        val timelineMs = currentTimelineMs(nowNs)
        val oldTopTrackCount = laneLayout.topTracks.size
        val oldBottomTrackCount = laneLayout.bottomOffsets.size
        val oldViewportScale = currentViewportAdaptiveScaleFor(oldw, oldh)
        rebuildLaneLayout()
        val newTopTrackCount = laneLayout.topTracks.size
        val newBottomTrackCount = laneLayout.bottomOffsets.size
        val newViewportScale = currentViewportAdaptiveScaleFor(w, h)
        if (
            shouldRebuildTimelineForViewportChange(
                newWidth = w,
                newHeight = h,
                oldWidth = oldw,
                oldHeight = oldh,
                oldTopTrackCount = oldTopTrackCount,
                oldBottomTrackCount = oldBottomTrackCount,
                newTopTrackCount = newTopTrackCount,
                newBottomTrackCount = newBottomTrackCount,
                oldViewportScale = oldViewportScale,
                newViewportScale = newViewportScale,
            )
        ) {
            if (comments.isNotEmpty()) {
                Log.d(
                    TAG,
                    "[DANMAKU][NATIVE] viewport_rebuild old=${oldw}x${oldh} new=${w}x${h} " +
                        "tracks=${oldTopTrackCount}/${oldBottomTrackCount}->${newTopTrackCount}/${newBottomTrackCount} " +
                        "scale=${"%.3f".format(oldViewportScale)}->${"%.3f".format(newViewportScale)} " +
                        "timeline=${timelineMs.toInt()}",
                )
            }
            rebuildTimeline(timelineMs, nowNs, resetDynamicState = false)
        } else {
            relayoutActiveItems(timelineMs)
        }
        invalidate()
        if (shouldAnimate()) {
            scheduleFrame()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val drawStartedNs = System.nanoTime()
        if (!settings.enabled || comments.isEmpty() || width <= 0 || height <= 0) {
            return
        }
        val timelineMs = currentTimelineMs(currentAnimationClockNs(drawStartedNs))
        pruneExpiredItems(timelineMs)
        emitPendingComments(timelineMs)
        evaluateQueuePressure(timelineMs)
        val timelineCostNs = System.nanoTime() - drawStartedNs
        if (activeItems.isEmpty()) {
            recordDrawStats(
                drawStartedNs = drawStartedNs,
                totalCostNs = timelineCostNs,
                timelineCostNs = timelineCostNs,
                bitmapCostNs = 0L,
                maskCostNs = 0L,
                drawnItems = 0,
            )
            return
        }
        val shouldDrawMask = shouldDrawOcclusionMask()
        val layerCount =
            if (shouldDrawMask) {
                canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), layerPaint)
            } else {
                -1
            }
        bitmapPaint.alpha = settings.effectiveOpacity
        val viewportWidth = width.toFloat()
        val bitmapDrawStartedNs = System.nanoTime()
        var drawnItems = 0
        // Phase 3: when masking, comments that sit mostly over the subject are deferred and
        // drawn AFTER the mask pass (uncarved) so they aren't sliced into fragments.
        val coverageMask = if (shouldDrawMask) maskCoverageContext(timelineMs) else null
        val coverageReady = coverageMask != null && ensureCoveragePixels(coverageMask)
        drawWholeItems.clear()
        for (item in activeItems) {
            val left = item.left(viewportWidth, timelineMs)
            if (left >= viewportWidth || left + item.bitmap.drawWidth <= 0f) {
                continue
            }
            if (item.bitmap.bitmap.isRecycled) continue
            if (coverageReady && itemMostlyOverSubject(item, timelineMs)) {
                drawWholeItems.add(item)
                continue
            }
            canvas.drawBitmap(item.bitmap.bitmap, left, item.top, bitmapPaint)
            drawnItems += 1
        }
        val bitmapCostNs = System.nanoTime() - bitmapDrawStartedNs
        var maskCostNs = 0L
        if (shouldDrawMask) {
            val maskDrawStartedNs = System.nanoTime()
            drawOcclusionMask(canvas)
            // Draw the "mostly over subject" comments on top of the carved layer, whole.
            for (item in drawWholeItems) {
                if (item.bitmap.bitmap.isRecycled) continue
                val left = item.left(viewportWidth, timelineMs)
                canvas.drawBitmap(item.bitmap.bitmap, left, item.top, bitmapPaint)
                drawnItems += 1
            }
            canvas.restoreToCount(layerCount)
            maskCostNs = System.nanoTime() - maskDrawStartedNs
        }
        val totalCostNs = System.nanoTime() - drawStartedNs
        recordDrawStats(
            drawStartedNs = drawStartedNs,
            totalCostNs = totalCostNs,
            timelineCostNs = timelineCostNs,
            bitmapCostNs = bitmapCostNs,
            maskCostNs = maskCostNs,
            drawnItems = drawnItems,
        )
    }

    private fun preprocessPayload(payload: Map<String, Any?>): NativeDanmakuPayload {
        val nextSettings =
            NativeDanmakuSettings(
                enabled = payload["enabled"] as? Boolean ?: false,
                opacity = (payload["opacity"].toDoubleValue() ?: 0.85).toFloat(),
                density = (payload["density"].toDoubleValue() ?: 1.0).toFloat(),
                fontScale = (payload["fontScale"].toDoubleValue() ?: 1.0).toFloat(),
                fontThickness =
                    ((payload["fontThickness"].toDoubleValue() ?: 1.0).toFloat()).coerceIn(0.8f, 1.4f),
                speed =
                    ((payload["speed"].toDoubleValue() ?: 0.85).toFloat()).coerceIn(
                        DANMAKU_SPEED_MIN,
                        DANMAKU_SPEED_MAX,
                    ),
                displayAreaRatio =
                    ((payload["displayAreaRatio"].toDoubleValue() ?: 0.5).toFloat()).coerceIn(0.25f, 1.0f),
                targetFrameRateHz =
                    (payload["targetFrameRateHz"].toIntValue() ?: DEFAULT_TARGET_FPS)
                        .coerceIn(MIN_TARGET_FPS, MAX_TARGET_FPS),
                scrollEnabled = payload["scrollEnabled"] as? Boolean ?: true,
                topEnabled = payload["topEnabled"] as? Boolean ?: true,
                bottomEnabled = payload["bottomEnabled"] as? Boolean ?: false,
                colorEnabled = payload["colorEnabled"] as? Boolean ?: true,
                hideDuplicate = payload["hideDuplicate"] as? Boolean ?: true,
                avoidSubtitleArea = payload["avoidSubtitleArea"] as? Boolean ?: true,
                playbackSpeed = ((payload["playbackSpeed"].toDoubleValue() ?: 1.0).toFloat()).coerceAtLeast(0.1f),
                sourceKey = payload["sourceKey"]?.toString().orEmpty(),
            )
        val parsedComments =
            if (payload.containsKey("commentsCompact")) {
                // Flutter 编排层下发的紧凑格式：每条为数组 [id, timeMs, text, typeIndex, colorArgb]。
                // 注意：必须先于 "comments" 分支判断——Flutter 只发 commentsCompact，缺这段弹幕永远进不了 overlay。
                val rawCompact = payload["commentsCompact"] as? List<*> ?: emptyList<Any?>()
                rawCompact.mapNotNull { entry ->
                    val cols = entry as? List<*> ?: return@mapNotNull null
                    if (cols.size < 5) return@mapNotNull null
                    val text = cols[2]?.toString()?.trim().orEmpty()
                    if (text.isEmpty()) return@mapNotNull null
                    val timeMs = cols[1].toIntValue() ?: 0
                    val type =
                        when (cols[3].toIntValue() ?: 0) {
                            1 -> NativeDanmakuType.TOP
                            2 -> NativeDanmakuType.BOTTOM
                            else -> NativeDanmakuType.SCROLL
                        }
                    NativeDanmakuComment(
                        id =
                            cols[0]?.toString()?.takeIf { it.isNotBlank() }
                                ?: "$timeMs:${text.hashCode()}",
                        timeMs = timeMs.coerceAtLeast(0),
                        text = text,
                        type = type,
                        color = cols[4].toIntValue() ?: Color.WHITE,
                    )
                }.sortedBy { it.timeMs }
            } else if (payload.containsKey("comments")) {
                val rawComments = payload["comments"] as? List<*> ?: emptyList<Any?>()
                rawComments.mapNotNull { entry ->
                    val raw = entry as? Map<*, *> ?: return@mapNotNull null
                    val text = raw["text"]?.toString()?.trim().orEmpty()
                    if (text.isEmpty()) {
                        return@mapNotNull null
                    }
                    val timeMs = raw["timeMs"].toIntValue() ?: 0
                    val type =
                        when (raw["type"]?.toString()?.trim()?.lowercase()) {
                            "top" -> NativeDanmakuType.TOP
                            "bottom" -> NativeDanmakuType.BOTTOM
                            else -> NativeDanmakuType.SCROLL
                        }
                    NativeDanmakuComment(
                        id =
                            raw["id"]?.toString()?.takeIf { it.isNotBlank() }
                                ?: "$timeMs:${text.hashCode()}",
                        timeMs = timeMs.coerceAtLeast(0),
                        text = text,
                        type = type,
                        color = raw["color"].toIntValue() ?: Color.WHITE,
                    )
                }.sortedBy { it.timeMs }
            } else {
                null
            }
        return NativeDanmakuPayload(
            settings = nextSettings,
            comments = parsedComments,
            initialPositionMs =
                payload["initialPositionMs"]
                    .toDoubleValue()
                    ?.toFloat()
                    ?.coerceAtLeast(0f),
        )
    }

    private fun applyPayload(payload: NativeDanmakuPayload) {
        val anchorClockNs = currentAnimationClockNs(System.nanoTime())
        val currentTimelineMs = currentTimelineMs(anchorClockNs)
        val previousSettings = settings
        val oldSourceKey = settings.sourceKey
        val oldFontScale = settings.fontScale
        val oldFontThickness = settings.fontThickness
        val oldColorEnabled = settings.colorEnabled
        val oldTargetFrameRateHz = settings.targetFrameRateHz
        val oldPlaybackSpeed = settings.playbackSpeed
        settings = payload.settings
        if (payload.comments != null) {
            comments = payload.comments
        }
        if (oldFontScale != settings.fontScale ||
            oldFontThickness != settings.fontThickness ||
            oldColorEnabled != settings.colorEnabled
        ) {
            textCache.evictAll()
        }
        if (oldTargetFrameRateHz != settings.targetFrameRateHz) {
            resetFrameScheduler()
            resetFrameStats()
            Log.d(
                TAG,
                "[DANMAKU][NATIVE] frame_rate target=${settings.targetFrameRateHz}fps",
            )
        }
        applyRequestedFrameRateVote(reason = "payload")
        val requiresTimelineRebuild =
            payload.comments != null ||
                oldSourceKey != settings.sourceKey ||
                previousSettings.density != settings.density ||
                previousSettings.fontScale != settings.fontScale ||
                previousSettings.fontThickness != settings.fontThickness ||
                previousSettings.speed != settings.speed ||
                previousSettings.displayAreaRatio != settings.displayAreaRatio ||
                previousSettings.scrollEnabled != settings.scrollEnabled ||
                previousSettings.topEnabled != settings.topEnabled ||
                previousSettings.bottomEnabled != settings.bottomEnabled ||
                previousSettings.colorEnabled != settings.colorEnabled ||
                previousSettings.hideDuplicate != settings.hideDuplicate ||
                previousSettings.avoidSubtitleArea != settings.avoidSubtitleArea
        if (requiresTimelineRebuild) {
            rebuildLaneLayout()
            val resetPosition =
                if (oldSourceKey != settings.sourceKey) {
                    payload.initialPositionMs ?: 0f
                } else {
                    currentTimelineMs
                }
            rebuildTimeline(resetPosition)
        } else {
            timelineAnchorPositionMs = currentTimelineMs
            timelineAnchorTimeNs = anchorClockNs
            relayoutActiveItems(currentTimelineMs)
            if (oldPlaybackSpeed != settings.playbackSpeed) {
                armTimelineContinuityGuard(anchorClockNs)
            }
        }
        invalidate()
        if (shouldAnimate()) {
            scheduleFrame()
        } else {
            cancelFrame()
        }
    }

    private fun rebuildLaneLayout() {
        if (width <= 0 || height <= 0) {
            laneLayout = NativeDanmakuLaneLayout(FloatArray(0), FloatArray(0))
            effectiveDensityRatio = settings.density.coerceIn(0.2f, 1.0f)
            topLaneAvailableAtMs = FloatArray(0)
            bottomLaneAvailableAtMs = FloatArray(0)
            topLaneLastSpeedPxPerMs = FloatArray(0)
            topLaneLastStartMs = FloatArray(0)
            topLaneLastDrawWidthPx = FloatArray(0)
            return
        }
        laneLayout =
            buildLaneLayout(
                displayAreaRatio = currentEffectiveDisplayAreaRatio(),
                fontScale = settings.fontScale,
            )
        effectiveDensityRatio = computeEffectiveDensityRatio(laneLayout)
        topLaneAvailableAtMs = FloatArray(laneLayout.topTracks.size)
        bottomLaneAvailableAtMs = FloatArray(laneLayout.bottomOffsets.size)
        topLaneLastSpeedPxPerMs = FloatArray(laneLayout.topTracks.size)
        topLaneLastStartMs = FloatArray(laneLayout.topTracks.size)
        topLaneLastDrawWidthPx = FloatArray(laneLayout.topTracks.size)
    }

    private fun buildLaneLayout(
        displayAreaRatio: Float,
        fontScale: Float,
    ): NativeDanmakuLaneLayout {
        if (width <= 0 || height <= 0) {
            return NativeDanmakuLaneLayout(FloatArray(0), FloatArray(0))
        }
        val trackHeight = currentLaneSlotHeightPx(fontScale)
        val edgePadding = (trackHeight * 0.18f).coerceIn(edgePaddingMinPx, edgePaddingMaxPx)
        val topAreaHeight =
            max(0f, (height * displayAreaRatio.coerceIn(0.25f, 1.0f)) - edgePadding)
        val bottomAreaHeight = topAreaHeight
        val totalTopTracks =
            if (trackHeight <= 0f) {
                0
            } else {
                (topAreaHeight / trackHeight).roundToInt().coerceAtLeast(0)
            }
        val totalBottomTracks =
            if (trackHeight <= 0f) {
                0
            } else {
                (bottomAreaHeight / trackHeight).roundToInt().coerceAtLeast(0)
            }
        val subtitleReserveHeight =
            if (settings.avoidSubtitleArea) {
                height * SUBTITLE_RESERVED_AREA_RATIO
            } else {
                0f
            }
        val topTrackYs =
            FloatArray(totalTopTracks) { index ->
                edgePadding + (index * trackHeight)
            }
        val bottomOffsets =
            FloatArray(totalBottomTracks) { index ->
                subtitleReserveHeight + edgePadding + (index * trackHeight)
            }
        return NativeDanmakuLaneLayout(
            topTracks = topTrackYs,
            bottomOffsets = bottomOffsets,
        )
    }

    private fun computeEffectiveDensityRatio(layout: NativeDanmakuLaneLayout): Float {
        val baseDensity = settings.density.coerceIn(0.2f, 1.0f)
        if (layout.topTracks.isEmpty() && layout.bottomOffsets.isEmpty()) {
            return baseDensity
        }
        return when (overloadLevel) {
            NativeDanmakuOverloadLevel.NORMAL -> baseDensity
            NativeDanmakuOverloadLevel.SOFT -> (baseDensity * 0.92f).coerceIn(
                1f / DENSITY_BUCKET_SCALE.toFloat(),
                1.0f,
            )
            NativeDanmakuOverloadLevel.HARD -> (baseDensity * 0.82f).coerceIn(
                1f / DENSITY_BUCKET_SCALE.toFloat(),
                1.0f,
            )
        }
    }

    private fun visibleLaneCapacity(layout: NativeDanmakuLaneLayout): Int {
        var capacity = 0
        if (settings.scrollEnabled || settings.topEnabled) {
            capacity += layout.topTracks.size
        }
        if (settings.bottomEnabled) {
            capacity += layout.bottomOffsets.size
        }
        return capacity
    }

    private fun currentEffectiveDisplayAreaRatio(): Float {
        val baseRatio = settings.displayAreaRatio.coerceIn(0.25f, 1.0f)
        return when (overloadLevel) {
            NativeDanmakuOverloadLevel.NORMAL -> baseRatio
            NativeDanmakuOverloadLevel.SOFT -> (baseRatio + 0.10f).coerceIn(baseRatio, 1.0f)
            NativeDanmakuOverloadLevel.HARD -> (baseRatio + 0.20f).coerceIn(baseRatio, 1.0f)
        }
    }

    private fun visibleScrollCapacity(): Int {
        val trackCount = laneLayout.topTracks.size
        if (trackCount <= 0) {
            return MIN_VISIBLE_SCROLL_ITEMS
        }
        val scaledMultiplier = PER_TRACK_VISIBLE_SCROLL_MULTIPLIER * effectiveDensityRatio
        val dynamicMinimum = max(MIN_VISIBLE_SCROLL_ITEMS, trackCount * 2)
        return max(
            dynamicMinimum,
            min(MAX_VISIBLE_SCROLL_ITEMS, (trackCount * scaledMultiplier).roundToInt()),
        )
    }

    private fun pendingVisibleSafetyLimit(): Int {
        val baseCapacity = visibleScrollCapacity()
        return max(
            MAX_VISIBLE_SCROLL_ITEMS,
            min(MAX_PENDING_VISIBLE_SCROLL_ITEMS, baseCapacity * 3),
        )
    }

    private fun visibleScrollItemCountAt(timelineMs: Float): Int {
        if (width <= 0) {
            return 0
        }
        val viewportWidth = width.toFloat()
        var count = 0
        for (item in activeItems) {
            if (item.type != NativeDanmakuType.SCROLL || item.isExpired(timelineMs)) {
                continue
            }
            val left = item.left(viewportWidth, timelineMs)
            if (left < viewportWidth && left + item.bitmap.drawWidth > 0f) {
                count += 1
            }
        }
        return count
    }

    private fun pendingDrainBudget(): Int {
        return max(PENDING_DRAIN_MINIMUM_BUDGET, visibleScrollCapacity() / 3)
    }

    private fun maxPendingScrollCount(): Int {
        return max(
            PENDING_QUEUE_MINIMUM_SIZE,
            visibleScrollCapacity() * PENDING_QUEUE_CAPACITY_MULTIPLIER,
        )
    }

    private fun normalizedMergeKey(text: String): String {
        return text.replace(Regex("\\s+"), " ").trim()
    }

    private fun pendingTimeBucket(timeMs: Int): Int {
        return timeMs / MERGE_TIME_BUCKET_MS
    }

    private fun clearPendingScrollQueue() {
        pendingScrollItems.clear()
        pendingScrollIds.clear()
    }

    private fun resetDynamicDanmakuState(clearOverload: Boolean) {
        clearPendingScrollQueue()
        recentDrawElapsedNs.clear()
        paintSoftStreak = 0
        paintHardStreak = 0
        recoveryStreak = 0
        queuePressureStreak = 0
        queueHealthyForRecovery = true
        lastQueuePressureEvaluationMs = 0f
        schedulerQueuedByCapacityCount = 0
        schedulerQueuedByTrackCount = 0
        schedulerBlockedByCapacityCount = 0
        schedulerBlockedByTrackCount = 0
        schedulerDrainedFromQueueCount = 0
        schedulerDroppedFromQueueCount = 0
        schedulerDroppedByTrimCount = 0
        schedulerMergedCount = 0
        lastWindowPendingCount = 0
        lastWindowDrainedCount = 0
        lastWindowBlockedCount = 0
        if (clearOverload) {
            overloadLevel = NativeDanmakuOverloadLevel.NORMAL
        }
    }

    private fun rebuildTimeline(
        positionMs: Float,
        nowNs: Long = System.nanoTime(),
        resetDynamicState: Boolean = true,
    ) {
        if (resetDynamicState) {
            resetDynamicDanmakuState(clearOverload = true)
            rebuildLaneLayout()
        } else {
            clearPendingScrollQueue()
        }
        lastKnownPositionMs = positionMs.coerceAtLeast(0f)
        lastSoftSyncAppliedNs = 0L
        reanchorTimeline(lastKnownPositionMs, nowNs)
        activeItems.clear()
        duplicateWindow.clear()
        topLaneAvailableAtMs.fill(0f)
        bottomLaneAvailableAtMs.fill(0f)
        topLaneLastSpeedPxPerMs.fill(0f)
        topLaneLastStartMs.fill(0f)
        topLaneLastDrawWidthPx.fill(0f)
        nextCommentIndex =
            lowerBoundCommentIndex(
                max(0f, lastKnownPositionMs - MAX_LOOKBACK_MS).toInt(),
            )
        replayCommentsUntil(lastKnownPositionMs)
    }

    private fun relayoutActiveItems(timelineMs: Float) {
        topLaneAvailableAtMs.fill(0f)
        bottomLaneAvailableAtMs.fill(0f)
        topLaneLastSpeedPxPerMs.fill(0f)
        topLaneLastStartMs.fill(0f)
        topLaneLastDrawWidthPx.fill(0f)
        if (activeItems.isEmpty()) {
            return
        }
        val iterator = activeItems.iterator()
        while (iterator.hasNext()) {
            val item = iterator.next()
            if (item.isExpired(timelineMs)) {
                iterator.remove()
                continue
            }
            when (item.type) {
                NativeDanmakuType.SCROLL,
                NativeDanmakuType.TOP -> {
                    if (item.laneIndex !in laneLayout.topTracks.indices) {
                        iterator.remove()
                        continue
                    }
                    item.top = laneLayout.topTracks[item.laneIndex]
                    topLaneAvailableAtMs[item.laneIndex] =
                        max(topLaneAvailableAtMs[item.laneIndex], item.laneReleaseMs)
                    if (item.type == NativeDanmakuType.SCROLL) {
                        topLaneLastSpeedPxPerMs[item.laneIndex] = item.speedPxPerMs
                        topLaneLastStartMs[item.laneIndex] = item.startMs
                        topLaneLastDrawWidthPx[item.laneIndex] = item.bitmap.drawWidth
                    }
                }
                NativeDanmakuType.BOTTOM -> {
                    if (item.laneIndex !in laneLayout.bottomOffsets.indices) {
                        iterator.remove()
                        continue
                    }
                    item.top = height - laneLayout.bottomOffsets[item.laneIndex] - item.bitmap.drawHeight
                    bottomLaneAvailableAtMs[item.laneIndex] =
                        max(bottomLaneAvailableAtMs[item.laneIndex], item.laneReleaseMs)
                }
            }
        }
    }

    private fun shouldRebuildTimelineForViewportChange(
        newWidth: Int,
        newHeight: Int,
        oldWidth: Int,
        oldHeight: Int,
        oldTopTrackCount: Int,
        oldBottomTrackCount: Int,
        newTopTrackCount: Int,
        newBottomTrackCount: Int,
        oldViewportScale: Float,
        newViewportScale: Float,
    ): Boolean {
        if (oldWidth <= 0 || oldHeight <= 0) {
            return true
        }
        if (oldTopTrackCount != newTopTrackCount || oldBottomTrackCount != newBottomTrackCount) {
            return true
        }
        if (abs(oldViewportScale - newViewportScale) >= VIEWPORT_REBUILD_SCALE_DELTA) {
            return true
        }
        val widthRatio = abs(newWidth - oldWidth).toFloat() / oldWidth.toFloat()
        val heightRatio = abs(newHeight - oldHeight).toFloat() / oldHeight.toFloat()
        return widthRatio >= VIEWPORT_REBUILD_WIDTH_DELTA_RATIO ||
            heightRatio >= VIEWPORT_REBUILD_HEIGHT_DELTA_RATIO
    }

    private fun replayCommentsUntil(timelineMs: Float) {
        while (nextCommentIndex < comments.size) {
            val comment = comments[nextCommentIndex]
            if (comment.timeMs > timelineMs + FRAME_LOOKAHEAD_MS) {
                break
            }
            scheduleComment(comment, timelineMs, queueOnBlocked = false)
            nextCommentIndex += 1
        }
        pruneExpiredItems(timelineMs)
    }

    private fun emitPendingComments(timelineMs: Float) {
        drainPendingScrollComments(timelineMs)
        while (nextCommentIndex < comments.size) {
            val comment = comments[nextCommentIndex]
            if (comment.timeMs > timelineMs + FRAME_LOOKAHEAD_MS) {
                break
            }
            scheduleComment(comment, timelineMs, queueOnBlocked = true)
            nextCommentIndex += 1
        }
    }

    private fun scheduleComment(
        comment: NativeDanmakuComment,
        timelineMs: Float,
        queueOnBlocked: Boolean,
    ): NativeDanmakuAdmissionResult {
        if (!settings.enabled) return NativeDanmakuAdmissionResult.SKIPPED
        val normalizedText = normalizedMergeKey(comment.text)
        if (normalizedText.isEmpty()) return NativeDanmakuAdmissionResult.SKIPPED
        if (!shouldRenderCommentByDensity(comment)) return NativeDanmakuAdmissionResult.SKIPPED
        if (settings.hideDuplicate) {
            val previousTimeMs = duplicateWindow[normalizedText]
            if (previousTimeMs != null && comment.timeMs - previousTimeMs < DUPLICATE_WINDOW_MS) {
                if (
                    overloadLevel != NativeDanmakuOverloadLevel.NORMAL &&
                    queueOnBlocked &&
                    comment.type == NativeDanmakuType.SCROLL &&
                    mergePendingScrollComment(comment)
                ) {
                    return NativeDanmakuAdmissionResult.QUEUED
                }
                return NativeDanmakuAdmissionResult.SKIPPED
            }
        }
        val result =
            tryAdmitComment(
                comment = comment,
                timelineMs = timelineMs,
                queueOnBlocked = queueOnBlocked,
                fromPending = false,
                textOverride = null,
            )
        if (result == NativeDanmakuAdmissionResult.ADMITTED ||
            result == NativeDanmakuAdmissionResult.QUEUED
        ) {
            duplicateWindow[normalizedText] = comment.timeMs
        }
        return result
    }

    private fun tryAdmitComment(
        comment: NativeDanmakuComment,
        timelineMs: Float,
        queueOnBlocked: Boolean,
        fromPending: Boolean,
        textOverride: String?,
    ): NativeDanmakuAdmissionResult {
        when (comment.type) {
            NativeDanmakuType.SCROLL -> {
                if (!settings.scrollEnabled || laneLayout.topTracks.isEmpty()) {
                    return NativeDanmakuAdmissionResult.SKIPPED
                }
                val visibleLimit =
                    if (fromPending) pendingVisibleSafetyLimit() else visibleScrollCapacity()
                if (visibleScrollItemCountAt(timelineMs) >= visibleLimit) {
                    if (!fromPending && queueOnBlocked && queuePendingScrollComment(comment, timelineMs)) {
                        schedulerQueuedByCapacityCount += 1
                        return NativeDanmakuAdmissionResult.QUEUED
                    }
                    schedulerBlockedByCapacityCount += 1
                    return NativeDanmakuAdmissionResult.BLOCKED
                }
                val bitmap = obtainBitmap(comment, textOverride)
                // 恒定「基础穿屏时长」→ 速度由 (视口宽 + 弹幕宽) / 时长 反推：弹幕越宽速度越快，
                // 不同宽度弹幕呈现不同飘动速度（而非全局单一速度）。
                val travelDurationMs = currentScrollBaseTravelDurationMs().coerceAtLeast(2000f)
                val speedPxPerMs =
                    ((width + bitmap.drawWidth) / travelDurationMs).coerceAtLeast(TIMELINE_SOFT_SYNC_GAIN)
                val startMs = if (fromPending) timelineMs else comment.timeMs.toFloat()
                val releaseAfterMs = (bitmap.drawWidth + currentItemGapPx()) / speedPxPerMs
                val laneIndex =
                    findScrollLaneAntiCollision(
                        topLaneAvailableAtMs, topLaneLastSpeedPxPerMs,
                        topLaneLastStartMs, topLaneLastDrawWidthPx, startMs, speedPxPerMs,
                    )
                        ?: run {
                            if (!fromPending && queueOnBlocked && queuePendingScrollComment(comment, timelineMs)) {
                                schedulerQueuedByTrackCount += 1
                                return NativeDanmakuAdmissionResult.QUEUED
                            }
                            schedulerBlockedByTrackCount += 1
                            return NativeDanmakuAdmissionResult.BLOCKED
                        }
                topLaneAvailableAtMs[laneIndex] =
                    max(topLaneAvailableAtMs[laneIndex], startMs + releaseAfterMs)
                topLaneLastSpeedPxPerMs[laneIndex] = speedPxPerMs
                topLaneLastStartMs[laneIndex] = startMs
                topLaneLastDrawWidthPx[laneIndex] = bitmap.drawWidth
                val endMs = startMs + travelDurationMs
                if (endMs <= timelineMs) {
                    return NativeDanmakuAdmissionResult.DROPPED
                }
                activeItems.add(
                    ActiveDanmakuItem(
                        id = comment.id,
                        type = NativeDanmakuType.SCROLL,
                        bitmap = bitmap,
                        laneIndex = laneIndex,
                        top = laneLayout.topTracks[laneIndex],
                        startMs = startMs,
                        endMs = endMs,
                        laneReleaseMs = startMs + releaseAfterMs,
                        speedPxPerMs = speedPxPerMs,
                    ),
                )
                return NativeDanmakuAdmissionResult.ADMITTED
            }
            NativeDanmakuType.TOP -> {
                if (!settings.topEnabled || laneLayout.topTracks.isEmpty()) {
                    return NativeDanmakuAdmissionResult.SKIPPED
                }
                val bitmap = obtainBitmap(comment, textOverride)
                val durationMs = currentStaticDurationMs()
                val startMs = comment.timeMs.toFloat()
                val laneIndex =
                    findAvailableLane(topLaneAvailableAtMs, startMs)
                        ?: return NativeDanmakuAdmissionResult.BLOCKED
                topLaneAvailableAtMs[laneIndex] = startMs + durationMs
                // 静态顶部弹幕占用滚动共享的顶部轨道：把该轨道前车速度标记为 0，
                // 后续滚动弹幕的追及碰撞会按「静态占位」分支只看 availableAtMs。
                topLaneLastSpeedPxPerMs[laneIndex] = 0f
                val endMs = startMs + durationMs
                if (endMs <= timelineMs) {
                    return NativeDanmakuAdmissionResult.DROPPED
                }
                activeItems.add(
                    ActiveDanmakuItem(
                        id = comment.id,
                        type = NativeDanmakuType.TOP,
                        bitmap = bitmap,
                        laneIndex = laneIndex,
                        top = laneLayout.topTracks[laneIndex],
                        startMs = startMs,
                        endMs = endMs,
                        laneReleaseMs = startMs + durationMs,
                        speedPxPerMs = 0f,
                    ),
                )
                return NativeDanmakuAdmissionResult.ADMITTED
            }
            NativeDanmakuType.BOTTOM -> {
                if (!settings.bottomEnabled || laneLayout.bottomOffsets.isEmpty()) {
                    return NativeDanmakuAdmissionResult.SKIPPED
                }
                val bitmap = obtainBitmap(comment, textOverride)
                val durationMs = currentStaticDurationMs()
                val startMs = comment.timeMs.toFloat()
                val laneIndex =
                    findAvailableLane(bottomLaneAvailableAtMs, startMs)
                        ?: return NativeDanmakuAdmissionResult.BLOCKED
                bottomLaneAvailableAtMs[laneIndex] = startMs + durationMs
                val endMs = startMs + durationMs
                if (endMs <= timelineMs) {
                    return NativeDanmakuAdmissionResult.DROPPED
                }
                activeItems.add(
                    ActiveDanmakuItem(
                        id = comment.id,
                        type = NativeDanmakuType.BOTTOM,
                        bitmap = bitmap,
                        laneIndex = laneIndex,
                        top = height - laneLayout.bottomOffsets[laneIndex] - bitmap.drawHeight,
                        startMs = startMs,
                        endMs = endMs,
                        laneReleaseMs = startMs + durationMs,
                        speedPxPerMs = 0f,
                    ),
                )
                return NativeDanmakuAdmissionResult.ADMITTED
            }
        }
        return NativeDanmakuAdmissionResult.SKIPPED
    }

    private fun mergePendingScrollComment(comment: NativeDanmakuComment): Boolean {
        if (overloadLevel == NativeDanmakuOverloadLevel.NORMAL) {
            return false
        }
        val normalizedText = normalizedMergeKey(comment.text)
        if (normalizedText.isEmpty()) {
            return false
        }
        val timeBucket = pendingTimeBucket(comment.timeMs)
        for (index in pendingScrollItems.indices.reversed()) {
            val pending = pendingScrollItems[index]
            if (pending.normalizedText == normalizedText && pending.timeBucket == timeBucket) {
                pending.mergeWith()
                schedulerMergedCount += 1
                return true
            }
        }
        return false
    }

    private fun queuePendingScrollComment(comment: NativeDanmakuComment, timelineMs: Float): Boolean {
        if (pendingScrollIds.contains(comment.id)) {
            return false
        }
        if (mergePendingScrollComment(comment)) {
            return true
        }
        val normalizedText = normalizedMergeKey(comment.text)
        if (normalizedText.isEmpty()) {
            return false
        }
        pendingScrollIds.add(comment.id)
        pendingScrollItems.add(
            PendingNativeScrollDanmaku(
                comment = comment,
                eligibleAtMs = timelineMs,
                enqueuedAtMs = timelineMs,
                delayBudgetMs = MAX_PENDING_DELAY_MS,
                normalizedText = normalizedText,
                timeBucket = pendingTimeBucket(comment.timeMs),
            ),
        )
        trimPendingScrollQueue(timelineMs)
        return true
    }

    private fun trimPendingScrollQueue(timelineMs: Float) {
        val maxPendingCount = maxPendingScrollCount()
        while (pendingScrollItems.size > maxPendingCount) {
            val index = pickPendingTrimIndex(timelineMs)
            dropPendingScrollCommentAt(index, reason = "trim")
        }
    }

    private fun pickPendingTrimIndex(timelineMs: Float): Int {
        if (pendingScrollItems.isEmpty()) {
            return -1
        }
        for (index in pendingScrollItems.indices) {
            val pending = pendingScrollItems[index]
            if (timelineMs - pending.enqueuedAtMs >= pending.delayBudgetMs) {
                return index
            }
        }
        return 0
    }

    private fun dropPendingScrollCommentAt(index: Int, reason: String) {
        if (index !in pendingScrollItems.indices) {
            return
        }
        val pending = pendingScrollItems.removeAt(index)
        pendingScrollIds.remove(pending.comment.id)
        schedulerDroppedFromQueueCount += 1
        if (reason == "trim") {
            schedulerDroppedByTrimCount += 1
        }
    }

    private fun drainPendingScrollComments(timelineMs: Float): Int {
        if (pendingScrollItems.isEmpty() || !settings.scrollEnabled) {
            return 0
        }
        val successBudget = pendingDrainBudget()
        val scanBudget = max(successBudget * 4, 24)
        var admittedCount = 0
        var scannedCount = 0
        var index = 0
        while (index < pendingScrollItems.size && scannedCount < scanBudget) {
            val pending = pendingScrollItems[index]
            if (timelineMs < pending.eligibleAtMs) {
                break
            }
            scannedCount += 1
            if (timelineMs - pending.enqueuedAtMs >= pending.delayBudgetMs) {
                dropPendingScrollCommentAt(index, reason = "expired")
                continue
            }
            val result =
                tryAdmitComment(
                    comment = pending.comment,
                    timelineMs = timelineMs,
                    queueOnBlocked = false,
                    fromPending = true,
                    textOverride = pending.displayText,
                )
            when (result) {
                NativeDanmakuAdmissionResult.ADMITTED -> {
                    pendingScrollIds.remove(pending.comment.id)
                    pendingScrollItems.removeAt(index)
                    schedulerDrainedFromQueueCount += 1
                    admittedCount += 1
                    if (admittedCount >= successBudget) {
                        return admittedCount
                    }
                    continue
                }
                NativeDanmakuAdmissionResult.DROPPED,
                NativeDanmakuAdmissionResult.SKIPPED -> {
                    pendingScrollIds.remove(pending.comment.id)
                    pendingScrollItems.removeAt(index)
                    continue
                }
                NativeDanmakuAdmissionResult.BLOCKED,
                NativeDanmakuAdmissionResult.QUEUED -> {
                    index += 1
                }
            }
        }
        return admittedCount
    }

    private fun pruneExpiredItems(timelineMs: Float) {
        if (activeItems.isEmpty()) return
        val iterator = activeItems.iterator()
        while (iterator.hasNext()) {
            if (iterator.next().isExpired(timelineMs)) {
                iterator.remove()
            }
        }
        if (duplicateWindow.size > 512) {
            val threshold = max(0f, timelineMs - DUPLICATE_WINDOW_MS * 2).toInt()
            duplicateWindow.entries.removeAll { it.value < threshold }
        }
    }

    private fun shouldRenderCommentByDensity(comment: NativeDanmakuComment): Boolean {
        val densityRatio = effectiveDensityRatio
        if (densityRatio >= 0.999f) {
            return true
        }
        val threshold =
            (densityRatio * DENSITY_BUCKET_SCALE).toInt().coerceIn(1, DENSITY_BUCKET_SCALE)
        return commentDensityBucket(comment) < threshold
    }

    private fun commentDensityBucket(comment: NativeDanmakuComment): Int {
        var hash = comment.timeMs and 0x7fffffff
        val id = comment.id
        for (index in id.indices) {
            hash = ((hash * 33) xor id[index].code) and 0x7fffffff
        }
        return hash % DENSITY_BUCKET_SCALE
    }

    private fun obtainBitmap(
        comment: NativeDanmakuComment,
        textOverride: String? = null,
    ): NativeDanmakuBitmap {
        val displayText = textOverride ?: comment.text
        val textSizePx = currentTextSizePx()
        val textThickness = currentFontThickness()
        val strokeWidth = currentStrokeWidthPx()
        val effectiveColor = if (settings.colorEnabled) comment.color else Color.WHITE
        val key =
            "$displayText|$effectiveColor|${textSizePx.toInt()}|${(textThickness * 100f).toInt()}"
        textCache.get(key)?.let { return it }
        applyCurrentTextPaints(textSizePx, effectiveColor)
        val fontMetrics = fillPaint.fontMetrics
        val textWidth = fillPaint.measureText(displayText).coerceAtLeast(1f)
        val textHeight = (fontMetrics.descent - fontMetrics.ascent).coerceAtLeast(textSizePx)
        val padding = max(strokeWidth * 2f, textSizePx * 0.08f)
        val bitmapWidth = ceil(textWidth + padding * 2f).toInt().coerceAtLeast(1)
        val bitmapHeight = ceil(textHeight + padding * 2f).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val baseline = padding - fontMetrics.ascent
        canvas.drawText(displayText, padding, baseline, strokePaint)
        canvas.drawText(displayText, padding, baseline, fillPaint)
        val entry =
            NativeDanmakuBitmap(
                bitmap = bitmap,
                drawWidth = bitmapWidth.toFloat(),
                drawHeight = bitmapHeight.toFloat(),
            )
        textCache.put(key, entry)
        return entry
    }

    private fun currentTextSizePx(fontScale: Float = settings.fontScale): Float {
        return density *
            BASE_TEXT_SIZE_SP *
            fontScale.coerceIn(0.6f, 1.4f) *
            currentViewportAdaptiveScale()
    }

    private fun currentFontThickness(): Float {
        return settings.fontThickness.coerceIn(0.8f, 1.4f)
    }

    private fun currentViewportAdaptiveScale(): Float {
        return currentViewportAdaptiveScaleFor(width, height)
    }

    private fun currentViewportAdaptiveScaleFor(viewWidth: Int, viewHeight: Int): Float {
        if (viewWidth <= 0 || viewHeight <= 0) {
            return 1f
        }
        val safeDensity = density.coerceAtLeast(1f)
        val shortSideDp = min(viewWidth, viewHeight).toFloat() / safeDensity
        return (shortSideDp / VIEWPORT_FONT_SCALE_REFERENCE_DP)
            .coerceIn(MIN_VIEWPORT_FONT_SCALE, 1f)
    }

    private fun currentStrokeWidthPx(): Float {
        return strokeWidthPx * currentFontThickness() * currentViewportAdaptiveScale()
    }

    private fun applyCurrentTextPaints(textSizePx: Float, fillColor: Int) {
        val useFakeBold = currentFontThickness() >= 1.2f
        val currentStrokeWidth = currentStrokeWidthPx()
        fillPaint.textSize = textSizePx
        fillPaint.color = fillColor
        fillPaint.isFakeBoldText = useFakeBold
        strokePaint.textSize = textSizePx
        strokePaint.color = Color.BLACK
        strokePaint.strokeWidth = currentStrokeWidth
        strokePaint.isFakeBoldText = useFakeBold
    }

    private fun currentTrackHeightPx(fontScale: Float = settings.fontScale): Float {
        val textSizePx = currentTextSizePx(fontScale)
        applyCurrentTextPaints(textSizePx, Color.WHITE)
        val fontMetrics = fillPaint.fontMetrics
        val textHeight = (fontMetrics.descent - fontMetrics.ascent).coerceAtLeast(textSizePx)
        val padding = max(currentStrokeWidthPx() * 2f, textSizePx * 0.08f)
        return textHeight + (padding * 2f) + (trackVerticalPaddingPx * currentViewportAdaptiveScale())
    }

    private fun currentLaneSlotHeightPx(fontScale: Float = settings.fontScale): Float {
        val actualTrackHeight = currentTrackHeightPx(fontScale)
        val referenceTrackHeight = currentTrackHeightPx(1.0f)
        return max(actualTrackHeight, referenceTrackHeight)
    }

    private fun currentMotionDurationScale(): Float {
        if (width <= 0 || height <= 0) {
            return 1f
        }
        val safeDensity = density.coerceAtLeast(1f)
        val shortSideDp = min(width, height).toFloat() / safeDensity
        return (shortSideDp / MOTION_DURATION_REFERENCE_SHORT_SIDE_DP)
            .coerceIn(MIN_MOTION_DURATION_SCALE, MAX_MOTION_DURATION_SCALE)
    }

    /**
     * 滚动弹幕「追及碰撞」检测：返回一条不会与前车追尾的可用轨道，没有则 null。
     * - 前车速度<=0（空轨道 / 静态占位）：availableAtMs 到点即空闲。
     * - 本条更快(newSpeed>prevSpeed)：会追上前车，要求前车已行进足够久——前车宽 +
     *   按速度差折算的安全等效宽度，全部按前车速度换算成时长。
     * - 本条不快于前车：只需前车尾部 + 安全间距已离开入场点。
     */
    private fun findScrollLaneAntiCollision(
        availableAtMs: FloatArray,
        laneLastSpeedPxPerMs: FloatArray,
        laneLastStartMs: FloatArray,
        laneLastDrawWidthPx: FloatArray,
        targetTimeMs: Float,
        newSpeedPxPerMs: Float,
    ): Int? {
        val antiCollisionMarginPx = density * 20f
        val viewportWidthPx = width.toFloat()
        for (i in availableAtMs.indices) {
            val prevSpeed = laneLastSpeedPxPerMs[i]
            if (prevSpeed <= 0f) {
                if (availableAtMs[i] <= targetTimeMs) return i
            } else if (newSpeedPxPerMs > prevSpeed) {
                val speedDiff = newSpeedPxPerMs - prevSpeed
                val widthEquiv = ((viewportWidthPx + antiCollisionMarginPx) * speedDiff) / newSpeedPxPerMs
                val minElapsedMs = (laneLastDrawWidthPx[i] + widthEquiv) / prevSpeed
                if (targetTimeMs - laneLastStartMs[i] >= minElapsedMs) return i
            } else {
                val minElapsedMs = (laneLastDrawWidthPx[i] + antiCollisionMarginPx) / prevSpeed
                if (targetTimeMs - laneLastStartMs[i] >= minElapsedMs) return i
            }
        }
        return null
    }

    private fun currentScrollBaseTravelDurationMs(): Float {
        val baseDurationMs =
            (SCROLL_BASE_TRAVEL_MS * currentMotionDurationScale()) / currentMotionSpeedFactor()
        return when (overloadLevel) {
            NativeDanmakuOverloadLevel.NORMAL -> baseDurationMs
            NativeDanmakuOverloadLevel.SOFT -> max(2400f, baseDurationMs * 0.88f)
            NativeDanmakuOverloadLevel.HARD -> max(2200f, baseDurationMs * 0.75f)
        }
    }

    private fun currentStaticDurationMs(): Float {
        return STATIC_BASE_DURATION_MS / currentMotionSpeedFactor()
    }

    private fun currentItemGapPx(): Float {
        val viewportScale = currentViewportAdaptiveScale()
        val baseGap = max(density * 24f * viewportScale, currentTextSizePx() * 0.6f)
        return baseGap
    }

    private fun currentMotionSpeedFactor(): Float {
        val rawSpeed =
            (settings.speed.coerceIn(DANMAKU_SPEED_MIN, DANMAKU_SPEED_MAX) + DANMAKU_SPEED_STEP)
                .coerceIn(DANMAKU_SPEED_MIN, DANMAKU_SPEED_MAX)
        return if (rawSpeed >= 1f) {
            1f + ((rawSpeed - 1f) * 0.55f)
        } else {
            1f - ((1f - rawSpeed) * 0.45f)
        }
    }

    private fun currentFrameIntervalNs(): Long {
        val fps =
            settings.targetFrameRateHz
                .coerceIn(MIN_TARGET_FPS, MAX_TARGET_FPS)
                .takeIf { it > 0 }
                ?: DEFAULT_TARGET_FPS
        return 1_000_000_000L / fps.toLong()
    }

    private fun shouldThrottleFrame(frameTimeNanos: Long): Boolean {
        val frameIntervalNs = currentFrameIntervalNs()
        val displayRefreshRateHz = display?.refreshRate ?: 0f
        if (displayRefreshRateHz >= 1f &&
            settings.targetFrameRateHz.toFloat() >= displayRefreshRateHz - 1f
        ) {
            frameBudgetLastCallbackNs = frameTimeNanos
            frameBudgetAccumulatorNs = frameIntervalNs
            return false
        }
        if (frameBudgetLastCallbackNs == 0L) {
            frameBudgetLastCallbackNs = frameTimeNanos
            frameBudgetAccumulatorNs = frameIntervalNs
            return false
        }
        val elapsedNs = (frameTimeNanos - frameBudgetLastCallbackNs).coerceAtLeast(0L)
        frameBudgetLastCallbackNs = frameTimeNanos
        val maxBudgetNs = frameIntervalNs * MAX_FRAME_BUDGET_MULTIPLIER
        frameBudgetAccumulatorNs =
            (frameBudgetAccumulatorNs + elapsedNs).coerceIn(0L, maxBudgetNs)
        if (frameBudgetAccumulatorNs + FRAME_SCHEDULER_TOLERANCE_NS < frameIntervalNs) {
            return true
        }
        frameBudgetAccumulatorNs = (frameBudgetAccumulatorNs - frameIntervalNs).coerceAtLeast(0L)
        return false
    }

    private fun currentAnimationClockNs(fallbackNs: Long): Long {
        if (paused) {
            return fallbackNs
        }
        val frameNs = renderFrameTimeNs
        if (frameNs == 0L) {
            return fallbackNs
        }
        val maxStalenessNs = currentFrameIntervalNs() * MAX_FRAME_BUDGET_MULTIPLIER * 2L
        val frameLagNs = fallbackNs - frameNs
        return if (frameLagNs in 0L..maxStalenessNs) frameNs else fallbackNs
    }

    private fun applyRequestedFrameRateVote(reason: String) {
        if (Build.VERSION.SDK_INT < 35) {
            return
        }
        val nextHint =
            if (settings.enabled) {
                settings.targetFrameRateHz
                    .coerceIn(MIN_TARGET_FPS, MAX_TARGET_FPS)
                    .toFloat()
            } else {
                View.REQUESTED_FRAME_RATE_CATEGORY_NO_PREFERENCE
            }
        if (!appliedRequestedFrameRateHint.isNaN() &&
            abs(appliedRequestedFrameRateHint - nextHint) <= 0.1f
        ) {
            return
        }
        setRequestedFrameRate(nextHint)
        appliedRequestedFrameRateHint = nextHint
        val displayHz = display?.refreshRate ?: 0f
        Log.d(
            TAG,
            "[DANMAKU][NATIVE] view_frame_rate_vote " +
                "reason=$reason requested=${"%.1f".format(Locale.US, nextHint)}fps " +
                "displayHz=${"%.1f".format(Locale.US, displayHz)} attached=$attachedToHost",
        )
    }

    private fun clearRequestedFrameRateVote(reason: String) {
        if (Build.VERSION.SDK_INT < 35) {
            return
        }
        setRequestedFrameRate(View.REQUESTED_FRAME_RATE_CATEGORY_NO_PREFERENCE)
        appliedRequestedFrameRateHint = View.REQUESTED_FRAME_RATE_CATEGORY_NO_PREFERENCE
        Log.d(
            TAG,
            "[DANMAKU][NATIVE] view_frame_rate_vote reason=$reason requested=no_preference",
        )
    }

    private fun recordFrameStats(
        frameTimeNanos: Long,
        throttledByScheduler: Boolean,
    ) {
        if (fpsWindowStartNs == 0L) {
            fpsWindowStartNs = frameTimeNanos
            rawCallbackLastFrameNs = frameTimeNanos
            rawCallbackFrameCount = 1
            rawCallbackAccumulatedDeltaNs = 0L
            rawCallbackMaxDeltaNs = 0L
            throttledCallbackCount = if (throttledByScheduler) 1 else 0
            acceptedFrameLastNs = if (throttledByScheduler) 0L else frameTimeNanos
            acceptedFrameCount = if (throttledByScheduler) 0 else 1
            acceptedSlowFrameCount = 0
            acceptedAccumulatedDeltaNs = 0L
            acceptedMaxDeltaNs = 0L
            return
        }

        val rawFrameDeltaNs = (frameTimeNanos - rawCallbackLastFrameNs).coerceAtLeast(0L)
        rawCallbackLastFrameNs = frameTimeNanos
        rawCallbackFrameCount += 1
        if (rawFrameDeltaNs > 0L) {
            rawCallbackAccumulatedDeltaNs += rawFrameDeltaNs
            if (rawFrameDeltaNs > rawCallbackMaxDeltaNs) {
                rawCallbackMaxDeltaNs = rawFrameDeltaNs
            }
        }

        if (throttledByScheduler) {
            throttledCallbackCount += 1
        } else if (acceptedFrameLastNs == 0L) {
            acceptedFrameLastNs = frameTimeNanos
            acceptedFrameCount = 1
        } else {
            val acceptedFrameDeltaNs = (frameTimeNanos - acceptedFrameLastNs).coerceAtLeast(0L)
            acceptedFrameLastNs = frameTimeNanos
            acceptedFrameCount += 1
            if (acceptedFrameDeltaNs > 0L) {
                acceptedAccumulatedDeltaNs += acceptedFrameDeltaNs
                if (acceptedFrameDeltaNs > acceptedMaxDeltaNs) {
                    acceptedMaxDeltaNs = acceptedFrameDeltaNs
                }
                val slowThresholdNs =
                    (currentFrameIntervalNs().toDouble() * SLOW_FRAME_THRESHOLD_MULTIPLIER.toDouble()).toLong()
                if (acceptedFrameDeltaNs >= slowThresholdNs) {
                    acceptedSlowFrameCount += 1
                }
            }
        }

        val windowDurationNs = frameTimeNanos - fpsWindowStartNs
        if (windowDurationNs < FPS_LOG_WINDOW_NS) {
            return
        }
        if (!enablePerfLogs) {
            fpsWindowStartNs = frameTimeNanos
            rawCallbackFrameCount = 1
            rawCallbackAccumulatedDeltaNs = 0L
            rawCallbackMaxDeltaNs = 0L
            throttledCallbackCount = 0
            acceptedFrameLastNs = if (throttledByScheduler) 0L else frameTimeNanos
            acceptedFrameCount = if (throttledByScheduler) 0 else 1
            acceptedSlowFrameCount = 0
            acceptedAccumulatedDeltaNs = 0L
            acceptedMaxDeltaNs = 0L
            return
        }

        val rawCallbackFps =
            if (windowDurationNs > 0L) {
                rawCallbackFrameCount.toDouble() * 1_000_000_000.0 / windowDurationNs.toDouble()
            } else {
                0.0
            }
        val actualFps =
            if (windowDurationNs > 0L) {
                acceptedFrameCount.toDouble() * 1_000_000_000.0 / windowDurationNs.toDouble()
            } else {
                0.0
            }
        val rawAverageDeltaMs =
            if (rawCallbackFrameCount > 1 && rawCallbackAccumulatedDeltaNs > 0L) {
                rawCallbackAccumulatedDeltaNs.toDouble() /
                    (rawCallbackFrameCount - 1).toDouble() / 1_000_000.0
            } else {
                0.0
            }
        val averageDeltaMs =
            if (acceptedFrameCount > 1 && acceptedAccumulatedDeltaNs > 0L) {
                acceptedAccumulatedDeltaNs.toDouble() /
                    (acceptedFrameCount - 1).toDouble() / 1_000_000.0
            } else {
                0.0
            }
        val rawMaxDeltaMs = rawCallbackMaxDeltaNs.toDouble() / 1_000_000.0
        val maxDeltaMs = acceptedMaxDeltaNs.toDouble() / 1_000_000.0
        Log.d(
            TAG,
            String.format(
                Locale.US,
                "[DANMAKU][NATIVE] fps actual=%.1f rawCallback=%.1f target=%dfps avgDeltaMs=%.2f rawAvgDeltaMs=%.2f maxDeltaMs=%.2f rawMaxDeltaMs=%.2f slowFrames=%d throttledCallbacks=%d windowMs=%d",
                actualFps,
                rawCallbackFps,
                settings.targetFrameRateHz,
                averageDeltaMs,
                rawAverageDeltaMs,
                maxDeltaMs,
                rawMaxDeltaMs,
                acceptedSlowFrameCount,
                throttledCallbackCount,
                windowDurationNs / 1_000_000L,
            ),
        )
        fpsWindowStartNs = frameTimeNanos
        rawCallbackFrameCount = 1
        rawCallbackAccumulatedDeltaNs = 0L
        rawCallbackMaxDeltaNs = 0L
        throttledCallbackCount = 0
        acceptedFrameLastNs = if (throttledByScheduler) 0L else frameTimeNanos
        acceptedFrameCount = if (throttledByScheduler) 0 else 1
        acceptedSlowFrameCount = 0
        acceptedAccumulatedDeltaNs = 0L
        acceptedMaxDeltaNs = 0L
    }

    private fun recordDrawStats(
        drawStartedNs: Long,
        totalCostNs: Long,
        timelineCostNs: Long,
        bitmapCostNs: Long,
        maskCostNs: Long,
        drawnItems: Int,
    ) {
        recordDrawPressure(totalCostNs)
        if (drawWindowStartNs == 0L) {
            drawWindowStartNs = drawStartedNs
        }
        drawFrameCount += 1
        drawAccumulatedTotalNs += totalCostNs
        drawAccumulatedTimelineNs += timelineCostNs
        drawAccumulatedBitmapNs += bitmapCostNs
        drawAccumulatedMaskNs += maskCostNs
        drawAccumulatedItems += drawnItems
        if (totalCostNs > drawMaxNs) {
            drawMaxNs = totalCostNs
        }
        val windowDurationNs = drawStartedNs - drawWindowStartNs
        if (windowDurationNs < FPS_LOG_WINDOW_NS) {
            return
        }
        if (!enablePerfLogs) {
            drawWindowStartNs = drawStartedNs
            drawFrameCount = 0
            drawAccumulatedTotalNs = 0L
            drawAccumulatedTimelineNs = 0L
            drawAccumulatedBitmapNs = 0L
            drawAccumulatedMaskNs = 0L
            drawAccumulatedItems = 0
            drawMaxNs = 0L
            return
        }
        val safeFrameCount = drawFrameCount.coerceAtLeast(1)
        Log.d(
            TAG,
            String.format(
                Locale.US,
                "[DANMAKU][NATIVE] draw avgMs=%.2f timelineMs=%.2f bitmapMs=%.2f maskMs=%.2f avgItems=%.1f maxMs=%.2f frames=%d",
                drawAccumulatedTotalNs.toDouble() / safeFrameCount.toDouble() / 1_000_000.0,
                drawAccumulatedTimelineNs.toDouble() / safeFrameCount.toDouble() / 1_000_000.0,
                drawAccumulatedBitmapNs.toDouble() / safeFrameCount.toDouble() / 1_000_000.0,
                drawAccumulatedMaskNs.toDouble() / safeFrameCount.toDouble() / 1_000_000.0,
                drawAccumulatedItems.toDouble() / safeFrameCount.toDouble(),
                drawMaxNs.toDouble() / 1_000_000.0,
                drawFrameCount,
            ),
        )
        drawWindowStartNs = drawStartedNs
        drawFrameCount = 0
        drawAccumulatedTotalNs = 0L
        drawAccumulatedTimelineNs = 0L
        drawAccumulatedBitmapNs = 0L
        drawAccumulatedMaskNs = 0L
        drawAccumulatedItems = 0
        drawMaxNs = 0L
    }

    private fun recordDrawPressure(totalCostNs: Long) {
        recentDrawElapsedNs.add(totalCostNs)
        while (recentDrawElapsedNs.size > DRAW_SAMPLE_WINDOW_SIZE) {
            recentDrawElapsedNs.removeAt(0)
        }
        val averageDrawNs =
            if (recentDrawElapsedNs.isEmpty()) {
                0L
            } else {
                recentDrawElapsedNs.sum() / recentDrawElapsedNs.size
            }
        if (averageDrawNs >= DRAW_HARD_THRESHOLD_NS) {
            paintHardStreak += 1
            paintSoftStreak += 1
            recoveryStreak = 0
            if (paintHardStreak >= DRAW_PRESSURE_SAMPLES) {
                setOverloadLevel(NativeDanmakuOverloadLevel.HARD)
            }
            return
        }
        if (averageDrawNs >= DRAW_SOFT_THRESHOLD_NS) {
            paintSoftStreak += 1
            paintHardStreak = 0
            recoveryStreak = 0
            if (
                paintSoftStreak >= DRAW_PRESSURE_SAMPLES &&
                overloadLevel == NativeDanmakuOverloadLevel.NORMAL
            ) {
                setOverloadLevel(NativeDanmakuOverloadLevel.SOFT)
            }
            return
        }
        paintSoftStreak = 0
        paintHardStreak = 0
        if (queueHealthyForRecovery) {
            recoveryStreak += 1
            if (recoveryStreak >= RECOVERY_SAMPLES) {
                when (overloadLevel) {
                    NativeDanmakuOverloadLevel.HARD -> setOverloadLevel(NativeDanmakuOverloadLevel.SOFT)
                    NativeDanmakuOverloadLevel.SOFT -> setOverloadLevel(NativeDanmakuOverloadLevel.NORMAL)
                    NativeDanmakuOverloadLevel.NORMAL -> Unit
                }
                recoveryStreak = 0
            }
        } else {
            recoveryStreak = 0
        }
    }

    private fun evaluateQueuePressure(timelineMs: Float) {
        if (lastQueuePressureEvaluationMs <= 0f || timelineMs < lastQueuePressureEvaluationMs) {
            snapshotQueuePressureWindow(timelineMs)
            return
        }
        if (timelineMs - lastQueuePressureEvaluationMs < QUEUE_PRESSURE_WINDOW_MS) {
            return
        }
        val pendingDelta = pendingScrollItems.size - lastWindowPendingCount
        val drainedDelta = schedulerDrainedFromQueueCount - lastWindowDrainedCount
        val blockedCount = schedulerBlockedByCapacityCount + schedulerBlockedByTrackCount
        val blockedDelta = blockedCount - lastWindowBlockedCount
        val backlogGrowing = pendingDelta > 0 && drainedDelta == 0
        val stalledOnCapacity = blockedDelta > 0 && drainedDelta == 0
        queueHealthyForRecovery =
            pendingScrollItems.isEmpty() ||
            drainedDelta > 0 ||
            pendingDelta <= 0 ||
            blockedDelta == 0
        if (backlogGrowing || stalledOnCapacity) {
            queuePressureStreak += 1
            recoveryStreak = 0
            if (queuePressureStreak >= 2) {
                when (overloadLevel) {
                    NativeDanmakuOverloadLevel.NORMAL -> setOverloadLevel(NativeDanmakuOverloadLevel.SOFT)
                    NativeDanmakuOverloadLevel.SOFT -> setOverloadLevel(NativeDanmakuOverloadLevel.HARD)
                    NativeDanmakuOverloadLevel.HARD -> Unit
                }
                queuePressureStreak = 0
            }
        } else {
            queuePressureStreak = 0
        }
        snapshotQueuePressureWindow(timelineMs)
    }

    private fun snapshotQueuePressureWindow(timelineMs: Float) {
        lastQueuePressureEvaluationMs = timelineMs
        lastWindowPendingCount = pendingScrollItems.size
        lastWindowDrainedCount = schedulerDrainedFromQueueCount
        lastWindowBlockedCount = schedulerBlockedByCapacityCount + schedulerBlockedByTrackCount
    }

    private fun setOverloadLevel(nextLevel: NativeDanmakuOverloadLevel) {
        if (overloadLevel == nextLevel) {
            return
        }
        val previousLevel = overloadLevel
        overloadLevel = nextLevel
        val nowNs = currentAnimationClockNs(System.nanoTime())
        val timelineMs = currentTimelineMs(nowNs)
        rebuildLaneLayout()
        relayoutActiveItems(timelineMs)
        Log.d(
            TAG,
            "[DANMAKU][NATIVE] overload ${overloadLabel(previousLevel)}->${overloadLabel(nextLevel)} " +
                "active=${activeItems.size} pending=${pendingScrollItems.size} " +
                "blocked=${schedulerBlockedByCapacityCount + schedulerBlockedByTrackCount} " +
                "queued=${schedulerQueuedByCapacityCount + schedulerQueuedByTrackCount} " +
                "drained=$schedulerDrainedFromQueueCount dropped=$schedulerDroppedFromQueueCount " +
                "merged=$schedulerMergedCount density=${"%.3f".format(effectiveDensityRatio)} " +
                "durationMs=${"%.0f".format(currentScrollBaseTravelDurationMs())} " +
                "area=${"%.3f".format(currentEffectiveDisplayAreaRatio())}",
        )
        invalidate()
        if (shouldAnimate()) {
            scheduleFrame()
        }
    }

    private fun overloadLabel(level: NativeDanmakuOverloadLevel): String {
        return when (level) {
            NativeDanmakuOverloadLevel.NORMAL -> "normal"
            NativeDanmakuOverloadLevel.SOFT -> "soft"
            NativeDanmakuOverloadLevel.HARD -> "hard"
        }
    }

    private fun recordPlaybackSyncStats(
        nowNs: Long,
        sampleLatencyMs: Float,
        projectionMs: Float,
        rawDriftMs: Float,
        stabilizedDriftMs: Float,
        rebuildTimeline: Boolean,
        reanchorTimeline: Boolean,
        softSyncSelected: Boolean,
        softSyncApplied: Boolean,
        latencyFiltered: Boolean,
    ) {
        if (playbackSyncWindowStartNs == 0L) {
            playbackSyncWindowStartNs = nowNs
        }
        playbackSyncSampleCount += 1
        playbackSyncAccumulatedSampleLatencyMs += sampleLatencyMs
        playbackSyncMaxSampleLatencyMs = max(playbackSyncMaxSampleLatencyMs, sampleLatencyMs)
        val absProjectionMs = abs(projectionMs)
        playbackSyncAccumulatedProjectionMs += absProjectionMs
        playbackSyncMaxProjectionMs = max(playbackSyncMaxProjectionMs, absProjectionMs)
        val absRawDriftMs = abs(rawDriftMs)
        playbackSyncAccumulatedRawDriftAbsMs += absRawDriftMs
        playbackSyncMaxRawDriftAbsMs = max(playbackSyncMaxRawDriftAbsMs, absRawDriftMs)
        val absStabilizedDriftMs = abs(stabilizedDriftMs)
        playbackSyncAccumulatedStabilizedDriftAbsMs += absStabilizedDriftMs
        playbackSyncMaxStabilizedDriftAbsMs =
            max(playbackSyncMaxStabilizedDriftAbsMs, absStabilizedDriftMs)
        if (rebuildTimeline) {
            playbackSyncRebuildCount += 1
        }
        if (reanchorTimeline) {
            playbackSyncReanchorCount += 1
        }
        if (softSyncSelected) {
            playbackSyncSoftSyncPathCount += 1
        }
        if (softSyncApplied) {
            playbackSyncSoftSyncAppliedCount += 1
        }
        if (latencyFiltered) {
            playbackSyncLatencyFilteredCount += 1
        }
        val windowDurationNs = nowNs - playbackSyncWindowStartNs
        if (windowDurationNs < FPS_LOG_WINDOW_NS) {
            return
        }
        if (!enablePerfLogs) {
            resetPlaybackSyncStats(nextWindowStartNs = nowNs)
            return
        }
        val safeSampleCount = playbackSyncSampleCount.coerceAtLeast(1)
        Log.d(
            TAG,
            String.format(
                Locale.US,
                "[DANMAKU][NATIVE] sync updates=%d avgSampleLatencyMs=%.2f maxSampleLatencyMs=%.2f avgProjectionMs=%.2f maxProjectionMs=%.2f avgAbsRawDriftMs=%.2f maxAbsRawDriftMs=%.2f avgAbsStabilizedDriftMs=%.2f maxAbsStabilizedDriftMs=%.2f rebuild=%d reanchor=%d softSyncPath=%d softSyncApplied=%d latencyFiltered=%d windowMs=%d",
                playbackSyncSampleCount,
                playbackSyncAccumulatedSampleLatencyMs / safeSampleCount.toFloat(),
                playbackSyncMaxSampleLatencyMs,
                playbackSyncAccumulatedProjectionMs / safeSampleCount.toFloat(),
                playbackSyncMaxProjectionMs,
                playbackSyncAccumulatedRawDriftAbsMs / safeSampleCount.toFloat(),
                playbackSyncMaxRawDriftAbsMs,
                playbackSyncAccumulatedStabilizedDriftAbsMs / safeSampleCount.toFloat(),
                playbackSyncMaxStabilizedDriftAbsMs,
                playbackSyncRebuildCount,
                playbackSyncReanchorCount,
                playbackSyncSoftSyncPathCount,
                playbackSyncSoftSyncAppliedCount,
                playbackSyncLatencyFilteredCount,
                windowDurationNs / 1_000_000L,
            ),
        )
        resetPlaybackSyncStats(nextWindowStartNs = nowNs)
    }

    private fun resetFrameStats() {
        fpsWindowStartNs = 0L
        rawCallbackLastFrameNs = 0L
        rawCallbackFrameCount = 0
        rawCallbackAccumulatedDeltaNs = 0L
        rawCallbackMaxDeltaNs = 0L
        throttledCallbackCount = 0
        acceptedFrameLastNs = 0L
        acceptedFrameCount = 0
        acceptedSlowFrameCount = 0
        acceptedAccumulatedDeltaNs = 0L
        acceptedMaxDeltaNs = 0L
        drawWindowStartNs = 0L
        drawFrameCount = 0
        drawAccumulatedTotalNs = 0L
        drawAccumulatedTimelineNs = 0L
        drawAccumulatedBitmapNs = 0L
        drawAccumulatedMaskNs = 0L
        drawAccumulatedItems = 0
        drawMaxNs = 0L
    }

    private fun resetPlaybackSyncStats(nextWindowStartNs: Long = 0L) {
        playbackSyncWindowStartNs = nextWindowStartNs
        playbackSyncSampleCount = 0
        playbackSyncAccumulatedSampleLatencyMs = 0f
        playbackSyncMaxSampleLatencyMs = 0f
        playbackSyncAccumulatedProjectionMs = 0f
        playbackSyncMaxProjectionMs = 0f
        playbackSyncAccumulatedRawDriftAbsMs = 0f
        playbackSyncAccumulatedStabilizedDriftAbsMs = 0f
        playbackSyncMaxRawDriftAbsMs = 0f
        playbackSyncMaxStabilizedDriftAbsMs = 0f
        playbackSyncRebuildCount = 0
        playbackSyncReanchorCount = 0
        playbackSyncSoftSyncPathCount = 0
        playbackSyncSoftSyncAppliedCount = 0
        playbackSyncLatencyFilteredCount = 0
    }

    private fun resetFrameScheduler() {
        frameBudgetAccumulatorNs = 0L
        frameBudgetLastCallbackNs = 0L
        renderFrameTimeNs = 0L
    }

    private fun currentTimelineMs(nowNs: Long): Float {
        if (paused) {
            return timelineAnchorPositionMs
        }
        val elapsedNs = (nowNs - timelineAnchorTimeNs).coerceAtLeast(0L)
        val elapsedMs = elapsedNs / 1_000_000f
        return timelineAnchorPositionMs + (elapsedMs * settings.playbackSpeed.coerceAtLeast(0.1f))
    }

    private fun shouldAnimate(): Boolean {
        if (!attachedToHost || !settings.enabled || width <= 0 || height <= 0) {
            return false
        }
        if (comments.isEmpty()) {
            return false
        }
        return !paused || activeItems.isNotEmpty()
    }

    private fun scheduleFrame() {
        if (frameScheduled) return
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun cancelFrame() {
        if (!frameScheduled) {
            resetFrameScheduler()
            resetFrameStats()
            return
        }
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        frameScheduled = false
        resetFrameScheduler()
        resetFrameStats()
    }

    private fun lowerBoundCommentIndex(targetMs: Int): Int {
        var low = 0
        var high = comments.size
        while (low < high) {
            val mid = (low + high) ushr 1
            if (comments[mid].timeMs < targetMs) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private fun findAvailableLane(availableAtMs: FloatArray, targetTimeMs: Float): Int? {
        return NativeDanmakuLaneScheduler.findReleasedLane(
            availableAtMs = availableAtMs,
            targetTimeMs = targetTimeMs,
        )
    }

    private fun shouldDrawOcclusionMask(): Boolean {
        if (!occlusion.enabled) {
            return false
        }
        return when (occlusion.mode) {
            NativeDanmakuOcclusionMode.MASK -> {
                val currentMask = currentMaskBitmap ?: return false
                !currentMask.isRecycled
            }
            NativeDanmakuOcclusionMode.BBOX -> occlusion.hasUsableRect
            NativeDanmakuOcclusionMode.DISABLED -> false
        }
    }

    // Phase 3: returns the mask bitmap used for per-comment coverage and fills
    // [occlusionContentRect] with the screen rect that mask maps onto (the letterboxed
    // video area in PTS mode, or the displayed danmaku area in the live path). null when
    // the split is disabled / no usable mask this frame.
    private fun maskCoverageContext(timelineMs: Float): Bitmap? {
        if (occlusionDrawWholeRatio <= 0f) return null
        if (occlusion.mode != NativeDanmakuOcclusionMode.MASK) return null
        val frame = selectMaskForTimeline(timelineMs.toLong())
        val mask = if (ptsMaskMode) frame?.bitmap else (frame?.bitmap ?: currentMaskBitmap)
        if (mask == null || mask.isRecycled) return null
        val destinationCoverage = settings.displayAreaRatio.coerceIn(0.25f, 1.0f)
        val visibleDestinationBottom =
            ceil(height.toDouble() * destinationCoverage.toDouble())
                .toFloat()
                .coerceIn(1f, height.toFloat())
        val destinationBottom =
            (visibleDestinationBottom + partialMaskBoundaryBleedPx(destinationCoverage))
                .coerceIn(1f, height.toFloat())
        if (ptsMaskMode && occlusionVideoAspect > 0f) {
            val viewAspect = width.toFloat() / height.toFloat()
            if (occlusionVideoAspect > viewAspect) {
                val ch = width.toFloat() / occlusionVideoAspect
                val ct = (height.toFloat() - ch) / 2f
                occlusionContentRect.set(0f, ct, width.toFloat(), ct + ch)
            } else {
                val cw = height.toFloat() * occlusionVideoAspect
                val cl = (width.toFloat() - cw) / 2f
                occlusionContentRect.set(cl, 0f, cl + cw, height.toFloat())
            }
        } else {
            occlusionContentRect.set(0f, 0f, width.toFloat(), destinationBottom)
        }
        return mask
    }

    // Extract the mask's ARGB pixels once per bitmap change (not per frame) for fast
    // per-comment alpha sampling.
    private fun ensureCoveragePixels(mask: Bitmap): Boolean {
        if (mask === coverageMaskRef && coveragePixels != null) return true
        val w = mask.width
        val h = mask.height
        if (w <= 0 || h <= 0) return false
        val px = coveragePixels?.takeIf { it.size == w * h } ?: IntArray(w * h)
        val ok = runCatching { mask.getPixels(px, 0, w, 0, 0, w, h) }.isSuccess
        if (!ok) return false
        coveragePixels = px
        coverageMaskRef = mask
        coverageMaskW = w
        coverageMaskH = h
        return true
    }

    // True when the comment sits mostly over the subject → draw it whole (uncarved) so it
    // isn't sliced into unreadable fragments.
    private fun itemMostlyOverSubject(
        item: ActiveDanmakuItem,
        timelineMs: Float,
    ): Boolean {
        val px = coveragePixels ?: return false
        val mw = coverageMaskW
        val mh = coverageMaskH
        if (mw <= 0 || mh <= 0) return false
        val cl = occlusionContentRect.left
        val ct = occlusionContentRect.top
        val cw = occlusionContentRect.width()
        val ch = occlusionContentRect.height()
        if (cw <= 0f || ch <= 0f) return false
        val itemLeft = item.left(width.toFloat(), timelineMs)
        val itemTop = item.top
        val itemW = item.bitmap.drawWidth
        val itemH = item.bitmap.drawHeight
        if (itemW <= 0f || itemH <= 0f) return false
        val gx = occlusionCoverageSamplesX
        val gy = occlusionCoverageSamplesY
        var subject = 0
        var total = 0
        var iy = 0
        while (iy < gy) {
            val sy = itemTop + itemH * (iy + 0.5f) / gy
            var ix = 0
            while (ix < gx) {
                val sx = itemLeft + itemW * (ix + 0.5f) / gx
                total += 1
                if (sx >= cl && sx < cl + cw && sy >= ct && sy < ct + ch) {
                    val mx = (((sx - cl) / cw) * mw).toInt().coerceIn(0, mw - 1)
                    val my = (((sy - ct) / ch) * mh).toInt().coerceIn(0, mh - 1)
                    val alpha = (px[my * mw + mx] ushr 24) and 0xFF
                    if (alpha >= occlusionCoverageAlphaThreshold) subject += 1
                }
                ix += 1
            }
            iy += 1
        }
        return total > 0 && subject.toFloat() / total.toFloat() >= occlusionDrawWholeRatio
    }

    // E1: draw one PTS mask mapped onto the letterboxed video rect (the mask is the RAW
    // square video frame; the displayed video is centered+fit with bars). [offsetX/Y] is
    // the motion-extrapolation nudge (0 for the bracket's "next" mask — it IS the future
    // position). DST_OUT erases the danmaku layer under the subject.
    private fun drawPtsMaskBitmap(
        canvas: Canvas,
        mask: Bitmap,
        offsetX: Float,
        offsetY: Float,
        destinationBottom: Float,
    ) {
        val viewAspect = width.toFloat() / height.toFloat()
        val contentLeft: Float
        val contentTop: Float
        val contentWidth: Float
        val contentHeight: Float
        if (occlusionVideoAspect > viewAspect) {
            contentWidth = width.toFloat()
            contentHeight = width.toFloat() / occlusionVideoAspect
            contentLeft = 0f
            contentTop = (height.toFloat() - contentHeight) / 2f
        } else {
            contentHeight = height.toFloat()
            contentWidth = height.toFloat() * occlusionVideoAspect
            contentLeft = (width.toFloat() - contentWidth) / 2f
            contentTop = 0f
        }
        maskSrcRect.set(0, 0, mask.width, mask.height)
        maskDstRect.set(
            contentLeft + offsetX,
            contentTop + offsetY,
            contentLeft + contentWidth + offsetX,
            contentTop + contentHeight + offsetY,
        )
        val restoreCount = canvas.save()
        canvas.clipRect(0f, 0f, width.toFloat(), destinationBottom)
        canvas.drawBitmap(mask, maskSrcRect, maskDstRect, maskPaintCrisp)
        canvas.restoreToCount(restoreCount)
    }

    private fun drawOcclusionMask(canvas: Canvas) {
        when (occlusion.mode) {
            NativeDanmakuOcclusionMode.MASK -> {
                val timelineMs = currentTimelineMs(System.nanoTime()).toLong()
                val destinationCoverage = settings.displayAreaRatio.coerceIn(0.25f, 1.0f)
                val visibleDestinationBottom =
                    ceil(height.toDouble() * destinationCoverage.toDouble())
                        .toFloat()
                        .coerceIn(1f, height.toFloat())
                val destinationBottom =
                    (visibleDestinationBottom + partialMaskBoundaryBleedPx(destinationCoverage))
                        .coerceIn(1f, height.toFloat())

                // Plan B v2 (local): bracket dual-mask. Draw the floor mask (extrapolated by
                // its own per-step velocity over t-pts, capped at one step) AND, at full
                // alpha with no extrapolation, the next (future) mask. Their union covers the
                // subject's swept path t0→t1 → the lag of a moving subject disappears without
                // relying on velocity accuracy. NO cross-fade: partial alpha = ghost (the
                // historical "半透明残留" pitfall) — both masks must be full alpha. Static
                // shots reuse the same bitmap reference → next === floor → union auto-skips.
                if (ptsMaskMode && occlusionVideoAspect > 0f) {
                    val bracket = selectMaskBracket(timelineMs)
                    if (bracket == null) {
                        maybeLogMaskBias(timelineMs, null, null, false)
                        return
                    }
                    val floor = bracket.floor
                    if (floor.bitmap.isRecycled) return
                    val extrapMs = (timelineMs - floor.ptsMs).coerceIn(0L, floor.stepMs.coerceAtLeast(1L))
                    val maxOffX = width.toFloat() * maskExtrapMaxFraction
                    val maxOffY = height.toFloat() * maskExtrapMaxFraction
                    val offX =
                        (floor.vxPerMs * extrapMs.toDouble() * width.toDouble())
                            .toFloat()
                            .coerceIn(-maxOffX, maxOffX)
                    val offY =
                        (floor.vyPerMs * extrapMs.toDouble() * height.toDouble())
                            .toFloat()
                            .coerceIn(-maxOffY, maxOffY)
                    drawPtsMaskBitmap(canvas, floor.bitmap, offX, offY, destinationBottom)
                    val next = bracket.next
                    val unionDrawn =
                        next != null &&
                            !next.sceneCut &&
                            !next.bitmap.isRecycled &&
                            next.bitmap !== floor.bitmap
                    if (unionDrawn) {
                        drawPtsMaskBitmap(canvas, next!!.bitmap, 0f, 0f, destinationBottom)
                    }
                    maybeLogMaskBias(timelineMs, floor, next, unionDrawn)
                    return
                }

                // Live-capture path (network): single mask, full-view mapping with a source
                // crop, wall-clock extrapolation off the controller's global velocity.
                val ptsFrame = selectMaskForTimeline(timelineMs)
                val currentMask =
                    if (ptsMaskMode) {
                        ptsFrame?.bitmap ?: return
                    } else {
                        ptsFrame?.bitmap ?: currentMaskBitmap ?: return
                    }
                if (currentMask.isRecycled) return
                val sourceCoverage = resolveMaskSourceCoverageRatio(
                    displayAreaRatio = (destinationBottom / height.toFloat()).coerceIn(0f, 1f),
                    captureAreaRatio = occlusion.captureAreaRatio,
                )
                val sourceHeight =
                    ceil(currentMask.height.toDouble() * sourceCoverage.toDouble())
                        .toInt()
                        .coerceIn(1, currentMask.height)
                maskSrcRect.set(0, 0, currentMask.width, sourceHeight)
                val extrapMs =
                    (SystemClock.uptimeMillis() - maskAnchorUptimeMs)
                        .coerceIn(0L, maskExtrapMaxMs)
                val maxOffX = width.toFloat() * maskExtrapMaxFraction
                val maxOffY = height.toFloat() * maskExtrapMaxFraction
                val maskOffsetX =
                    (maskVelocityX * extrapMs.toDouble() * width.toDouble())
                        .toFloat()
                        .coerceIn(-maxOffX, maxOffX)
                val maskOffsetY =
                    (maskVelocityY * extrapMs.toDouble() * height.toDouble())
                        .toFloat()
                        .coerceIn(-maxOffY, maxOffY)
                maskDstRect.set(
                    maskOffsetX,
                    maskOffsetY,
                    width.toFloat() + maskOffsetX,
                    destinationBottom + maskOffsetY,
                )
                val restoreCount = canvas.save()
                canvas.clipRect(0f, 0f, width.toFloat(), destinationBottom)
                val drawPaint =
                    if (destinationCoverage < 0.999f || sourceCoverage < 0.999f) {
                        maskPaintCrisp
                    } else {
                        maskPaint
                    }
                canvas.drawBitmap(currentMask, maskSrcRect, maskDstRect, drawPaint)
                canvas.restoreToCount(restoreCount)
            }
            NativeDanmakuOcclusionMode.BBOX -> {
                val rect = occlusion.normalizedRect ?: return
                if (!rect.hasArea) return
                val left = (rect.x * width).coerceIn(0f, width.toFloat())
                val top = (rect.y * height).coerceIn(0f, height.toFloat())
                val right = ((rect.x + rect.width) * width).coerceIn(left, width.toFloat())
                val bottom = ((rect.y + rect.height) * height).coerceIn(top, height.toFloat())
                if (right - left < 1f || bottom - top < 1f) {
                    return
                }
                bboxDstRect.set(left, top, right, bottom)
                val radius = min((right - left), (bottom - top)) * 0.12f
                canvas.drawRoundRect(bboxDstRect, radius, radius, maskPaint)
            }
            NativeDanmakuOcclusionMode.DISABLED -> Unit
        }
    }

    private fun partialMaskBoundaryBleedPx(displayAreaRatio: Float): Float {
        if (displayAreaRatio >= 0.999f || width <= 0 || height <= 0) {
            return 0f
        }
        val viewportScale = currentViewportAdaptiveScale()
        val textEdgeBleed =
            max(
                density * PARTIAL_MASK_BOUNDARY_BLEED_DP,
                currentStrokeWidthPx() * 3f + trackVerticalPaddingPx * viewportScale,
            )
        val maxBleed = height.toFloat() * PARTIAL_MASK_BOUNDARY_MAX_BLEED_RATIO
        return textEdgeBleed.coerceIn(2f, maxBleed.coerceAtLeast(2f))
    }

    private fun resolveMaskSourceCoverageRatio(
        displayAreaRatio: Float,
        captureAreaRatio: Float,
    ): Float {
        val capture = captureAreaRatio.coerceIn(0.1f, 1.0f)
        return (displayAreaRatio / capture).coerceIn(0f, 1f)
    }

    private fun loadMaskAsync(
        payload: NativeDanmakuOcclusionPayload,
        maskKey: String,
    ) {
        val path = payload.maskPath ?: return
        val generation = ++maskGeneration
        maskExecutor.execute {
            val decodedBitmap = BitmapFactory.decodeFile(path)
            mainHandler.post {
                if (generation != maskGeneration) {
                    decodedBitmap?.takeIf { !it.isRecycled }?.recycle()
                    return@post
                }
                if (decodedBitmap == null) {
                    if (payload.shouldDelayMaskClear) {
                        scheduleMaskClear()
                    } else {
                        clearMaskState()
                    }
                    invalidate()
                    return@post
                }
                cancelPendingMaskClear()
                replaceMaskBitmap(decodedBitmap, maskKey)
                invalidate()
            }
        }
    }

    private fun replaceMaskBitmap(
        nextBitmap: Bitmap,
        nextMaskKey: String,
    ) {
        if (currentMaskKey == nextMaskKey && currentMaskBitmap === nextBitmap) {
            return
        }
        currentMaskBitmap?.takeIf { it !== nextBitmap && !it.isRecycled }?.recycle()
        currentMaskBitmap = nextBitmap
        currentMaskKey = nextMaskKey
    }

    private fun scheduleMaskClear() {
        if (currentMaskBitmap == null && currentMaskKey == null) {
            return
        }
        if (pendingMaskClear != null) {
            return
        }
        val generation = ++maskGeneration
        val runnable =
            Runnable {
                pendingMaskClear = null
                if (generation != maskGeneration) {
                    return@Runnable
                }
                if (occlusion.hasUsableMask) {
                    return@Runnable
                }
                clearMaskState()
                invalidate()
            }
        pendingMaskClear = runnable
        mainHandler.postDelayed(runnable, MASK_CLEAR_GRACE_MS)
    }

    private fun cancelPendingMaskClear() {
        val runnable = pendingMaskClear ?: return
        mainHandler.removeCallbacks(runnable)
        pendingMaskClear = null
    }

    private fun clearLoadedMaskBitmap() {
        currentMaskBitmap?.takeIf { !it.isRecycled }?.recycle()
        currentMaskBitmap = null
        currentMaskKey = null
    }

    private fun clearMaskState() {
        cancelPendingMaskClear()
        clearLoadedMaskBitmap()
        clearMaskPtsBuffer()
    }
}
