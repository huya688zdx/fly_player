package com.geqian.flyplayer.fly_player.mpv

data class PlaybackRecoveryRuntimeSnapshot(
    val sourceSwitchInProgress: Boolean,
    val sourceFileLoaded: Boolean,
    val videoStreamLost: Boolean,
    val suppressRetryRecovery: Boolean,
    val hlsSubResourceLog: Boolean,
    val hasUsableVideoOutputTarget: Boolean,
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
            ),
            lowerMessage,
        )
        if (decision.action == PlaybackRecoveryAction.IGNORE) {
            return PlaybackRecoveryExecution()
        }
        return PlaybackRecoveryExecution(
            recoverVideoOutput = decision.action == PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT,
            reloadCurrentSource = decision.action == PlaybackRecoveryAction.RELOAD_CURRENT_FILE,
            queueSeekPositionMs = snapshot.positionMs.takeIf { it > 0L },
            markVideoStreamLost = decision.markVideoStreamLost,
            videoStreamLossReason = lowerMessage.takeIf { decision.markVideoStreamLost },
        )
    }

    fun resolveAudioOnlyState(
        snapshot: PlaybackRecoveryRuntimeSnapshot,
        reason: String,
    ): PlaybackRecoveryExecution {
        return PlaybackRecoveryExecution(
            recoverVideoOutput = !snapshot.hasUsableVideoOutputTarget || !snapshot.currentSourceStable,
            reloadCurrentSource = snapshot.hasUsableVideoOutputTarget && snapshot.currentSourceStable,
            queueSeekPositionMs = snapshot.positionMs.takeIf { it > 0L },
            markVideoStreamLost = true,
            videoStreamLossReason = reason,
            clearSourceFileLoaded = true,
        )
    }
}
