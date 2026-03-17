package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock

data class PlaybackSessionSnapshot(
    val generation: Long,
    val sourceSwitchInProgress: Boolean,
    val loadCommandInFlight: Boolean,
    val suppressRetryRecovery: Boolean,
    val currentPlaybackUrl: String?,
)

class PlaybackSessionGate(
    private val nowMs: () -> Long = { SystemClock.elapsedRealtime() },
) {
    private var generation: Long = 0L
    private var sourceSwitchInProgress = false
    private var loadCommandInFlight = false
    private var suppressRecoveryUntilMs = 0L
    private var currentPlaybackUrl: String? = null

    fun reset() {
        sourceSwitchInProgress = false
        loadCommandInFlight = false
        suppressRecoveryUntilMs = 0L
        currentPlaybackUrl = null
    }

    fun beginSourceChange() {
        generation += 1L
        // Advance generation and suppress stale callbacks, but do not block the
        // next load command. The actual switch starts when beginLoad() runs.
        sourceSwitchInProgress = false
        loadCommandInFlight = false
        currentPlaybackUrl = null
        suppressRecoveryUntilMs = nowMs() + LOAD_SUPPRESSION_WINDOW_MS
    }

    fun currentSnapshot(): PlaybackSessionSnapshot {
        return PlaybackSessionSnapshot(
            generation = generation,
            sourceSwitchInProgress = sourceSwitchInProgress,
            loadCommandInFlight = loadCommandInFlight,
            suppressRetryRecovery = shouldSuppressRetryRecovery(false),
            currentPlaybackUrl = currentPlaybackUrl,
        )
    }

    fun beginLoad(playbackUrl: String?): Long {
        generation += 1L
        sourceSwitchInProgress = true
        loadCommandInFlight = true
        currentPlaybackUrl = playbackUrl
        suppressRecoveryUntilMs = nowMs() + LOAD_SUPPRESSION_WINDOW_MS
        return generation
    }

    fun onLoadCommandFinished(success: Boolean) {
        loadCommandInFlight = false
        if (!success) {
            sourceSwitchInProgress = false
            suppressRecoveryUntilMs = 0L
        }
    }

    fun onFileLoaded() {
        loadCommandInFlight = false
        sourceSwitchInProgress = false
        val candidate = nowMs() + POST_FILE_LOADED_SUPPRESSION_WINDOW_MS
        if (candidate > suppressRecoveryUntilMs) {
            suppressRecoveryUntilMs = candidate
        }
    }

    fun onPlaybackEnded() {
        sourceSwitchInProgress = false
        loadCommandInFlight = false
        suppressRecoveryUntilMs = 0L
    }

    fun onProxyFailure() {
        sourceSwitchInProgress = false
        loadCommandInFlight = false
        suppressRecoveryUntilMs = 0L
    }

    fun onVideoRecoveryTriggered() {
        val candidate = nowMs() + VIDEO_RECOVERY_SUPPRESSION_WINDOW_MS
        if (candidate > suppressRecoveryUntilMs) {
            suppressRecoveryUntilMs = candidate
        }
    }

    fun onSurfaceLost() {
        val candidate = nowMs() + SURFACE_LOSS_SUPPRESSION_WINDOW_MS
        if (candidate > suppressRecoveryUntilMs) {
            suppressRecoveryUntilMs = candidate
        }
    }

    fun canStartLoad(): Boolean {
        return !loadCommandInFlight && !sourceSwitchInProgress
    }

    fun shouldIgnoreEndFile(
        internalSeekOrRestore: Boolean,
        surfaceUnavailable: Boolean = false,
        sourceStable: Boolean = true,
    ): Boolean {
        return loadCommandInFlight ||
            sourceSwitchInProgress ||
            surfaceUnavailable ||
            !sourceStable ||
            internalSeekOrRestore ||
            isWithinSuppressionWindow()
    }

    fun shouldSuppressRetryRecovery(
        internalSeekOrRestore: Boolean,
        surfaceUnavailable: Boolean = false,
        sourceStable: Boolean = true,
    ): Boolean {
        return loadCommandInFlight ||
            sourceSwitchInProgress ||
            surfaceUnavailable ||
            !sourceStable ||
            internalSeekOrRestore ||
            isWithinSuppressionWindow()
    }

    fun isHlsSubResourceLog(lowerMessage: String): Boolean {
        val playbackUrl = currentPlaybackUrl?.lowercase()
        if (playbackUrl.isNullOrBlank()) return false
        if (!playbackUrl.contains(".m3u8")) return false
        return lowerMessage.contains(".ts") ||
            lowerMessage.contains(".m4s") ||
            lowerMessage.contains(".cmfv") ||
            lowerMessage.contains(".cmfa")
    }

    private fun isWithinSuppressionWindow(): Boolean {
        return nowMs() < suppressRecoveryUntilMs
    }

    companion object {
        private const val LOAD_SUPPRESSION_WINDOW_MS = 4000L
        private const val POST_FILE_LOADED_SUPPRESSION_WINDOW_MS = 1500L
        private const val VIDEO_RECOVERY_SUPPRESSION_WINDOW_MS = 1200L
        private const val SURFACE_LOSS_SUPPRESSION_WINDOW_MS = 1500L
    }
}
