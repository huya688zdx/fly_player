package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.util.AttributeSet
import android.util.Log
import android.util.LruCache
import android.view.Choreographer
import android.view.View
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

private enum class NativeDanmakuType {
    SCROLL,
    TOP,
    BOTTOM,
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
    val speed: Float = 1.0f,
    val displayAreaRatio: Float = 0.5f,
    val scrollEnabled: Boolean = true,
    val topEnabled: Boolean = true,
    val bottomEnabled: Boolean = false,
    val colorEnabled: Boolean = true,
    val hideDuplicate: Boolean = true,
    val avoidSubtitleArea: Boolean = true,
    val avoidCenterArea: Boolean = true,
    val playbackSpeed: Float = 1.0f,
    val sourceKey: String = "",
) {
    val effectiveOpacity: Int
        get() = (opacity.coerceIn(0.2f, 1.0f) * 255f).toInt().coerceIn(0, 255)
}

private data class NativeDanmakuLayout(
    val topTracks: List<Float>,
    val bottomTracks: List<Float>,
    val trackHeight: Float,
)

private data class NativeDanmakuTextMetrics(
    val width: Float,
    val baselineOffset: Float,
    val ascent: Float,
    val descent: Float,
)

private data class ActiveDanmakuItem(
    val id: String,
    val text: String,
    val type: NativeDanmakuType,
    val color: Int,
    val width: Float,
    val baselineOffset: Float,
    val ascent: Float,
    val descent: Float,
    val trackPosition: Float,
    val startMs: Int,
    val durationMs: Int,
) {
    fun isExpired(timelineMs: Int, viewportWidth: Float): Boolean {
        val elapsedMs = timelineMs - startMs
        if (elapsedMs < 0) return false
        if (type != NativeDanmakuType.SCROLL) {
            return elapsedMs >= durationMs
        }
        return xFor(viewportWidth, timelineMs) <= -width
    }

    fun xFor(viewportWidth: Float, timelineMs: Int): Float {
        if (type != NativeDanmakuType.SCROLL) {
            return (viewportWidth - width) / 2f
        }
        val elapsedMs = (timelineMs - startMs).coerceIn(0, durationMs)
        val progress = if (durationMs <= 0) 1f else elapsedMs.toFloat() / durationMs.toFloat()
        return viewportWidth - (progress * (viewportWidth + width))
    }

    fun baselineYFor(viewportHeight: Float): Float {
        return if (type == NativeDanmakuType.BOTTOM) {
            viewportHeight - trackPosition - descent
        } else {
            trackPosition + baselineOffset
        }
    }
}

class NativeDanmakuOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs), Choreographer.FrameCallback {
    companion object {
        private const val TAG = "NativeDanmaku"
        private const val DENSITY_BUCKET_SCALE = 1000
        private const val MASSIVE_MODE_THRESHOLD = 1200
        private const val MINIMUM_DUPLICATE_WINDOW_MS = 2500
        private const val STATIC_DANMAKU_DURATION_MS = 2600
        private const val SUBTITLE_RESERVED_AREA_RATIO = 0.16f
        private const val LINE_HEIGHT = 1.0f
        private const val STROKE_WIDTH_DP = 0.9f
        private const val EDGE_PADDING_MIN_DP = 3f
        private const val EDGE_PADDING_MAX_DP = 10f
        private const val TEXT_CACHE_SIZE = 256
    }

    private val density = resources.displayMetrics.density
    private val strokeWidthPx = density * STROKE_WIDTH_DP
    private val edgePaddingMinPx = density * EDGE_PADDING_MIN_DP
    private val edgePaddingMaxPx = density * EDGE_PADDING_MAX_DP
    private val fillPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
        textAlign = Paint.Align.LEFT
        isSubpixelText = true
    }
    private val strokePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        textAlign = Paint.Align.LEFT
        strokeJoin = Paint.Join.ROUND
        strokeMiter = 10f
        isSubpixelText = true
        strokeWidth = strokeWidthPx
    }
    private val textMetricsCache = object : LruCache<String, NativeDanmakuTextMetrics>(TEXT_CACHE_SIZE) {}

    private var settings = NativeDanmakuSettings()
    private var sourceComments: List<NativeDanmakuComment> = emptyList()
    private var scheduledComments: List<NativeDanmakuComment> = emptyList()
    private val emittedCommentIds = HashSet<String>()
    private val scrollItems = ArrayList<ActiveDanmakuItem>()
    private val staticItems = ArrayList<ActiveDanmakuItem>()
    private var layoutCache: NativeDanmakuLayout? = null
    private var layoutSignature = ""
    private var commentsSignature = ""
    private var visualStateKey = ""
    private var currentSourceKey = ""
    private var currentPositionMs = 0
    private var lastScheduledPositionMs = 0
    private var timelineMs = 0
    private var frameAnchorPositionMs = 0
    private var frameAnchorTimeNs = 0L
    private var lastFrameTimeNs = 0L
    private var paused = true
    private var listenVideoModeEnabled = false
    private var attached = false
    private var framePosted = false
    private var lastVisibleState: Boolean? = null
    private var lastLoggedSize: Pair<Int, Int>? = null

    init {
        setWillNotDraw(false)
        isClickable = false
        isFocusable = false
        alpha = settings.opacity
    }

    fun updatePlaybackState(state: MpvPlayerState) {
        paused = state.paused
        listenVideoModeEnabled = state.listenVideoModeEnabled
        currentPositionMs = state.positionMs.coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        frameAnchorPositionMs = currentPositionMs
        frameAnchorTimeNs = System.nanoTime()
        if (paused) {
            timelineMs = currentPositionMs
        }
        syncTimelineForPosition()
        updateVisualState()
        invalidate()
    }

    fun setPayload(arguments: Map<String, Any?>) {
        val nextSettings = NativeDanmakuSettings(
            enabled = arguments["enabled"] as? Boolean ?: false,
            opacity = (arguments["opacity"] as? Number)?.toFloat() ?: 0.85f,
            density = (arguments["density"] as? Number)?.toFloat() ?: 1.0f,
            fontScale = (arguments["fontScale"] as? Number)?.toFloat() ?: 1.0f,
            speed = (arguments["speed"] as? Number)?.toFloat() ?: 1.0f,
            displayAreaRatio = (arguments["displayAreaRatio"] as? Number)?.toFloat() ?: 0.5f,
            scrollEnabled = arguments["scrollEnabled"] as? Boolean ?: true,
            topEnabled = arguments["topEnabled"] as? Boolean ?: true,
            bottomEnabled = arguments["bottomEnabled"] as? Boolean ?: false,
            colorEnabled = arguments["colorEnabled"] as? Boolean ?: true,
            hideDuplicate = arguments["hideDuplicate"] as? Boolean ?: true,
            avoidSubtitleArea = arguments["avoidSubtitleArea"] as? Boolean ?: true,
            avoidCenterArea = arguments["avoidCenterArea"] as? Boolean ?: true,
            playbackSpeed = (arguments["playbackSpeed"] as? Number)?.toFloat() ?: 1.0f,
            sourceKey = arguments["sourceKey"]?.toString().orEmpty(),
        )
        val nextComments = parseComments(arguments["comments"])
        val sourceChanged = nextSettings.sourceKey != currentSourceKey
        currentSourceKey = nextSettings.sourceKey
        settings = nextSettings
        alpha = settings.opacity.coerceIn(0.2f, 1.0f)
        sourceComments = nextComments
        Log.d(
            TAG,
            "setPayload source=${nextSettings.sourceKey} comments=${nextComments.size} " +
                "enabled=${nextSettings.enabled} size=${width}x${height}",
        )
        commentsSignature = buildCommentsSignature(nextComments, nextSettings)
        scheduledComments = buildVisibleComments(nextComments, nextSettings)
        if (sourceChanged) {
            resetEngine(clearScreen = true)
            timelineMs = currentPositionMs
        } else {
            resetEngine(clearScreen = false)
        }
        layoutCache = null
        layoutSignature = ""
        syncTimelineForPosition(forceResync = true)
        updateVisualState()
        invalidate()
    }

    fun clear() {
        Log.d(TAG, "clear source=$currentSourceKey")
        settings = NativeDanmakuSettings()
        sourceComments = emptyList()
        scheduledComments = emptyList()
        currentSourceKey = ""
        commentsSignature = ""
        layoutCache = null
        layoutSignature = ""
        resetEngine(clearScreen = true)
        updateVisualState()
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attached = true
        updateVisualState()
    }

    override fun onDetachedFromWindow() {
        attached = false
        stopFrames()
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layoutCache = null
        layoutSignature = ""
        lastLoggedSize = null
        syncTimelineForPosition(forceResync = true)
    }

    override fun doFrame(frameTimeNanos: Long) {
        framePosted = false
        if (!shouldAnimate()) {
            lastFrameTimeNs = 0L
            return
        }
        val effectiveTimelineMs = resolveRealtimeTimelineMs(frameTimeNanos)
        timelineMs = effectiveTimelineMs
        syncTimelineForPosition()
        if (purgeExpiredItems()) {
            invalidate()
        } else {
            invalidate()
        }
        postNextFrame()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!shouldDrawDanmaku()) {
            return
        }
        val viewportWidth = width.toFloat()
        val viewportHeight = height.toFloat()
        val nowTimelineMs = resolveNowTimelineMs()
        timelineMs = nowTimelineMs
        drawItems(canvas, scrollItems, viewportWidth, viewportHeight, nowTimelineMs)
        drawItems(canvas, staticItems, viewportWidth, viewportHeight, nowTimelineMs)
    }

    private fun drawItems(
        canvas: Canvas,
        items: List<ActiveDanmakuItem>,
        viewportWidth: Float,
        viewportHeight: Float,
        timelineMs: Int,
    ) {
        val fontSizePx = fontSizePx(settings)
        fillPaint.textSize = fontSizePx
        strokePaint.textSize = fontSizePx
        strokePaint.strokeWidth = strokeWidthPx
        val alpha = settings.effectiveOpacity
        fillPaint.alpha = alpha
        strokePaint.alpha = alpha
        for (item in items) {
            if (item.isExpired(timelineMs, viewportWidth)) continue
            val x = item.xFor(viewportWidth, timelineMs)
            val baselineY = item.baselineYFor(viewportHeight)
            fillPaint.color = if (settings.colorEnabled) item.color else Color.WHITE
            canvas.drawText(item.text, x, baselineY, strokePaint)
            canvas.drawText(item.text, x, baselineY, fillPaint)
        }
    }

    private fun parseComments(raw: Any?): List<NativeDanmakuComment> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val text = map["text"]?.toString().orEmpty().trim()
            if (text.isEmpty()) return@mapNotNull null
            NativeDanmakuComment(
                id = map["id"]?.toString().orEmpty(),
                timeMs = (map["timeMs"] as? Number)?.toInt() ?: 0,
                text = text,
                type = when (map["type"]?.toString()?.lowercase()) {
                    "top" -> NativeDanmakuType.TOP
                    "bottom" -> NativeDanmakuType.BOTTOM
                    else -> NativeDanmakuType.SCROLL
                },
                color = (map["color"] as? Number)?.toInt() ?: Color.WHITE,
            )
        }.sortedWith(compareBy<NativeDanmakuComment> { it.timeMs }.thenBy { it.id })
    }

    private fun buildVisibleComments(
        comments: List<NativeDanmakuComment>,
        settings: NativeDanmakuSettings,
    ): List<NativeDanmakuComment> {
        var visible = comments
        if (settings.hideDuplicate) {
            val seenTimeByText = HashMap<String, Int>()
            val duplicateWindowMs = max(activeWindowMs(settings), MINIMUM_DUPLICATE_WINDOW_MS)
            visible = comments.filter { comment ->
                val key = comment.text.replace(Regex("\\s+"), " ").trim()
                if (key.isEmpty()) {
                    false
                } else {
                    val lastSeen = seenTimeByText[key]
                    seenTimeByText[key] = comment.timeMs
                    lastSeen == null || comment.timeMs - lastSeen >= duplicateWindowMs
                }
            }
        }
        val densityValue = settings.density.coerceIn(0.2f, 1.0f)
        if (densityValue >= 0.999f || visible.isEmpty()) {
            return visible
        }
        val threshold = (densityValue * DENSITY_BUCKET_SCALE).toInt().coerceIn(1, DENSITY_BUCKET_SCALE)
        return visible.filter { comment ->
            commentBucket(comment) < threshold
        }
    }

    private fun commentBucket(comment: NativeDanmakuComment): Int {
        var hash = 0
        val seed = "${comment.id}|${comment.text}|${comment.timeMs}"
        for (index in seed.indices) {
            hash = ((hash * 33) xor seed[index].code) and 0x7fffffff
        }
        return hash % DENSITY_BUCKET_SCALE
    }

    private fun resetEngine(clearScreen: Boolean) {
        if (clearScreen) {
            scrollItems.clear()
            staticItems.clear()
        }
        emittedCommentIds.clear()
        lastScheduledPositionMs = 0
    }

    private fun syncTimelineForPosition(forceResync: Boolean = false) {
        if (!shouldDrawDanmaku()) {
            stopFrames()
            return
        }
        val positionMs = resolveNowTimelineMs()
        if (forceResync ||
            commentsSignature != visualStateKey ||
            positionMs < lastScheduledPositionMs - 800 ||
            positionMs > lastScheduledPositionMs + 1500
        ) {
            visualStateKey = commentsSignature
            resyncVisibleWindow(positionMs, forceClear = true)
            updateVisualState()
            return
        }
        if (positionMs <= lastScheduledPositionMs) {
            updateVisualState()
            return
        }
        emitCommentsInRange(lastScheduledPositionMs, positionMs)
        lastScheduledPositionMs = positionMs
        updateVisualState()
    }

    private fun resyncVisibleWindow(currentPositionMs: Int, forceClear: Boolean) {
        if (forceClear) {
            scrollItems.clear()
            staticItems.clear()
        }
        emittedCommentIds.clear()
        val startMs = max(0, currentPositionMs - activeWindowMs(settings))
        emitCommentsInRange(startMs, currentPositionMs)
        lastScheduledPositionMs = currentPositionMs
        timelineMs = currentPositionMs
    }

    private fun emitCommentsInRange(startMs: Int, endMs: Int) {
        if (scheduledComments.isEmpty() || endMs < startMs) {
            return
        }
        val startIndex = lowerBound(scheduledComments, startMs)
        val endIndex = upperBound(scheduledComments, endMs)
        for (index in startIndex until endIndex) {
            enqueueComment(scheduledComments[index], endMs)
        }
    }

    private fun enqueueComment(comment: NativeDanmakuComment, currentPositionMs: Int) {
        if (!isCommentTypeEnabled(comment.type)) return
        if (!emittedCommentIds.add(comment.id)) return
        val layout = resolveLayout() ?: return
        val durationMs = if (comment.type == NativeDanmakuType.SCROLL) {
            scrollDurationMs(settings)
        } else {
            STATIC_DANMAKU_DURATION_MS
        }
        val ageMs = max(0, currentPositionMs - comment.timeMs)
        if (ageMs >= durationMs) return
        val metrics = resolveTextMetrics(comment.text, settings)
        val item = ActiveDanmakuItem(
            id = comment.id,
            text = comment.text,
            type = comment.type,
            color = if (settings.colorEnabled) comment.color else Color.WHITE,
            width = metrics.width,
            baselineOffset = metrics.baselineOffset,
            ascent = metrics.ascent,
            descent = metrics.descent,
            trackPosition = 0f,
            startMs = timelineMs - ageMs,
            durationMs = durationMs,
        )
        val trackPosition = pickTrackPosition(
            layout = layout,
            item = item,
            allowOverlap = comment.type == NativeDanmakuType.SCROLL &&
                scheduledComments.size >= MASSIVE_MODE_THRESHOLD,
            overlapSeed = comment.id,
        ) ?: return
        val placed = item.copy(trackPosition = trackPosition)
        if (placed.type == NativeDanmakuType.SCROLL) {
            scrollItems += placed
        } else {
            staticItems += placed
        }
    }

    private fun resolveTextMetrics(text: String, settings: NativeDanmakuSettings): NativeDanmakuTextMetrics {
        val cacheKey = buildTextMetricsKey(text, settings)
        textMetricsCache.get(cacheKey)?.let { return it }
        val fontSizePx = fontSizePx(settings)
        fillPaint.textSize = fontSizePx
        val metrics = fillPaint.fontMetrics
        val width = fillPaint.measureText(text)
        val resolved = NativeDanmakuTextMetrics(
            width = width,
            baselineOffset = -metrics.ascent + textVerticalPaddingPx(settings),
            ascent = metrics.ascent,
            descent = metrics.descent,
        )
        textMetricsCache.put(cacheKey, resolved)
        return resolved
    }

    private fun buildTextMetricsKey(text: String, settings: NativeDanmakuSettings): String {
        return listOf(
            text,
            fontSizePx(settings).toString(),
            settings.colorEnabled.toString(),
        ).joinToString("|")
    }

    private fun resolveLayout(): NativeDanmakuLayout? {
        val viewportWidth = width.toFloat()
        val viewportHeight = height.toFloat()
        if (viewportWidth <= 0f || viewportHeight <= 0f) return null
        val signature = listOf(
            viewportWidth.toInt(),
            viewportHeight.toInt(),
            fontSizePx(settings).toString(),
            effectiveAreaRatio(settings).toString(),
            settings.avoidSubtitleArea.toString(),
            settings.avoidCenterArea.toString(),
        ).joinToString("|")
        if (layoutCache != null && signature == layoutSignature) {
            return layoutCache
        }
        layoutSignature = signature
        val trackHeight = trackHeightPx(settings)
        val edgePadding = (trackHeight * 0.18f).coerceIn(edgePaddingMinPx, edgePaddingMaxPx)
        val subtitleReserveHeight = if (settings.avoidSubtitleArea) {
            viewportHeight * SUBTITLE_RESERVED_AREA_RATIO.coerceIn(0f, 0.5f)
        } else {
            0f
        }
        val topAreaHeight = max(0f, (viewportHeight * effectiveAreaRatio(settings)) - edgePadding)
        val bottomAreaHeight = max(0f, (viewportHeight * effectiveAreaRatio(settings)) - edgePadding)
        val exclusionRects = mutableListOf<RectF>()
        if (settings.avoidCenterArea) {
            exclusionRects += RectF(
                viewportWidth * 0.22f,
                viewportHeight * 0.28f,
                viewportWidth * 0.78f,
                viewportHeight * 0.70f,
            )
        }
        val topTrackCount = if (trackHeight <= 0f) 0 else (topAreaHeight / trackHeight).toInt().coerceIn(0, 1000)
        val bottomTrackCount = if (trackHeight <= 0f) 0 else (bottomAreaHeight / trackHeight).toInt().coerceIn(0, 1000)
        val topTracks = ArrayList<Float>(topTrackCount)
        for (index in 0 until topTrackCount) {
            val y = edgePadding + (index * trackHeight)
            val rect = RectF(0f, y, viewportWidth, y + trackHeight)
            if (exclusionRects.any { RectF.intersects(it, rect) }) continue
            topTracks += y
        }
        val bottomTracks = ArrayList<Float>(bottomTrackCount)
        for (index in 0 until bottomTrackCount) {
            val offset = subtitleReserveHeight + edgePadding + (index * trackHeight)
            val top = viewportHeight - offset - trackHeight
            if (top < 0f) break
            val rect = RectF(0f, top, viewportWidth, top + trackHeight)
            if (exclusionRects.any { RectF.intersects(it, rect) }) continue
            bottomTracks += offset
        }
        val resolved = NativeDanmakuLayout(
            topTracks = topTracks,
            bottomTracks = bottomTracks,
            trackHeight = trackHeight,
        )
        layoutCache = resolved
        return resolved
    }

    private fun pickTrackPosition(
        layout: NativeDanmakuLayout,
        item: ActiveDanmakuItem,
        allowOverlap: Boolean,
        overlapSeed: String,
    ): Float? {
        return when (item.type) {
            NativeDanmakuType.SCROLL -> {
                val topTracks = layout.topTracks
                val track = findTrack(topTracks, overlapSeed) { trackY ->
                    scrollCanAddToTrack(trackY, item.width)
                }
                if (track != null) {
                    track
                } else if (allowOverlap && topTracks.isNotEmpty()) {
                    fallbackTrack(topTracks, overlapSeed)
                } else {
                    null
                }
            }
            NativeDanmakuType.TOP -> {
                findTrack(layout.topTracks, overlapSeed) { trackY ->
                    staticCanAddToTrack(trackY, NativeDanmakuType.TOP)
                }
            }
            NativeDanmakuType.BOTTOM -> {
                findTrack(layout.bottomTracks, overlapSeed) { track ->
                    staticCanAddToTrack(track, NativeDanmakuType.BOTTOM)
                }
            }
        }
    }

    private fun findTrack(
        tracks: List<Float>,
        seed: String,
        canUse: (Float) -> Boolean,
    ): Float? {
        if (tracks.isEmpty()) return null
        val startIndex = seedTrackIndex(seed, tracks.size)
        for (offset in tracks.indices) {
            val track = tracks[(startIndex + offset) % tracks.size]
            if (canUse(track)) {
                return track
            }
        }
        return null
    }

    private fun scrollCanAddToTrack(trackY: Float, newItemWidth: Float): Boolean {
        val viewportWidth = width.toFloat()
        for (item in scrollItems) {
            if (abs(item.trackPosition - trackY) > 0.5f) continue
            if (item.isExpired(timelineMs, viewportWidth)) continue
            val x = item.xFor(viewportWidth, timelineMs)
            val existingEndPosition = x + item.width
            if (viewportWidth - existingEndPosition < 0f) {
                return false
            }
            if (item.width < newItemWidth) {
                val existingProgress = 1f - ((viewportWidth - x) / (item.width + viewportWidth))
                val newThreshold = viewportWidth / (viewportWidth + newItemWidth)
                if (existingProgress > newThreshold) {
                    return false
                }
            }
        }
        return true
    }

    private fun staticCanAddToTrack(trackPosition: Float, type: NativeDanmakuType): Boolean {
        val viewportWidth = width.toFloat()
        for (item in staticItems) {
            if (item.type != type) continue
            if (abs(item.trackPosition - trackPosition) > 0.5f) continue
            if (item.isExpired(timelineMs, viewportWidth)) continue
            return false
        }
        return true
    }

    private fun fallbackTrack(tracks: List<Float>, seed: String): Float {
        return tracks[seedTrackIndex(seed, tracks.size)]
    }

    private fun seedTrackIndex(seed: String, length: Int): Int {
        if (length <= 1) return 0
        var hash = 0
        for (index in seed.indices) {
            hash = ((hash * 33) xor seed[index].code) and 0x7fffffff
        }
        return hash % length
    }

    private fun purgeExpiredItems(): Boolean {
        val viewportWidth = width.toFloat()
        var changed = false
        scrollItems.removeAll { item ->
            val expired = item.isExpired(timelineMs, viewportWidth)
            if (expired) changed = true
            expired
        }
        staticItems.removeAll { item ->
            val expired = item.isExpired(timelineMs, viewportWidth)
            if (expired) changed = true
            expired
        }
        return changed
    }

    private fun isCommentTypeEnabled(type: NativeDanmakuType): Boolean {
        return when (type) {
            NativeDanmakuType.SCROLL -> settings.scrollEnabled
            NativeDanmakuType.TOP -> settings.topEnabled
            NativeDanmakuType.BOTTOM -> settings.bottomEnabled
        }
    }

    private fun fontSizePx(settings: NativeDanmakuSettings): Float {
        return max(16f * density, 24f * density * settings.fontScale.coerceIn(0.6f, 1.4f))
    }

    private fun textVerticalPaddingPx(settings: NativeDanmakuSettings): Float {
        return max(strokeWidthPx + density, fontSizePx(settings) * 0.18f)
    }

    private fun trackHeightPx(settings: NativeDanmakuSettings): Float {
        fillPaint.textSize = fontSizePx(settings)
        val metrics = fillPaint.fontMetrics
        return ceil((metrics.descent - metrics.ascent) + (textVerticalPaddingPx(settings) * 2f))
    }

    private fun effectiveAreaRatio(settings: NativeDanmakuSettings): Float {
        val base = settings.displayAreaRatio.coerceIn(0.1f, 1.0f)
        return if (settings.avoidSubtitleArea) min(base, 1.0f - SUBTITLE_RESERVED_AREA_RATIO) else base
    }

    private fun scrollDurationMs(settings: NativeDanmakuSettings): Int {
        val speed = settings.speed.coerceIn(0.7f, 1.8f)
        val seconds = (8.5f / speed).coerceIn(3.2f, 8.5f)
        return (seconds * 1000f).toInt()
    }

    private fun activeWindowMs(settings: NativeDanmakuSettings): Int {
        return max(scrollDurationMs(settings), STATIC_DANMAKU_DURATION_MS)
    }

    private fun buildCommentsSignature(
        comments: List<NativeDanmakuComment>,
        settings: NativeDanmakuSettings,
    ): String {
        val tail = comments.lastOrNull()
        return listOf(
            settings.sourceKey,
            comments.size,
            tail?.id.orEmpty(),
            tail?.timeMs ?: 0,
            settings.hideDuplicate,
            settings.density,
            settings.scrollEnabled,
            settings.topEnabled,
            settings.bottomEnabled,
            settings.fontScale,
            settings.speed,
            settings.displayAreaRatio,
        ).joinToString("|")
    }

    private fun resolveNowTimelineMs(): Int {
        return if (paused) {
            currentPositionMs
        } else {
            resolveRealtimeTimelineMs(System.nanoTime())
        }
    }

    private fun resolveRealtimeTimelineMs(frameTimeNs: Long): Int {
        val playbackSpeed = settings.playbackSpeed.coerceIn(0.25f, 4.0f)
        if (frameAnchorTimeNs == 0L) {
            frameAnchorTimeNs = frameTimeNs
            frameAnchorPositionMs = currentPositionMs
            lastFrameTimeNs = frameTimeNs
            return currentPositionMs
        }
        lastFrameTimeNs = frameTimeNs
        val elapsedMs = ((frameTimeNs - frameAnchorTimeNs).coerceAtLeast(0L) / 1_000_000.0 * playbackSpeed).toInt()
        return (frameAnchorPositionMs + elapsedMs).coerceAtLeast(currentPositionMs)
    }

    private fun lowerBound(comments: List<NativeDanmakuComment>, targetMs: Int): Int {
        var low = 0
        var high = comments.size
        while (low < high) {
            val mid = low + ((high - low) shr 1)
            if (comments[mid].timeMs < targetMs) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private fun upperBound(comments: List<NativeDanmakuComment>, targetMs: Int): Int {
        var low = 0
        var high = comments.size
        while (low < high) {
            val mid = low + ((high - low) shr 1)
            if (comments[mid].timeMs <= targetMs) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private fun shouldDrawDanmaku(): Boolean {
        return settings.enabled &&
            currentSourceKey.isNotBlank() &&
            !listenVideoModeEnabled &&
            width > 0 &&
            height > 0 &&
            scheduledComments.isNotEmpty()
    }

    private fun shouldAnimate(): Boolean {
        return attached && shouldDrawDanmaku() && !paused
    }

    private fun updateVisualState() {
        val nextVisible = shouldDrawDanmaku()
        visibility = if (nextVisible) VISIBLE else INVISIBLE
        val currentSize = width to height
        if (lastVisibleState != nextVisible || lastLoggedSize != currentSize) {
            lastVisibleState = nextVisible
            lastLoggedSize = currentSize
            Log.d(
                TAG,
                "updateVisualState visible=$nextVisible attached=$attached " +
                    "paused=$paused source=$currentSourceKey scheduled=${scheduledComments.size} " +
                    "size=${width}x${height}",
            )
        }
        if (shouldAnimate()) {
            postNextFrame()
        } else {
            stopFrames()
        }
    }

    private fun postNextFrame() {
        if (framePosted || !attached) return
        framePosted = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    private fun stopFrames() {
        if (!framePosted) return
        Choreographer.getInstance().removeFrameCallback(this)
        framePosted = false
    }
}
