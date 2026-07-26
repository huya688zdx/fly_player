package com.geqian.flyplayer.fly_player.mpv

data class MpvPlaybackRestorePlan(
    val seekPositionMs: Long? = null,
    val applyExternalSubtitle: Boolean = false,
    val retryVideoRecovery: Boolean = false,
)

class MpvPlaybackRestoreCoordinator {
    var pendingSeekPositionMs: Long = 0L
        private set
    val isSeekingOrRestoringVideo: Boolean
        get() = seeking || waitingForVideoAfterSeek
    val hasReachedVideoEof: Boolean
        get() = videoEofReached
    var activeSeekEpoch: Long = 0L
        private set
    var completedSeekEpoch: Long = 0L
        private set

    private var sourceFileLoaded = false
    private var waitingForVideoAfterSeek = false
    private var pendingExternalSubtitle = false
    private var seeking = false
    private var videoEofReached = false
    private var abnormalVideoRetryCount = 0
    private var seekingStartedEpoch = 0L
    private var seekFallbackLastPositionMs = -1L
    private var seekFallbackAdvanceCount = 0

    fun onLoadRequested(startPositionMs: Long, hasPendingExternalSubtitle: Boolean) {
        pendingSeekPositionMs = startPositionMs.coerceAtLeast(0L)
        sourceFileLoaded = false
        waitingForVideoAfterSeek = pendingSeekPositionMs > 0L
        pendingExternalSubtitle = hasPendingExternalSubtitle
        seeking = false
        videoEofReached = false
        abnormalVideoRetryCount = 0
        resetSeekCompletionFallback()
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

    fun onSeekQueued(
        positionMs: Long,
        seekEpoch: Long = activeSeekEpoch + 1L,
    ): MpvPlaybackRestorePlan {
        val inheritStartedSeeking =
            seeking &&
                activeSeekEpoch > completedSeekEpoch &&
                seekingStartedEpoch == activeSeekEpoch
        pendingSeekPositionMs = positionMs.coerceAtLeast(0L)
        waitingForVideoAfterSeek = pendingSeekPositionMs > 0L
        seeking = pendingSeekPositionMs > 0L
        resetSeekCompletionFallback()
        if (seekEpoch > activeSeekEpoch) {
            activeSeekEpoch = seekEpoch
            seekingStartedEpoch = if (inheritStartedSeeking) activeSeekEpoch else 0L
        }
        return MpvPlaybackRestorePlan(seekPositionMs = pendingSeekPositionMs)
    }

    fun onSeekingChanged(isSeeking: Boolean): MpvPlaybackRestorePlan {
        if (isSeeking) {
            seeking = true
            seekingStartedEpoch = activeSeekEpoch
            resetSeekCompletionFallback()
        } else if (activeSeekEpoch <= completedSeekEpoch || seekingStartedEpoch == activeSeekEpoch) {
            seeking = false
            completedSeekEpoch = activeSeekEpoch
        }
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
            if (!seeking) {
                resetSeekCompletionFallback()
                pendingSeekPositionMs = 0L
                abnormalVideoRetryCount = 0
                return maybeApplySubtitle()
            }
            // seeking 完成兜底：mpv 属性通知在快速翻转时会合并，缓存内 hr-seek 的
            // seeking true/false 边沿可能整个丢失——此时 seeking 从 onSeekQueued 置上
            // 后没有任何信号能清掉（false 被 epoch 守卫当旧信号忽略、true 永不再来），
            // phase 永久 SEEKING、弹幕时间轴永久 SEEK_HOLD（真机拖进度条弹幕冻死实录）。
            // seek 真在执行时 mpv 不会流式推进 time-pos；连续多个推进样本 = 播放早已
            // 重启、完成边沿丢了，按显式完成处理。单个近目标样本不算数（防 UI 线程
            // 先入 hold、播放线程未执行 seek 的异步窗口串台，见 DanmakuSeekCompletionChainTest）。
            if (seekFallbackLastPositionMs in 0 until positionMs) {
                seekFallbackAdvanceCount += 1
            } else {
                seekFallbackAdvanceCount = 0
            }
            seekFallbackLastPositionMs = positionMs
            if (seekFallbackAdvanceCount >= SEEK_COMPLETION_FALLBACK_ADVANCES) {
                seeking = false
                completedSeekEpoch = activeSeekEpoch
                resetSeekCompletionFallback()
                pendingSeekPositionMs = 0L
                abnormalVideoRetryCount = 0
                return maybeApplySubtitle()
            }
        }
        return MpvPlaybackRestorePlan()
    }

    private fun resetSeekCompletionFallback() {
        seekFallbackLastPositionMs = -1L
        seekFallbackAdvanceCount = 0
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

    private companion object {
        // 连续推进对数（即约 4 个样本）；mpv time-pos 约 5Hz，兜底最迟 ~0.8s 生效。
        const val SEEK_COMPLETION_FALLBACK_ADVANCES = 3
    }
}
