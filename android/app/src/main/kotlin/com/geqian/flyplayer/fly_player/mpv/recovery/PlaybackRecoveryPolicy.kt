package com.geqian.flyplayer.fly_player.mpv

enum class PlaybackRecoveryAction {
    IGNORE,
    RECOVER_VIDEO_OUTPUT,
    RELOAD_CURRENT_FILE,
}

data class PlaybackRecoverySnapshot(
    val sourceSwitchInProgress: Boolean,
    val sourceFileLoaded: Boolean,
    val videoStreamLost: Boolean,
    val suppressRetryRecovery: Boolean,
    val hlsSubResourceLog: Boolean,
    val surfaceTransitionInProgress: Boolean,
)

data class PlaybackRecoveryDecision(
    val action: PlaybackRecoveryAction,
    val markVideoStreamLost: Boolean = false,
)

class PlaybackRecoveryPolicy {
    fun evaluateLog(
        snapshot: PlaybackRecoverySnapshot,
        lowerMessage: String,
    ): PlaybackRecoveryDecision {
        if (
            snapshot.sourceSwitchInProgress ||
            snapshot.suppressRetryRecovery ||
            snapshot.hlsSubResourceLog
        ) {
            return PlaybackRecoveryDecision(PlaybackRecoveryAction.IGNORE)
        }
        if (
            snapshot.sourceFileLoaded &&
            lowerMessage.contains("seeking stream 0 (video) to nothing")
        ) {
            return PlaybackRecoveryDecision(
                action = if (snapshot.surfaceTransitionInProgress) {
                    PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT
                } else {
                    PlaybackRecoveryAction.RELOAD_CURRENT_FILE
                },
                markVideoStreamLost = true,
            )
        }
        if (
            lowerMessage.contains("playback restart complete") &&
            lowerMessage.contains("audio=playing") &&
            (lowerMessage.contains("video=eof") || lowerMessage.contains("video=playing")) &&
            lowerMessage.contains("(paused)")
        ) {
            return PlaybackRecoveryDecision(PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT)
        }
        if (
            snapshot.videoStreamLost &&
            lowerMessage.contains("playback restart complete") &&
            lowerMessage.contains("audio=playing") &&
            lowerMessage.contains("video=eof")
        ) {
            return PlaybackRecoveryDecision(
                action = if (snapshot.surfaceTransitionInProgress) {
                    PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT
                } else {
                    PlaybackRecoveryAction.RELOAD_CURRENT_FILE
                },
                markVideoStreamLost = true,
            )
        }
        if (
            lowerMessage.contains("missing surface pointer") ||
            lowerMessage.contains("failed initializing any suitable gpu context") ||
            lowerMessage.contains("error opening/initializing the vo window") ||
            lowerMessage.contains("vo=null") ||
            lowerMessage.contains("vo/null")
        ) {
            return PlaybackRecoveryDecision(PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT)
        }
        return PlaybackRecoveryDecision(PlaybackRecoveryAction.IGNORE)
    }
}
