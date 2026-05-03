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

class TextureViewVideoOutputTarget(
    context: Context,
) : VideoOutputTarget,
    TextureView.SurfaceTextureListener {
    private companion object {
        const val SURFACE_TRANSITION_VISIBILITY_TIMEOUT_MS = 200L
    }

    private val textureView = TextureView(context)
    private var listener: VideoOutputTarget.Listener? = null
    private var currentSurface: Surface? = null
    private var currentGeneration = 0L
    private var waitingForFreshFrame = false
    private var reusableBitmap: Bitmap? = null
    private var reusableFocusedBitmap: Bitmap? = null
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

    override val supportsAsyncBitmapCapture: Boolean
        get() = false

    override fun currentSurface(): Surface? = currentSurface

    override fun isSurfaceValid(): Boolean = currentSurface?.isValid == true

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
    ): Long? = null

    override fun cancelBitmapCapture(requestId: Long) {
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
        clearReusableBitmaps()
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        releaseCurrentSurface()
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
        listener?.onSurfaceDestroyed(generation)
        releaseCurrentSurface()
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
        if (waitingForFreshFrame) {
            restoreTextureVisibility()
        }
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
