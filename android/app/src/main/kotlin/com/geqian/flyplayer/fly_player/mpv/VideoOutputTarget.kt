package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.graphics.SurfaceTexture
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import java.util.concurrent.atomic.AtomicLong

enum class VideoOutputBackend(
    val wireValue: String,
) {
    TEXTURE("texture"),
    SURFACE("surface"),
    ;

    companion object {
        fun fromValue(raw: String?): VideoOutputBackend {
            return when (raw?.trim()?.lowercase()) {
                SURFACE.wireValue -> SURFACE
                else -> TEXTURE
            }
        }
    }
}

data class VideoOutputCapturedFrame(
    val bitmap: Bitmap,
    val sampleAreaRatio: Float,
    val captureBackend: String,
    val capturedAtUptimeMs: Long,
)

interface VideoOutputTarget {
    val backend: VideoOutputBackend
    val view: View
    val isSurfaceReady: Boolean
    val supportsBitmapCapture: Boolean
    val supportsAsyncBitmapCapture: Boolean

    fun currentSurface(): Surface?

    /** 当前 surface 代数（每次重建递增）；交接中止重绑需要带上它过 VideoOutputController 代数门。 */
    val currentSurfaceGeneration: Long

    fun isSurfaceValid(): Boolean

    fun captureBitmap(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
    ): VideoOutputCapturedFrame?

    fun requestBitmapCapture(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ): Long?

    fun cancelBitmapCapture(requestId: Long)

    fun setListener(listener: Listener?)

    fun release()

    interface Listener {
        fun onSurfaceAvailable(
            surface: Surface,
            generation: Long,
            width: Int,
            height: Int,
        )

        fun onSurfaceSizeChanged(
            surface: Surface,
            generation: Long,
            width: Int,
            height: Int,
        )

        fun onSurfaceDestroyed(generation: Long)
    }
}

/**
 * 必要改造 A/B 的 destroy 分支裁决（悬浮小窗方案 3.3）：交接窗口内且保活开关开启 →
 * `onSurfaceTextureDestroyed` 返回 false 自持 SurfaceTexture（改造 B，零黑帧复用）；
 * 保活开关关闭（真机复用验证不过的降级路径）→ 纹理照常随窗口销毁，只靠 mpv 侧改造 A
 * 旁路不断播，交接黑帧由定格图覆盖（P3 <200ms 预算兜底）。
 */
internal fun textureHandoffShouldKeepTexture(
    handoffActive: Boolean,
    keepTextureEnabled: Boolean,
): Boolean = handoffActive && keepTextureEnabled

class TextureViewVideoOutputTarget(
    context: Context,
    private val surfaceHandoffGate: SurfaceHandoffGate? = null,
    private val keepTextureAcrossHandoff: Boolean = true,
) : VideoOutputTarget,
    TextureView.SurfaceTextureListener {
    private companion object {
        const val SURFACE_TRANSITION_VISIBILITY_TIMEOUT_MS = 200L
    }

    private val textureView = TextureView(context)
    private var listener: VideoOutputTarget.Listener? = null
    private var currentSurface: Surface? = null
    private var currentGeneration = 0L
    // 改造 B：交接窗口内自持的 SurfaceTexture（destroy 返回 false 后框架不回收），
    // 重挂由 reattachKeptSurfaceTexture 复用；最终释放服从释放顺序红线（见 release）。
    private var keptSurfaceTexture: SurfaceTexture? = null
    private var waitingForFreshFrame = false
    private var reusableBitmap: Bitmap? = null
    private var reusableFocusedBitmap: Bitmap? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val captureThread = HandlerThread("FlyPlayerTextureCapture").apply { start() }
    private val captureHandler = Handler(captureThread.looper)
    private val nextCaptureRequestId = AtomicLong(0L)
    private val cancelledCaptureRequestIds = HashSet<Long>()
    private val cancelledCaptureRequestIdsLock = Any()
    private val restoreVisibilityRunnable =
        Runnable {
            restoreTextureVisibility()
        }

    init {
        textureView.isOpaque = true
        textureView.surfaceTextureListener = this
    }

    override val backend: VideoOutputBackend
        get() = VideoOutputBackend.TEXTURE

    override val view: View
        get() = textureView

    override val isSurfaceReady: Boolean
        get() = isSurfaceValid()

    override val supportsBitmapCapture: Boolean
        get() = true

    // 后台抓帧：API 24+ 可用 PixelCopy 从视频 Surface 离屏读回，避免主线程 getBitmap。
    override val supportsAsyncBitmapCapture: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N

    override fun currentSurface(): Surface? = currentSurface

    override val currentSurfaceGeneration: Long
        get() = currentGeneration

    override fun isSurfaceValid(): Boolean = currentSurface?.isValid == true

    /** 交接期是否仍自持 SurfaceTexture（日志/诊断用；正常在重挂或 release 时清零）。 */
    val holdsKeptSurfaceTexture: Boolean
        get() = keptSurfaceTexture != null

    override fun captureBitmap(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
    ): VideoOutputCapturedFrame? {
        if (!textureView.isAvailable) {
            return null
        }
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
            return VideoOutputCapturedFrame(
                bitmap = captured,
                sampleAreaRatio = 1.0f,
                captureBackend = "texture_sync",
                capturedAtUptimeMs = SystemClock.uptimeMillis(),
            )
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
        val sourceHeight =
            (captured.height.toFloat() * clampedRatio).toInt().coerceIn(1, captured.height)
        val canvas = Canvas(focused)
        canvas.drawColor(android.graphics.Color.BLACK)
        canvas.drawBitmap(
            captured,
            Rect(0, 0, captured.width, sourceHeight),
            Rect(0, 0, focused.width, focused.height),
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG),
        )
        return VideoOutputCapturedFrame(
            bitmap = focused,
            sampleAreaRatio = clampedRatio,
            captureBackend = "texture_sync",
            capturedAtUptimeMs = SystemClock.uptimeMillis(),
        )
    }

    override fun requestBitmapCapture(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || !textureView.isAvailable) {
            return null
        }
        val surface = currentSurface?.takeIf { it.isValid } ?: return null
        val requestId = nextCaptureRequestId.incrementAndGet()
        val outputWidth = width.coerceAtLeast(1)
        val outputHeight = height.coerceAtLeast(1)
        val clampedRatio = sampleAreaRatio.coerceIn(0.1f, 1.0f)
        val srcWidth = textureView.width.coerceAtLeast(1)
        val srcHeight = textureView.height.coerceAtLeast(1)
        val fullBitmap = Bitmap.createBitmap(srcWidth, srcHeight, Bitmap.Config.ARGB_8888)
        val copyListener =
            PixelCopy.OnPixelCopyFinishedListener { result ->
                if (result == PixelCopy.SUCCESS) {
                    val frame =
                        runCatching {
                            buildCroppedFrame(
                                source = fullBitmap,
                                outputWidth = outputWidth,
                                outputHeight = outputHeight,
                                sampleAreaRatio = clampedRatio,
                                captureBackend = "texture_pixelcopy",
                            )
                        }.getOrNull()
                    fullBitmap.recycle()
                    deliverCaptureResult(requestId, frame, callback)
                } else {
                    fullBitmap.recycle()
                    fallbackMainThreadCapture(
                        requestId = requestId,
                        outputWidth = outputWidth,
                        outputHeight = outputHeight,
                        sampleAreaRatio = clampedRatio,
                        callback = callback,
                    )
                }
            }
        val dispatched =
            runCatching {
                PixelCopy.request(surface, fullBitmap, copyListener, captureHandler)
            }.isSuccess
        if (!dispatched) {
            fullBitmap.recycle()
            fallbackMainThreadCapture(
                requestId = requestId,
                outputWidth = outputWidth,
                outputHeight = outputHeight,
                sampleAreaRatio = clampedRatio,
                callback = callback,
            )
        }
        return requestId
    }

    override fun cancelBitmapCapture(requestId: Long) {
        synchronized(cancelledCaptureRequestIdsLock) {
            cancelledCaptureRequestIds += requestId
        }
    }

    private fun buildCroppedFrame(
        source: Bitmap,
        outputWidth: Int,
        outputHeight: Int,
        sampleAreaRatio: Float,
        captureBackend: String,
    ): VideoOutputCapturedFrame {
        val output = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
        val sourceHeight =
            (source.height.toFloat() * sampleAreaRatio).toInt().coerceIn(1, source.height)
        val canvas = Canvas(output)
        canvas.drawColor(Color.BLACK)
        canvas.drawBitmap(
            source,
            Rect(0, 0, source.width, sourceHeight),
            Rect(0, 0, output.width, output.height),
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG),
        )
        return VideoOutputCapturedFrame(
            bitmap = output,
            sampleAreaRatio = sampleAreaRatio,
            captureBackend = captureBackend,
            capturedAtUptimeMs = SystemClock.uptimeMillis(),
        )
    }

    private fun fallbackMainThreadCapture(
        requestId: Long,
        outputWidth: Int,
        outputHeight: Int,
        sampleAreaRatio: Float,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ) {
        mainHandler.post {
            if (isCaptureCancelled(requestId)) {
                return@post
            }
            val frame =
                runCatching {
                    if (!textureView.isAvailable) {
                        return@runCatching null
                    }
                    val source =
                        Bitmap.createBitmap(
                            textureView.width.coerceAtLeast(1),
                            textureView.height.coerceAtLeast(1),
                            Bitmap.Config.ARGB_8888,
                        )
                    val captured = textureView.getBitmap(source)
                    if (captured == null) {
                        source.recycle()
                        null
                    } else {
                        val output =
                            buildCroppedFrame(
                                source = captured,
                                outputWidth = outputWidth,
                                outputHeight = outputHeight,
                                sampleAreaRatio = sampleAreaRatio,
                                captureBackend = "texture_getbitmap",
                            )
                        captured.recycle()
                        output
                    }
                }.getOrNull()
            callback(frame)
        }
    }

    private fun deliverCaptureResult(
        requestId: Long,
        frame: VideoOutputCapturedFrame?,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ) {
        mainHandler.post {
            if (isCaptureCancelled(requestId)) {
                frame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
                return@post
            }
            callback(frame)
        }
    }

    private fun isCaptureCancelled(requestId: Long): Boolean {
        synchronized(cancelledCaptureRequestIdsLock) {
            return cancelledCaptureRequestIds.remove(requestId)
        }
    }

    override fun setListener(listener: VideoOutputTarget.Listener?) {
        this.listener = listener
    }

    override fun release() {
        listener = null
        textureView.surfaceTextureListener = null
        textureView.removeCallbacks(restoreVisibilityRunnable)
        restoreTextureVisibility()
        releaseCurrentSurface()
        // 释放顺序红线（悬浮小窗方案 3.3，与 MpvPlayerView.dispose 同款）：本方法只在
        // NativePlayerSurface.release 的 controller.disposeBlocking 之后执行，交接期
        // 自持的 SurfaceTexture 此刻才允许随宿主释放。
        releaseKeptSurfaceTexture()
        clearReusableBitmaps()
        synchronized(cancelledCaptureRequestIdsLock) {
            cancelledCaptureRequestIds.clear()
        }
        captureHandler.removeCallbacksAndMessages(null)
        captureThread.quitSafely()
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        releaseCurrentSurface()
        adoptHandoffTexture(surface)
        currentGeneration += 1L
        val nextSurface = Surface(surface)
        currentSurface = nextSurface
        suppressStaleFrameUntilNextUpdate()
        listener?.onSurfaceAvailable(nextSurface, currentGeneration, width, height)
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        val current = currentSurface ?: return
        suppressStaleFrameUntilNextUpdate()
        listener?.onSurfaceSizeChanged(current, currentGeneration, width, height)
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        val generation = currentGeneration
        textureView.removeCallbacks(restoreVisibilityRunnable)
        restoreTextureVisibility()
        // 改造 A 的 View 半边：交接窗口内 destroy 链照样上报——mpv 侧由
        // MpvPlaybackController 走 detach-only 旁路（不 pause、不 vid=no）。
        listener?.onSurfaceDestroyed(generation)
        return if (
            textureHandoffShouldKeepTexture(
                handoffActive = surfaceHandoffGate?.active == true,
                keepTextureEnabled = keepTextureAcrossHandoff,
            )
        ) {
            // 必要改造 B：返回 false 且不释放 surface，SurfaceTexture 交宿主自持，
            // remove→add 迁移期间帧缓冲不销毁；重挂由 reattachKeptSurfaceTexture 复用。
            keptSurfaceTexture = surface
            false
        } else {
            releaseCurrentSurface()
            true
        }
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
        if (waitingForFreshFrame) {
            restoreTextureVisibility()
        }
    }

    /**
     * 交接重挂（改造 B 的复用入口，主线程调用）：把自持的 SurfaceTexture 装回
     * TextureView。返回 false 表示无可复用纹理或装回失败（失败时就地释放防泄漏），
     * 后续走框架新纹理 + 定格图兜底（改造 A 路径）。
     */
    fun reattachKeptSurfaceTexture(): Boolean {
        val kept = keptSurfaceTexture ?: return false
        keptSurfaceTexture = null
        if (textureView.surfaceTexture === kept) {
            // 同一 TextureView remove→add 后框架仍持有该纹理：无需重设。
            return true
        }
        return runCatching {
            textureView.setSurfaceTexture(kept)
            true
        }.onFailure {
            runCatching { kept.release() }
        }.getOrDefault(false)
    }

    /** 纹理回到框架/复用持有：清自持引用；框架重建了新纹理则就地释放自持旧纹理防泄漏。 */
    private fun adoptHandoffTexture(surface: SurfaceTexture) {
        val kept = keptSurfaceTexture ?: return
        keptSurfaceTexture = null
        if (kept !== surface) {
            runCatching { kept.release() }
        }
    }

    private fun releaseKeptSurfaceTexture() {
        val kept = keptSurfaceTexture ?: return
        keptSurfaceTexture = null
        runCatching { kept.release() }
    }

    private fun releaseCurrentSurface() {
        currentSurface?.release()
        currentSurface = null
    }

    private fun clearReusableBitmaps() {
        reusableBitmap?.recycle()
        reusableBitmap = null
        reusableFocusedBitmap?.recycle()
        reusableFocusedBitmap = null
    }

    private fun suppressStaleFrameUntilNextUpdate() {
        waitingForFreshFrame = true
        textureView.removeCallbacks(restoreVisibilityRunnable)
        textureView.alpha = 0f
        textureView.postDelayed(
            restoreVisibilityRunnable,
            SURFACE_TRANSITION_VISIBILITY_TIMEOUT_MS,
        )
    }

    private fun restoreTextureVisibility() {
        waitingForFreshFrame = false
        textureView.removeCallbacks(restoreVisibilityRunnable)
        if (textureView.alpha != 1f) {
            textureView.alpha = 1f
        }
    }
}

class SurfaceViewVideoOutputTarget(
    context: Context,
) : VideoOutputTarget,
    SurfaceHolder.Callback {
    private val surfaceView = SurfaceView(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val captureThread = HandlerThread("FlyPlayerSurfaceCapture").apply { start() }
    private val captureHandler = Handler(captureThread.looper)
    private val nextCaptureRequestId = AtomicLong(0L)
    private val cancelledCaptureRequestIds = HashSet<Long>()
    private val cancelledCaptureRequestIdsLock = Any()
    private var listener: VideoOutputTarget.Listener? = null
    private var currentGeneration = 0L

    init {
        surfaceView.holder.addCallback(this)
    }

    override val backend: VideoOutputBackend
        get() = VideoOutputBackend.SURFACE

    override val view: View
        get() = surfaceView

    override val isSurfaceReady: Boolean
        get() = isSurfaceValid()

    override val supportsBitmapCapture: Boolean
        get() = false

    override val supportsAsyncBitmapCapture: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N

    override fun currentSurface(): Surface? {
        val surface = surfaceView.holder.surface
        return surface?.takeIf { it.isValid }
    }

    override val currentSurfaceGeneration: Long
        get() = currentGeneration

    override fun isSurfaceValid(): Boolean = surfaceView.holder.surface?.isValid == true

    override fun captureBitmap(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
    ): VideoOutputCapturedFrame? = null

    override fun requestBitmapCapture(
        width: Int,
        height: Int,
        sampleAreaRatio: Float,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ): Long? {
        if (!supportsAsyncBitmapCapture || !isSurfaceValid()) {
            return null
        }
        val requestId = nextCaptureRequestId.incrementAndGet()
        val surfaceFrame = surfaceView.holder.surfaceFrame ?: Rect(0, 0, surfaceView.width, surfaceView.height)
        val frameWidth = surfaceFrame.width().coerceAtLeast(1)
        val frameHeight = surfaceFrame.height().coerceAtLeast(1)
        val outputWidth = width.coerceAtLeast(1)
        val outputHeight = height.coerceAtLeast(1)
        val clampedRatio = sampleAreaRatio.coerceIn(0.1f, 1.0f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && clampedRatio < 0.999f) {
            val sourceHeight = (frameHeight.toFloat() * clampedRatio).toInt().coerceIn(1, frameHeight)
            val sourceRect =
                Rect(
                    surfaceFrame.left,
                    surfaceFrame.top,
                    surfaceFrame.right,
                    surfaceFrame.top + sourceHeight,
                )
            val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            requestPixelCopy(
                requestId = requestId,
                destination = outputBitmap,
                callback = callback,
                sampleAreaRatio = clampedRatio,
                captureBackend = "surface_pixelcopy_crop",
                sourceRect = sourceRect,
                postProcess = null,
            )
            return requestId
        }
        if (clampedRatio >= 0.999f) {
            val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            requestPixelCopy(
                requestId = requestId,
                destination = outputBitmap,
                callback = callback,
                sampleAreaRatio = 1.0f,
                captureBackend = "surface_pixelcopy",
                sourceRect = null,
                postProcess = null,
            )
            return requestId
        }
        val fullBitmap = Bitmap.createBitmap(frameWidth, frameHeight, Bitmap.Config.ARGB_8888)
        requestPixelCopy(
            requestId = requestId,
            destination = fullBitmap,
            callback = callback,
            sampleAreaRatio = clampedRatio,
            captureBackend = "surface_pixelcopy_legacy_crop",
            sourceRect = null,
            postProcess = { captured ->
                val sourceHeight = (captured.height.toFloat() * clampedRatio).toInt().coerceIn(1, captured.height)
                val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(outputBitmap)
                canvas.drawColor(Color.BLACK)
                canvas.drawBitmap(
                    captured,
                    Rect(0, 0, captured.width, sourceHeight),
                    Rect(0, 0, outputBitmap.width, outputBitmap.height),
                    android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG),
                )
                outputBitmap
            },
        )
        return requestId
    }

    override fun cancelBitmapCapture(requestId: Long) {
        synchronized(cancelledCaptureRequestIdsLock) {
            cancelledCaptureRequestIds += requestId
        }
    }

    override fun setListener(listener: VideoOutputTarget.Listener?) {
        this.listener = listener
    }

    override fun release() {
        listener = null
        surfaceView.holder.removeCallback(this)
        synchronized(cancelledCaptureRequestIdsLock) {
            cancelledCaptureRequestIds.clear()
        }
        captureHandler.removeCallbacksAndMessages(null)
        captureThread.quitSafely()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        val surface = holder.surface ?: return
        if (!surface.isValid) {
            return
        }
        currentGeneration += 1L
        val frame = holder.surfaceFrame
        listener?.onSurfaceAvailable(
            surface,
            currentGeneration,
            frame?.width() ?: surfaceView.width,
            frame?.height() ?: surfaceView.height,
        )
    }

    override fun surfaceChanged(
        holder: SurfaceHolder,
        format: Int,
        width: Int,
        height: Int,
    ) {
        val surface = holder.surface ?: return
        if (!surface.isValid) {
            return
        }
        listener?.onSurfaceSizeChanged(surface, currentGeneration, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        listener?.onSurfaceDestroyed(currentGeneration)
    }

    private fun requestPixelCopy(
        requestId: Long,
        destination: Bitmap,
        callback: (VideoOutputCapturedFrame?) -> Unit,
        sampleAreaRatio: Float,
        captureBackend: String,
        sourceRect: Rect?,
        postProcess: ((Bitmap) -> Bitmap)?,
    ) {
        val listener =
            PixelCopy.OnPixelCopyFinishedListener { result ->
                captureHandler.post {
                    if (isCaptureCancelled(requestId)) {
                        destination.recycle()
                        return@post
                    }
                    if (result != PixelCopy.SUCCESS) {
                        destination.recycle()
                        postCaptureResult(requestId, null, callback)
                        return@post
                    }
                    val outputBitmap =
                        runCatching {
                            postProcess?.invoke(destination) ?: destination
                        }.getOrElse {
                            destination.recycle()
                            null
                        }
                    if (outputBitmap !== destination) {
                        destination.recycle()
                    }
                    val frame =
                        outputBitmap?.let {
                            VideoOutputCapturedFrame(
                                bitmap = it,
                                sampleAreaRatio = sampleAreaRatio,
                                captureBackend = captureBackend,
                                capturedAtUptimeMs = SystemClock.uptimeMillis(),
                            )
                        }
                    postCaptureResult(requestId, frame, callback)
                }
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && sourceRect != null) {
            PixelCopy.request(surfaceView, sourceRect, destination, listener, captureHandler)
        } else {
            PixelCopy.request(surfaceView, destination, listener, captureHandler)
        }
    }

    private fun postCaptureResult(
        requestId: Long,
        frame: VideoOutputCapturedFrame?,
        callback: (VideoOutputCapturedFrame?) -> Unit,
    ) {
        mainHandler.post {
            if (isCaptureCancelled(requestId)) {
                frame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
                return@post
            }
            callback(frame)
        }
    }

    private fun isCaptureCancelled(requestId: Long): Boolean {
        synchronized(cancelledCaptureRequestIdsLock) {
            return cancelledCaptureRequestIds.remove(requestId)
        }
    }
}
