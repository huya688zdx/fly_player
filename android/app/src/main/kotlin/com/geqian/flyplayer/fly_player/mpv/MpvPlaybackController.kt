package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import `is`.xyz.mpv.MPVLib
import java.util.concurrent.FutureTask

private const val TAG = "FlyPlayerMpv"
private const val AUTO_SOFTWARE_DECODER_FALLBACK_STATUS = "Auto decoder fallback: software"

class MpvPlaybackController(
    private val context: Context,
    private val surfaceView: SurfaceView,
    creationParams: Map<String, Any?>,
    private val stateListener: MpvPlaybackStateListener,
) : SurfaceHolder.Callback,
    MPVLib.EventObserver,
    MPVLib.LogObserver {
    private val mpv: MpvFacade = DefaultMpvFacade
    private val mainHandler = Handler(Looper.getMainLooper())
    private val playbackThread = HandlerThread("FlyPlayerMpvPlayback").apply { start() }
    private val playbackHandler = Handler(playbackThread.looper)
    private val displayProfile = detectDisplayProfile(context)
    private val hostActivity = findActivity(context)
    @Volatile
    private var disposed = false

    private var state = MpvPlayerState(
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
    private val restoreCoordinator = MpvPlaybackRestoreCoordinator()
    private val loadState = PlaybackLoadStateTracker()
    private val sourceResolver = PlaybackSourceResolver()
    private val trackSelectionController = TrackSelectionController(mpv)
    private val recoveryPolicy = PlaybackRecoveryPolicy()
    private val recoveryOrchestrator = PlaybackRecoveryOrchestrator(recoveryPolicy)
    private val sessionGate = PlaybackSessionGate()
    private val runtimeBootstrap = MpvRuntimeBootstrap(context, mpv)
    private val stateReporter = MpvPlaybackStateReporter(
        runOnMainThread = ::runOnMainThread,
        stateListener = stateListener,
        mpv = mpv,
    )
    private val videoOutputController = VideoOutputController(
        surfaceView = surfaceView,
        hostActivity = hostActivity,
        displayProfile = displayProfile,
        deviceProfile = deviceProfile,
        runOnMainThread = ::runOnMainThread,
        mpv = mpv,
    )

    init {
        mpv.addObserver(this)
        mpv.addLogObserver(this)
        loadState.reset()
        Log.d(
            TAG,
            "view init title=${source.title} url=${source.url} deviceProfile=${deviceProfile.summary} displayProfile=${displayProfile.summary}",
        )
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
            disposeInternal()
            playbackThread.quitSafely()
        }
    }

    private fun disposeInternal() {
        sourceResolver.release()
        if (mpv.isAvailable() && mpv.isCreated()) {
            runCatching {
                mpv.setPropertyBoolean("pause", true)
                mpv.setPropertyString("vid", "auto")
                mpv.setPropertyString("vo", "null")
                mpv.detachSurface()
            }
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
        clearVideoStreamFailure()
        sessionGate.reset()
        videoOutputController.onDispose()
        syncVideoOutputState()
    }

    fun getStateMap(): Map<String, Any?> {
        if (disposed) return state.toMap()
        return callOnPlaybackThread { state.toMap() }
    }

    fun getPlaybackDiagnosticsMap(): Map<String, Any?> {
        if (disposed) return state.toMap()
        return callOnPlaybackThread { buildPlaybackDiagnostics() }
    }

    fun getChapters(): List<Map<String, Any?>> {
        if (disposed) return emptyList()
        return callOnPlaybackThread { buildChapterList() }
    }

    fun load(args: Map<String, Any?>) {
        runOnPlaybackThread {
            val previousUrl = source.url
            source = MpvSource.fromMap(args)
            if (previousUrl != source.url) {
                sourceResolver.releaseOnSourceChange(previousUrl, source.url)
            }
            resumeAfterSurfaceRestore = false
            loadState.resetForSource(source.url)
            trackSelectionController.reset()
            sessionGate.beginSourceChange()
            videoOutputController.resetForSourceLoad()
            syncVideoOutputState()
            clearVideoStreamFailure()
            clearProxyOpenFailure()
            Log.d(TAG, "method load url=${source.url} startMs=${source.startPositionMs}")
            loadCurrentSource()
        }
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
            val success = if (initialized && mpv.isAvailable()) {
                runCatching { mpv.setPropertyBoolean("pause", false) }.getOrDefault(false)
            } else {
                false
            }
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
            val success = if (initialized && mpv.isAvailable()) {
                runCatching { mpv.setPropertyBoolean("pause", true) }.getOrDefault(false)
            } else {
                false
            }
            updateState(
                state.copy(
                    paused = true,
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
                    error = if (success) null else buildUnavailableMessage("seek"),
                ),
            )
        }
        return true
    }

    fun setAudioTrack(trackIndex: Int?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val success = if (initialized && mpv.isAvailable() && trackIndex != null) {
                runCatching { mpv.setPropertyInt("aid", trackIndex.toLong()) }.getOrDefault(false)
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

    fun setSubtitleTrack(trackIndex: Int?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val success = if (initialized && mpv.isAvailable()) {
                trackSelectionController.onSubtitleTrackSelectedManually()
                when {
                    trackIndex == null -> runCatching {
                        mpv.setPropertyString("sid", "no")
                    }.getOrDefault(false)
                    else -> runCatching {
                        mpv.setPropertyInt("sid", trackIndex.toLong())
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

    fun setSubtitlePosition(position: Int?): Boolean {
        if (disposed) return false
        runOnPlaybackThread {
            val normalized = (position ?: 100).coerceIn(0, 100)
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
                    mpv.setPropertyInt("sub-pos", 100L)
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

    override fun surfaceCreated(holder: SurfaceHolder) {
        runOnPlaybackThread {
            surfaceReady = true
            Log.d(
                TAG,
                "surfaceCreated created=$created initialized=$initialized mpvAvailable=${mpv.isAvailable()} url=${source.url}",
            )
            if (created && mpv.isAvailable()) {
                val initSuccess = runCatching {
                    if (!initialized) {
                        if (!mpv.maybeInit()) {
                            false
                        } else {
                            initialized = true
                            if (!propertiesObserved) {
                                mpv.observeProperty("time-pos", 5)
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
                    Log.e(TAG, "surfaceCreated init failed", error)
                }.getOrDefault(false)
                if (!initSuccess) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to initialize mpv",
                            error = buildUnavailableMessage("surface initialization"),
                        ),
                    )
                    return@runOnPlaybackThread
                }
                val attachSuccess = videoOutputController.onSurfaceCreated(holder)
                syncVideoOutputState()
                if (!attachSuccess) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to attach mpv surface",
                            error = buildUnavailableMessage("surface attachment"),
                        ),
                    )
                    return@runOnPlaybackThread
                }
                if (!restoreVideoTrackAfterSurfaceReady()) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to restore video track",
                            error = buildUnavailableMessage("video track restore"),
                        ),
                    )
                    return@runOnPlaybackThread
                }
                if (!ensureVideoOutputReady()) {
                    updateState(
                        state.copy(
                            ready = false,
                            statusText = "Failed to configure video output",
                            error = buildUnavailableMessage("video output configuration"),
                        ),
                    )
                    return@runOnPlaybackThread
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
                    runCatching {
                        mpv.setPropertyBoolean("pause", false)
                    }.getOrDefault(false)
                } else {
                    false
                }
                resumeAfterSurfaceRestore = false
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
                return@runOnPlaybackThread
            }
            if (loadState.shouldRunDeferredLoad(source.url)) {
                loadCurrentSource()
            }
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        runOnPlaybackThread {
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
            sessionGate.onSurfaceLost()
            videoOutputController.onSurfaceDestroyed(initialized, mpv.isAvailable())
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
        resumeAfterSurfaceRestore = false
        clearVideoStreamFailure()
        clearProxyOpenFailure()
        Log.d(
            TAG,
            "loadCurrentSource initialized=$initialized surfaceReady=$surfaceReady surfaceAttached=$surfaceAttached videoOutputReady=$videoOutputReady hwdec=${preferredHwdecMode()} pipeline=${preferredColorPipeline()} hdr=${source.isHdrLikely()} url=${source.url}",
        )
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
                    error = buildUnavailableMessage("video track"),
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
                    error = buildUnavailableMessage("video track"),
                ),
            )
            return
        }
        if (!ensureVideoOutputReady()) {
            updateState(
                state.copy(
                    ready = false,
                    statusText = "Video output unavailable",
                    error = buildUnavailableMessage("video output"),
                ),
            )
            return
        }

        val playbackTarget = sourceResolver.prepare(source)
        sessionGate.beginLoad(playbackTarget.url)
        val initialStartPositionMs = preferredResumePositionMs()
        val loadCommand = MpvLoadfileOptions.buildCommand(
            url = playbackTarget.url,
            headers = playbackTarget.headers,
            disableTlsVerify = playbackTarget.disableTlsVerify,
            startPositionMs = initialStartPositionMs,
        )
        val loaded = runCatching {
            Log.d(
                TAG,
                "loadfile remote=${source.url} playback=${playbackTarget.url} nativeProxy=${playbackTarget.viaNativeProxy} headers=${playbackTarget.headers.isNotEmpty()} disableTls=${playbackTarget.disableTlsVerify}",
            )
            mpv.command(loadCommand) >= 0
        }.onFailure { error ->
            Log.e(TAG, "loadfile failed url=${source.url}", error)
        }.getOrDefault(false)
        sessionGate.onLoadCommandFinished(loaded)
        if (loaded) {
            loadState.onLoadCommandStarted(source.url, playbackTarget.url)
            restoreCoordinator.onLoadRequested(
                0L,
                trackSelectionController.hasPendingExternalSubtitle(),
            )
            trackSelectionController.onLoadRequested(source)
        } else {
            loadState.onLoadCommandFailed()
        }

        updateState(
            state.copy(
                ready = true,
                nativeLibLoaded = mpv.isAvailable(),
                paused = !loaded,
                positionMs = source.startPositionMs,
                statusText = if (loaded) {
                    "Source loaded"
                } else {
                    "mpv-android runtime rejected source"
                },
                error = if (loaded) null else buildUnavailableMessage("source loading"),
            ),
        )
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

    private fun updateState(next: MpvPlayerState) {
        state = next
        stateReporter.dispatch(next, source.title)
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
    }

    private fun buildPlaybackDiagnostics(): Map<String, Any?> {
        val sessionSnapshot = sessionGate.currentSnapshot()
        return stateReporter.buildDiagnostics(
            MpvPlaybackControllerDiagnosticsSnapshot(
                state = state,
                source = source,
                loadedSourceUrl = loadState.loadedSourceUrl,
                loadingSourceUrl = loadState.loadingSourceUrl,
                activePlaybackUrl = loadState.activePlaybackUrl,
                nativeProxyUrl = sourceResolver.activeProxyUrl,
                nativeProxySessionId = sourceResolver.activeProxySessionId,
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
                pendingLoadRequested = loadState.pendingLoadRequested,
                sourceFileLoaded = loadState.sourceFileLoaded,
                sessionSnapshot = sessionSnapshot,
                resumeAfterSurfaceRestore = resumeAfterSurfaceRestore,
                pendingSeekPositionMs = restoreCoordinator.pendingSeekPositionMs,
                activeHwdecMode = activeHwdecMode,
                forcedHwdecMode = forcedHwdecMode,
                activeColorPipeline = activeColorPipeline,
                forcedColorPipeline = forcedColorPipeline,
                preferredHwdecMode = preferredHwdecMode(),
                preferredColorPipeline = preferredColorPipeline(),
                windowColorMode = currentWindowColorMode(),
                displayProfile = displayProfile,
                deviceProfile = deviceProfile,
            ),
        )
    }

    private fun currentWindowColorMode(): String {
        return videoOutputController.currentWindowColorMode()
    }

    private fun buildChapterList(): List<Map<String, Any?>> {
        if (!mpv.isAvailable()) return emptyList()
        val reportedCount = runCatching { mpv.getPropertyInt("chapters") }.getOrDefault(0L).toInt()
        if (reportedCount <= 0) return emptyList()
        val chapters = mutableListOf<Map<String, Any?>>()
        for (index in 0 until reportedCount) {
            val timeSeconds = safeGetChapterTime(index)
            if (timeSeconds == null) {
                if (chapters.isNotEmpty()) {
                    break
                }
                continue
            }
            val title = safeGetChapterTitle(index)
            chapters += mapOf(
                "index" to index,
                "title" to title,
                "timeMs" to (timeSeconds * 1000.0).toLong(),
            )
        }
        Log.d(
            TAG,
            "chapter-debug reportedCount=$reportedCount returnedCount=${chapters.size} chapterTimes=${
                chapters.joinToString(prefix = "[", postfix = "]") { chapter ->
                    "${chapter["index"]}:${chapter["timeMs"]}"
                }
            }",
        )
        return chapters
    }

    private fun safeGetChapterTime(index: Int): Double? {
        val timeProperty = "chapter-list/$index/time"
        val stringValue =
            runCatching { mpv.getPropertyString(timeProperty) }
                .getOrNull()
                ?.trim()
                ?.takeIf { it.isNotEmpty() && it != "-" }
                ?: return null
        return parseMpvTimeString(stringValue)
    }

    private fun safeGetChapterTitle(index: Int): String {
        return safeGetPropertyString("chapter-list/$index/title")
            ?: safeGetPropertyString("chapter-list/$index/name")
            ?: ""
    }

    private fun safeGetPropertyString(property: String): String? {
        return runCatching { mpv.getPropertyString(property) }
            .getOrNull()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun safeGetPropertyDouble(property: String): Double? {
        val stringValue =
            runCatching { mpv.getPropertyString(property) }
                .getOrNull()
                ?.trim()
                ?.takeIf { it.isNotEmpty() && it != "-" }
        parseMpvTimeString(stringValue)?.let { return it }
        return runCatching { mpv.getPropertyDouble(property) }.getOrNull()
    }

    private fun parseMpvTimeString(value: String?): Double? {
        val text = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        text.toDoubleOrNull()?.let { return it }
        val parts = text.split(":")
        if (parts.isEmpty()) return null
        return when (parts.size) {
            3 -> {
                val hours = parts[0].toDoubleOrNull() ?: return null
                val minutes = parts[1].toDoubleOrNull() ?: return null
                val seconds = parts[2].toDoubleOrNull() ?: return null
                (hours * 3600.0) + (minutes * 60.0) + seconds
            }
            2 -> {
                val minutes = parts[0].toDoubleOrNull() ?: return null
                val seconds = parts[1].toDoubleOrNull() ?: return null
                (minutes * 60.0) + seconds
            }
            else -> null
        }
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
            Log.e(TAG, "MPVLib unavailable: ${mpv.loadErrorMessage()}")
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
                error = if (ready) null else buildUnavailableMessage("player initialization"),
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
        return runCatching {
            mpv.command(
                arrayOf(
                    "seek",
                    seconds.toString(),
                    "absolute+exact",
                ),
            ) >= 0
        }.onFailure { error ->
            Log.e(TAG, "seek failed positionMs=$positionMs", error)
        }.getOrDefault(false)
    }

    override fun eventProperty(property: String, value: Boolean) {
        runOnPlaybackThread {
            when (property) {
                "pause" -> updateState(state.copy(paused = value, error = null))
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
                            error = null,
                        ),
                    )
                    handleRestorePlan(
                        restoreCoordinator.onTimePosition(positionMs),
                        "property:time-pos",
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
                    handleRestorePlan(
                        restoreCoordinator.onSourceFileLoaded(),
                        "event:file-loaded",
                    )
                    updateState(
                        state.copy(
                            paused = false,
                            statusText = "Playback started",
                            error = null,
                        ),
                    )
                    if (loadState.shouldRunDeferredLoad(source.url)) {
                        loadCurrentSource()
                    }
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
                        Log.d(
                            TAG,
                            "ignoring end-file during source switch remote=${source.url} playback=${loadState.activePlaybackUrl} generation=${sessionGate.currentSnapshot().generation}",
                        )
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
            Log.d(TAG, "mpv[$level][$prefix] $message")
            val lowerMessage = message.lowercase()
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
                Log.i(TAG, "subtitle-debug[$level][$prefix] $message")
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

    private fun clearVideoStreamFailure() {
        videoStreamLost = false
        videoStreamLossReason = null
    }

    private fun clearProxyOpenFailure() {
        proxyOpenFailed = false
        proxyOpenFailureReason = null
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
        val failedOpen =
            lowerMessage.contains("failed to open http://127.0.0.1:") ||
                (lowerMessage.contains("opening failed or was aborted") && !loadState.sourceFileLoaded) ||
                (lowerMessage.contains("loading failed (reason 4)") && prefix == "cplayer" && !loadState.sourceFileLoaded)
        if (!failedOpen) return
        val reason = when {
            lowerMessage.contains("failed to open http://127.0.0.1:") -> message
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
        val audioCodec = currentMpvString("audio-codec-name")
        if (audioCodec == null) return false
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

    private fun currentMpvInt(property: String): Long? {
        return sanitizeMpvIntProperty(
            property = property,
            value = runCatching { mpv.getPropertyInt(property) }.getOrNull(),
        )
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
}
