package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Color
import android.view.SurfaceHolder
import android.view.SurfaceView
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
    SurfaceHolder.Callback {
    private val mpv: MpvFacade = DefaultMpvFacade
    private val rootView = FrameLayout(context)
    private val surfaceView = SurfaceView(context)
    private val methodChannel = MethodChannel(messenger, "fly_player/mpv_view_$viewId/methods")
    private val eventChannel = EventChannel(messenger, "fly_player/mpv_view_$viewId/events")
    private var eventSink: EventChannel.EventSink? = null
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
        surfaceView = surfaceView,
        creationParams = creationParams,
        stateListener = MpvPlaybackStateListener { state, overlayText ->
            latestState = state
            eventSink?.success(state.toMap())
        },
    )

    init {
        rootView.setBackgroundColor(Color.BLACK)
        surfaceView.holder.addCallback(this)
        rootView.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (disposed) return
        disposed = true
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        surfaceView.holder.removeCallback(this)
        eventSink = null
        controller.dispose()
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
                controller.seek(args["positionMs"].toLongValue())
                result.success(null)
            }
            "setAudioTrack" -> {
                val args = methodArgumentsMap(call)
                controller.setAudioTrack(args["trackIndex"].toIntValue())
                result.success(null)
            }
            "setSubtitleTrack" -> {
                val args = methodArgumentsMap(call)
                controller.setSubtitleTrack(args["trackIndex"].toIntValue())
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
            else -> result.notImplemented()
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (disposed) return
        controller.surfaceCreated(holder)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (disposed) return
        controller.surfaceChanged(holder, format, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        if (disposed) return
        controller.surfaceDestroyed(holder)
    }

    @Suppress("UNCHECKED_CAST")
    private fun methodArgumentsMap(call: MethodCall): Map<String, Any?> {
        return call.arguments as? Map<String, Any?> ?: emptyMap()
    }
}
