package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Color
import android.view.Surface
import android.view.View
import android.widget.FrameLayout
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
    private val mpv: MpvFacade = DefaultMpvFacade
    private val rootView = FrameLayout(context)
    private val videoOutputTarget: VideoOutputTarget = TextureViewVideoOutputTarget(context)
    private val nativeDanmakuOverlayView = NativeDanmakuOverlayView(context)
    private val methodChannel = MethodChannel(messenger, "fly_player/mpv_view_$viewId/methods")
    private val eventChannel = EventChannel(messenger, "fly_player/mpv_view_$viewId/events")
    private val danmakuAiEventChannel =
        EventChannel(messenger, "fly_player/mpv_view_$viewId/danmaku_ai_events")
    private var eventSink: EventChannel.EventSink? = null
    private var danmakuAiEventSink: EventChannel.EventSink? = null
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
    private val controller = MpvPlaybackController(
        context = context,
        videoOutputTarget = videoOutputTarget,
        creationParams = creationParams,
        stateListener = MpvPlaybackStateListener { state, overlayText ->
            latestState = state
            nativeDanmakuOverlayView.updatePlaybackState(state)
            eventSink?.success(state.toMap())
        },
        danmakuOcclusionStateListener = { state ->
            danmakuAiEventSink?.success(state.toMap())
        },
    )

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
        rootView.addView(
            nativeDanmakuOverlayView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        danmakuAiEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    if (disposed) return
                    danmakuAiEventSink = events
                    danmakuAiEventSink?.success(controller.getDanmakuOcclusionStateMap())
                }

                override fun onCancel(arguments: Any?) {
                    danmakuAiEventSink = null
                }
            },
        )
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (disposed) return
        disposed = true
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        danmakuAiEventChannel.setStreamHandler(null)
        eventSink = null
        danmakuAiEventSink = null
        videoOutputTarget.setListener(null)
        controller.dispose()
        videoOutputTarget.release()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (disposed) return
        eventSink = events
        eventSink?.success(latestState.toMap())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.success(null)
            return
        }
        when (call.method) {
            "getState" -> result.success(latestState.toMap())
            "getTrackSnapshot" -> result.success(controller.getTrackSnapshotMap())
            "getPlaybackDiagnostics" -> result.success(controller.getPlaybackDiagnosticsMap())
            "getPerformanceOverlayStats" -> result.success(controller.getPerformanceOverlayStatsMap())
            "getChapters" -> result.success(controller.getChapters())
            "getDanmakuOcclusionState" -> result.success(controller.getDanmakuOcclusionStateMap())
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
                controller.seek(args["positionMs"].toLongValue())
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
                controller.setDanmakuOcclusionConfig(methodArgumentsMap(call))
                result.success(null)
            }
            "setNativeDanmakuPayload" -> {
                nativeDanmakuOverlayView.setPayload(methodArgumentsMap(call))
                result.success(null)
            }
            "clearNativeDanmaku" -> {
                nativeDanmakuOverlayView.clear()
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

    @Suppress("UNCHECKED_CAST")
    private fun methodArgumentsMap(call: MethodCall): Map<String, Any?> {
        return call.arguments as? Map<String, Any?> ?: emptyMap()
    }
}
