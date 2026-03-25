package com.geqian.flyplayer.fly_player.mpv

import android.media.AudioManager
import android.content.ContentValues
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.view.Surface
import com.geqian.flyplayer.fly_player.PlayerLayoutHandoffCoordinator
import `is`.xyz.mpv.MPVLib
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.FutureTask

private const val TAG = "FlyPlayerMpv"
private const val AUTO_SOFTWARE_DECODER_FALLBACK_STATUS = "Auto decoder fallback: software"
private const val AUTO_FILTER_FALLBACK_STATUS = "Auto performance fallback: filters disabled"
private const val FILTER_FALLBACK_SAMPLE_INTERVAL_MS = 1500L
private const val FILTER_FALLBACK_DROP_THRESHOLD = 6L
private const val FILTER_FALLBACK_MISTIMED_THRESHOLD = 12L
private const val SURFACE_TRANSITION_GRACE_MS = 2500L
private const val ENABLE_MPV_VERBOSE_LOGS = false
private const val DEFAULT_SUBTITLE_POSITION = 92

class MpvPlaybackController(
    private val context: Context,
    private val videoOutputTarget: VideoOutputTarget,
    creationParams: Map<String, Any?>,
    private val stateListener: MpvPlaybackStateListener,
    private val danmakuOcclusionStateListener: ((DanmakuDynamicOcclusionState) -> Unit)? = null,
) : MPVLib.EventObserver,
    MPVLib.LogObserver {
    private val mpv: MpvFacade = DefaultMpvFacade
    private val mainHandler = Handler(Looper.getMainLooper())
    private val playbackThread = HandlerThread("FlyPlayerMpvPlayback").apply { start() }
    private val playbackHandler = Handler(playbackThread.looper)
    private val displayProfile = detectDisplayProfile(context)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private val audioOutputDiagnostics = PlaybackAudioOutputDiagnostics(audioManager)
    private val hostActivity = findActivity(context)
    @Volatile
    private var disposed = false

    private var state = MpvPlayerState(
        loadNonce = 0,
        nativeLibLoaded = mpv.isAvailable(),
        statusText = if (mpv.isAvailable()) {
            "mpv-android runtime detected"
        } else {
            "mpv-android native runtime missing"
        },
        error = mpv.loadErrorMessage(),
    )
    private var source = MpvSource.fromMap(creationParams)
    private var surfaceReady = false
    private var created = false
    private var initialized = false
    private var propertiesObserved = false
    private var resumeAfterSurfaceRestore = false
    private val deviceProfile = detectDeviceProfile()
    private var surfaceAttached = false
    private var videoOutputReady = false
    private var activeHwdecMode = "mediacodec,auto-safe"
    private var forcedHwdecMode: String? = null
    private var forcedColorPipeline: VideoColorPipeline? = null
    private var activeColorPipeline = VideoColorPipeline.SDR
    private var videoTrackSuspended = false
    private var videoStreamLost = false
    private var videoStreamLossReason: String? = null
    private var proxyOpenFailed = false
    private var proxyOpenFailureReason: String? = null
    private var autoFilterFallbackTriggeredForSource = false
    private var lastFilterFallbackSampleUptimeMs = 0L
    private var lastDropFrameCount = 0L
    private var lastDecoderDropFrameCount = 0L
    private var lastMistimedFrameCount = 0L
    private var lastVoDelayedFrameCount = 0L
    private var observedCacheDurationMs = 0L
    private var videoOutputSanityCheckToken = 0L
    private var playbackResumeCheckToken = 0L
    private var pendingAutoResumeAfterSurfaceRestore = false
    private var pendingVideoRecoveryAfterSurfaceRestore = false
    private var pendingVideoRecoveryReason: String? = null
    private var lastSurfaceTransitionUptimeMs = 0L
    private val restoreCoordinator = MpvPlaybackRestoreCoordinator()
    private val loadState = PlaybackLoadStateTracker()
    private val sourceResolver = PlaybackSourceResolver(context)
    private val trackSelectionController = TrackSelectionController(mpv)
    private val recoveryPolicy = PlaybackRecoveryPolicy()
    private val recoveryOrchestrator = PlaybackRecoveryOrchestrator(recoveryPolicy)
    private val sessionGate = PlaybackSessionGate()
    private val runtimeBootstrap = MpvRuntimeBootstrap(context, mpv)
    private val performanceSampler = PlaybackPerformanceSampler(context)
    private val captureExportController = MpvCaptureExportController(context, mpv)
    private val chapterSnapshotBuilder = MpvChapterSnapshotBuilder(TAG, mpv)
    private val pauseController = PlaybackPauseController(TAG, mpv)
    private val stateReporter = MpvPlaybackStateReporter(
        runOnMainThread = ::runOnMainThread,
        stateListener = stateListener,
        mpv = mpv,
    )
    private val videoAdjustmentController = VideoAdjustmentController(mpv)
    private val videoOutputController = VideoOutputController(
        videoOutputTarget = videoOutputTarget,
        hostActivity = hostActivity,
        displayProfile = displayProfile,
        deviceProfile = deviceProfile,
        runOnMainThread = ::runOnMainThread,
        mpv = mpv,
    )
    private val advancedSettingsController = MpvAdvancedSettingsController(
        mpv = mpv,
        videoOutputController = videoOutputController,
    )
    private val diagnosticsSnapshotFactory = PlaybackDiagnosticsSnapshotFactory(
        sessionGate = sessionGate,
        sourceResolver = sourceResolver,
        restoreCoordinator = restoreCoordinator,
        advancedSettingsController = advancedSettingsController,
        videoOutputController = videoOutputController,
        audioOutputDiagnostics = audioOutputDiagnostics,
    )
    private val danmakuOcclusionController = DanmakuDynamicOcclusionController(
        context = context,
        videoOutputTarget = videoOutputTarget,
        stateListener = { state ->
            runOnMainThread {
                danmakuOcclusionStateListener?.invoke(state)
            }
        },
    )

    private fun verboseLog(message: () -> String) {
        if (ENABLE_MPV_VERBOSE_LOGS) {
            Log.d(TAG, message())
        }
    }

    init {
        mpv.addObserver(this)
        mpv.addLogObserver(this)
        loadState.reset()
        danmakuOcclusionController.onSourceChanged(source)
        verboseLog {
            "view init title=${source.title} url=${source.url} deviceProfile=${deviceProfile.summary} displayProfile=${displayProfile.summary}"
        }
        runOnPlaybackThread {
            initializeMpv()
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        mpv.removeObserver(this)
        mpv.removeLogObserver(this)
        playbackHandler.post {
            playbackHandler.removeCallbacksAndMessages(null)
            disposeInternal()
            playbackThread.quitSafely()
        }
    }

    private fun disposeInternal() {
        invalidateVideoOutputSanityChecks()
        sourceResolver.release()
        val preserveSessionForHandoff = shouldPreserveSessionForHostHandoff()
        if (preserveSessionForHandoff) {
            Log.d(
                TAG,
                "preserving mpv session during host handoff host=${hostActivity?.javaClass?.simpleName}",
            )
            videoOutputController.detachSurfaceForHandoff()
        } else if (mpv.isAvailable() && mpv.isCreated()) {
            clearRetainedPlaybackStateForReuse()
        }
        runtimeBootstrap.release()
        created = false
        initialized = false
        propertiesObserved = false
        surfaceAttached = false
        videoOutputReady = false
        loadState.reset()
        activeColorPipeline = VideoColorPipeline.SDR
        videoTrackSuspended = false
        advancedSettingsController.resetTransientOverrides()
        resetAutomaticFilterFallbackMonitor()
        performanceSampler.reset()
        clearVideoStreamFailure()
        sessionGate.reset()
        videoOutputController.onDispose()
        syncVideoOutputState()
        danmakuOcclusionController.dispose()
    }

    private fun clearRetainedPlaybackStateForReuse() {
        runCatching { mpv.setPropertyBoolean("pause", true) }
        runCatching { mpv.setPropertyString("sid", "no") }
        runCatching { mpv.setPropertyString("aid", "auto") }
        runCatching { mpv.setPropertyString("vid", "auto") }
        runCatching { trackSelectionController.reset() }
        restoreCoordinator.clearPendingExternalSubtitle()
        runCatching { mpv.command(arrayOf("playlist-clear")) }
        runCatching { mpv.command(arrayOf("stop")) }
        runCatching { mpv.setPropertyString("vo", "null") }
        runCatching { mpv.detachSurface() }
        Log.d(TAG, "cleared retained mpv playback state before reuse")
    }

    fun getStateMap(): Map<String, Any?> {
        if (disposed) return state.toMap()
        return callOnPlaybackThread { state.toMap() }
    }

    fun getPlaybackDiagnosticsMap(): Map<String, Any?> {
        if (disposed) return state.toMap()
        return callOnPlaybackThread { buildPlaybackDiagnostics() }
    }

    fun getPerformanceOverlayStatsMap(): Map<String, Any?> {
        if (disposed) return emptyMap()
        return callOnPlaybackThread { performanceSampler.sample().toMap() }
    }

    fun getDanmakuOcclusionStateMap(): Map<String, Any?> {
        if (disposed) return DanmakuDynamicOcclusionState.disabled().toMap()
        return callOnPlaybackThread { danmakuOcclusionController.currentStateMap() }
    }

    fun getChapters(): List<Map<String, Any?>> {
        if (disposed) return emptyList()
        return callOnPlaybackThread { buildChapterList() }
    }

    fun getTrackSnapshotMap(): Map<String, Any?> {
        if (disposed) return emptyMap()
        return callOnPlaybackThread { buildTrackSnapshotMap() }
    }

    fun setListenVideoMode(enabled: Boolean): Map<String, Any?> {
        if (disposed) {
            return mapOf(
                "success" to false,
                "enabled" to state.listenVideoModeEnabled,
                "message" to "播放器已释放",
            )
        }
        return callOnPlaybackThread { setListenVideoModeInternal(enabled) }
    }

    fun captureFrame(args: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        if (disposed) {
            return mapOf(
                "success" to false,
                "message" to "播放器已释放",
            )
        }
        return callOnPlaybackThread { captureFrameInternal(args) }
    }

    fun setDanmakuOcclusionConfig(args: Map<String, Any?>): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            danmakuOcclusionController.updateConfig(args)
            syncDanmakuOcclusionRuntime()
        }
        return true
    }

    fun load(args: Map<String, Any?>) {
        runOnPlaybackThread {
            invalidateVideoOutputSanityChecks()
            val nextSource = MpvSource.fromMap(args)
            if (isDuplicateLoadRequest(nextSource)) {
                source = nextSource
                state = state.copy(loadNonce = nextSource.loadNonce)
                verboseLog {
                    "skip duplicate method load nonce=${nextSource.loadNonce} url=${nextSource.url} startMs=${nextSource.startPositionMs}"
                }
                return@runOnPlaybackThread
            }
            val previousUrl = source.url
            source = nextSource
            state = state.copy(loadNonce = source.loadNonce)
            if (previousUrl != source.url) {
                sourceResolver.releaseOnSourceChange(previousUrl, source.url)
            }
            danmakuOcclusionController.onSourceChanged(source)
            resumeAfterSurfaceRestore = false
            loadState.resetForSource(source.url)
            trackSelectionController.reset()
            sessionGate.beginSourceChange()
            videoOutputController.resetForSourceLoad()
            advancedSettingsController.resetTransientOverrides()
            resetAutomaticFilterFallbackMonitor()
            performanceSampler.reset()
            syncVideoOutputState()
            clearVideoStreamFailure()
            clearProxyOpenFailure()
            verboseLog { "method load url=${source.url} startMs=${source.startPositionMs}" }
            loadCurrentSource()
        }
    }

    private fun setListenVideoModeInternal(enabled: Boolean): Map<String, Any?> {
        val currentEnabled = state.listenVideoModeEnabled
        if (currentEnabled == enabled && source.listenVideoModeEnabled == enabled) {
            return mapOf(
                "success" to true,
                "enabled" to enabled,
                "message" to null,
            )
        }
        source = source.copy(listenVideoModeEnabled = enabled)
        if (!initialized || !mpv.isAvailable()) {
            updateState(
                state.copy(
                    listenVideoModeEnabled = enabled,
                    statusText = if (enabled) "Listen video mode queued" else "Video playback mode queued",
                    error = null,
                ),
            )
            return mapOf(
                "success" to true,
                "enabled" to enabled,
                "message" to null,
            )
        }
        val success =
            if (enabled) {
                videoOutputController.enableListenVideoMode(
                    initialized = initialized,
                    available = mpv.isAvailable(),
                )
            } else {
                videoOutputController.disableListenVideoMode(
                    initialized = initialized,
                    available = mpv.isAvailable(),
                )
            }
        syncVideoOutputState()
        if (!enabled) {
            ensureVideoOutputReady()
        }
        if (success) {
            updateState(
                state.copy(
                    listenVideoModeEnabled = enabled,
                    statusText = if (enabled) "Listen video mode enabled" else "Video playback mode restored",
                    error = null,
                ),
            )
            return mapOf(
                "success" to true,
                "enabled" to enabled,
                "message" to null,
            )
        }
        val errorMessage =
            consumeVideoOutputErrorMessage(
                if (enabled) "listen video mode" else "video playback mode",
            )
        updateState(
            state.copy(
                listenVideoModeEnabled = currentEnabled,
                error = errorMessage,
            ),
        )
        source = source.copy(listenVideoModeEnabled = currentEnabled)
        return mapOf(
            "success" to false,
            "enabled" to currentEnabled,
            "message" to errorMessage,
        )
    }

    private fun isDuplicateLoadRequest(nextSource: MpvSource): Boolean {
        if (nextSource.loadNonce == 0 || nextSource.loadNonce != source.loadNonce) return false
        if (nextSource.url != source.url) return false
        if (nextSource.startPositionMs != source.startPositionMs) return false
        if (nextSource.forceNativeProxy != source.forceNativeProxy) return false
        if (nextSource.extremePlaybackEnabled != source.extremePlaybackEnabled) return false
        if (nextSource.reliableSeek != source.reliableSeek) return false
        if (nextSource.headers != source.headers) return false
        return loadState.hasPendingOrInFlightLoad(nextSource.url) ||
            loadState.hasLoadedSource(nextSource.url)
    }

    private fun captureFrameInternal(args: Map<String, Any?>): Map<String, Any?> {
        return captureExportController.captureFrame(
            initialized = initialized,
            sourceFileLoaded = loadState.sourceFileLoaded,
            currentSource = source,
            args = args,
        )
    }

    fun setMpvAdvancedSettings(args: Map<String, Any?>): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val update = advancedSettingsController.update(args)
            advancedSettingsController.resetTransientOverrides()
            resetAutomaticFilterFallbackMonitor()
            performanceSampler.reset()
            val readyToApply = initialized && mpv.isAvailable()
            val applied = advancedSettingsController.apply(initialized, mpv.isAvailable(), source)
            syncVideoOutputState()
            if (update.requiresReload && readyToApply && surfaceReady && surfaceAttached && currentSurfaceValid()) {
                val resumePositionMs =
                    if (source.reliableSeek) {
                        state.positionMs.coerceAtLeast(0L)
                    } else {
                        0L
                    }
                source = source.copy(startPositionMs = resumePositionMs)
                loadState.clearForRecovery(source.url)
                sessionGate.onVideoRecoveryTriggered()
                loadCurrentSource()
                return@runOnPlaybackThread
            }
            if (update.changed) {
                updateState(
                    state.copy(
                        statusText =
                            when {
                                applied -> "MPV advanced settings updated"
                                readyToApply -> state.statusText
                                else -> "MPV advanced settings queued"
                            },
                        error =
                            when {
                                applied -> null
                                readyToApply -> buildUnavailableMessage("mpv advanced settings")
                                else -> null
                            },
                    ),
                )
            }
        }
        return true
    }

    fun play() {
        runOnPlaybackThread {
            if (initialized &&
                mpv.isAvailable() &&
                loadState.shouldStartLoad(source.url)
            ) {
                loadState.requestLoad(source.url)
                loadCurrentSource()
            }
            if (!hasUsableVideoOutputTarget()) {
                resumeAfterSurfaceRestore = true
                updateState(
                    state.copy(
                        paused = true,
                        statusText = "Waiting for video surface",
                        error = null,
                    ),
                )
                return@runOnPlaybackThread
            }
            val success = pauseController.setPausedState(
                paused = false,
                initialized = initialized,
            )
            updateState(
                state.copy(
                    paused = !success,
                    statusText = if (success) "Playback resumed" else state.statusText,
                    error = if (success || !surfaceReady) null else buildUnavailableMessage("playback"),
                ),
            )
        }
    }

    fun pause() {
        runOnPlaybackThread {
            val success = pauseController.setPausedState(
                paused = true,
                initialized = initialized,
            )
            updateState(
                state.copy(
                    paused = if (success) true else state.paused,
                    statusText = if (success || !surfaceReady) "Playback paused" else state.statusText,
                    error = null,
                ),
            )
        }
    }

    fun seek(positionMs: Long): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val success = seekTo(positionMs)
            val sourceStable = loadState.isCurrentSourceStable(source.url)
            if (!success && !sourceStable) {
                Log.d(
                    TAG,
                    "suppressing seek error while source not stable positionMs=$positionMs url=${source.url}",
                )
                updateState(
                    state.copy(
                        positionMs = positionMs,
                        error = null,
                    ),
                )
                return@runOnPlaybackThread
            }
            updateState(
                state.copy(
                    positionMs = if (success) positionMs else state.positionMs,
                    statusText = if (success) "Seek applied" else state.statusText,
                    error = if (success) null else state.error ?: buildUnavailableMessage("seek"),
                ),
            )
        }
        return true
    }

    fun setAudioTrack(trackIndex: Int?, trackGuid: String?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val resolvedTrackId = resolveRequestedTrackId(
                type = "audio",
                trackIndex = trackIndex,
                trackGuid = trackGuid,
            )
            Log.d(
                TAG,
                "setAudioTrack requestedIndex=$trackIndex requestedGuid=${trackGuid.orEmpty()} resolvedId=$resolvedTrackId",
            )
            val success = if (initialized && mpv.isAvailable() && resolvedTrackId != null) {
                runCatching { mpv.setPropertyInt("aid", resolvedTrackId.toLong()) }.getOrDefault(false)
            } else {
                false
            }
            updateState(
                state.copy(
                    statusText = if (success) "Audio track changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("audio track selection"),
                ),
            )
        }
        return true
    }

    fun setSubtitleTrack(trackIndex: Int?, trackGuid: String?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val resolvedTrackId = resolveRequestedTrackId(
                type = "sub",
                trackIndex = trackIndex,
                trackGuid = trackGuid,
            )
            Log.d(
                TAG,
                "setSubtitleTrack requestedIndex=$trackIndex requestedGuid=${trackGuid.orEmpty()} resolvedId=$resolvedTrackId",
            )
            val success = if (initialized && mpv.isAvailable()) {
                trackSelectionController.onSubtitleTrackSelectedManually()
                when {
                    resolvedTrackId == null -> runCatching {
                        mpv.setPropertyString("sid", "no")
                    }.getOrDefault(false)
                    else -> runCatching {
                        mpv.setPropertyInt("sid", resolvedTrackId.toLong())
                    }.getOrDefault(false)
                }
            } else {
                false
            }
            updateState(
                state.copy(
                    statusText = if (success) "Subtitle track changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("subtitle selection"),
                ),
            )
        }
        return true
    }

    fun setExternalSubtitleFile(path: String): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val success = queueExternalSubtitle(path)
            updateState(
                state.copy(
                    statusText = if (success) {
                        if (loadState.sourceFileLoaded) "External subtitle loaded" else "External subtitle queued"
                    } else {
                        state.statusText
                    },
                    error = if (success) null else buildUnavailableMessage("external subtitle loading"),
                ),
            )
        }
        return true
    }

    fun setSubtitleDelay(delay: Double?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val normalized = delay ?: 0.0
            trackSelectionController.setSubtitleDelay(normalized)
            val success = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyDouble("sub-delay", normalized)
                }.getOrDefault(false)
            } else {
                true
            }
            Log.d(TAG, "setSubtitleDelay delay=$normalized success=$success")
            updateState(
                state.copy(
                    statusText = if (success) "Subtitle delay changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("subtitle delay"),
                ),
            )
        }
        return true
    }

    fun setAudioDelay(delay: Double?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val normalized = delay ?: 0.0
            trackSelectionController.setAudioDelay(normalized)
            val success =
                if (initialized && mpv.isAvailable()) {
                    runCatching {
                        mpv.setPropertyDouble("audio-delay", normalized)
                    }.getOrDefault(false)
                } else {
                    true
                }
            Log.d(TAG, "setAudioDelay delay=$normalized success=$success")
            updateState(
                state.copy(
                    statusText = if (success) "Audio delay changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("audio delay"),
                ),
            )
        }
        return true
    }

    fun setSubtitlePosition(position: Int?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val normalized = (position ?: DEFAULT_SUBTITLE_POSITION).coerceIn(0, 100)
            trackSelectionController.setSubtitlePosition(normalized)
            val success = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyInt("sub-pos", normalized.toLong())
                }.getOrDefault(false)
            } else {
                true
            }
            Log.d(TAG, "setSubtitlePosition position=$normalized success=$success")
            updateState(
                state.copy(
                    statusText = if (success) "Subtitle position changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("subtitle position"),
                ),
            )
        }
        return true
    }

    fun setSubtitleScale(scale: Double?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val normalized = (scale ?: 1.0).coerceIn(0.5, 2.5)
            trackSelectionController.setSubtitleScale(normalized)
            val success = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyDouble("sub-scale", normalized)
                }.getOrDefault(false)
            } else {
                true
            }
            Log.d(TAG, "setSubtitleScale scale=$normalized success=$success")
            updateState(
                state.copy(
                    statusText = if (success) "Subtitle size changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("subtitle size"),
                ),
            )
        }
        return true
    }

    fun resetSubtitleStyle(): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            trackSelectionController.resetSubtitleStyle()
            val delaySuccess = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyDouble("sub-delay", 0.0)
                }.getOrDefault(false)
            } else {
                true
            }
            val positionSuccess = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyInt("sub-pos", DEFAULT_SUBTITLE_POSITION.toLong())
                }.getOrDefault(false)
            } else {
                true
            }
            val scaleSuccess = if (initialized && mpv.isAvailable()) {
                runCatching {
                    mpv.setPropertyDouble("sub-scale", 1.0)
                }.getOrDefault(false)
            } else {
                true
            }
            val success = delaySuccess && positionSuccess && scaleSuccess
            Log.d(TAG, "resetSubtitleStyle success=$success")
            updateState(
                state.copy(
                    statusText = if (success) "Subtitle style reset" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("subtitle reset"),
                ),
            )
        }
        return true
    }

    fun setDecoderMode(mode: String?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val changed = videoOutputController.setDecoderMode(mode)
            syncVideoOutputState()
            if (changed) {
                val resumePositionMs =
                    if (source.reliableSeek) {
                        state.positionMs.coerceAtLeast(0L)
                    } else {
                        0L
                    }
                source = source.copy(startPositionMs = resumePositionMs)
                loadState.clearForRecovery(source.url)
                sessionGate.onVideoRecoveryTriggered()
                if (surfaceReady && surfaceAttached && currentSurfaceValid()) {
                    loadCurrentSource()
                    return@runOnPlaybackThread
                }
            }
            updateState(
                state.copy(
                    statusText = "Decoder mode changed",
                    error = null,
                ),
            )
        }
        return true
    }

    fun setDisplayAspectRatioMode(mode: String?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val changed = videoOutputController.setDisplayAspectRatioMode(
                mode = mode,
                initialized = initialized,
                available = mpv.isAvailable(),
            )
            syncVideoOutputState()
            if (!changed) return@runOnPlaybackThread
            updateState(
                state.copy(
                    statusText = "Display aspect ratio changed",
                    error = null,
                ),
            )
        }
        return true
    }

    fun setSpeed(speed: Double?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val success = if (initialized && mpv.isAvailable() && speed != null) {
                runCatching { mpv.setPropertyDouble("speed", speed) }.getOrDefault(false)
            } else {
                false
            }
            updateState(
                state.copy(
                    statusText = if (success) "Playback speed changed" else state.statusText,
                    error = if (success) null else buildUnavailableMessage("playback speed change"),
                ),
            )
        }
        return true
    }

    fun setVideoAdjustments(args: Map<String, Any?>): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val changed = videoAdjustmentController.update(args)
            val readyToApply = initialized && mpv.isAvailable()
            val applied = videoAdjustmentController.apply(initialized, mpv.isAvailable())
            if (!changed) return@runOnPlaybackThread
            updateState(
                state.copy(
                    statusText =
                        when {
                            applied -> "Video adjustments changed"
                            readyToApply -> state.statusText
                            else -> "Video adjustments queued"
                        },
                    error =
                        when {
                            applied -> null
                            readyToApply -> buildUnavailableMessage("video adjustments")
                            else -> null
                        },
                ),
            )
        }
        return true
    }

    fun onVideoOutputSurfaceAvailable(
        surface: Surface,
        generation: Long,
        width: Int,
        height: Int,
    ) {
        runOnPlaybackThread {
            surfaceReady = true
            lastSurfaceTransitionUptimeMs = SystemClock.uptimeMillis()
            Log.d(
                TAG,
                "surfaceAvailable generation=$generation size=${width}x$height created=$created initialized=$initialized mpvAvailable=${mpv.isAvailable()} url=${source.url}",
            )
            if (created && mpv.isAvailable()) {
                var initError: Throwable? = null
                val initSuccess = runCatching {
                    if (!initialized) {
                        if (!mpv.maybeInit()) {
                            false
                        } else {
                            initialized = true
                            if (!propertiesObserved) {
                                mpv.observeProperty("time-pos", 5)
                                mpv.observeProperty("demuxer-cache-duration", 5)
                                mpv.observeProperty("duration", 5)
                                mpv.observeProperty("pause", 4)
                                mpv.observeProperty("seeking", 4)
                                mpv.observeProperty("eof-reached", 4)
                                propertiesObserved = true
                            }
                            true
                        }
                    } else {
                        true
                    }
                }.onFailure { error ->
                    initError = error
                }.getOrDefault(false)
                if (!initSuccess) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to initialize mpv",
                            error = formatNativePlaybackError(
                                action = "surface initialization",
                                error = initError,
                                fallbackReason = runtimeBootstrap.consumeLastErrorMessage(),
                            ),
                        ),
                    )
                    return@runOnPlaybackThread
                }
                val attachSuccess = videoOutputController.onSurfaceAvailable(
                    surface = surface,
                    generation = generation,
                )
                syncVideoOutputState()
                if (!attachSuccess) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to attach mpv surface",
                            error = consumeVideoOutputErrorMessage("surface attachment"),
                        ),
                    )
                    return@runOnPlaybackThread
                }
                if (source.listenVideoModeEnabled) {
                    if (
                        !videoOutputController.enableListenVideoMode(
                            initialized = initialized,
                            available = mpv.isAvailable(),
                        )
                    ) {
                        syncVideoOutputState()
                        updateState(
                            state.copy(
                                ready = false,
                                listenVideoModeEnabled = true,
                                statusText = "Failed to enable listen video mode",
                                error = consumeVideoOutputErrorMessage("listen video mode"),
                            ),
                        )
                        return@runOnPlaybackThread
                    }
                    syncVideoOutputState()
                } else {
                    if (!restoreVideoTrackAfterSurfaceReady()) {
                        updateState(
                            state.copy(
                                ready = false,
                                statusText = "Failed to restore video track",
                                error = consumeVideoOutputErrorMessage("video track restore"),
                            ),
                        )
                        return@runOnPlaybackThread
                    }
                    if (!ensureVideoOutputReady()) {
                        updateState(
                            state.copy(
                                ready = false,
                                statusText = "Failed to configure video output",
                                error = consumeVideoOutputErrorMessage("video output configuration"),
                            ),
                        )
                        return@runOnPlaybackThread
                    }
                }
                if (pendingVideoRecoveryAfterSurfaceRestore) {
                    val recoveryReason = pendingVideoRecoveryReason ?: "surface-restored"
                    pendingVideoRecoveryAfterSurfaceRestore = false
                    pendingVideoRecoveryReason = null
                    recoverVideoOutputOnly("pending:$recoveryReason")
                }
            }
            if (loadState.hasLoadedSource(source.url)) {
                if (shouldForceSourceReloadAfterSurfaceRestore()) {
                    Log.w(
                        TAG,
                        "forcing source reload after surface restore hwdec=${preferredHwdecMode()} pipeline=${preferredColorPipeline()} source=[${source.debugSummary()}]",
                    )
                    loadState.clearForRecovery(source.url)
                    loadCurrentSource()
                    return@runOnPlaybackThread
                }
                val shouldResume = resumeAfterSurfaceRestore
                val resumed = if (shouldResume && initialized && mpv.isAvailable()) {
                    pauseController.setPausedState(
                        paused = false,
                        initialized = initialized,
                    )
                } else {
                    false
                }
                resumeAfterSurfaceRestore = false
                pendingAutoResumeAfterSurfaceRestore = false
                updateState(
                    state.copy(
                        ready = true,
                        paused = if (shouldResume) !resumed else state.paused,
                        statusText = if (resumed) {
                            "Playback resumed"
                        } else if (state.paused) {
                            "Playback paused"
                        } else {
                            "Playback resumed"
                        },
                        error = if (resumed || !shouldResume) {
                            null
                        } else {
                            buildUnavailableMessage("playback resume")
                        },
                    ),
                )
                if (shouldResume && !resumed) {
                    pendingAutoResumeAfterSurfaceRestore = true
                    schedulePlaybackResumeCheck("surface-restored")
                }
                scheduleVideoOutputSanityCheck("surface-restored")
                return@runOnPlaybackThread
            }
            if (loadState.shouldRunDeferredLoad(source.url)) {
                loadCurrentSource()
            }
        }
    }

    fun onVideoOutputSurfaceSizeChanged(
        surface: Surface,
        generation: Long,
        width: Int,
        height: Int,
    ) = Unit

    fun onVideoOutputSurfaceDestroyed(generation: Long) {
        runOnPlaybackThread {
            invalidateVideoOutputSanityChecks()
            lastSurfaceTransitionUptimeMs = SystemClock.uptimeMillis()
            if (shouldPreserveSessionForHostHandoff()) {
                Log.d(
                    TAG,
                    "surfaceDestroyed generation=$generation preserving mpv session during host handoff host=${hostActivity?.javaClass?.simpleName}",
                )
                videoOutputController.detachSurfaceForHandoff()
                syncVideoOutputState()
                surfaceReady = false
                surfaceAttached = false
                videoOutputReady = false
                resumeAfterSurfaceRestore = false
                pendingAutoResumeAfterSurfaceRestore = false
                updateState(
                    state.copy(
                        ready = false,
                        statusText = "Player host switching",
                        error = null,
                    ),
                )
                return@runOnPlaybackThread
            }
            val wasPlaying = !state.paused
            if (state.positionMs > 0L) {
                restoreCoordinator.onSeekQueued(state.positionMs)
            }
            val pausedForSurfaceLoss = if (initialized && mpv.isAvailable() && wasPlaying) {
                runCatching {
                    mpv.setPropertyBoolean("pause", true)
                }.getOrDefault(false)
            } else {
                false
            }
            resumeAfterSurfaceRestore = wasPlaying && pausedForSurfaceLoss
            pendingAutoResumeAfterSurfaceRestore = false
            sessionGate.onSurfaceLost()
            videoOutputController.onSurfaceDestroyed(
                initialized = initialized,
                available = mpv.isAvailable(),
                generation = generation,
            )
            syncVideoOutputState()
            updateState(
                state.copy(
                    ready = false,
                    paused = if (pausedForSurfaceLoss) true else state.paused,
                    statusText = if (pausedForSurfaceLoss || state.paused) {
                        "Playback paused"
                    } else {
                        "Video surface released"
                    },
                    error = null,
                ),
            )
        }
    }

    private fun loadCurrentSource() {
        if (!sessionGate.canStartLoad()) {
            loadState.requestLoad(source.url)
            Log.d(
                TAG,
                "deferring loadCurrentSource while switch active generation=${sessionGate.currentSnapshot().generation} url=${source.url}",
            )
            return
        }
        syncVideoOutputState()
        loadState.requestLoad(source.url)
        advancedSettingsController.apply(initialized, mpv.isAvailable(), source)
        resumeAfterSurfaceRestore = false
        clearVideoStreamFailure()
        clearProxyOpenFailure()
        verboseLog {
            "loadCurrentSource initialized=$initialized surfaceReady=$surfaceReady surfaceAttached=$surfaceAttached videoOutputReady=$videoOutputReady hwdec=${preferredHwdecMode()} pipeline=${preferredColorPipeline()} hdr=${source.isHdrLikely()} url=${source.url}"
        }
        if (!created || !mpv.isAvailable()) {
            updateState(
                state.copy(
                    ready = false,
                    statusText = "Native player unavailable",
                    error = buildUnavailableMessage("player initialization"),
                ),
            )
            return
        }
        if (source.url.isBlank()) {
            updateState(
                state.copy(
                    ready = true,
                    statusText = "Waiting for playback source",
                    error = "Playback URL has not been provided yet",
                ),
            )
            return
        }
        if (!hasUsableVideoOutputTarget()) {
            updateState(
                state.copy(
                    ready = true,
                    statusText = "Waiting for video surface",
                    error = null,
                ),
            )
            return
        }
        if (!restoreVideoTrackAfterSurfaceReady()) {
            updateState(
                state.copy(
                    ready = false,
                    statusText = "Video track unavailable",
                    error = consumeVideoOutputErrorMessage("video track"),
                ),
            )
            return
        }
        if (!initialized) {
            updateState(
                state.copy(
                    ready = true,
                    statusText = "Preparing video renderer",
                    error = null,
                ),
            )
            return
        }
        if (!ensureVideoTrackSelected()) {
            updateState(
                state.copy(
                    ready = false,
                    statusText = "Video track unavailable",
                    error = consumeVideoOutputErrorMessage("video track"),
                ),
            )
            return
        }
        if (!ensureVideoOutputReady()) {
            updateState(
                state.copy(
                    ready = false,
                    statusText = "Video output unavailable",
                    error = consumeVideoOutputErrorMessage("video output"),
                ),
            )
            return
        }

        val playbackTarget = sourceResolver.prepare(source)
        if (loadState.isSameLoadInFlight(source.url, playbackTarget.url)) {
            Log.d(
                TAG,
                "skip duplicate loadCurrentSource source=${source.url} playback=${playbackTarget.url}",
            )
            return
        }
        sessionGate.beginLoad(playbackTarget.url)
        observedCacheDurationMs = 0L
        val initialStartPositionMs = preferredResumePositionMs()
        val loadCommand = MpvLoadfileOptions.buildCommand(
            url = playbackTarget.url,
            headers = playbackTarget.headers,
            disableTlsVerify = playbackTarget.disableTlsVerify,
            startPositionMs = initialStartPositionMs,
        )
        var loadError: Throwable? = null
        val loaded = runCatching {
            verboseLog {
                "loadfile remote=${source.url} playback=${playbackTarget.url} nativeProxy=${playbackTarget.viaNativeProxy} headers=${playbackTarget.headers.isNotEmpty()} disableTls=${playbackTarget.disableTlsVerify}"
            }
            mpv.command(loadCommand) >= 0
        }.onFailure { error ->
            loadError = error
        }.getOrDefault(false)
        sessionGate.onLoadCommandFinished(loaded)
        if (loaded) {
            loadState.onLoadCommandStarted(source.url, playbackTarget.url)
            // Seed track selection state before building the restore plan so
            // mode switches/reloads can correctly carry external subtitles.
            trackSelectionController.onLoadRequested(source)
            restoreCoordinator.onLoadRequested(
                0L,
                trackSelectionController.hasPendingExternalSubtitle(),
            )
        } else {
            loadState.onLoadCommandFailed()
        }

        updateState(
            state.copy(
                ready = true,
                nativeLibLoaded = mpv.isAvailable(),
                paused = if (loaded) state.paused else true,
                positionMs = source.startPositionMs,
                bufferedPositionMs = source.startPositionMs.coerceAtLeast(0L),
                listenVideoModeEnabled = source.listenVideoModeEnabled,
                statusText = if (loaded) {
                    "Source loaded"
                } else {
                    "mpv-android runtime rejected source"
                },
                error = if (loaded) {
                    null
                } else {
                    formatNativePlaybackError(
                        action = "source loading",
                        error = loadError,
                        fallbackReason = buildUnavailableMessage("source loading"),
                    )
                },
            ),
        )
        if (loaded && source.listenVideoModeEnabled) {
            val applied =
                videoOutputController.enableListenVideoMode(
                    initialized = initialized,
                    available = mpv.isAvailable(),
                )
            syncVideoOutputState()
            if (applied) {
                updateState(
                    state.copy(
                        listenVideoModeEnabled = true,
                        statusText = "Listen video mode enabled",
                        error = null,
                    ),
                )
            } else {
                val errorMessage = consumeVideoOutputErrorMessage("listen video mode")
                source = source.copy(listenVideoModeEnabled = false)
                updateState(
                    state.copy(
                        listenVideoModeEnabled = false,
                        statusText = "Source loaded",
                        error = errorMessage,
                    ),
                )
            }
        }
    }

    private fun currentSurfaceValid(): Boolean {
        return videoOutputController.isSurfaceValid()
    }

    private fun hasUsableVideoOutputTarget(): Boolean {
        syncVideoOutputState()
        return videoOutputController.hasUsableVideoOutputTarget()
    }

    private fun preferredHwdecMode(): String {
        syncVideoOutputState()
        return videoOutputController.preferredHwdecMode(source)
    }

    private fun preferredColorPipeline(): VideoColorPipeline {
        syncVideoOutputState()
        return videoOutputController.preferredColorPipeline(source)
    }

    private fun shouldForceSourceReloadAfterSurfaceRestore(): Boolean {
        return videoOutputController.shouldForceSourceReloadAfterSurfaceRestore(source)
    }

    private fun ensureVideoOutputReady(): Boolean {
        val success = videoOutputController.ensureVideoOutputReady(
            initialized = initialized,
            available = mpv.isAvailable(),
            source = source,
        )
        syncVideoOutputState()
        return success
    }

    private fun suspendVideoOutputForSurfaceLoss() {
        videoOutputController.onSurfaceDestroyed(initialized, mpv.isAvailable())
        syncVideoOutputState()
    }

    private fun restoreVideoTrackAfterSurfaceReady(): Boolean {
        val success = videoOutputController.restoreVideoTrackAfterSurfaceReady(
            initialized = initialized,
            available = mpv.isAvailable(),
        )
        syncVideoOutputState()
        return success
    }

    private fun ensureVideoTrackSelected(): Boolean {
        val success = videoOutputController.ensureVideoTrackSelected(
            initialized = initialized,
            available = mpv.isAvailable(),
        )
        syncVideoOutputState()
        return success
    }

    private fun recoverVideoOutputOnly(reason: String) {
        videoOutputController.recoverVideoOutputOnly(
            reason = reason,
            initialized = initialized,
            available = mpv.isAvailable(),
        )
        syncVideoOutputState()
        restoreVideoTrackAfterSurfaceReady()
        ensureVideoOutputReady()
    }

    private fun reloadCurrentSource(reason: String) {
        Log.w(TAG, "reload current source reason=$reason playback=${loadState.activePlaybackUrl}")
        if (source.url.isNotBlank()) {
            resumeAfterSurfaceRestore = false
            loadState.clearForRecovery(source.url)
            sessionGate.onVideoRecoveryTriggered()
            loadCurrentSource()
        }
    }

    private fun preferredResumePositionMs(): Long {
        if (!source.reliableSeek) return 0L
        val pending = restoreCoordinator.pendingSeekPositionMs
        return if (pending > 0L) pending else source.startPositionMs
    }

    private fun handleRestorePlan(plan: MpvPlaybackRestorePlan, reason: String) {
        val execution = recoveryOrchestrator.resolveRestorePlan(
            plan = plan,
            suppressRetryRecovery = shouldSuppressAutomaticRecovery(),
        )
        if (execution.suppressRetryRecovery) {
            Log.d(TAG, "suppressing retry video recovery reason=$reason")
            return
        }
        when {
            execution.recoverVideoOutput -> {
                Log.w(TAG, "retry video recovery reason=$reason")
                recoverVideoOutputOnly(reason)
            }
            execution.seekPositionMs != null && execution.seekPositionMs > 0L -> {
                val success = seekTo(execution.seekPositionMs)
                if (!success) {
                    if (loadState.isCurrentSourceStable(source.url)) {
                        Log.w(TAG, "restore seek failed reason=$reason target=${execution.seekPositionMs}")
                    } else {
                        Log.d(
                            TAG,
                            "suppressing restore seek failure while source not stable reason=$reason target=${execution.seekPositionMs}",
                        )
                    }
                }
            }
            execution.applyExternalSubtitle -> {
                applyPendingExternalSubtitle()
            }
        }
    }

    private fun buildUnavailableMessage(action: String): String {
        if (!mpv.isAvailable()) {
            val reason = mpv.loadErrorMessage() ?: "native libraries are missing"
            return "mpv-android runtime is unavailable, cannot handle $action: $reason"
        }
        return "mpv-android runtime rejected $action"
    }

    private fun consumeVideoOutputErrorMessage(action: String): String {
        return videoOutputController.consumeLastErrorMessage()
            ?: buildUnavailableMessage(action)
    }

    private fun updateState(next: MpvPlayerState) {
        val enriched =
            next.copy(
                nativeProxySessionId = sourceResolver.activeProxySessionId,
                cacheResourceKey = sourceResolver.activeCacheResourceKey,
            )
        state = enriched
        syncDanmakuOcclusionRuntime()
        stateReporter.dispatch(enriched, source.title)
    }

    private fun isCurrentSourceStable(): Boolean {
        return loadState.isCurrentSourceStable(source.url)
    }

    private fun shouldSuppressAutomaticRecovery(): Boolean {
        return sessionGate.shouldSuppressRetryRecovery(
            internalSeekOrRestore = restoreCoordinator.isSeekingOrRestoringVideo,
            surfaceUnavailable = !hasUsableVideoOutputTarget(),
            sourceStable = isCurrentSourceStable(),
        )
    }

    private fun shouldIgnoreCurrentEndFile(): Boolean {
        return sessionGate.shouldIgnoreEndFile(
            internalSeekOrRestore = restoreCoordinator.isSeekingOrRestoringVideo,
            surfaceUnavailable = !hasUsableVideoOutputTarget(),
            sourceStable = isCurrentSourceStable(),
        )
    }

    private fun buildRecoveryRuntimeSnapshot(): PlaybackRecoveryRuntimeSnapshot {
        return PlaybackRecoveryRuntimeSnapshot(
            sourceSwitchInProgress = sessionGate.currentSnapshot().sourceSwitchInProgress,
            sourceFileLoaded = loadState.sourceFileLoaded,
            videoStreamLost = videoStreamLost,
            suppressRetryRecovery = shouldSuppressAutomaticRecovery(),
            hlsSubResourceLog = false,
            hasUsableVideoOutputTarget = hasUsableVideoOutputTarget(),
            videoOutputReady = videoOutputReady,
            surfaceTransitionInProgress = isSurfaceTransitionInProgress(),
            currentSourceStable = isCurrentSourceStable(),
            positionMs = state.positionMs,
            durationMs = state.durationMs,
            audioOnlyVideoState = isAudioOnlyVideoState(),
        )
    }

    private fun applyRecoveryExecution(execution: PlaybackRecoveryExecution, reason: String) {
        execution.queueSeekPositionMs?.takeIf { it > 0L }?.let(restoreCoordinator::onSeekQueued)
        if (execution.markVideoStreamLost) {
            videoStreamLost = true
            videoStreamLossReason = execution.videoStreamLossReason ?: reason
            resumeAfterSurfaceRestore = false
        }
        if (execution.clearSourceFileLoaded) {
            loadState.clearSourceFileLoaded()
        }
        if (execution.recoverVideoOutput || execution.reloadCurrentSource) {
            videoOutputReady = false
            sessionGate.onVideoRecoveryTriggered()
            val action = when {
                execution.reloadCurrentSource -> PlaybackRecoveryAction.RELOAD_CURRENT_FILE
                execution.recoverVideoOutput -> PlaybackRecoveryAction.RECOVER_VIDEO_OUTPUT
                else -> PlaybackRecoveryAction.IGNORE
            }
            Log.w(
                TAG,
                "playback recovery action=$action reason=\"$reason\" hwdec=${preferredHwdecMode()} pipeline=${preferredColorPipeline()}",
            )
        }
        if (execution.recoverVideoOutput && !hasUsableVideoOutputTarget()) {
            pendingVideoRecoveryAfterSurfaceRestore = true
            pendingVideoRecoveryReason = reason
        }
        if (execution.reloadCurrentSource && isSurfaceTransitionInProgress()) {
            Log.w(
                TAG,
                "deferring source reload during surface transition reason=$reason ready=$surfaceReady attached=$surfaceAttached outputReady=$videoOutputReady",
            )
            if (execution.recoverVideoOutput || hasUsableVideoOutputTarget()) {
                recoverVideoOutputOnly("deferred:$reason")
            }
            scheduleVideoOutputSanityCheck("deferred-reload", 900L)
            return
        }
        if (execution.recoverVideoOutput) {
            recoverVideoOutputOnly(reason)
        }
        if (execution.reloadCurrentSource) {
            reloadCurrentSource(reason)
        }
    }

    private fun syncVideoOutputState() {
        surfaceReady = videoOutputController.surfaceReady
        surfaceAttached = videoOutputController.surfaceAttached
        videoOutputReady = videoOutputController.videoOutputReady
        videoTrackSuspended = videoOutputController.videoTrackSuspended
        activeHwdecMode = videoOutputController.activeHwdecMode
        forcedHwdecMode = videoOutputController.forcedHwdecMode
        forcedColorPipeline = videoOutputController.forcedColorPipeline
        activeColorPipeline = videoOutputController.activeColorPipeline
        syncDanmakuOcclusionRuntime()
    }

    private fun syncDanmakuOcclusionRuntime() {
        danmakuOcclusionController.updatePlaybackState(
            paused = state.paused,
            sourceLoaded = loadState.sourceFileLoaded,
            surfaceReady = surfaceReady,
            videoOutputReady = videoOutputReady,
        )
    }

    private fun isSurfaceTransitionInProgress(): Boolean {
        val lastTransitionUptimeMs = lastSurfaceTransitionUptimeMs
        if (lastTransitionUptimeMs <= 0L) return false
        val withinGraceWindow =
            (SystemClock.uptimeMillis() - lastTransitionUptimeMs) < SURFACE_TRANSITION_GRACE_MS
        if (!withinGraceWindow) {
            return false
        }
        return !surfaceReady || !surfaceAttached || !currentSurfaceValid() || !videoOutputReady
    }

    private fun shouldPreserveSessionForHostHandoff(): Boolean {
        return PlayerLayoutHandoffCoordinator.shouldPreserveFor(hostActivity)
    }

    private fun buildPlaybackDiagnostics(): Map<String, Any?> {
        return stateReporter.buildDiagnostics(
            diagnosticsSnapshotFactory.build(
                args = PlaybackDiagnosticsSnapshotArgs(
                    state = state,
                    source = source,
                    audioOnlyVideoState = isAudioOnlyVideoState(),
                    surfaceReady = surfaceReady,
                    surfaceAttached = surfaceAttached,
                    surfaceValid = currentSurfaceValid(),
                    videoOutputReady = videoOutputReady,
                    videoTrackSuspended = videoTrackSuspended,
                    videoStreamLost = videoStreamLost,
                    videoStreamLossReason = videoStreamLossReason,
                    proxyOpenFailed = proxyOpenFailed,
                    proxyOpenFailureReason = proxyOpenFailureReason,
                    resumeAfterSurfaceRestore = resumeAfterSurfaceRestore,
                    activeHwdecMode = activeHwdecMode,
                    forcedHwdecMode = forcedHwdecMode,
                    activeColorPipeline = activeColorPipeline,
                    forcedColorPipeline = forcedColorPipeline,
                    preferredHwdecMode = preferredHwdecMode(),
                    preferredColorPipeline = preferredColorPipeline(),
                    displayProfile = displayProfile,
                    deviceProfile = deviceProfile,
                ),
                loadState = loadState,
            ),
        )
    }

    private fun buildChapterList(): List<Map<String, Any?>> {
        return chapterSnapshotBuilder.buildChapterList()
    }

    private fun buildTrackSnapshotMap(): Map<String, Any?> {
        val trackEntries = readRuntimeTrackEntries()
        val selectedAudioId =
            trackEntries.firstOrNull { it.type == "audio" && it.selected }?.id
                ?: currentTrackId("aid")
        val selectedSubtitleId =
            trackEntries.firstOrNull { it.type == "sub" && it.selected }?.id
                ?: currentTrackId("sid")
        val mediaGuid = source.mediaGuid.trim()
        val audioTracks = mutableListOf<Map<String, Any?>>()
        val subtitleTracks = mutableListOf<Map<String, Any?>>()
        var fallbackAudioGuid = ""

        for (entry in trackEntries) {
            when (entry.type) {
                "audio" -> {
                    val guid = "mpv-audio:${entry.id}"
                    if (fallbackAudioGuid.isEmpty()) {
                        fallbackAudioGuid = guid
                    }
                    val selected = selectedAudioId == entry.id
                    audioTracks +=
                        mapOf(
                            "mediaGuid" to mediaGuid,
                            "guid" to guid,
                            "title" to entry.title,
                            "codecName" to entry.codec,
                            "profile" to "",
                            "language" to entry.language,
                            "audioType" to "",
                            "channelLayout" to entry.channelLayout,
                            "channels" to entry.channels,
                            "sampleRate" to entry.sampleRate,
                            "bps" to entry.bitrate,
                            "index" to entry.id,
                            "isDefault" to if (selected || (selectedAudioId == null && audioTracks.isEmpty())) 1 else 0,
                        )
                }
                "sub" -> {
                    val guid = "mpv-subtitle:${entry.id}"
                    val selected = selectedSubtitleId == entry.id
                    subtitleTracks +=
                        mapOf(
                            "mediaGuid" to mediaGuid,
                            "guid" to guid,
                            "title" to entry.title,
                            "codecName" to entry.codec,
                            "format" to entry.codec,
                            "language" to entry.language,
                            "index" to entry.id,
                            "isDefault" to if (selected || (selectedSubtitleId == null && subtitleTracks.isEmpty())) 1 else 0,
                            "forced" to if (entry.forced) 1 else 0,
                            "isExternal" to if (entry.external) 1 else 0,
                            "extraFile" to if (entry.external) 1 else 0,
                            "isBitmap" to if (entry.bitmap) 1 else 0,
                        )
                }
            }
        }

        val selectedAudioGuid =
            when {
                selectedAudioId != null && selectedAudioId > 0 -> "mpv-audio:$selectedAudioId"
                fallbackAudioGuid.isNotEmpty() -> fallbackAudioGuid
                else -> ""
            }
        val selectedSubtitleGuid =
            when {
                selectedSubtitleId != null && selectedSubtitleId > 0 -> "mpv-subtitle:$selectedSubtitleId"
                else -> ""
            }
        return mapOf(
            "audioTracks" to audioTracks,
            "subtitleTracks" to subtitleTracks,
            "selectedAudioGuid" to selectedAudioGuid,
            "selectedSubtitleGuid" to selectedSubtitleGuid,
        )
    }

    private fun readRuntimeTrackEntries(): List<RuntimeTrackEntry> {
        val entries = mutableListOf<RuntimeTrackEntry>()
        val reportedCount = rawMpvInt("track-list/count")?.toInt()?.coerceIn(0, 64) ?: 0
        val maxIndex = if (reportedCount > 0) reportedCount else 32
        var emptyStreak = 0
        var audioOrdinal = 0
        var subtitleOrdinal = 0
        for (index in 0 until maxIndex) {
            val type = currentMpvString("track-list/$index/type")?.lowercase() ?: ""
            if (type.isEmpty()) {
                emptyStreak += 1
                if (reportedCount <= 0 && emptyStreak >= 3 && entries.isNotEmpty()) {
                    break
                }
                continue
            }
            emptyStreak = 0
            if (type != "audio" && type != "sub") {
                continue
            }
            val trackId =
                when (type) {
                    "audio" -> {
                        audioOrdinal += 1
                        audioOrdinal
                    }
                    "sub" -> {
                        subtitleOrdinal += 1
                        subtitleOrdinal
                    }
                    else -> index + 1
                }
            val externalFileName =
                currentMpvString("track-list/$index/external-filename").orEmpty()
            entries +=
                RuntimeTrackEntry(
                    id = trackId,
                    type = type,
                    title = currentMpvString("track-list/$index/title").orEmpty(),
                    language = currentMpvString("track-list/$index/lang").orEmpty(),
                    codec = currentMpvString("track-list/$index/codec").orEmpty(),
                    external =
                        externalFileName.isNotEmpty() ||
                            currentMpvFlag("track-list/$index/external") == true,
                    selected =
                        currentMpvFlag("track-list/$index/selected") == true ||
                            currentMpvFlag("track-list/$index/current") == true,
                    forced = currentMpvFlag("track-list/$index/forced") == true,
                    bitmap = currentMpvFlag("track-list/$index/image") == true,
                    channels = currentMpvInt("track-list/$index/demux-channel-count")?.toInt() ?: 0,
                    channelLayout = currentMpvString("track-list/$index/demux-channels").orEmpty(),
                    sampleRate = currentMpvInt("track-list/$index/demux-samplerate")?.toInt() ?: 0,
                    bitrate = currentMpvInt("track-list/$index/demux-bitrate")?.toInt() ?: 0,
                )
        }
        return entries
    }

    private fun resolveRequestedTrackId(
        type: String,
        trackIndex: Int?,
        trackGuid: String?,
    ): Int? {
        val normalizedType =
            when (type.trim().lowercase()) {
                "audio" -> "audio"
                "sub", "subtitle" -> "sub"
                else -> return trackIndex?.takeIf { it > 0 }
            }
        val normalizedGuid = trackGuid?.trim().orEmpty()
        if (normalizedGuid.isNotEmpty()) {
            val parsedFromGuid = when {
                normalizedType == "audio" && normalizedGuid.startsWith("mpv-audio:") ->
                    normalizedGuid.substringAfter("mpv-audio:").toIntOrNull()
                normalizedType == "sub" && normalizedGuid.startsWith("mpv-subtitle:") ->
                    normalizedGuid.substringAfter("mpv-subtitle:").toIntOrNull()
                else -> null
            }
            if (parsedFromGuid != null && parsedFromGuid > 0) {
                val runtimeMatch =
                    readRuntimeTrackEntries().firstOrNull {
                        it.type == normalizedType && it.id == parsedFromGuid
                    }
                if (runtimeMatch != null) {
                    return runtimeMatch.id
                }
            }
        }
        return trackIndex?.takeIf { it > 0 }
    }

    private fun runOnMainThread(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private fun runOnPlaybackThread(block: () -> Unit) {
        if (disposed) return
        if (Looper.myLooper() == playbackThread.looper) {
            block()
        } else {
            playbackHandler.post {
                if (!disposed) {
                    block()
                }
            }
        }
    }

    private fun <T> callOnPlaybackThread(block: () -> T): T {
        if (Looper.myLooper() == playbackThread.looper) {
            return block()
        }
        val task = FutureTask(block)
        playbackHandler.post(task)
        return task.get()
    }

    private fun initializeMpv() {
        if (!mpv.isAvailable()) {
            updateState(
                state.copy(
                    ready = false,
                    nativeLibLoaded = false,
                    statusText = "mpv-android native runtime missing",
                    error = mpv.loadErrorMessage(),
                ),
            )
            return
        }

        val ready = runtimeBootstrap.initialize(source.playbackSpeed)
        created = ready

        initialized = false
        propertiesObserved = false
        Log.d(TAG, "initializeMpv done ready=$ready created=$created")
        updateState(
            state.copy(
                ready = ready,
                nativeLibLoaded = mpv.isAvailable(),
                statusText = if (ready) {
                    if (!surfaceReady) {
                        "Waiting for video surface"
                    } else if (source.url.isBlank()) {
                        "Waiting for playback source"
                    } else {
                        "Preparing playback"
                    }
                } else {
                    "Failed to initialize mpv-android runtime"
                },
                error = if (ready) {
                    null
                } else {
                    runtimeBootstrap.consumeLastErrorMessage()
                        ?: buildUnavailableMessage("player initialization")
                },
            ),
        )
    }

    private fun seekTo(positionMs: Long): Boolean {
        if (!initialized || !mpv.isAvailable()) return false
        if (!hasUsableVideoOutputTarget()) {
            restoreCoordinator.onSeekQueued(positionMs)
            Log.w(TAG, "seek queued while surface unavailable positionMs=$positionMs")
            return true
        }
        restoreCoordinator.onSeekQueued(positionMs)
        if (videoStreamLost) {
            Log.w(
                TAG,
                "seek rerouted to recovery positionMs=$positionMs reason=${videoStreamLossReason ?: "video stream lost"}",
            )
            reloadCurrentSource(videoStreamLossReason ?: "video stream lost during seek")
            return true
        }
        val seconds = positionMs / 1000.0
        var seekError: Throwable? = null
        return runCatching {
            mpv.command(
                arrayOf(
                    "seek",
                    seconds.toString(),
                    "absolute+exact",
                ),
            ) >= 0
        }.onFailure { error ->
            seekError = error
        }.getOrDefault(false)
            .also { success ->
                if (!success) {
                    updateState(
                        state.copy(
                            statusText = "Seek failed",
                            error = formatNativePlaybackError("seek", seekError),
                        ),
                    )
                }
            }
    }

    override fun eventProperty(property: String, value: Boolean) {
        runOnPlaybackThread {
            when (property) {
                "pause" -> {
                    if (value) {
                        pendingAutoResumeAfterSurfaceRestore = false
                    }
                    updateState(state.copy(paused = value, error = null))
                }
                "seeking" -> handleRestorePlan(
                    restoreCoordinator.onSeekingChanged(value),
                    "property:seeking=$value",
                )
                "eof-reached" -> {
                    if (shouldSuppressAutomaticRecovery()) {
                        Log.d(TAG, "ignoring eof-reached=$value during source switch")
                    } else {
                        handleRestorePlan(
                            restoreCoordinator.onVideoEofChanged(
                                eofReached = value,
                                positionMs = state.positionMs,
                                durationMs = state.durationMs,
                            ),
                            "property:eof-reached=$value",
                        )
                    }
                }
            }
        }
    }

    override fun eventProperty(property: String, value: Double) {
        runOnPlaybackThread {
            when (property) {
                "time-pos" -> {
                    val positionMs = (value * 1000.0).toLong()
                    updateState(
                        state.copy(
                            positionMs = positionMs,
                            bufferedPositionMs = bufferedPositionFor(positionMs),
                            error = null,
                        ),
                    )
                    handleRestorePlan(
                        restoreCoordinator.onTimePosition(positionMs),
                        "property:time-pos",
                    )
                    maybeTriggerAutomaticFilterFallback()
                }
                "demuxer-cache-duration" -> {
                    observedCacheDurationMs = (value * 1000.0).toLong().coerceAtLeast(0L)
                    updateState(
                        state.copy(
                            bufferedPositionMs = bufferedPositionFor(state.positionMs),
                            error = null,
                        ),
                    )
                }
                "duration" -> updateState(
                    state.copy(
                        durationMs = (value * 1000.0).toLong(),
                        error = null,
                    ),
                )
            }
        }
    }

    private fun bufferedPositionFor(positionMs: Long): Long {
        val demuxerBufferedPositionMs = if (positionMs <= 0L) {
            observedCacheDurationMs.coerceAtLeast(0L)
        } else {
            (positionMs + observedCacheDurationMs).coerceAtLeast(positionMs)
        }
        val extremeBufferedPositionMs = sourceResolver.activeBufferedPositionMs(
            source = source,
            positionMs = positionMs,
            durationMs = state.durationMs,
        ) ?: 0L
        return maxOf(demuxerBufferedPositionMs, extremeBufferedPositionMs)
    }

    override fun event(eventId: Int) {
        runOnPlaybackThread {
            when (eventId) {
                mpv.onFileLoaded() -> {
                    sessionGate.onFileLoaded()
                    val completedSourceUrl = loadState.takeLoadingSourceUrl()
                    if (completedSourceUrl != null && completedSourceUrl != source.url) {
                        Log.w(
                            TAG,
                            "ignoring stale file-loaded loaded=$completedSourceUrl current=${source.url}",
                        )
                        if (loadState.shouldRunDeferredLoad(source.url)) {
                            loadCurrentSource()
                        }
                        return@runOnPlaybackThread
                    }
                    if (completedSourceUrl == null || completedSourceUrl == source.url) {
                        loadState.markCurrentSourceLoaded(source.url)
                    }
                    resumeAfterSurfaceRestore = false
                    clearVideoStreamFailure()
                    clearProxyOpenFailure()
                    sourceResolver.releaseRetiredSessions()
                    trackSelectionController.onFileLoaded()
                    videoAdjustmentController.onFileLoaded(initialized, mpv.isAvailable())
                    handleRestorePlan(
                        restoreCoordinator.onSourceFileLoaded(),
                        "event:file-loaded",
                    )
                    val pausedAfterFileLoaded = currentMpvFlag("pause") ?: false
                    updateState(
                        state.copy(
                            paused = pausedAfterFileLoaded,
                            statusText = if (pausedAfterFileLoaded) {
                                "Playback paused"
                            } else {
                                "Playback started"
                            },
                            error = null,
                        ),
                    )
                    if (loadState.shouldRunDeferredLoad(source.url)) {
                        loadCurrentSource()
                    }
                    scheduleVideoOutputSanityCheck("file-loaded")
                }
                mpv.onEndFile() -> {
                    if (proxyOpenFailed) {
                        loadState.clearSourceFileLoaded()
                        sessionGate.onProxyFailure()
                        updateState(
                            state.copy(
                                paused = true,
                                statusText = "Proxy stream open failed",
                                error = proxyOpenFailureReason,
                            ),
                        )
                        return@runOnPlaybackThread
                    }
                    val prematureEndWithoutEof =
                        !restoreCoordinator.hasReachedVideoEof &&
                            state.durationMs > 0L &&
                            state.positionMs <= 1000L
                    if (prematureEndWithoutEof) {
                        Log.w(
                            TAG,
                            "ignoring spurious end-file before eof positionMs=${state.positionMs} durationMs=${state.durationMs}",
                        )
                        return@runOnPlaybackThread
                    }
                    if (shouldIgnoreCurrentEndFile()) {
                        verboseLog {
                            "ignoring end-file during source switch remote=${source.url} playback=${loadState.activePlaybackUrl} generation=${sessionGate.currentSnapshot().generation}"
                        }
                        return@runOnPlaybackThread
                    }
                    if (isAudioOnlyVideoState()) {
                        recoverFromAudioOnlyVideoState("event:end-file")
                        return@runOnPlaybackThread
                    }
                    if (!isNearPlaybackCompletion()) {
                        Log.w(
                            TAG,
                            "unexpected end-file before completion positionMs=${state.positionMs} durationMs=${state.durationMs}",
                        )
                        handleRestorePlan(
                            MpvPlaybackRestorePlan(retryVideoRecovery = true),
                            "event:end-file",
                        )
                        return@runOnPlaybackThread
                    }
                    loadState.clearSourceFileLoaded()
                    sessionGate.onPlaybackEnded()
                    updateState(
                        state.copy(
                            paused = true,
                            statusText = "Playback ended",
                            error = null,
                        ),
                    )
                }
            }
        }
    }

    override fun logMessage(prefix: String, level: Int, text: String) {
        runOnPlaybackThread {
            val message = text.trim()
            val lowerMessage = message.lowercase()
            if (
                ENABLE_MPV_VERBOSE_LOGS ||
                    level <= 1 ||
                    lowerMessage.contains("tls:") ||
                    lowerMessage.contains("certificate") ||
                    lowerMessage.contains("failed to open") ||
                    lowerMessage.contains("opening failed") ||
                    lowerMessage.contains("video output still null") ||
                    lowerMessage.contains("retry video recovery")
            ) {
                Log.d(TAG, "mpv[$level][$prefix] $message")
            }
            maybeMarkProxyOpenFailure(prefix, message, lowerMessage)
            maybeTriggerHdrHwdecFallback(lowerMessage)
            maybeTriggerAutomaticSoftwareDecoderFallback(lowerMessage)
            applyRecoveryDecision(lowerMessage)
            if (
                lowerMessage.contains("font") ||
                lowerMessage.contains("fallback") ||
                lowerMessage.contains("subtitle decoder") ||
                lowerMessage.contains("srt")
            ) {
                verboseLog { "subtitle-debug[$level][$prefix] $message" }
            }
            if (level <= 1 && !shouldSuppressAutomaticRecovery()) {
                updateState(
                    state.copy(
                        statusText = "mpv runtime error",
                        error = "$prefix: $message",
                    ),
                )
            }
        }
    }

    private fun applyRecoveryDecision(lowerMessage: String) {
        if (proxyOpenFailed) return
        val execution = recoveryOrchestrator.resolveLogMessage(
            snapshot = buildRecoveryRuntimeSnapshot().copy(
                hlsSubResourceLog = sessionGate.isHlsSubResourceLog(lowerMessage),
            ),
            lowerMessage = lowerMessage,
        )
        if (
            !execution.recoverVideoOutput &&
            !execution.reloadCurrentSource &&
            !execution.markVideoStreamLost &&
            execution.queueSeekPositionMs == null
        ) {
            return
        }
        applyRecoveryExecution(execution, lowerMessage)
    }

    private fun maybeTriggerHdrHwdecFallback(lowerMessage: String) {
        val changed = videoOutputController.maybeTriggerHdrHwdecFallback(source, lowerMessage)
        syncVideoOutputState()
        if (!changed) return
        loadState.clearForRecovery(source.url)
        sessionGate.onVideoRecoveryTriggered()
        if (surfaceReady && surfaceAttached && currentSurfaceValid()) {
            loadCurrentSource()
        }
    }

    private fun maybeTriggerAutomaticSoftwareDecoderFallback(lowerMessage: String) {
        val changed = videoOutputController.maybeTriggerSoftwareDecoderFallback(source, lowerMessage)
        syncVideoOutputState()
        if (!changed) return
        updateState(
            state.copy(
                statusText = AUTO_SOFTWARE_DECODER_FALLBACK_STATUS,
                error = null,
            ),
        )
        loadState.clearForRecovery(source.url)
        sessionGate.onVideoRecoveryTriggered()
        if (surfaceReady && surfaceAttached && currentSurfaceValid()) {
            loadCurrentSource()
        }
    }

    private fun maybeTriggerAutomaticFilterFallback() {
        if (autoFilterFallbackTriggeredForSource) return
        if (!advancedSettingsController.canTriggerAutomaticFilterFallback(source)) return
        if (!initialized || !mpv.isAvailable()) return
        if (!loadState.sourceFileLoaded || !isCurrentSourceStable()) return
        if (state.paused || state.positionMs < 3000L) return

        val now = SystemClock.uptimeMillis()
        val dropFrameCount = currentPerformanceCounter("drop-frame-count")
        val decoderDropFrameCount = currentPerformanceCounter("decoder-frame-drop-count")
        val mistimedFrameCount = currentPerformanceCounter("mistimed-frame-count")
        val voDelayedFrameCount = currentPerformanceCounter("vo-delayed-frame-count")

        if (lastFilterFallbackSampleUptimeMs == 0L) {
            lastFilterFallbackSampleUptimeMs = now
            lastDropFrameCount = dropFrameCount
            lastDecoderDropFrameCount = decoderDropFrameCount
            lastMistimedFrameCount = mistimedFrameCount
            lastVoDelayedFrameCount = voDelayedFrameCount
            return
        }

        val elapsedMs = now - lastFilterFallbackSampleUptimeMs
        if (elapsedMs < FILTER_FALLBACK_SAMPLE_INTERVAL_MS) {
            return
        }

        val dropDelta =
            (dropFrameCount - lastDropFrameCount).coerceAtLeast(0L) +
                (decoderDropFrameCount - lastDecoderDropFrameCount).coerceAtLeast(0L)
        val mistimedDelta =
            (mistimedFrameCount - lastMistimedFrameCount).coerceAtLeast(0L) +
                (voDelayedFrameCount - lastVoDelayedFrameCount).coerceAtLeast(0L)

        lastFilterFallbackSampleUptimeMs = now
        lastDropFrameCount = dropFrameCount
        lastDecoderDropFrameCount = decoderDropFrameCount
        lastMistimedFrameCount = mistimedFrameCount
        lastVoDelayedFrameCount = voDelayedFrameCount

        val unstablePlayback =
            dropDelta >= FILTER_FALLBACK_DROP_THRESHOLD ||
                mistimedDelta >= FILTER_FALLBACK_MISTIMED_THRESHOLD
        if (!unstablePlayback) return

        val changed = advancedSettingsController.triggerAutomaticFilterFallback(
            initialized = initialized,
            available = mpv.isAvailable(),
            source = source,
        )
        syncVideoOutputState()
        if (!changed) return

        autoFilterFallbackTriggeredForSource = true
        Log.w(
            TAG,
            "triggered automatic filter fallback dropDelta=$dropDelta mistimedDelta=$mistimedDelta source=[${source.debugSummary()}]",
        )
        updateState(
            state.copy(
                statusText = AUTO_FILTER_FALLBACK_STATUS,
                error = null,
            ),
        )
    }

    private fun clearVideoStreamFailure() {
        videoStreamLost = false
        videoStreamLossReason = null
    }

    private fun clearProxyOpenFailure() {
        proxyOpenFailed = false
        proxyOpenFailureReason = null
    }

    private fun resetAutomaticFilterFallbackMonitor() {
        autoFilterFallbackTriggeredForSource = false
        lastFilterFallbackSampleUptimeMs = 0L
        lastDropFrameCount = 0L
        lastDecoderDropFrameCount = 0L
        lastMistimedFrameCount = 0L
        lastVoDelayedFrameCount = 0L
    }

    private fun markProxyOpenFailure(reason: String, failedUrl: String?) {
        proxyOpenFailed = true
        proxyOpenFailureReason = reason
        sessionGate.onProxyFailure()
        loadState.clearForProxyFailure()
        sourceResolver.releaseRetiredSessions()
        if (!failedUrl.isNullOrBlank()) {
            sourceResolver.invalidateActiveProxy(failedUrl)
        }
    }

    private fun maybeMarkProxyOpenFailure(prefix: String, message: String, lowerMessage: String) {
        val playbackUrl = loadState.activePlaybackUrl
        val usingLocalProxy = playbackUrl?.startsWith("http://127.0.0.1:") == true
        if (!usingLocalProxy) return
        val explicitHttpFailure =
            lowerMessage.contains("failed to open http://127.0.0.1:") ||
                lowerMessage.contains("http error")
        if (shouldSuppressAutomaticRecovery() && !explicitHttpFailure) {
            return
        }
        val failedOpen =
            explicitHttpFailure ||
                (lowerMessage.contains("opening failed or was aborted") && !loadState.sourceFileLoaded) ||
                (lowerMessage.contains("loading failed (reason 4)") && prefix == "cplayer" && !loadState.sourceFileLoaded)
        if (!failedOpen) return
        val reason = when {
            lowerMessage.contains("failed to open http://127.0.0.1:") -> message
            lowerMessage.contains("http error") -> message
            proxyOpenFailureReason != null -> proxyOpenFailureReason!!
            else -> "Failed to open local proxy stream: $playbackUrl"
        }
        markProxyOpenFailure(reason, playbackUrl)
        updateState(
            state.copy(
                paused = true,
                statusText = "Proxy stream open failed",
                error = reason,
            ),
        )
    }

    private fun recoverFromAudioOnlyVideoState(reason: String) {
        Log.w(
            TAG,
            "audio-only playback state detected; recovering video reason=$reason positionMs=${state.positionMs} durationMs=${state.durationMs}",
        )
        applyRecoveryExecution(
            recoveryOrchestrator.resolveAudioOnlyState(
                snapshot = buildRecoveryRuntimeSnapshot(),
                reason = reason,
            ),
            reason,
        )
    }

    private fun isNearPlaybackCompletion(): Boolean {
        val durationMs = state.durationMs
        if (durationMs <= 0L) return false
        return state.positionMs >= (durationMs - 1500L).coerceAtLeast(0L)
    }

    private fun isAudioOnlyVideoState(): Boolean {
        if (state.listenVideoModeEnabled || source.listenVideoModeEnabled) {
            return false
        }
        if (!loadState.sourceFileLoaded) return false
        if (!isCurrentSourceStable()) return false
        val videoCodec = currentMpvString("video-codec")
        val videoFormat = currentMpvString("video-format")
        val videoWidth = currentMpvInt("video-params/w") ?: 0L
        val videoHeight = currentMpvInt("video-params/h") ?: 0L
        return videoCodec == null &&
            videoFormat == null &&
            videoWidth <= 0L &&
            videoHeight <= 0L
    }

    private fun currentMpvString(property: String): String? {
        return runCatching { mpv.getPropertyString(property) }
            .getOrNull()
            ?.trim()
            ?.takeUnless { it.isEmpty() || it == "-" }
    }

    private fun rawMpvInt(property: String): Long? {
        return runCatching { mpv.getPropertyInt(property) }.getOrNull()
    }

    private fun currentMpvFlag(property: String): Boolean? {
        val rawString =
            runCatching { mpv.getPropertyString(property) }
                .getOrNull()
                ?.trim()
                ?.lowercase()
        when (rawString) {
            "yes", "true", "1" -> return true
            "no", "false", "0" -> return false
        }
        val rawInt = rawMpvInt(property)
        if (rawInt == 0L) return false
        if (rawInt == 1L) return true
        return null
    }

    private fun currentTrackId(property: String): Int? {
        val rawString = currentMpvString(property)
        if (rawString != null) {
            val normalized = rawString.trim().lowercase()
            if (normalized == "no" || normalized == "auto") {
                return null
            }
            val parsed = normalized.toIntOrNull()
            if (parsed != null && parsed > 0) {
                return parsed
            }
        }
        val rawInt = rawMpvInt(property)?.toInt()
        if (rawInt != null && rawInt > 0) {
            return rawInt
        }
        return null
    }

    private fun currentVideoOutputName(): String? = currentMpvString("vo")

    private fun isNullVideoOutputMode(mode: String?): Boolean {
        val normalized = mode?.trim()?.lowercase() ?: return false
        return normalized == "null" ||
            normalized.contains("vo/null") ||
            normalized.contains("/null")
    }

    private fun invalidateVideoOutputSanityChecks() {
        videoOutputSanityCheckToken += 1L
        pendingVideoRecoveryAfterSurfaceRestore = false
        pendingVideoRecoveryReason = null
    }

    private fun invalidatePlaybackResumeChecks() {
        playbackResumeCheckToken += 1L
        pendingAutoResumeAfterSurfaceRestore = false
    }

    private fun schedulePlaybackResumeCheck(
        reason: String,
        delayMs: Long = 320L,
    ) {
        val token = ++playbackResumeCheckToken
        playbackHandler.postDelayed(
            {
                if (disposed || token != playbackResumeCheckToken) {
                    return@postDelayed
                }
                if (!initialized || !mpv.isAvailable()) {
                    return@postDelayed
                }
                if (!loadState.sourceFileLoaded || !surfaceReady || !surfaceAttached || !currentSurfaceValid()) {
                    return@postDelayed
                }
                if (!pendingAutoResumeAfterSurfaceRestore) {
                    return@postDelayed
                }
                if (!state.paused) {
                    pendingAutoResumeAfterSurfaceRestore = false
                    return@postDelayed
                }
                val resumed = pauseController.setPausedState(
                    paused = false,
                    initialized = initialized,
                )
                if (resumed) {
                    pendingAutoResumeAfterSurfaceRestore = false
                    updateState(
                        state.copy(
                            paused = false,
                            statusText = "Playback resumed",
                            error = null,
                        ),
                    )
                    return@postDelayed
                }
                if (isSurfaceTransitionInProgress()) {
                    schedulePlaybackResumeCheck("surface-transition:$reason", 420L)
                    return@postDelayed
                }
                Log.w(
                    TAG,
                    "playback resume check failed reason=$reason ready=$surfaceReady attached=$surfaceAttached outputReady=$videoOutputReady",
                )
            },
            delayMs,
        )
    }

    private fun scheduleVideoOutputSanityCheck(
        reason: String,
        delayMs: Long = 700L,
    ) {
        val token = ++videoOutputSanityCheckToken
        playbackHandler.postDelayed(
            {
                if (disposed || token != videoOutputSanityCheckToken) {
                    return@postDelayed
                }
                if (!initialized || !mpv.isAvailable()) {
                    return@postDelayed
                }
                if (!loadState.sourceFileLoaded || !surfaceReady || !surfaceAttached || !currentSurfaceValid()) {
                    return@postDelayed
                }
                val currentVo = currentVideoOutputName()
                if (!isNullVideoOutputMode(currentVo) && videoOutputReady) {
                    return@postDelayed
                }
                Log.w(
                    TAG,
                    "video output sanity recovery reason=$reason vo=$currentVo ready=$videoOutputReady attached=$surfaceAttached",
                )
                recoverVideoOutputOnly("sanity:$reason")
                playbackHandler.postDelayed(
                    {
                        if (disposed || token != videoOutputSanityCheckToken) {
                            return@postDelayed
                        }
                        if (!loadState.sourceFileLoaded || !surfaceReady || !surfaceAttached || !currentSurfaceValid()) {
                            return@postDelayed
                        }
                        val recoveredVo = currentVideoOutputName()
                        if (!isNullVideoOutputMode(recoveredVo)) {
                            return@postDelayed
                        }
                        if (isSurfaceTransitionInProgress()) {
                            Log.d(
                                TAG,
                                "postpone sanity reload during surface transition reason=$reason vo=$recoveredVo ready=$videoOutputReady",
                            )
                            scheduleVideoOutputSanityCheck("surface-transition:$reason", 900L)
                            return@postDelayed
                        }
                        Log.w(
                            TAG,
                            "video output still null after recovery reason=$reason vo=$recoveredVo playback=${loadState.activePlaybackUrl}",
                        )
                        reloadCurrentSource("video output stuck at ${recoveredVo ?: "unknown"} after $reason")
                    },
                    450L,
                )
            },
            delayMs,
        )
    }

    private fun currentMpvInt(property: String): Long? {
        return sanitizeMpvIntProperty(
            property = property,
            value = runCatching { mpv.getPropertyInt(property) }.getOrNull(),
        )
    }

    private fun currentPerformanceCounter(property: String): Long {
        return currentMpvInt(property) ?: 0L
    }

    private fun queueExternalSubtitle(path: String): Boolean {
        if (!initialized || !mpv.isAvailable()) {
            return false
        }
        val queued = trackSelectionController.queueExternalSubtitle(path, initialized)
        if (!queued) return false
        handleRestorePlan(
            restoreCoordinator.onExternalSubtitleQueued(loadState.sourceFileLoaded),
            "queueExternalSubtitle",
        )
        return true
    }

    private fun applyPendingExternalSubtitle(): Boolean {
        val success = trackSelectionController.applyPendingExternalSubtitle()
        if (success) {
            restoreCoordinator.clearPendingExternalSubtitle()
        }
        return success
    }

    private data class RuntimeTrackEntry(
        val id: Int,
        val type: String,
        val title: String,
        val language: String,
        val codec: String,
        val external: Boolean,
        val selected: Boolean,
        val forced: Boolean,
        val bitmap: Boolean,
        val channels: Int,
        val channelLayout: String,
        val sampleRate: Int,
        val bitrate: Int,
    )
}
