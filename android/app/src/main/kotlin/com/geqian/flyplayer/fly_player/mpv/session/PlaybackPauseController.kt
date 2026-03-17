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
        val directSuccess = runCatching {
            mpv.setPropertyBoolean("pause", paused)
        }.getOrDefault(false)
        val verifiedAfterDirect = readPausedProperty()
        if (directSuccess && verifiedAfterDirect == paused) {
            return true
        }

        val stringSuccess = runCatching {
            mpv.setPropertyString("pause", desiredString)
        }.getOrDefault(false)
        val verifiedAfterString = readPausedProperty()
        if (stringSuccess && verifiedAfterString == paused) {
            return true
        }

        val commandSuccess = runCatching {
            mpv.command(arrayOf("set", "pause", desiredString)) >= 0
        }.getOrDefault(false)
        val verifiedAfterCommand = readPausedProperty()
        val finalSuccess = commandSuccess && verifiedAfterCommand == paused
        if (!finalSuccess) {
            Log.w(
                tag,
                "setPausedState failed desired=$paused direct=$directSuccess string=$stringSuccess command=$commandSuccess verified=$verifiedAfterCommand",
            )
        }
        return finalSuccess
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
