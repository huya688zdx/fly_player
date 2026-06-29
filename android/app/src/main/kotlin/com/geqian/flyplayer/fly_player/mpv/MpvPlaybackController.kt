package com.geqian.flyplayer.fly_player.mpv

import android.media.AudioManager
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
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
import java.util.concurrent.TimeUnit

private const val TAG = "FlyPlayerMpv"
// 可位流直通的 mpv audio-codec-name 集（对齐 AudioPassthroughSupport.ALL_CODECS）。DTS 系
// FFmpeg 解码器名为 "dca"，另由 name.startsWith("dts") 兜住 dts/dts-hd 写法。
private val PASSTHROUGH_CAPABLE_CODECS =
    setOf("ac3", "eac3", "e-ac3", "dca", "dts", "dts-hd", "truehd", "mlp")
private const val AUTO_SOFTWARE_DECODER_FALLBACK_STATUS = "Auto decoder fallback: software"
private const val AUTO_FILTER_FALLBACK_STATUS = "Auto performance fallback: filters disabled"
private const val FILTER_FALLBACK_SAMPLE_INTERVAL_MS = 1500L
// 单窗(1.5s)判定"不稳"的阈值。注意 frame-drop-count 含启动/seek/切场景的瞬时丢帧,
// 流畅设备也常有个位数 VO 丢帧(尤其 mediacodec-copy + 高刷屏),故阈值给得高、避免误判。
private const val FILTER_FALLBACK_DROP_THRESHOLD = 20L
private const val FILTER_FALLBACK_MISTIMED_THRESHOLD = 24L
// 必须连续 N 个采样窗都"不稳"才降级——过滤瞬时尖峰(启动 settling/seek/场景切),
// 只抓真正持续的"跟不上"。N×1.5s≈4.5s 的持续卡顿才动手。
private const val FILTER_FALLBACK_CONSECUTIVE_WINDOWS = 3
// 性能阶梯最高级：1=视频降画质+宿主关 AI 遮罩（方案 B），2=并压弹幕（方案 C），
// 3=mpv 渲染后端 Vulkan→GLES 重载以保留 HDR 直通（路线1，避开双 Vulkan 争用），
// 4=仍掉帧才放弃 HDR、降为 HDR→SDR 映射（方案 D，最后兜底）。
private const val PERFORMANCE_FALLBACK_MAX_LEVEL = 4
private const val SURFACE_TRANSITION_GRACE_MS = 2500L
private const val VISUAL_PLAYBACK_PROGRESS_FALLBACK_MS = 900L
private const val ENABLE_MPV_VERBOSE_LOGS = false
// mpv 错误/警告级日志转发到 Flutter 应用内日志的去重窗口与单条上限，避免高频 log 灌爆
// MethodChannel 与日志列表。同一 "prefix|message" 在窗口内只上报一次。
private const val LOG_FORWARD_DEDUP_WINDOW_MS = 15000L
private const val LOG_FORWARD_MAX_MESSAGE_CHARS = 1000
// 属性探测类噪声(如 chapter-list/0/time not found)对排障无价值，转发前过滤掉。
private val LOG_FORWARD_BENIGN_PATTERNS =
    listOf("property not found", "property unavailable", "property not available")
private const val DEFAULT_SUBTITLE_POSITION = 92
private val VISUAL_PLAYBACK_RESET_STATUSES =
    setOf(
        "waiting for playback source",
        "waiting for video surface",
        "preparing video renderer",
        "opening source",
        "proxy stream open failed",
        "playback ended",
    )

/**
 * mpv 原生控制器入口。
 * 所有真正触碰 mpv runtime 的操作尽量收敛到 `playbackThread`，主线程只负责 Surface、UI 回调和状态分发，
 * 这样在 Flutter 页面切换、分屏切换和宿主切换时更容易控制竞态。
 */
class MpvPlaybackController(
    private val context: Context,
    private val videoOutputTarget: VideoOutputTarget,
    creationParams: Map<String, Any?>,
    private val stateListener: MpvPlaybackStateListener,
    private val danmakuOcclusionStateListener: ((DanmakuDynamicOcclusionState, Bitmap?) -> Unit)? = null,
) : MPVLib.EventObserver,
    MPVLib.LogObserver {
    private val mpv: MpvFacade = DefaultMpvFacade
    private val mainHandler = Handler(Looper.getMainLooper())
    // mpv 的生命周期与属性访问统一放到单线程里，减少与 UI 线程交错时的状态撕裂。
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
    // 熄屏继续播放音频（全局设置）：开启后看视频熄屏/锁屏也只停画面、不停声音。
    private var keepAudioWhenScreenOff = false
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
    // 自适应性能阶梯级别：0=未降级，1=视频已降画质，2=并已请求压弹幕。每个源重置。
    private var performanceFallbackLevel = 0
    private var lastFilterFallbackSampleUptimeMs = 0L
    private var lastDropFrameCount = 0L
    private var lastDecoderDropFrameCount = 0L
    private var lastMistimedFrameCount = 0L
    private var lastVoDelayedFrameCount = 0L
    // 本 mpv 构建里恒不可用的性能计数器(如本设备的 mistimed-frame-count / vo-delayed-frame-count,
    // getPropertyInt 返回 format-unavailable)。首次 miss 后记下,后续直接跳过——否则每个 time-pos
    // 都查一遍恒空属性,既白费 JNI 调用又刷 V/mpv 日志(实测一次会话刷 2000+ 行)。每源重置重新探测一次。
    private val unavailablePerfCounters = HashSet<String>()
    // 连续"不稳"采样窗计数,达到 FILTER_FALLBACK_CONSECUTIVE_WINDOWS 才真正降级(过滤瞬时尖峰)。
    private var consecutiveUnstableFallbackWindows = 0
    private var observedCacheDurationMs = 0L
    private var visualPlaybackStartAnchorMs = 0L
    private var lastAppliedCachePauseWaitMs = Long.MIN_VALUE
    private var videoOutputSanityCheckToken = 0L
    private var playbackResumeCheckToken = 0L
    private var pendingAutoResumeAfterSurfaceRestore = false
    private var pendingVideoRecoveryAfterSurfaceRestore = false
    private var pendingVideoRecoveryReason: String? = null
    private var lastSurfaceTransitionUptimeMs = 0L
    // 复杂播放能力尽量拆成协作者，主控制器主要负责线程切换、生命周期和状态编排。
    private val restoreCoordinator = MpvPlaybackRestoreCoordinator()
    private val loadState = PlaybackLoadStateTracker()
    private val sourceResolver = PlaybackSourceResolver(context)
    private val trackSelectionController = TrackSelectionController(mpv)
    private val weakNetworkBufferingController = WeakNetworkBufferingController()
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
        context = context,
    )
    private val diagnosticsSnapshotFactory = PlaybackDiagnosticsSnapshotFactory(
        sessionGate = sessionGate,
        sourceResolver = sourceResolver,
        restoreCoordinator = restoreCoordinator,
        advancedSettingsController = advancedSettingsController,
        videoOutputController = videoOutputController,
        audioOutputDiagnostics = audioOutputDiagnostics,
    )
    private val danmakuOcclusionController =
        DanmakuDynamicOcclusionController(
            context = context,
            videoOutputTarget = videoOutputTarget,
            stateListener = { next, runtimeMaskBitmap ->
                runOnMainThread {
                    danmakuOcclusionStateListener?.invoke(next, runtimeMaskBitmap)
                }
            },
            // Plan B: current playback position (ms) for decode-ahead. Read the
            // observer-tracked state (getPropertyDouble from the inference thread
            // returns 0); state.positionMs is updated by eventProperty("time-pos").
            positionProviderMs = { state.positionMs },
            // Plan B v2: playback speed scales the producer's lookahead window so
            // masks still land ahead of playback at 1.5x/2x.
            playbackSpeedProvider = { state.speed },
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
        danmakuOcclusionController?.onSourceChanged(source)
        verboseLog {
            "view init title=${source.title} url=${source.url} deviceProfile=${deviceProfile.summary} displayProfile=${displayProfile.summary}"
        }
        runOnPlaybackThread {
            initializeMpv()
        }
    }

    fun dispose() {
        dispose(waitForCompletion = false)
    }

    fun disposeBlocking() {
        dispose(waitForCompletion = true)
    }

    private fun dispose(waitForCompletion: Boolean) {
        if (disposed) return
        disposed = true
        mpv.removeObserver(this)
        mpv.removeLogObserver(this)
        val disposeTask = FutureTask {
            playbackHandler.removeCallbacksAndMessages(null)
            disposeInternal()
            playbackThread.quitSafely()
        }
        if (Looper.myLooper() == playbackThread.looper) {
            disposeTask.run()
            return
        }
        val posted = playbackHandler.postAtFrontOfQueue(disposeTask)
        if (waitForCompletion && posted) {
            runCatching {
                disposeTask.get(2, TimeUnit.SECONDS)
            }.onFailure { error ->
                Log.w(TAG, "timed out waiting for mpv controller dispose", error)
            }
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
            runtimeBootstrap.release()
        }
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
        resetWeakNetworkBuffering()
        performanceSampler.reset()
        clearVideoStreamFailure()
        sessionGate.reset()
        videoOutputController.onDispose()
        syncVideoOutputState()
        danmakuOcclusionController?.dispose()
    }

    private fun clearRetainedPlaybackStateForReuse() {
        val didClear =
            videoOutputController.clearRetainedPlaybackStateForReuse {
                runCatching { mpv.setPropertyBoolean("pause", true) }
                runCatching { mpv.setPropertyString("sid", "no") }
                runCatching { mpv.setPropertyString("aid", "auto") }
                runCatching { mpv.setPropertyString("vid", "auto") }
                runCatching { trackSelectionController.reset() }
                restoreCoordinator.clearPendingExternalSubtitle()
                runCatching { mpv.command(arrayOf("playlist-clear")) }
                runCatching { mpv.command(arrayOf("stop")) }
            }
        if (didClear) {
            Log.d(TAG, "cleared retained mpv playback state before reuse")
        } else {
            Log.d(TAG, "skipped retained mpv playback clear because another surface owns mpv")
        }
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
        val controller = danmakuOcclusionController ?: return DanmakuDynamicOcclusionState.disabled().toMap()
        return callOnPlaybackThread { controller.currentStateMap() }
    }

    fun getChapters(): List<Map<String, Any?>> {
        if (disposed) return emptyList()
        return callOnPlaybackThread { buildChapterList() }
    }

    fun getTrackSnapshotMap(): Map<String, Any?> {
        if (disposed) return emptyMap()
        return callOnPlaybackThread { buildTrackSnapshotMap() }
    }

    /** 熄屏继续播放音频开关（全局设置）：开启后看视频熄屏/锁屏不暂停，仅停画面、保留声音。 */
    fun setKeepAudioWhenScreenOff(enabled: Boolean) {
        keepAudioWhenScreenOff = enabled
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
        val controller = danmakuOcclusionController ?: return false
        runOnPlaybackThread {
            controller.updateConfig(args)
            syncDanmakuOcclusionRuntime()
        }
        return true
    }

    // 弹层/二级界面打开时暂停 AI 遮挡采样，不卸载模型。
    fun setDanmakuOcclusionSamplingPaused(paused: Boolean): Boolean {
        if (disposed) return false
        val controller = danmakuOcclusionController ?: return false
        runOnPlaybackThread {
            controller.setExternallyPaused(paused)
        }
        return true
    }

    // 当前屏幕上没有弹幕时暂停 AI 采样，避免无意义的推理消耗。
    fun setDanmakuHasOnScreenComments(hasComments: Boolean): Boolean {
        if (disposed) return false
        val controller = danmakuOcclusionController ?: return false
        runOnPlaybackThread {
            controller.setHasDanmakuOnScreen(hasComments)
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
            state = state.copy(
                loadNonce = source.loadNonce,
                paused = source.startPaused,
                // 新源从未降级开始（强设备/低负载源应保持满画质）。
                performanceFallbackLevel = 0,
            )
            if (previousUrl != source.url) {
                sourceResolver.releaseOnSourceChange(previousUrl, source.url)
            }
            danmakuOcclusionController?.onSourceChanged(source)
            resumeAfterSurfaceRestore = false
            loadState.resetForSource(source.url)
            trackSelectionController.reset()
            sessionGate.beginSourceChange()
            videoOutputController.resetForSourceLoad()
            advancedSettingsController.resetTransientOverrides()
            resetAutomaticFilterFallbackMonitor()
            resetWeakNetworkBuffering()
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
                source = source.copy(
                    startPositionMs = resumePositionMs,
                    startPaused = state.paused,
                )
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
            val success = applyMpvPropertyBestEffort(
                ready = initialized && mpv.isAvailable() && resolvedTrackId != null,
            ) {
                mpv.setPropertyString("aid", resolvedTrackId.toString())
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
                restoreCoordinator.clearPendingExternalSubtitle()
                trackSelectionController.onSubtitleTrackSelectedManually()
                when {
                    resolvedTrackId == null -> applyMpvPropertyBestEffort {
                        mpv.setPropertyString("sid", "no")
                    }
                    else -> applyMpvPropertyBestEffort {
                        mpv.setPropertyString("sid", resolvedTrackId.toString())
                    }
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
                applyMpvPropertyBestEffort {
                    mpv.setPropertyDouble("sub-delay", normalized)
                }
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
                    applyMpvPropertyBestEffort {
                        mpv.setPropertyDouble("audio-delay", normalized)
                    }
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
                applyMpvPropertyBestEffort {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyInt("sub-pos", normalized.toLong())
                }
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
                applyMpvPropertyBestEffort {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyDouble("sub-scale", normalized)
                }
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
                applyMpvPropertyBestEffort {
                    mpv.setPropertyDouble("sub-delay", 0.0)
                }
            } else {
                true
            }
            val positionSuccess = if (initialized && mpv.isAvailable()) {
                applyMpvPropertyBestEffort {
                    mpv.setPropertyString("sub-ass-override", "scale")
                    mpv.setPropertyInt("sub-pos", DEFAULT_SUBTITLE_POSITION.toLong())
                }
            } else {
                true
            }
            val scaleSuccess = if (initialized && mpv.isAvailable()) {
                applyMpvPropertyBestEffort {
                    mpv.setPropertyDouble("sub-scale", 1.0)
                }
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
                source = source.copy(
                    startPositionMs = resumePositionMs,
                    startPaused = state.paused,
                )
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
            val target = speed
            if (initialized && mpv.isAvailable() && target != null) {
                // 注意：当前预编译 libplayer.so 里 MPVLib.setProperty* 的布尔返回值是未定义的
                // 垃圾值——JNI 包装在调用 mpv_set_property 后尾调用了返回 void 的
                // ReleaseStringUTFChars，并未把 mpv 的结果保留到返回寄存器。因此绝不能拿它当
                // 成功标志，否则倍速明明已经生效，却会随机误报「mpv runtime rejected」。
                // 与音量/字幕延迟等其它属性一致，best-effort 设置后直接更新本地状态。
                runCatching { mpv.setPropertyDouble("speed", target) }
                updateState(
                    state.copy(
                        speed = target,
                        statusText = "Playback speed changed",
                        error = null,
                    ),
                )
            } else {
                updateState(
                    state.copy(error = buildUnavailableMessage("playback speed change")),
                )
            }
        }
        return true
    }

    /**
     * 临时改 mpv 输出音量（0~100，duck 用）。与音频页的「音量增益」走不同属性互不干扰：
     * 这里改的是 mpv `volume`（基础输出），增益走 af 滤镜链。焦点 duck/还原成对调用。
     */
    fun setPlaybackVolume(volume: Double) {
        if (disposed) return
        runOnPlaybackThread {
            if (initialized && mpv.isAvailable()) {
                runCatching { mpv.setPropertyDouble("volume", volume.coerceIn(0.0, 100.0)) }
            }
        }
    }

    /** 读当前 mpv `volume`（duck 前缓存原值用）。失败回退 100。 */
    fun getPlaybackVolume(): Double {
        if (disposed) return 100.0
        return runCatching { mpv.getPropertyDouble("volume") }
            .getOrDefault(100.0)
            .let { if (it <= 0.0) 100.0 else it }
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
                        mpv.observeProperty("paused-for-cache", 4)
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
    ) {
        // 分屏/resize 后 SurfaceView 尺寸变了，必须把新尺寸告诉 mpv，否则它仍按旧（全屏）
        // 尺寸渲染、被系统缩放进窄栏 → 画面被压缩（android-surface-size 是 mpv-android 标准机制）。
        if (width <= 0 || height <= 0) return
        runOnPlaybackThread {
            if (!initialized || !mpv.isAvailable()) return@runOnPlaybackThread
            runCatching {
                mpv.setPropertyString("android-surface-size", "${width}x$height")
            }
        }
    }

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
            val wasPlaying = state.playbackPhase == MpvPlaybackPhase.PLAYING.wireValue
            if (state.positionMs > 0L) {
                restoreCoordinator.onSeekQueued(state.positionMs)
            }
            // 听视频模式、或用户开了「熄屏继续播放音频」：熄屏/锁屏丢 surface 时不暂停，
            // 音频继续后台播放——否则一黑屏就静音，「听视频」失去意义。
            // 其余（看视频且未开此设置）仍按原行为暂停省电，亮屏复原时自动续播。
            val keepAudioOnSurfaceLoss =
                source.listenVideoModeEnabled || state.listenVideoModeEnabled ||
                    keepAudioWhenScreenOff
            val pausedForSurfaceLoss =
                if (!keepAudioOnSurfaceLoss && initialized && mpv.isAvailable() && wasPlaying) {
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
        applyWeakNetworkBufferingPolicy(force = true)
        val initialStartPositionMs = preferredResumePositionMs()
        visualPlaybackStartAnchorMs = initialStartPositionMs
        val desiredStartPaused = source.startPaused
        updateState(
            state.copy(
                ready = false,
                nativeLibLoaded = mpv.isAvailable(),
                visualPlaybackReady = false,
                buffering = false,
                paused = desiredStartPaused,
                positionMs = initialStartPositionMs,
                bufferedPositionMs = initialStartPositionMs.coerceAtLeast(0L),
                statusText = "Preparing player",
                error = null,
            ),
        )
        if (!pauseController.setPausedState(paused = desiredStartPaused, initialized = initialized)) {
            Log.w(
                TAG,
                "failed to prime pause state before load desired=$desiredStartPaused url=${source.url}",
            )
        }
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
                buffering = false,
                paused = if (loaded) desiredStartPaused else true,
                positionMs = initialStartPositionMs,
                bufferedPositionMs = initialStartPositionMs.coerceAtLeast(0L),
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
            source = source.copy(startPaused = state.paused)
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

    private fun derivePlaybackPhase(next: MpvPlayerState): MpvPlaybackPhase {
        val sessionSnapshot = sessionGate.currentSnapshot()
        if (!next.error.isNullOrBlank()) {
            return MpvPlaybackPhase.ERROR
        }
        if (
            !sessionSnapshot.sourceSwitchInProgress &&
            !sessionSnapshot.loadCommandInFlight &&
            !loadState.sourceFileLoaded &&
            next.paused &&
            isNearPlaybackCompletion(next.positionMs, next.durationMs)
        ) {
            return MpvPlaybackPhase.ENDED
        }
        if (restoreCoordinator.isSeekingOrRestoringVideo) {
            return MpvPlaybackPhase.SEEKING
        }
        if (next.buffering) {
            return MpvPlaybackPhase.BUFFERING
        }
        if (
            !next.nativeLibLoaded ||
            !created ||
            !next.ready ||
            source.url.isBlank() ||
            sessionSnapshot.sourceSwitchInProgress ||
            sessionSnapshot.loadCommandInFlight ||
            !loadState.sourceFileLoaded ||
            !hasUsableVideoOutputTarget() ||
            (!source.listenVideoModeEnabled && !state.listenVideoModeEnabled && !videoOutputReady)
        ) {
            return MpvPlaybackPhase.PREPARING
        }
        if (next.paused) {
            return MpvPlaybackPhase.PAUSED
        }
        if (
            !next.visualPlaybackReady &&
            !source.listenVideoModeEnabled &&
            !next.listenVideoModeEnabled
        ) {
            return MpvPlaybackPhase.PREPARING
        }
        if (next.ready && next.nativeLibLoaded) {
            return MpvPlaybackPhase.PLAYING
        }
        return MpvPlaybackPhase.IDLE
    }

    private fun resumedStatusText(): String {
        return when {
            state.paused -> "Playback paused"
            loadState.sourceFileLoaded -> "Playback resumed"
            else -> state.statusText
        }
    }

    private fun handleBufferingLog(prefix: String, lowerMessage: String): Boolean {
        val lowerPrefix = prefix.lowercase()
        if (!lowerPrefix.startsWith("cplayer")) {
            return false
        }
        val nowUptimeMs = SystemClock.uptimeMillis()
        return when {
            lowerMessage.contains("enter buffering") || lowerMessage.contains("still buffering") -> {
                weakNetworkBufferingController.onBufferingStateChanged(
                    buffering = true,
                    qualifiesAsRebuffer = shouldTrackWeakNetworkRebuffer(),
                    nowUptimeMs = nowUptimeMs,
                )
                refreshWeakNetworkMetrics()
                if (state.playbackPhase != MpvPlaybackPhase.BUFFERING.wireValue || !state.buffering) {
                    updateState(
                        state.copy(
                            buffering = true,
                            statusText = "Buffering",
                            error = null,
                        ),
                    )
                }
                true
            }
            lowerMessage.contains("end buffering") -> {
                weakNetworkBufferingController.onBufferingStateChanged(
                    buffering = false,
                    qualifiesAsRebuffer = false,
                    nowUptimeMs = nowUptimeMs,
                )
                refreshWeakNetworkMetrics()
                if (state.buffering || state.playbackPhase == MpvPlaybackPhase.BUFFERING.wireValue) {
                    updateState(
                        state.copy(
                            buffering = false,
                            statusText = resumedStatusText(),
                            error = null,
                        ),
                    )
                }
                true
            }
            else -> false
        }
    }

    private fun defaultStatusTextForPhase(phase: MpvPlaybackPhase, previous: MpvPlayerState): String {
        return when (phase) {
            MpvPlaybackPhase.IDLE -> "Preparing player"
            MpvPlaybackPhase.PREPARING ->
                when {
                    source.url.isBlank() -> "Waiting for playback source"
                    !hasUsableVideoOutputTarget() -> "Waiting for video surface"
                    !videoOutputReady && !source.listenVideoModeEnabled && !state.listenVideoModeEnabled ->
                        "Preparing video renderer"
                    else -> "Preparing playback"
                }
            MpvPlaybackPhase.BUFFERING -> "Buffering"
            MpvPlaybackPhase.PLAYING -> "Playback started"
            MpvPlaybackPhase.PAUSED -> "Playback paused"
            MpvPlaybackPhase.SEEKING -> "Seeking"
            MpvPlaybackPhase.ENDED -> "Playback ended"
            MpvPlaybackPhase.ERROR -> previous.statusText.ifBlank { "Playback error" }
        }
    }

    private fun updateState(next: MpvPlayerState) {
        val positionSampleTimeNs =
            when {
                next.positionSampleTimeNs > 0L -> next.positionSampleTimeNs
                next.positionMs != state.positionMs -> System.nanoTime()
                else -> state.positionSampleTimeNs
            }
        val weakNetworkSnapshot = currentWeakNetworkSnapshot()
        val phase = derivePlaybackPhase(next)
        val buffering = phase == MpvPlaybackPhase.BUFFERING
        val normalizedStatus =
            next.statusText.trim().ifBlank {
                defaultStatusTextForPhase(phase, state)
            }.lowercase()
        val clearVisualPlaybackReady =
            !next.ready ||
                next.error != null ||
                VISUAL_PLAYBACK_RESET_STATUSES.contains(normalizedStatus)
        val enriched =
            next.copy(
                playbackPhase = phase.wireValue,
                buffering = buffering,
                statusText = next.statusText.trim().ifBlank {
                    defaultStatusTextForPhase(phase, state)
                },
                weakNetworkMode = weakNetworkSnapshot.weakNetworkMode,
                networkSpeedBytesPerSecond = weakNetworkSnapshot.networkSpeedBytesPerSecond,
                rebufferTargetMs = weakNetworkSnapshot.rebufferTargetMs,
                estimatedResumeWaitMs = weakNetworkSnapshot.estimatedResumeWaitMs,
                visualPlaybackReady =
                    if (clearVisualPlaybackReady) {
                        false
                    } else {
                        next.visualPlaybackReady
                    },
                nativeProxySessionId = sourceResolver.activeProxySessionId,
                cacheResourceKey = sourceResolver.activeCacheResourceKey,
                positionSampleTimeNs = positionSampleTimeNs,
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
        val controller = danmakuOcclusionController ?: return
        controller.updatePlaybackState(
            paused = state.playbackPhase != MpvPlaybackPhase.PLAYING.wireValue,
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
        if (!initialized || !mpv.isAvailable() || !loadState.sourceFileLoaded) {
            return emptyList()
        }
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
                if (entries.isNotEmpty() && emptyStreak >= 3) {
                    break
                }
                if (reportedCount > 0 && index >= 7 && emptyStreak >= 8) {
                    // Some mpv/Android states report a bogus count (for example 64)
                    // while every track-list/N/type read is empty. Stop scanning early
                    // in that case instead of hammering nonexistent entries.
                    break
                }
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
                    selected = currentMpvFlag("track-list/$index/selected") == true,
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
            updateState(
                state.copy(
                    statusText = "Seeking",
                    error = null,
                ),
            )
            Log.w(TAG, "seek queued while surface unavailable positionMs=$positionMs")
            return true
        }
        restoreCoordinator.onSeekQueued(positionMs)
        updateState(
            state.copy(
                statusText = "Seeking",
                error = null,
            ),
        )
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
                    updateState(
                        state.copy(
                            paused = value,
                            statusText =
                                when {
                                    state.buffering && !value -> "Buffering"
                                    value && !state.buffering -> "Playback paused"
                                    !value && !state.buffering && loadState.sourceFileLoaded -> "Playback resumed"
                                    else -> state.statusText
                                },
                            error = null,
                        ),
                    )
                }
                "paused-for-cache" -> {
                    weakNetworkBufferingController.onBufferingStateChanged(
                        buffering = value,
                        qualifiesAsRebuffer = if (value) shouldTrackWeakNetworkRebuffer() else false,
                        nowUptimeMs = SystemClock.uptimeMillis(),
                    )
                    refreshWeakNetworkMetrics()
                    updateState(
                        state.copy(
                            buffering = value,
                            statusText =
                                when {
                                    value -> "Buffering"
                                    else -> resumedStatusText()
                                },
                            error = null,
                        ),
                    )
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
                    val positionSampleTimeNs = System.nanoTime()
                    val visualReadyFromProgress =
                        shouldMarkVisualPlaybackReadyFromProgress(positionMs)
                    // 蠢措施：paused-for-cache 真生效时画面是停的、time-pos 不会前进。所以一旦位置在推进
                    // 又没暂停，缓冲态必是残留（漏报 end-buffering / paused-for-cache=false）——强制收掉，
                    // 否则正在播放却一直挂「缓冲中…网速」。换源/seek 由各自路径另行置位，不受影响。
                    val advancingWhilePlaying =
                        state.buffering &&
                            !state.paused &&
                            !restoreCoordinator.isSeekingOrRestoringVideo &&
                            positionMs > state.positionMs
                    if (advancingWhilePlaying) {
                        weakNetworkBufferingController.onBufferingStateChanged(
                            buffering = false,
                            qualifiesAsRebuffer = false,
                            nowUptimeMs = SystemClock.uptimeMillis(),
                        )
                    }
                    refreshWeakNetworkMetrics()
                    handleRestorePlan(
                        restoreCoordinator.onTimePosition(positionMs),
                        "property:time-pos",
                    )
                    updateState(
                        state.copy(
                            visualPlaybackReady =
                                state.visualPlaybackReady || visualReadyFromProgress,
                            buffering = if (advancingWhilePlaying) false else state.buffering,
                            positionMs = positionMs,
                            bufferedPositionMs = bufferedPositionFor(positionMs),
                            error = null,
                            positionSampleTimeNs = positionSampleTimeNs,
                        ),
                    )
                    maybeTriggerAutomaticFilterFallback()
                }
                "demuxer-cache-duration" -> {
                    observedCacheDurationMs = (value * 1000.0).toLong().coerceAtLeast(0L)
                    refreshWeakNetworkMetrics()
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
                mpv.onStartFile() -> {
                    val pausedOnStart = currentMpvFlag("pause") ?: state.paused
                    updateState(
                        state.copy(
                            ready = false,
                            nativeLibLoaded = mpv.isAvailable(),
                            visualPlaybackReady = false,
                            buffering = false,
                            paused = pausedOnStart,
                            statusText = "Opening source",
                            error = null,
                        ),
                    )
                }
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
                    visualPlaybackStartAnchorMs = maxOf(
                        visualPlaybackStartAnchorMs,
                        state.positionMs,
                    )
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
                    val bufferingAfterFileLoaded = currentMpvFlag("paused-for-cache") == true
                    if (bufferingAfterFileLoaded) {
                        weakNetworkBufferingController.onBufferingStateChanged(
                            buffering = true,
                            qualifiesAsRebuffer = shouldTrackWeakNetworkRebuffer(),
                            nowUptimeMs = SystemClock.uptimeMillis(),
                        )
                        refreshWeakNetworkMetrics()
                    }
                    updateState(
                        state.copy(
                            ready = true,
                            nativeLibLoaded = mpv.isAvailable(),
                            paused = pausedAfterFileLoaded,
                            visualPlaybackReady = false,
                            buffering = bufferingAfterFileLoaded,
                            statusText = if (bufferingAfterFileLoaded) {
                                "Buffering"
                            } else if (pausedAfterFileLoaded) {
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
            handleBufferingLog(prefix, lowerMessage)
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
            maybeTriggerAudioPassthroughFallback(lowerMessage)
            applyRecoveryDecision(lowerMessage)
            maybeMarkVisualPlaybackReady(lowerMessage)
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
            maybeForwardLogToFlutter(prefix, level, message, lowerMessage)
        }
    }

    // 同一 playbackThread 内访问，无需额外同步。键=prefix|message，值=上次转发时刻。
    private val forwardedLogTimestamps =
        object : LinkedHashMap<String, Long>(32, 0.75f, false) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, Long>,
            ): Boolean = size > 64
        }

    /**
     * 把 mpv 的 error/warn 级日志(level<=2)经反向通道送进 Flutter 应用内日志，使设置→日志
     * 界面能看到原生播放内核的报错。过滤属性探测噪声、去重并限长；无 host 绑定时 dispatch
     * 自行降级丢弃，不影响播放。
     */
    private fun maybeForwardLogToFlutter(
        prefix: String,
        level: Int,
        message: String,
        lowerMessage: String,
    ) {
        if (level > 2 || message.isEmpty()) return
        if (LOG_FORWARD_BENIGN_PATTERNS.any { lowerMessage.contains(it) }) return
        val key = "$prefix|$message"
        val now = SystemClock.elapsedRealtime()
        val last = forwardedLogTimestamps[key]
        if (last != null && now - last < LOG_FORWARD_DEDUP_WINDOW_MS) return
        forwardedLogTimestamps[key] = now
        val trimmed =
            if (message.length > LOG_FORWARD_MAX_MESSAGE_CHARS) {
                message.substring(0, LOG_FORWARD_MAX_MESSAGE_CHARS) + "…"
            } else {
                message
            }
        NativePlayerReverseBridge.dispatch(
            "recordNativeLog",
            mapOf(
                "level" to if (level <= 1) "error" else "warning",
                "source" to "mpv",
                "prefix" to prefix,
                "message" to trimmed,
            ),
        )
    }

    private fun maybeMarkVisualPlaybackReady(lowerMessage: String) {
        if (state.visualPlaybackReady) return
        val firstVideoFrameShown =
            lowerMessage.contains("first video frame after restart shown")
        val playbackRestartComplete =
            lowerMessage.contains("playback restart complete") &&
                lowerMessage.contains("video=playing") &&
                (lowerMessage.contains("audio=playing") ||
                    lowerMessage.contains("audio=ready") ||
                    lowerMessage.contains("audio=disabled") ||
                    lowerMessage.contains("audio=none"))
        if (!firstVideoFrameShown && !playbackRestartComplete) return
        updateState(
            state.copy(
                ready = true,
                nativeLibLoaded = mpv.isAvailable(),
                visualPlaybackReady = true,
                error = null,
            ),
        )
    }

    private fun shouldMarkVisualPlaybackReadyFromProgress(positionMs: Long): Boolean {
        if (state.visualPlaybackReady) return false
        if (!loadState.sourceFileLoaded) return false
        if (!state.ready || !state.nativeLibLoaded) return false
        if (state.paused || state.buffering) return false
        if (restoreCoordinator.isSeekingOrRestoringVideo) return false
        if (source.listenVideoModeEnabled || state.listenVideoModeEnabled) return false
        if (!videoOutputReady || !hasUsableVideoOutputTarget()) return false
        return positionMs >= visualPlaybackStartAnchorMs + VISUAL_PLAYBACK_PROGRESS_FALLBACK_MS
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

    private fun maybeTriggerAudioPassthroughFallback(lowerMessage: String) {
        if (!isAudioPassthroughInitFailure(lowerMessage)) return
        if (!advancedSettingsController.triggerAudioPassthroughFallback()) return
        if (!initialized || !mpv.isAvailable()) return
        // 直通失败回退到解码：重套高级设置（fingerprint 含回退标志，不会被去抖跳过），af/spdif 立即生效。
        advancedSettingsController.apply(initialized, mpv.isAvailable(), source)
        updateState(
            state.copy(
                statusText = "直通输出不被支持，已切换为解码播放",
                error = null,
            ),
        )
        Log.w(TAG, "audio passthrough fallback applied after log=\"$lowerMessage\"")
    }

    /** 直通(spdif/AudioTrack)初始化失败的日志特征：保守匹配，避免误伤普通音频日志。 */
    private fun isAudioPassthroughInitFailure(lowerMessage: String): Boolean {
        val mentionsPassthrough =
            lowerMessage.contains("spdif") ||
                lowerMessage.contains("passthrough") ||
                lowerMessage.contains("audiotrack")
        if (!mentionsPassthrough) return false
        return lowerMessage.contains("fail") ||
            lowerMessage.contains("error") ||
            lowerMessage.contains("not support") ||
            lowerMessage.contains("unsupported") ||
            lowerMessage.contains("could not open") ||
            lowerMessage.contains("init")
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
        // 已到顶级（视频已最省 + 已请求压弹幕）就不再采样。
        if (performanceFallbackLevel >= PERFORMANCE_FALLBACK_MAX_LEVEL) return
        if (!initialized || !mpv.isAvailable()) return
        if (!loadState.sourceFileLoaded || !isCurrentSourceStable()) return
        if (state.playbackPhase != MpvPlaybackPhase.PLAYING.wireValue || state.positionMs < 3000L) {
            return
        }

        val now = SystemClock.uptimeMillis()
        // 间隔门提前到读取之前:采样窗只需 ~1.5s 一次,不必每个 time-pos(数 Hz)都查 mpv 计数器。
        // 首采样窗(lastFilterFallbackSampleUptimeMs==0)例外,需要立刻读取基线。
        val firstSampleWindow = lastFilterFallbackSampleUptimeMs == 0L
        if (!firstSampleWindow &&
            now - lastFilterFallbackSampleUptimeMs < FILTER_FALLBACK_SAMPLE_INTERVAL_MS
        ) {
            return
        }

        // 真实存在的 mpv 属性是 frame-drop-count（VO 丢帧），不是 drop-frame-count——后者在本
        // 构建里恒为 not-found，曾导致整个自适应降级形同虚设（4K60 HDR 无任何保护直接 ANR）。
        // mistimed-frame-count / vo-delayed-frame-count 在部分构建同样恒不可用,首次 miss 后缓存跳过。
        val dropFrameCount = samplePerformanceCounter("frame-drop-count")
        val decoderDropFrameCount = samplePerformanceCounter("decoder-frame-drop-count")
        val mistimedFrameCount = samplePerformanceCounter("mistimed-frame-count")
        val voDelayedFrameCount = samplePerformanceCounter("vo-delayed-frame-count")

        if (firstSampleWindow) {
            lastFilterFallbackSampleUptimeMs = now
            lastDropFrameCount = dropFrameCount
            lastDecoderDropFrameCount = decoderDropFrameCount
            lastMistimedFrameCount = mistimedFrameCount
            lastVoDelayedFrameCount = voDelayedFrameCount
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
        if (!unstablePlayback) {
            // 出现一个正常窗就清零连续计数——只对"持续"卡顿动手,不被瞬时尖峰带偏。
            consecutiveUnstableFallbackWindows = 0
            return
        }

        consecutiveUnstableFallbackWindows += 1
        Log.d(
            TAG,
            "perf sample unstable window=$consecutiveUnstableFallbackWindows/$FILTER_FALLBACK_CONSECUTIVE_WINDOWS " +
                "dropDelta=$dropDelta mistimedDelta=$mistimedDelta",
        )
        if (consecutiveUnstableFallbackWindows < FILTER_FALLBACK_CONSECUTIVE_WINDOWS) return
        consecutiveUnstableFallbackWindows = 0
        escalatePerformanceFallback(dropDelta, mistimedDelta)
    }

    /**
     * 自适应性能阶梯（反应式，强设备不掉帧就永不触发）：
     *  - L0→L1（方案 B）：把视频渲染降到最省档（剥离增强 + 缩放强制 bilinear），宿主并关 AI 遮罩，toast。
     *  - L1→L2（方案 C）：视频已最省仍掉帧，请求宿主压低弹幕负载（经 state 级别下发）。
     *  - L2→L3（路线1）：仍掉帧 → 把 mpv 渲染后端 Vulkan→GLES 重载（避开与 Flutter Impeller 的双
     *    Vulkan 显存争用），**保留 HDR 直通**。弱 Adreno 4K HDR 卡死多因双 Vulkan，退 GLES 常能直接播 HDR。
     *  - L3→L4（方案 D，最后兜底）：退 GLES 仍掉帧才放弃 HDR，降为 HDR→SDR 映射（8bit 输出），
     *    削掉 4K HDR 10bit 交换链 + libplacebo 大纹理分配导致的卡死/ANR 根因。
     * 每升一级就重置采样窗口，给上一级的缓解措施留出生效时间，避免一次性连跳多级。
     */
    private fun escalatePerformanceFallback(dropDelta: Long, mistimedDelta: Long) {
        when (performanceFallbackLevel) {
            0 -> {
                val changed = advancedSettingsController.escalateVideoPerformanceFallback(
                    initialized = initialized,
                    available = mpv.isAvailable(),
                    source = source,
                )
                syncVideoOutputState()
                // 即便属性下发个别失败，也置为已降级，避免在尖峰里反复重试。
                performanceFallbackLevel = 1
                Log.w(
                    TAG,
                    "perf fallback L1 (video) changed=$changed dropDelta=$dropDelta " +
                        "mistimedDelta=$mistimedDelta scale=${currentMpvString("scale")} " +
                        "cscale=${currentMpvString("cscale")} source=[${source.debugSummary()}]",
                )
                updateState(
                    state.copy(
                        statusText = AUTO_FILTER_FALLBACK_STATUS,
                        performanceFallbackLevel = 1,
                        error = null,
                    ),
                )
            }
            1 -> {
                performanceFallbackLevel = 2
                Log.w(
                    TAG,
                    "perf fallback L2 (danmaku) dropDelta=$dropDelta " +
                        "mistimedDelta=$mistimedDelta source=[${source.debugSummary()}]",
                )
                updateState(
                    state.copy(
                        performanceFallbackLevel = 2,
                        error = null,
                    ),
                )
            }
            2 -> {
                // L3（路线1）：先试把 mpv 渲染后端 Vulkan→GLES（避开与 Flutter Impeller 的双
                // Vulkan 显存争用），保留 HDR 直通——很多弱 Adreno 的 4K HDR 卡死根因是双 Vulkan，
                // 退 GLES 后直通能跑就不必牺牲 HDR。需重载让 VO 在 GLES 下重建。已是 GLES 则跳过。
                val switched = downgradeGpuContextToGles()
                performanceFallbackLevel = 3
                Log.w(
                    TAG,
                    "perf fallback L3 (vulkan->gles, keep HDR) switched=$switched dropDelta=$dropDelta " +
                        "mistimedDelta=$mistimedDelta source=[${source.debugSummary()}]",
                )
                updateState(
                    state.copy(
                        performanceFallbackLevel = 3,
                        error = null,
                    ),
                )
                if (switched) reloadCurrentSource("perf: vulkan->gles to keep 4K HDR direct")
            }
            3 -> {
                // L4（最后兜底）：退 GLES 仍掉帧，才放弃 HDR 直通，降为 HDR→SDR 映射。
                val changed = videoOutputController.escalateColorPipelineToTonemap(
                    initialized = initialized,
                    available = mpv.isAvailable(),
                )
                syncVideoOutputState()
                performanceFallbackLevel = 4
                Log.w(
                    TAG,
                    "perf fallback L4 (hdr->sdr) changed=$changed dropDelta=$dropDelta " +
                        "mistimedDelta=$mistimedDelta source=[${source.debugSummary()}]",
                )
                updateState(
                    state.copy(
                        performanceFallbackLevel = 4,
                        error = null,
                    ),
                )
            }
        }
        // 升级后重置窗口，下一级需要重新积累一窗掉帧。
        lastFilterFallbackSampleUptimeMs = 0L
    }

    private fun clearVideoStreamFailure() {
        videoStreamLost = false
        videoStreamLossReason = null
    }

    private fun downgradeGpuContextToGles(): Boolean {
        // 当前 VideoOutputController 没有公开 GPU backend 切换接口。
        // 保守返回 false，让后续 HDR->SDR 映射 fallback 继续接管。
        return false
    }

    private fun currentWeakNetworkSnapshot(): WeakNetworkBufferingSnapshot {
        return weakNetworkBufferingController.snapshot(
            isRemoteSource = source.isRemoteHttpSource(),
            sourceBitrateBitsPerSec = source.bitrate.toLong().coerceAtLeast(0L),
            demuxerCacheDurationMs = observedCacheDurationMs,
            nowUptimeMs = SystemClock.uptimeMillis(),
        )
    }

    private fun shouldTrackWeakNetworkRebuffer(): Boolean {
        return source.isRemoteHttpSource() &&
            loadState.sourceFileLoaded &&
            !restoreCoordinator.isSeekingOrRestoringVideo &&
            !sessionGate.currentSnapshot().sourceSwitchInProgress &&
            (state.playbackPhase == MpvPlaybackPhase.PLAYING.wireValue || state.visualPlaybackReady)
    }

    private fun refreshWeakNetworkMetrics() {
        if (!initialized || !mpv.isAvailable()) return
        if (!source.isRemoteHttpSource()) {
            applyWeakNetworkBufferingPolicy()
            return
        }
        val sampleBytesPerSecond =
            if (sourceResolver.activeProxySessionId != null) {
                sanitizeWeakNetworkSpeedSampleBytesPerSecond(
                    sourceResolver.activeNetworkSpeedBytesPerSecond(),
                )
            } else {
                resolveMpvCacheSpeedSampleBytesPerSecond(
                    rawIntBytesPerSecond = rawMpvInt("cache-speed"),
                    rawStringBytesPerSecond = currentMpvString("cache-speed"),
                )
            }
        weakNetworkBufferingController.onCacheSpeedSample(
            sampleBytesPerSecond = sampleBytesPerSecond,
            nowUptimeMs = SystemClock.uptimeMillis(),
        )
        applyWeakNetworkBufferingPolicy()
    }

    private fun applyWeakNetworkBufferingPolicy(force: Boolean = false) {
        if (!initialized || !mpv.isAvailable()) return
        val snapshot = currentWeakNetworkSnapshot()
        val targetMs = snapshot.rebufferTargetMs.coerceAtLeast(0L)
        if (!force && targetMs == lastAppliedCachePauseWaitMs) {
            return
        }
        lastAppliedCachePauseWaitMs = targetMs
        runCatching {
            mpv.setPropertyDouble("cache-pause-wait", targetMs.toDouble() / 1000.0)
        }.onFailure { error ->
            Log.w(TAG, "failed to apply cache-pause-wait=${targetMs}ms", error)
        }
    }

    private fun clearProxyOpenFailure() {
        proxyOpenFailed = false
        proxyOpenFailureReason = null
    }

    private fun resetAutomaticFilterFallbackMonitor() {
        performanceFallbackLevel = 0
        lastFilterFallbackSampleUptimeMs = 0L
        lastDropFrameCount = 0L
        lastDecoderDropFrameCount = 0L
        lastMistimedFrameCount = 0L
        lastVoDelayedFrameCount = 0L
        unavailablePerfCounters.clear()
        consecutiveUnstableFallbackWindows = 0
    }

    private fun resetWeakNetworkBuffering() {
        weakNetworkBufferingController.reset()
        observedCacheDurationMs = 0L
        lastAppliedCachePauseWaitMs = Long.MIN_VALUE
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
        return isNearPlaybackCompletion(state.positionMs, state.durationMs)
    }

    private fun isNearPlaybackCompletion(positionMs: Long, durationMs: Long): Boolean {
        if (durationMs <= 0L) return false
        return positionMs >= (durationMs - 1500L).coerceAtLeast(0L)
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

    /**
     * 解码/输出诊断快照（供轨道信息页排查用）：实际 hwdec、色彩管线、是否触发过自动回退、
     * 音频输出路径（直通编码 / PCM 解码）、丢帧数、容器帧率。直接读 mpv 属性，缺失项为 null。
     */
    fun getPlaybackDiagnostics(): Map<String, Any?> {
        val forcedHwdec = videoOutputController.forcedHwdecMode
        val forcedPipeline = videoOutputController.forcedColorPipeline
        val fallbackReasons = mutableListOf<String>()
        if (forcedHwdec != null) fallbackReasons += "hwdec→$forcedHwdec"
        if (forcedPipeline != null) fallbackReasons += "色彩→$forcedPipeline"
        // 直通仅对 spdif 可位流的压缩编码生效（见 AudioPassthroughSupport.ALL_CODECS：
        // ac3/eac3/dts/dts-hd/truehd）。FLAC/PCM/AAC/Opus 等即便配置开了直通也会被解码成 PCM，
        // 故诊断按「设置开直通 且 当前轨编码本身能位流」上报，避免把解码中的 FLAC 误标「直通(flac)」。
        val audioCodecName = currentMpvString("audio-codec-name")
        val passthroughCapableCodec = audioCodecName?.lowercase()?.let { name ->
            name in PASSTHROUGH_CAPABLE_CODECS || name.startsWith("dts")
        } ?: false
        val passthroughActive =
            advancedSettingsController.isAudioPassthroughActive() && passthroughCapableCodec
        return mapOf(
            "hwdecCurrent" to currentMpvString("hwdec-current"),
            "colorPipeline" to videoOutputController.activeColorPipeline.name,
            "windowColorMode" to videoOutputController.currentWindowColorMode(),
            "fallbackTriggered" to fallbackReasons.isNotEmpty(),
            "fallbackReason" to fallbackReasons.joinToString(" / "),
            "audioPassthrough" to passthroughActive,
            "audioCodec" to audioCodecName,
            "audioFormat" to currentMpvString("audio-params/format"),
            "audioOut" to currentMpvString("current-ao"),
            "audioChannels" to currentMpvString("audio-params/channels"),
            "audioOutChannels" to currentMpvString("audio-out-params/channels"),
            "audioChannels" to currentMpvString("audio-params/channels"),
            "audioOutChannels" to currentMpvString("audio-out-params/channels"),
            "containerFps" to (runCatching { mpv.getPropertyDouble("container-fps") }.getOrNull()),
            "estimatedFps" to (runCatching { mpv.getPropertyDouble("estimated-vf-fps") }.getOrNull()),
            "droppedFrames" to currentPerformanceCounter("frame-drop-count"),
            "decoderDroppedFrames" to currentPerformanceCounter("decoder-frame-drop-count"),
        )
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

    /**
     * 读取性能计数器,并缓存"恒不可用"的属性:首次返回 null(本构建没有该属性)后记入
     * [unavailablePerfCounters],后续直接返回 0 而不再发 JNI 查询——避免每个采样窗对恒空属性
     * 反复查询、刷 V/mpv 日志。每源 [resetAutomaticFilterFallbackMonitor] 时清空重新探测一次。
     */
    private fun samplePerformanceCounter(property: String): Long {
        if (property in unavailablePerfCounters) return 0L
        val value = currentMpvInt(property)
        if (value == null) {
            unavailablePerfCounters += property
            return 0L
        }
        return value
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
