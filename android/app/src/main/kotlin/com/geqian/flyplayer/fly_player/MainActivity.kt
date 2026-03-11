package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.provider.Settings
import com.geqian.flyplayer.fly_player.mpv.MpvPlayerViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fly_player/system",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setPlayerOrientation" -> {
                    val mode = call.argument<String>("mode").orEmpty()
                    requestedOrientation = when (mode) {
                        "landscape" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "system" -> ActivityInfo.SCREEN_ORIENTATION_FULL_USER
                        else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                    result.success(null)
                }
                "getPlaybackSystemState" -> {
                    result.success(
                        mapOf(
                            "brightness" to currentBrightness(),
                            "volume" to currentVolumeRatio(),
                        ),
                    )
                }
                "setPlaybackBrightness" -> {
                    val value = call.argument<Double>("value")
                    result.success(setPlaybackBrightness(value))
                }
                "setPlaybackVolume" -> {
                    val value = call.argument<Double>("value")
                    result.success(setPlaybackVolume(value))
                }
                else -> result.notImplemented()
            }
        }
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fly_player/mpv_view",
                MpvPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }

    private fun currentBrightness(): Double {
        val current = window.attributes.screenBrightness
        if (current >= 0f) {
            return current.coerceIn(0.0f, 1.0f).toDouble()
        }
        val systemBrightness = runCatching {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        }.getOrDefault(128)
        return (systemBrightness / 255.0).coerceIn(0.0, 1.0)
    }

    private fun setPlaybackBrightness(value: Double?): Double {
        val normalized = (value ?: currentBrightness()).coerceIn(0.02, 1.0)
        val attributes = window.attributes
        attributes.screenBrightness = normalized.toFloat()
        window.attributes = attributes
        return normalized
    }

    private fun currentVolumeRatio(): Double {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        return (current.toDouble() / max.toDouble()).coerceIn(0.0, 1.0)
    }

    private fun setPlaybackVolume(value: Double?): Double {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        val normalized = (value ?: currentVolumeRatio()).coerceIn(0.0, 1.0)
        val targetVolume = (normalized * max.toDouble()).roundToInt().coerceIn(0, max)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        return currentVolumeRatio()
    }
}
