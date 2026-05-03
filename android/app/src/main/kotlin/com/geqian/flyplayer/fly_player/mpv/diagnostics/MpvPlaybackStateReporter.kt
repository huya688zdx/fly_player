package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock
import kotlin.math.abs

data class MpvPlaybackControllerDiagnosticsSnapshot(
    val state: MpvPlayerState,
    val source: MpvSource,
    val loadedSourceUrl: String?,
    val loadingSourceUrl: String?,
    val activePlaybackUrl: String?,
    val nativeProxyUrl: String?,
    val nativeProxySessionId: String?,
    val audioOnlyVideoState: Boolean,
    val surfaceReady: Boolean,
    val surfaceAttached: Boolean,
    val surfaceValid: Boolean,
    val videoOutputReady: Boolean,
    val videoTrackSuspended: Boolean,
    val videoStreamLost: Boolean,
    val videoStreamLossReason: String?,
    val proxyOpenFailed: Boolean,
    val proxyOpenFailureReason: String?,
    val pendingLoadRequested: Boolean,
    val sourceFileLoaded: Boolean,
    val sessionSnapshot: PlaybackSessionSnapshot,
    val resumeAfterSurfaceRestore: Boolean,
    val pendingSeekPositionMs: Long,
    val activeHwdecMode: String,
    val forcedHwdecMode: String?,
    val activeColorPipeline: VideoColorPipeline,
    val forcedColorPipeline: VideoColorPipeline?,
    val preferredHwdecMode: String,
    val preferredColorPipeline: VideoColorPipeline,
    val advancedSettings: Map<String, Any?>,
    val windowColorMode: String,
    val displayProfile: DisplayProfile,
    val deviceProfile: DeviceProfile,
    val connectedAudioSummary: String?,
    val usbAudioConnected: Boolean,
    val usbAudioSummary: String?,
    val systemOutputSampleRate: Int?,
    val systemOutputFramesPerBuffer: Int?,
)

class MpvPlaybackStateReporter(
    private val runOnMainThread: (() -> Unit) -> Unit,
    private val stateListener: MpvPlaybackStateListener,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var lastDispatchedState: MpvPlayerState? = null
    private var lastDispatchUptimeMs = 0L

    fun dispatch(state: MpvPlayerState, sourceTitle: String) {
        if (!shouldDispatch(state)) return
        lastDispatchedState = state
        lastDispatchUptimeMs = SystemClock.uptimeMillis()
        runOnMainThread {
            stateListener.onStateChanged(state, "")
        }
    }

    private fun shouldDispatch(next: MpvPlayerState): Boolean {
        val previous = lastDispatchedState ?: return true
        if (previous == next) return false
        if (
            previous.ready != next.ready ||
                previous.nativeLibLoaded != next.nativeLibLoaded ||
                previous.visualPlaybackReady != next.visualPlaybackReady ||
                previous.paused != next.paused ||
                previous.playbackPhase != next.playbackPhase ||
                previous.buffering != next.buffering ||
                previous.bufferedPositionMs != next.bufferedPositionMs ||
                previous.durationMs != next.durationMs ||
                previous.weakNetworkMode != next.weakNetworkMode ||
                previous.networkSpeedBytesPerSecond != next.networkSpeedBytesPerSecond ||
                previous.rebufferTargetMs != next.rebufferTargetMs ||
                previous.estimatedResumeWaitMs != next.estimatedResumeWaitMs ||
                previous.statusText != next.statusText ||
                previous.error != next.error
        ) {
            return true
        }
        val now = SystemClock.uptimeMillis()
        val minIntervalMs =
            if (next.playbackPhase == MpvPlaybackPhase.PLAYING.wireValue) 250L else 1000L
        if (now - lastDispatchUptimeMs >= minIntervalMs) {
            return true
        }
        return abs(next.positionMs - previous.positionMs) >= minIntervalMs
    }

    fun buildDiagnostics(snapshot: MpvPlaybackControllerDiagnosticsSnapshot): Map<String, Any?> {
        val playback = linkedMapOf<String, Any?>(
            "ready" to snapshot.state.ready,
            "nativeLibLoaded" to snapshot.state.nativeLibLoaded,
            "visualPlaybackReady" to snapshot.state.visualPlaybackReady,
            "paused" to snapshot.state.paused,
            "playbackPhase" to snapshot.state.playbackPhase,
            "buffering" to snapshot.state.buffering,
            "positionMs" to snapshot.state.positionMs,
            "bufferedPositionMs" to snapshot.state.bufferedPositionMs,
            "durationMs" to snapshot.state.durationMs,
            "weakNetworkMode" to snapshot.state.weakNetworkMode,
            "networkSpeedBytesPerSecond" to snapshot.state.networkSpeedBytesPerSecond,
            "rebufferTargetMs" to snapshot.state.rebufferTargetMs,
            "estimatedResumeWaitMs" to snapshot.state.estimatedResumeWaitMs,
            "statusText" to snapshot.state.statusText,
            "error" to snapshot.state.error,
            "playbackSpeed" to snapshot.source.playbackSpeed,
        )
        val sourceInfo = linkedMapOf<String, Any?>(
            "title" to snapshot.source.title,
            "itemGuid" to snapshot.source.itemGuid,
            "mediaGuid" to snapshot.source.mediaGuid,
            "videoGuid" to snapshot.source.videoGuid,
            "url" to snapshot.source.url,
            "loadedSourceUrl" to snapshot.loadedSourceUrl,
            "loadingSourceUrl" to snapshot.loadingSourceUrl,
            "playbackUrl" to snapshot.activePlaybackUrl,
            "nativeProxyUrl" to snapshot.nativeProxyUrl,
            "nativeProxySessionId" to snapshot.nativeProxySessionId,
            "resolution" to snapshot.source.resolution,
            "bitrate" to snapshot.source.bitrate,
            "videoCodecName" to snapshot.source.videoCodecName,
            "videoProfile" to snapshot.source.videoProfile,
            "bitDepth" to snapshot.source.bitDepth,
            "colorSpace" to snapshot.source.colorSpace,
            "colorTransfer" to snapshot.source.colorTransfer,
            "colorPrimaries" to snapshot.source.colorPrimaries,
            "hdrLikely" to snapshot.source.isHdrLikely(),
            "preferExternalSubtitle" to snapshot.source.preferExternalSubtitle,
            "reliableSeek" to snapshot.source.reliableSeek,
            "seekProbeSummary" to snapshot.source.seekProbeSummary,
        )
        val output = linkedMapOf<String, Any?>(
            "surfaceReady" to snapshot.surfaceReady,
            "surfaceAttached" to snapshot.surfaceAttached,
            "surfaceValid" to snapshot.surfaceValid,
            "videoOutputReady" to snapshot.videoOutputReady,
            "videoTrackSuspended" to snapshot.videoTrackSuspended,
            "videoStreamLost" to snapshot.videoStreamLost,
            "videoStreamLossReason" to snapshot.videoStreamLossReason,
            "proxyOpenFailed" to snapshot.proxyOpenFailed,
            "proxyOpenFailureReason" to snapshot.proxyOpenFailureReason,
            "audioOnlyVideoState" to snapshot.audioOnlyVideoState,
            "videoChainEstablished" to !snapshot.audioOnlyVideoState,
            "pendingLoadRequested" to snapshot.pendingLoadRequested,
            "sourceFileLoaded" to snapshot.sourceFileLoaded,
            "sourceSwitchInProgress" to snapshot.sessionSnapshot.sourceSwitchInProgress,
            "loadCommandInFlight" to snapshot.sessionSnapshot.loadCommandInFlight,
            "playbackGeneration" to snapshot.sessionSnapshot.generation,
            "resumeAfterSurfaceRestore" to snapshot.resumeAfterSurfaceRestore,
            "pendingSeekPositionMs" to snapshot.pendingSeekPositionMs,
            "activeHwdecMode" to snapshot.activeHwdecMode,
            "forcedHwdecMode" to snapshot.forcedHwdecMode,
            "activeColorPipeline" to snapshot.activeColorPipeline.name,
            "forcedColorPipeline" to snapshot.forcedColorPipeline?.name,
            "preferredHwdecMode" to snapshot.preferredHwdecMode,
            "preferredColorPipeline" to snapshot.preferredColorPipeline.name,
            "windowColorMode" to snapshot.windowColorMode,
            "advancedSettings" to snapshot.advancedSettings,
            "connectedAudioSummary" to snapshot.connectedAudioSummary,
            "usbAudioConnected" to snapshot.usbAudioConnected,
            "usbAudioSummary" to snapshot.usbAudioSummary,
            "systemOutputSampleRate" to snapshot.systemOutputSampleRate,
            "systemOutputFramesPerBuffer" to snapshot.systemOutputFramesPerBuffer,
        )
        val display = linkedMapOf<String, Any?>(
            "displaySupportsHdr" to snapshot.displayProfile.supportsHdr,
            "displaySupportsWideColorGamut" to snapshot.displayProfile.supportsWideColorGamut,
            "displayProfileSummary" to snapshot.displayProfile.summary,
            "deviceIsLikelyMali" to snapshot.deviceProfile.isLikelyMali,
            "deviceProfileSummary" to snapshot.deviceProfile.summary,
        )
        return MpvPlaybackDiagnosticsBuilder.build(
            MpvPlaybackDiagnosticsSnapshot(
                playback = playback,
                source = sourceInfo,
                output = output,
                display = display,
                windowColorMode = snapshot.windowColorMode,
            ),
            mpv = mpv,
        )
    }
}
