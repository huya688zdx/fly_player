package com.geqian.flyplayer.fly_player.mpv

import android.util.Log

class TrackSelectionController(
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var pendingSubtitleDelay = 0.0
    private var pendingSubtitlePosition = 100
    private var pendingSubtitleScale = 1.0
    private var pendingExternalSubtitlePath: String? = null
    private var pendingPlaybackSpeed: Double = 1.0
    private var pendingAudioTrackIndex: Int? = null
    private var pendingSubtitleTrackIndex: Int? = null
    private var pendingPreferExternalSubtitle: Boolean = false
    private var pendingSubtitleGuid: String? = null

    fun onLoadRequested(source: MpvSource) {
        pendingPlaybackSpeed = source.playbackSpeed
        pendingAudioTrackIndex = source.audioTrackIndex
        pendingSubtitleTrackIndex = source.subtitleTrackIndex
        pendingPreferExternalSubtitle = source.preferExternalSubtitle
        pendingSubtitleGuid = source.subtitleTrackGuid
    }

    fun onSubtitleTrackSelectedManually() {
        pendingExternalSubtitlePath = null
    }

    fun onFileLoaded() {
        runCatching {
            mpv.setPropertyDouble("speed", pendingPlaybackSpeed)
        }
        runCatching {
            mpv.setPropertyDouble("sub-delay", pendingSubtitleDelay)
        }
        runCatching {
            mpv.setPropertyInt("sub-pos", pendingSubtitlePosition.toLong())
        }
        runCatching {
            mpv.setPropertyDouble("sub-scale", pendingSubtitleScale)
        }
        runCatching {
            mpv.setPropertyString("sub-ass-override", "scale")
        }
        pendingAudioTrackIndex?.let { index ->
            runCatching { mpv.setPropertyInt("aid", index.toLong()) }
        }
        when {
            pendingPreferExternalSubtitle -> runCatching {
                mpv.setPropertyString("sid", "no")
            }
            pendingSubtitleTrackIndex != null -> runCatching {
                mpv.setPropertyInt("sid", pendingSubtitleTrackIndex!!.toLong())
            }
            pendingSubtitleGuid.isNullOrBlank() -> runCatching {
                mpv.setPropertyString("sid", "no")
            }
        }
    }

    fun queueExternalSubtitle(path: String, initialized: Boolean): Boolean {
        if (!initialized || path.isBlank()) return false
        pendingExternalSubtitlePath = path
        return true
    }

    fun applyPendingExternalSubtitle(): Boolean {
        val path = pendingExternalSubtitlePath?.takeIf { it.isNotBlank() } ?: return false
        val success = runCatching {
            Log.d("FlyPlayerMpv", "sub-add path=$path")
            mpv.command(
                arrayOf(
                    "sub-add",
                    path,
                    "select",
                ),
            ) >= 0
        }.getOrDefault(false)
        if (success) {
            pendingExternalSubtitlePath = null
        }
        return success
    }

    fun clearPendingExternalSubtitle() {
        pendingExternalSubtitlePath = null
    }

    fun hasPendingExternalSubtitle(): Boolean {
        return pendingExternalSubtitlePath?.isNotBlank() == true
    }

    fun setSubtitleDelay(delay: Double): Boolean {
        pendingSubtitleDelay = delay
        return true
    }

    fun setSubtitlePosition(position: Int): Boolean {
        pendingSubtitlePosition = position.coerceIn(0, 100)
        return true
    }

    fun setSubtitleScale(scale: Double): Boolean {
        pendingSubtitleScale = scale.coerceIn(0.5, 2.5)
        return true
    }

    fun resetSubtitleStyle() {
        pendingSubtitleDelay = 0.0
        pendingSubtitlePosition = 100
        pendingSubtitleScale = 1.0
    }

    fun reset() {
        pendingExternalSubtitlePath = null
        pendingAudioTrackIndex = null
        pendingSubtitleTrackIndex = null
        pendingPreferExternalSubtitle = false
        pendingSubtitleGuid = null
    }
}
