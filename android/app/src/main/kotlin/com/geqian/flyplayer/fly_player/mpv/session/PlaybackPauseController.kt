package com.geqian.flyplayer.fly_player.mpv

import android.util.Log

class PlaybackPauseController(
    private val tag: String,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    fun setPausedState(
        paused: Boolean,
        initialized: Boolean,
    ): Boolean {
        if (!initialized || !mpv.isAvailable()) return false
        val desiredString = if (paused) "yes" else "no"
        val writeSuccess = runCatching {
            mpv.setPropertyString("pause", desiredString)
        }.getOrDefault(false)
        val verified = readPausedProperty()
        if (verified == null || verified == paused) {
            if (!writeSuccess) {
                Log.w(tag, "setPausedState write reported failure but verify passed desired=$paused")
            }
            return true
        }
        if (!writeSuccess) {
            Log.w(tag, "setPausedState write failed desired=$paused")
            return false
        }
        Log.w(tag, "setPausedState verify mismatch desired=$paused verified=$verified")
        return false
    }

    private fun readPausedProperty(): Boolean? {
        val rawValue = runCatching { mpv.getPropertyString("pause") }
            .getOrNull()
            ?.trim()
            ?.lowercase()
            ?: return null
        return when (rawValue) {
            "yes", "true", "1" -> true
            "no", "false", "0" -> false
            else -> null
        }
    }
}
