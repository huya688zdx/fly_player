package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.View
import android.widget.FrameLayout
import com.geqian.flyplayer.fly_player.ViewFrameRateProbe
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class MpvPlayerView(
    context: android.content.Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String, Any?>,
) : PlatformView,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    VideoOutputTarget.Listener {
    private companion object {
        const val TAG = "FlyPlayerMpvView"
        const val DEFAULT_NATIVE_DANMAKU_TARGET_FPS = 60
        const val MIN_NATIVE_DANMAKU_TARGET_FPS = 24
        const val MAX_NATIVE_DANMAKU_TARGET_FPS = 120
    }

    private val mpv: MpvFacade = DefaultMpvFacade
    private val rootView = FrameLayout(context)
    private val nativeDanmakuEnabled = creationParams["enableNativeDanmakuRenderer"] == true
    private val resolvedVideoOutputBackend =
        VideoOutputBackend.fromValue(creationParams["videoOutputBackend"]?.toString())
    private val videoOutputTarget: VideoOutputTarget =
        when (resolvedVideoOutputBackend) {
            VideoOutputBackend.SURFACE -> SurfaceViewVideoOutputTarget(context)
            VideoOutputBackend.TEXTURE -> TextureViewVideoOutputTarget(context)
        }
    private val nativeDanmakuOverlayView =
        if (nativeDanmakuEnabled) {
            NativeDanmakuOverlayView(context)
        } else {
            null
        }
    private val rootViewFrameRateProbe =
        if (nativeDanmakuEnabled) {
            ViewFrameRateProbe(
                logTag = TAG,
                label = "player_root_view",
                viewProvider = { rootView },
            )
        } else {
            null
        }
    private val videoTargetFrameRateProbe =
        if (nativeDanmakuEnabled) {
            ViewFrameRateProbe(
                logTag = TAG,
                label = "player_video_target",
                viewProvider = { videoOutputTarget.view },
            )
        } else {
            null
        }
    private val methodChannel = MethodChannel(messenger, "fly_player/mpv_view_$viewId/methods")
    private val eventChannel = EventChannel(messenger, "fly_player/mpv_view_$viewId/events")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var unregisterEventHandlerRunnable: Runnable? = null
    @Volatile
    private var disposed = false
    private var latestState = MpvPlayerState(
        nativeLibLoaded = mpv.isAvailable(),
        statusText = if (mpv.isAvailable()) {
            "mpv-android runtime detected"
        } else {
            "mpv-android native runtime missing"
        },
        error = mpv.loadErrorMessage(),
    )
    private var latestDanmakuOcclusionState = DanmakuDynamicOcclusionState.disabled()
    private val controller = MpvPlaybackController(
        context = context,
        videoOutputTarget = videoOutputTarget,
        creationParams = creationParams,
        stateListener = MpvPlaybackStateListener { state, overlayText ->
            latestState = state
            nativeDanmakuOverlayView?.updatePlaybackState(state)
            emitPlayerStateEvent(state)
        },
        danmakuOcclusionStateListener = { next, runtimeMaskBitmap ->
            latestDanmakuOcclusionState = next
            nativeDanmakuOverlayView?.setOcclusionState(next, runtimeMaskBitmap)
            emitDanmakuOcclusionStateEvent(next)
        },
    )
    private var requestedNativeDanmakuFrameRateHz = DEFAULT_NATIVE_DANMAKU_TARGET_FPS
    private var lastIssuedSeekEpoch = 0L
    private var lastIssuedSeekPositionMs = 0L

    init {
        rootView.setBackgroundColor(Color.BLACK)
        videoOutputTarget.setListener(this)
        rootView.addView(
            videoOutputTarget.view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        nativeDanmakuOverlayView?.let { overlayView ->
            rootView.addView(
                overlayView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        methodChannel.setMethodCallHandler(this)
        unregisterEventHandlerRunnable?.let(mainHandler::removeCallbacks)
        unregisterEventHandlerRunnable = null
        eventChannel.setStreamHandler(this)
        rootViewFrameRateProbe?.start()
        videoTargetFrameRateProbe?.start()
        applyNativeDanmakuFrameRateVote(
            targetFrameRateHz = requestedNativeDanmakuFrameRateHz,
            reason = "init",
        )
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (disposed) return
        disposed = true
        methodChannel.setMethodCallHandler(null)
        runCatching { eventSink?.endOfStream() }
        eventSink = null
        scheduleEventHandlerUnregister()
        rootViewFrameRateProbe?.stop(reason = "dispose")
        videoTargetFrameRateProbe?.stop(reason = "dispose")
        videoOutputTarget.setListener(null)
        // The Android surface must outlive mpv's detach/stop sequence. Releasing
        // TextureView first can leave MediaCodec/Flutter tearing down a surface
        // that mpv still owns, which is reproducible as a crash on the next play.
        controller.disposeBlocking()
        nativeDanmakuOverlayView?.release()
        videoOutputTarget.release()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (disposed) return
        eventSink = events
        emitPlayerStateEvent(latestState)
        emitDanmakuOcclusionStateEvent(latestDanmakuOcclusionState)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun scheduleEventHandlerUnregister() {
        unregisterEventHandlerRunnable?.let(mainHandler::removeCallbacks)
        val cleanup =
            Runnable {
                eventChannel.setStreamHandler(null)
                unregisterEventHandlerRunnable = null
            }
        unregisterEventHandlerRunnable = cleanup
        mainHandler.postDelayed(cleanup, 5_000L)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.success(null)
            return
        }
        when (call.method) {
            "getState" -> result.success(latestState.toMap())
            "getDanmakuOcclusionState" -> result.success(controller.getDanmakuOcclusionStateMap())
            "getTrackSnapshot" -> result.success(controller.getTrackSnapshotMap())
            "getPlaybackDiagnostics" -> result.success(controller.getPlaybackDiagnosticsMap())
            "getPerformanceOverlayStats" -> result.success(controller.getPerformanceOverlayStatsMap())
            "getChapters" -> result.success(controller.getChapters())
            "captureFrame" -> result.success(controller.captureFrame(methodArgumentsMap(call)))
            "load" -> {
                controller.load(methodArgumentsMap(call))
                result.success(null)
            }
            "play" -> {
                controller.play()
                result.success(null)
            }
            "pause" -> {
                controller.pause()
                result.success(null)
            }
            "seek" -> {
                val args = methodArgumentsMap(call)
                val positionMs = args["positionMs"].toLongValue()
                val seekEpoch = controller.seekWithEpoch(positionMs)
                if (seekEpoch > 0L) {
                    lastIssuedSeekEpoch = seekEpoch
                    lastIssuedSeekPositionMs = positionMs
                    nativeDanmakuOverlayView?.hintSeek(positionMs, seekEpoch)
                }
                result.success(null)
            }
            "hintNativeDanmakuSeek" -> {
                val args = methodArgumentsMap(call)
                val positionMs = args["positionMs"].toLongValue()
                val seekEpoch =
                    if (positionMs == lastIssuedSeekPositionMs) {
                        lastIssuedSeekEpoch
                    } else {
                        latestState.activeSeekEpoch
                    }
                nativeDanmakuOverlayView?.hintSeek(positionMs, seekEpoch)
                result.success(null)
            }
            "setAudioTrack" -> {
                val args = methodArgumentsMap(call)
                controller.setAudioTrack(
                    trackIndex = args["trackIndex"].toIntValue(),
                    trackGuid = args["trackGuid"]?.toString(),
                )
                result.success(null)
            }
            "setSubtitleTrack" -> {
                val args = methodArgumentsMap(call)
                controller.setSubtitleTrack(
                    trackIndex = args["trackIndex"].toIntValue(),
                    trackGuid = args["trackGuid"]?.toString(),
                )
                result.success(null)
            }
            "setExternalSubtitleFile" -> {
                val args = methodArgumentsMap(call)
                controller.setExternalSubtitleFile(args["path"]?.toString().orEmpty())
                result.success(null)
            }
            "setSubtitleDelay" -> {
                val args = methodArgumentsMap(call)
                controller.setSubtitleDelay(args["delay"].toDoubleValue())
                result.success(null)
            }
            "setAudioDelay" -> {
                val args = methodArgumentsMap(call)
                controller.setAudioDelay(args["delay"].toDoubleValue())
                result.success(null)
            }
            "setSubtitlePosition" -> {
                val args = methodArgumentsMap(call)
                controller.setSubtitlePosition(args["position"].toIntValue())
                result.success(null)
            }
            "setSubtitleScale" -> {
                val args = methodArgumentsMap(call)
                controller.setSubtitleScale(args["scale"].toDoubleValue())
                result.success(null)
            }
            "resetSubtitleStyle" -> {
                controller.resetSubtitleStyle()
                result.success(null)
            }
            "setDecoderMode" -> {
                val args = methodArgumentsMap(call)
                controller.setDecoderMode(args["mode"]?.toString())
                result.success(null)
            }
            "setDisplayAspectRatioMode" -> {
                val args = methodArgumentsMap(call)
                controller.setDisplayAspectRatioMode(args["mode"]?.toString())
                result.success(null)
            }
            "setSpeed" -> {
                val args = methodArgumentsMap(call)
                controller.setSpeed(args["speed"].toDoubleValue())
                result.success(null)
            }
            "setVideoAdjustments" -> {
                controller.setVideoAdjustments(methodArgumentsMap(call))
                result.success(null)
            }
            "setMpvAdvancedSettings" -> {
                controller.setMpvAdvancedSettings(methodArgumentsMap(call))
                result.success(null)
            }
            "setListenVideoMode" -> {
                val args = methodArgumentsMap(call)
                result.success(controller.setListenVideoMode(args["enabled"] == true))
            }
            "setDanmakuOcclusionConfig" -> {
                result.success(controller.setDanmakuOcclusionConfig(methodArgumentsMap(call)))
            }
            "setDanmakuOcclusionSamplingPaused" -> {
                val args = methodArgumentsMap(call)
                result.success(
                    controller.setDanmakuOcclusionSamplingPaused(args["paused"] == true),
                )
            }
            "setDanmakuHasOnScreenComments" -> {
                val args = methodArgumentsMap(call)
                result.success(
                    controller.setDanmakuHasOnScreenComments(args["hasComments"] == true),
                )
            }
            "setDanmakuPayload",
            "setNativeDanmakuPayload" -> {
                val args = methodArgumentsMap(call)
                applyNativeDanmakuFrameRateVote(
                    targetFrameRateHz = parseNativeDanmakuTargetFrameRateHz(args),
                    reason = "payload",
                )
                nativeDanmakuOverlayView?.setPayload(args)
                result.success(null)
            }
            "setNativeDanmakuOcclusion" -> {
                nativeDanmakuOverlayView?.setOcclusionState(methodArgumentsMap(call))
                result.success(null)
            }
            "clearDanmaku",
            "clearNativeDanmaku" -> {
                applyNativeDanmakuFrameRateVote(
                    targetFrameRateHz = DEFAULT_NATIVE_DANMAKU_TARGET_FPS,
                    reason = "clear",
                )
                nativeDanmakuOverlayView?.clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onSurfaceAvailable(
        surface: Surface,
        generation: Long,
        width: Int,
        height: Int,
    ) {
        if (disposed) return
        applyNativeDanmakuFrameRateVote(
            targetFrameRateHz = requestedNativeDanmakuFrameRateHz,
            reason = "surfaceAvailable",
        )
        controller.onVideoOutputSurfaceAvailable(
            surface = surface,
            generation = generation,
            width = width,
            height = height,
        )
    }

    override fun onSurfaceSizeChanged(
        surface: Surface,
        generation: Long,
        width: Int,
        height: Int,
    ) {
        if (disposed) return
        applyNativeDanmakuFrameRateVote(
            targetFrameRateHz = requestedNativeDanmakuFrameRateHz,
            reason = "surfaceSizeChanged",
        )
        controller.onVideoOutputSurfaceSizeChanged(
            surface = surface,
            generation = generation,
            width = width,
            height = height,
        )
    }

    override fun onSurfaceDestroyed(generation: Long) {
        if (disposed) return
        controller.onVideoOutputSurfaceDestroyed(generation)
    }

    private fun emitPlayerStateEvent(state: MpvPlayerState) {
        eventSink?.success(
            mapOf(
                "eventType" to "playerState",
                "state" to state.toMap(),
            ),
        )
    }

    private fun emitDanmakuOcclusionStateEvent(state: DanmakuDynamicOcclusionState) {
        eventSink?.success(
            mapOf(
                "eventType" to "danmakuOcclusionState",
                "state" to state.toMap(),
            ),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun methodArgumentsMap(call: MethodCall): Map<String, Any?> {
        return call.arguments as? Map<String, Any?> ?: emptyMap()
    }

    private fun parseNativeDanmakuTargetFrameRateHz(payload: Map<String, Any?>): Int {
        return (payload["targetFrameRateHz"].toIntValue() ?: DEFAULT_NATIVE_DANMAKU_TARGET_FPS)
            .coerceIn(MIN_NATIVE_DANMAKU_TARGET_FPS, MAX_NATIVE_DANMAKU_TARGET_FPS)
    }

    private fun applyNativeDanmakuFrameRateVote(targetFrameRateHz: Int, reason: String) {
        if (!nativeDanmakuEnabled) {
            return
        }
        val clampedTarget =
            targetFrameRateHz.coerceIn(
                MIN_NATIVE_DANMAKU_TARGET_FPS,
                MAX_NATIVE_DANMAKU_TARGET_FPS,
            )
        requestedNativeDanmakuFrameRateHz = clampedTarget
        if (Build.VERSION.SDK_INT >= 35) {
            val requestedRate = clampedTarget.toFloat()
            rootView.setRequestedFrameRate(requestedRate)
            videoOutputTarget.view.setRequestedFrameRate(requestedRate)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            videoOutputTarget.currentSurface()
                ?.takeIf { it.isValid }
                ?.setFrameRate(
                    clampedTarget.toFloat(),
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                )
        }
        val displayHz = rootView.display?.refreshRate ?: 0f
        Log.d(
            TAG,
            "[DANMAKU][NATIVE] host_frame_rate_vote " +
                "reason=$reason target=${clampedTarget}fps " +
                "displayHz=${"%.1f".format(displayHz)} " +
                "surfaceReady=${videoOutputTarget.isSurfaceReady} api=${Build.VERSION.SDK_INT}",
        )
    }
}
