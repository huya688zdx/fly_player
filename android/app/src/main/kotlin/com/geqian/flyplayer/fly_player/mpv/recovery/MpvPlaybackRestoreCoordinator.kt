package com.geqian.flyplayer.fly_player.mpv

import kotlin.math.abs

data class MpvPlaybackRestorePlan(
    val seekPositionMs: Long? = null,
    val applyExternalSubtitle: Boolean = false,
    val retryVideoRecovery: Boolean = false,
)

class MpvPlaybackRestoreCoordinator {
    companion object {
        private const val SEEK_SETTLE_TOLERANCE_MS = 3000L
    }

    var pendingSeekPositionMs: Long = 0L
        private set
    val isSeekingOrRestoringVideo: Boolean
        get() = seeking || waitingForVideoAfterSeek
    val hasReachedVideoEof: Boolean
        get() = videoEofReached

    private var sourceFileLoaded = false
    private var waitingForVideoAfterSeek = false
    private var pendingExternalSubtitle = false
    private var seeking = false
    private var videoEofReached = false
    private var abnormalVideoRetryCount = 0

    fun onLoadRequested(startPositionMs: Long, hasPendingExternalSubtitle: Boolean) {
        pendingSeekPositionMs = startPositionMs.coerceAtLeast(0L)
        sourceFileLoaded = false
        waitingForVideoAfterSeek = pendingSeekPositionMs > 0L
        pendingExternalSubtitle = hasPendingExternalSubtitle
        seeking = false
        videoEofReached = false
        abnormalVideoRetryCount = 0
    }

    fun onSourceFileLoaded(): MpvPlaybackRestorePlan {
        sourceFileLoaded = true
        return if (pendingSeekPositionMs > 0L) {
            seeking = true
            MpvPlaybackRestorePlan(seekPositionMs = pendingSeekPositionMs)
        } else {
            maybeApplySubtitle()
        }
    }

    fun onSeekQueued(positionMs: Long): MpvPlaybackRestorePlan {
        pendingSeekPositionMs = positionMs.coerceAtLeast(0L)
        waitingForVideoAfterSeek = pendingSeekPositionMs > 0L
        seeking = pendingSeekPositionMs > 0L
        return MpvPlaybackRestorePlan(seekPositionMs = pendingSeekPositionMs)
    }

    fun onSeekingChanged(isSeeking: Boolean): MpvPlaybackRestorePlan {
        seeking = isSeeking
        return maybeApplySubtitle()
    }

    fun onVideoEofChanged(
        eofReached: Boolean,
        positionMs: Long,
        durationMs: Long,
    ): MpvPlaybackRestorePlan {
        videoEofReached = eofReached
        if (!eofReached) return MpvPlaybackRestorePlan()
        if (!sourceFileLoaded) return MpvPlaybackRestorePlan()
        if (durationMs > 0L && positionMs >= (durationMs - 1500L).coerceAtLeast(0L)) {
            return MpvPlaybackRestorePlan()
        }
        if (abnormalVideoRetryCount >= 2) return MpvPlaybackRestorePlan()
        abnormalVideoRetryCount += 1
        return MpvPlaybackRestorePlan(retryVideoRecovery = true)
    }

    fun onTimePosition(positionMs: Long): MpvPlaybackRestorePlan {
        if (!sourceFileLoaded || videoEofReached) return MpvPlaybackRestorePlan()
        if (positionMs >= 0L) {
            waitingForVideoAfterSeek = false
            val targetReached =
                pendingSeekPositionMs > 0L &&
                    abs(positionMs - pendingSeekPositionMs) <= SEEK_SETTLE_TOLERANCE_MS
            if (targetReached) {
                seeking = false
            }
            if (!seeking) {
                pendingSeekPositionMs = 0L
                abnormalVideoRetryCount = 0
                return maybeApplySubtitle()
            }
        }
        return MpvPlaybackRestorePlan()
    }

    fun onExternalSubtitleQueued(sourceAlreadyLoaded: Boolean): MpvPlaybackRestorePlan {
        pendingExternalSubtitle = true
        if (!sourceAlreadyLoaded) return MpvPlaybackRestorePlan()
        return maybeApplySubtitle()
    }

    fun clearPendingExternalSubtitle() {
        pendingExternalSubtitle = false
    }

    private fun maybeApplySubtitle(): MpvPlaybackRestorePlan {
        if (!pendingExternalSubtitle) return MpvPlaybackRestorePlan()
        if (!sourceFileLoaded || seeking || waitingForVideoAfterSeek || videoEofReached) {
            return MpvPlaybackRestorePlan()
        }
        pendingExternalSubtitle = false
        return MpvPlaybackRestorePlan(applyExternalSubtitle = true)
    }
}
