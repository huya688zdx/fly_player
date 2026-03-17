package com.geqian.flyplayer.fly_player.mpv

import android.util.Log

private const val VIDEO_ADJUST_TAG = "FlyPlayerMpv"

class VideoAdjustmentController(
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var settings: Map<String, Double> = defaultSettings

    fun update(args: Map<String, Any?>): Boolean {
        val next = defaultSettings.toMutableMap()
        next.putAll(settings)
        val rawSettings = args["settings"]
        if (rawSettings is Map<*, *>) {
            for ((rawKey, rawValue) in rawSettings) {
                val key = rawKey?.toString()?.trim().orEmpty()
                if (!defaultSettings.containsKey(key)) continue
                next[key] = normalize(rawValue, defaultSettings.getValue(key))
            }
        }
        val changed = next != settings
        settings = next
        return changed
    }

    fun apply(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available || !mpv.isAvailable()) return false
        var success = true
        for ((key, value) in settings) {
            success =
                runCatching {
                    mpv.setPropertyDouble(key, value)
                }.getOrDefault(false) && success
        }
        Log.d(VIDEO_ADJUST_TAG, "apply video adjustments success=$success settings=$settings")
        return success
    }

    fun onFileLoaded(initialized: Boolean, available: Boolean) {
        apply(initialized, available)
    }

    private fun normalize(rawValue: Any?, fallback: Double): Double {
        val numericValue =
            when (rawValue) {
                is Number -> rawValue.toDouble()
                else -> rawValue?.toString()?.toDoubleOrNull()
            } ?: fallback
        return numericValue.coerceIn(-100.0, 100.0)
    }

    private companion object {
        val defaultSettings: Map<String, Double> =
            mapOf(
                "brightness" to 0.0,
                "contrast" to 0.0,
                "saturation" to 0.0,
                "gamma" to 0.0,
                "hue" to 0.0,
            )
    }
}
