package com.geqian.flyplayer.fly_player.mpv

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
    val windowColorMode: String,
    val displayProfile: DisplayProfile,
    val deviceProfile: DeviceProfile,
)

class MpvPlaybackStateReporter(
    private val runOnMainThread: (() -> Unit) -> Unit,
    private val stateListener: MpvPlaybackStateListener,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    fun dispatch(state: MpvPlayerState, sourceTitle: String) {
        runOnMainThread {
            stateListener.onStateChanged(state, "")
        }
    }

    fun buildDiagnostics(snapshot: MpvPlaybackControllerDiagnosticsSnapshot): Map<String, Any?> {
        val playback = linkedMapOf<String, Any?>(
            "ready" to snapshot.state.ready,
            "nativeLibLoaded" to snapshot.state.nativeLibLoaded,
            "paused" to snapshot.state.paused,
            "positionMs" to snapshot.state.positionMs,
            "durationMs" to snapshot.state.durationMs,
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
