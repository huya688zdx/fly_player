package com.geqian.flyplayer.fly_player.mpv

data class PlaybackRecoveryRuntimeSnapshot(
    val sourceSwitchInProgress: Boolean,
    val sourceFileLoaded: Boolean,
    val videoStreamLost: Boolean,
    val suppressRetryRecovery: Boolean,
    val hlsSubResourceLog: Boolean,
    val hasUsableVideoOutputTarget: Boolean,
    val videoOutputReady: Boolean,
    val surfaceTransitionInProgress: Boolean,
    val currentSourceStable: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val audioOnlyVideoState: Boolean,
)

data class PlaybackRecoveryExecution(
    val suppressRetryRecovery: Boolean = false,
    val recoverVideoOutput: Boolean = false,
    val reloadCurrentSource: Boolean = false,
    val seekPositionMs: Long? = null,
    val applyExternalSubtitle: Boolean = false,
    val queueSeekPositionMs: Long? = null,
    val markVideoStreamLost: Boolean = false,
    val videoStreamLossReason: String? = null,
    val clearSourceFileLoaded: Boolean = false,
)

class PlaybackRecoveryOrchestrator(
    private val recoveryPolicy: PlaybackRecoveryPolicy = PlaybackRecoveryPolicy(),
) {
    private fun shouldIgnoreLogRecovery(
        snapshot: PlaybackRecoveryRuntimeSnapshot,
    ): Boolean {
        return snapshot.sourceSwitchInProgress ||
            snapshot.suppressRetryRecovery ||
            snapshot.hlsSubResourceLog
    }

    private fun queuedRecoveryPositionMs(
        snapshot: PlaybackRecoveryRuntimeSnapshot,
    ): Long? {
        val positionMs = snapshot.positionMs.takeIf { it > 0L } ?: return null
        if (!snapshot.currentSourceStable) return null
        if (snapshot.durationMs > 0L) {
            val maxRecoverablePositionMs = (snapshot.durationMs - 1500L).coerceAtLeast(0L)
            if (positionMs >= maxRecoverablePositionMs) {
                return null
            }
        }
        return positionMs
    }

    fun resolveRestorePlan(
        plan: MpvPlaybackRestorePlan,
        suppressRetryRecovery: Boolean,
    ): PlaybackRecoveryExecution {
        if (plan.retryVideoRecovery && suppressRetryRecovery) {
            return PlaybackRecoveryExecution(suppressRetryRecovery = true)
        }
        return when {
            plan.retryVideoRecovery -> PlaybackRecoveryExecution(recoverVideoOutput = true)
            plan.seekPositionMs != null && plan.seekPositionMs > 0L ->
                PlaybackRecoveryExecution(seekPositionMs = plan.seekPositionMs)
            plan.applyExternalSubtitle -> PlaybackRecoveryExecution(applyExternalSubtitle = true)
            else -> PlaybackRecoveryExecution()
        }
    }

    fun resolveLogMessage(
        snapshot: PlaybackRecoveryRuntimeSnapshot,
        lowerMessage: String,
    ): PlaybackRecoveryExecution {
        if (shouldIgnoreLogRecovery(snapshot)) {
            return PlaybackRecoveryExecution()
        }
        if (
            lowerMessage.contains("playback restart complete") &&
            lowerMessage.contains("audio=playing") &&
            lowerMessage.contains("video=eof") &&
            (
                snapshot.surfaceTransitionInProgress ||
                    !snapshot.hasUsableVideoOutputTarget ||
                    !snapshot.videoOutputReady ||
                    !snapshot.currentSourceStable
            )
        ) {
            return PlaybackRecoveryExecution(
                recoverVideoOutput = true,
                queueSeekPositionMs = queuedRecoveryPositionMs(snapshot),
                markVideoStreamLost = true,
                videoStreamLossReason = lowerMessage,
            )
        }
        if (snapshot.audioOnlyVideoState && lowerMessage.contains("video=eof")) {
            return resolveAudioOnlyState(snapshot, lowerMessage)
        }
        val decision = recoveryPolicy.evaluateLog(
            PlaybackRecoverySnapshot(
                sourceSwitchInProgress = snapshot.sourceSwitchInProgress,
                sourceFileLoaded = snapshot.sourceFileLoaded,
                videoStreamLost = snapshot.videoStreamLost,
                suppressRetryRecovery = snapshot.suppressRetryRecovery,
                hlsSubResourceLog = snapshot.hlsSubResourceLog,
                surfaceTransitionInProgress = snapshot.surfaceTransitionInProgress,
            ),
            lowerMessage,
        )
        if (decision.action == PlaybackRecoveryAction.IGNORE) {
            return PlaybackRecoveryExecution()
        }
        return PlaybackRecoveryExecution(
            recoverVideoOutput = decision.action == PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT,
            reloadCurrentSource = decision.action == PlaybackRecoveryAction.RELOAD_CURRENT_FILE,
            queueSeekPositionMs = queuedRecoveryPositionMs(snapshot),
            markVideoStreamLost = decision.markVideoStreamLost,
            videoStreamLossReason = lowerMessage.takeIf { decision.markVideoStreamLost },
        )
    }

    fun resolveAudioOnlyState(
        snapshot: PlaybackRecoveryRuntimeSnapshot,
        reason: String,
    ): PlaybackRecoveryExecution {
        val shouldRecoverVideoOutput =
            snapshot.surfaceTransitionInProgress ||
                !snapshot.hasUsableVideoOutputTarget ||
                !snapshot.videoOutputReady ||
                !snapshot.currentSourceStable
        return PlaybackRecoveryExecution(
            recoverVideoOutput = shouldRecoverVideoOutput,
            reloadCurrentSource = !shouldRecoverVideoOutput,
            queueSeekPositionMs = queuedRecoveryPositionMs(snapshot),
            markVideoStreamLost = true,
            videoStreamLossReason = reason,
            clearSourceFileLoaded = true,
        )
    }
}
