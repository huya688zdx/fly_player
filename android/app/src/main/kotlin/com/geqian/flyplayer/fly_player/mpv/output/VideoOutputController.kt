package com.geqian.flyplayer.fly_player.mpv

import android.app.Activity
import android.content.pm.ActivityInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Log
import android.view.Surface
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

private const val VIDEO_OUTPUT_TAG = "FlyPlayerMpv"
private const val VIDEO_OUTPUT_GPU = "gpu"
private const val VIDEO_OUTPUT_NONE = "null"
private const val VIDEO_HWDEC_DEFAULT = "mediacodec,auto-safe"
private const val VIDEO_HWDEC_HDR_COPY = "mediacodec-copy"
private const val VIDEO_HWDEC_DISABLED = "no"
private const val VIDEO_ASPECT_OVERRIDE_NONE = "no"
private const val VIDEO_ASPECT_MODE_FIT = "fit"
private const val VIDEO_ASPECT_MODE_FILL = "fill"
private const val VIDEO_ASPECT_MODE_4X3 = "4:3"
private const val VIDEO_ASPECT_MODE_16X9 = "16:9"
private const val VIDEO_ASPECT_MODE_21X9 = "21:9"
private const val VIDEO_TONE_MAPPING = "bt.2390"
private const val VIDEO_TARGET_PRIM_SDR = "bt.709"
private const val VIDEO_TARGET_TRC_SDR = "bt.1886"

class VideoOutputController(
    private val videoOutputTarget: VideoOutputTarget,
    private val hostActivity: Activity?,
    val displayProfile: DisplayProfile,
    val deviceProfile: DeviceProfile,
    private val runOnMainThread: (() -> Unit) -> Unit,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private val controllerInstanceId = nextControllerInstanceId()
    private var lastErrorMessage: String? = null
    private var latestSurfaceGeneration = -1L
    private var attachedSurfaceGeneration = -1L
    private var attachedSurfaceIdentity = 0
    var surfaceReady = false
        private set
    var surfaceAttached = false
        private set
    var videoOutputReady = false
        private set
    var videoTrackSuspended = false
        private set
    var activeHwdecMode = VIDEO_HWDEC_DEFAULT
        private set
    var forcedHwdecMode: String? = null
        private set
    private var userHwdecMode: String? = null
    private var displayAspectRatioMode = VIDEO_ASPECT_MODE_FIT
    var forcedColorPipeline: VideoColorPipeline? = null
        private set
    var activeColorPipeline = VideoColorPipeline.SDR
        private set
    private var advancedHdrMode = "auto"
    private var toneMappingPreference = "auto"
    // 会话级性能学习：一旦本会话因弱 GPU 4K HDR 触发过 L3（HDR 直通→映射），就记住——
    // 之后同类内容（超高清 + HDR）直接从映射起步，不再每次重载都弹回 HDR 直通再卡死。
    // 跟 URL 无关（代理源每次重解析 URL 会变，URL-gate 失效），按内容类判定。仅 onDispose 清。
    private var sessionForceHdrTonemapForUltraHd = false
    private var compatibilityProfile = "default"
    private var filterCompatibleFramesRequired = false
    private var activeVideoOutputName = VIDEO_OUTPUT_NONE
    private var forceWindowEnabled = true
    private var activeAspectOverride = VIDEO_ASPECT_OVERRIDE_NONE
    private var activePanscan = 0.0

    fun resetForSourceLoad() {
        forcedHwdecMode = null
        forcedColorPipeline = null
        activeColorPipeline = VideoColorPipeline.SDR
    }

    fun onDispose() {
        clearGlobalSurfaceOwnerIfOwned()
        surfaceAttached = false
        videoOutputReady = false
        videoTrackSuspended = false
        activeColorPipeline = VideoColorPipeline.SDR
        lastErrorMessage = null
        latestSurfaceGeneration = -1L
        attachedSurfaceGeneration = -1L
        attachedSurfaceIdentity = 0
        activeVideoOutputName = VIDEO_OUTPUT_NONE
        forceWindowEnabled = true
        activeAspectOverride = VIDEO_ASPECT_OVERRIDE_NONE
        activePanscan = 0.0
        sessionForceHdrTonemapForUltraHd = false
        applyWindowColorMode(VideoColorPipeline.SDR)
    }

    fun consumeLastErrorMessage(): String? {
        val message = lastErrorMessage
        lastErrorMessage = null
        return message
    }

    fun onSurfaceAvailable(
        surface: Surface,
        generation: Long,
    ): Boolean {
        if (generation < latestSurfaceGeneration) {
            return true
        }
        latestSurfaceGeneration = generation
        surfaceReady = true
        lastErrorMessage = null
        return runCatching {
            rebindSurface(surface, "surfaceAvailable", generation)
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("surface attachment", error)
        }.getOrDefault(false)
    }

    fun onSurfaceDestroyed(
        initialized: Boolean,
        available: Boolean,
        generation: Long,
    ) {
        if (generation < latestSurfaceGeneration) {
            return
        }
        latestSurfaceGeneration = generation
        surfaceReady = false
        videoOutputReady = false
        lastErrorMessage = null
        runCatching {
            if (surfaceAttached && attachedSurfaceGeneration <= generation) {
                detachAttachedSurface("surfaceDestroyed:$generation")
            }
            if (initialized && available) {
                mpv.setPropertyString("vid", "no")
                videoTrackSuspended = true
                setVideoOutputProperty(VIDEO_OUTPUT_NONE)
            }
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("video output suspension", error)
        }
        applyWindowColorMode(VideoColorPipeline.SDR)
    }

    fun onSurfaceDestroyed(initialized: Boolean, available: Boolean) {
        onSurfaceDestroyed(
            initialized = initialized,
            available = available,
            generation = latestSurfaceGeneration,
        )
    }

    fun detachSurfaceForHandoff() {
        surfaceReady = false
        videoOutputReady = false
        lastErrorMessage = null
        runCatching {
            detachAttachedSurface("handoff")
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("surface handoff", error)
        }
    }

    fun clearRetainedPlaybackStateForReuse(clearPlaybackState: () -> Unit): Boolean {
        var didClear = false
        synchronized(SURFACE_BIND_LOCK) {
            if (globalSurfaceOwnerId != 0L && globalSurfaceOwnerId != controllerInstanceId) {
                Log.d(
                    VIDEO_OUTPUT_TAG,
                    "skip retained playback clear owner=$globalSurfaceOwnerId controller=$controllerInstanceId",
                )
                resetSurfaceAttachmentState()
                return false
            }
            clearPlaybackState()
            runCatching {
                setVideoOutputProperty(VIDEO_OUTPUT_NONE)
                if (surfaceAttached && globalSurfaceOwnerId == controllerInstanceId) {
                    mpv.detachSurface()
                    globalSurfaceOwnerId = 0L
                }
                didClear = true
            }.onFailure { error ->
                lastErrorMessage = formatNativePlaybackError("surface reuse cleanup", error)
            }
            resetSurfaceAttachmentState()
        }
        return didClear
    }

    fun hasUsableVideoOutputTarget(): Boolean {
        return surfaceReady && surfaceAttached && currentSurfaceValid()
    }

    fun isSurfaceValid(): Boolean = currentSurfaceValid()

    fun preferredHwdecMode(source: MpvSource): String {
        if (compatibilityProfile == "software_fallback") {
            return VIDEO_HWDEC_DISABLED
        }
        if (userHwdecMode == VIDEO_HWDEC_DISABLED) {
            return VIDEO_HWDEC_DISABLED
        }
        if (filterCompatibleFramesRequired) {
            return VIDEO_HWDEC_HDR_COPY
        }
        forcedHwdecMode?.let { return it }
        // DV P5 无 DV 解码器：copy 出帧再走映射，避免直通 gralloc 绿/紫屏。
        if (shouldForceDolbyVisionTonemap(source)) {
            return VIDEO_HWDEC_HDR_COPY
        }
        // Mali GPU：改用 mediacodec-copy（解码帧拷回普通内存再常规上传），绕开 Mali 不认的
        // gralloc 直通格式（尤其 10-bit HEVC 的 0x38/0x3b，会触发 BufferQueue 超时）。
        // 多一次 CPU 拷贝，天玑 9200 无压力；作为 10-bit 内容的低成本保险。
        if (deviceProfile.isLikelyMali) {
            return VIDEO_HWDEC_HDR_COPY
        }
        return if (shouldPreferHwdecCopy(source)) {
            VIDEO_HWDEC_HDR_COPY
        } else {
            VIDEO_HWDEC_DEFAULT
        }
    }

    fun setDecoderMode(mode: String?): Boolean {
        val normalized = mode?.trim()?.lowercase(Locale.US)
        val nextUserMode = when (normalized) {
            "software", "soft", VIDEO_HWDEC_DISABLED -> VIDEO_HWDEC_DISABLED
            else -> null
        }
        val changed =
            userHwdecMode != nextUserMode ||
                forcedHwdecMode != null
        userHwdecMode = nextUserMode
        forcedHwdecMode = null
        return changed
    }

    fun setDisplayAspectRatioMode(
        mode: String?,
        initialized: Boolean,
        available: Boolean,
    ): Boolean {
        val normalized = when (mode?.trim()?.lowercase(Locale.US)) {
            VIDEO_ASPECT_MODE_FILL -> VIDEO_ASPECT_MODE_FILL
            VIDEO_ASPECT_MODE_4X3 -> VIDEO_ASPECT_MODE_4X3
            VIDEO_ASPECT_MODE_16X9 -> VIDEO_ASPECT_MODE_16X9
            VIDEO_ASPECT_MODE_21X9 -> VIDEO_ASPECT_MODE_21X9
            else -> VIDEO_ASPECT_MODE_FIT
        }
        val changed = displayAspectRatioMode != normalized
        displayAspectRatioMode = normalized
        if (initialized && available) {
            applyDisplayAspectRatioMode()
        }
        return changed
    }

    fun preferredColorPipeline(source: MpvSource): VideoColorPipeline {
        forcedColorPipeline?.let { return it }
        // Dolby Vision Profile 5（无 HDR10 兼容层）在无 DV 解码器的设备 mediacodec 直出会绿/紫屏，
        // 强制走 HDR→SDR 映射（配合下面 hwdec mediacodec-copy）。
        if (shouldForceDolbyVisionTonemap(source)) return VideoColorPipeline.HDR_TONEMAP_SDR
        // 会话级学习：本设备已被证明扛不住 4K HDR 直通（触发过 L3），同类内容直接走映射，
        // 否则重载会弹回直通→再卡死→再降级，无限循环。用户显式选「增强」会清除此学习。
        if (sessionForceHdrTonemapForUltraHd && source.isHdrLikely() && source.isUltraHighResolution()) {
            return VideoColorPipeline.HDR_TONEMAP_SDR
        }
        when (advancedHdrMode) {
            "sdr_map", "conservative" -> return VideoColorPipeline.HDR_TONEMAP_SDR
            "enhanced" -> {
                // 增强：仅对 HDR 片源更激进地走直出（显示器支持则直出，否则映射）。
                // SDR 片源不在此强转——不 return，落到下方 isHdrLikely 判定后归 SDR，
                // 避免把 SDR 内容塞进 HDR 容器导致发灰/发暗。
                if (source.isHdrLikely()) {
                    return if (displayProfile.supportsHdr) {
                        VideoColorPipeline.HDR_DIRECT
                    } else {
                        VideoColorPipeline.HDR_TONEMAP_SDR
                    }
                }
            }
        }
        if (!source.isHdrLikely()) return VideoColorPipeline.SDR
        return if (displayProfile.supportsHdr) {
            VideoColorPipeline.HDR_DIRECT
        } else {
            VideoColorPipeline.HDR_TONEMAP_SDR
        }
    }

    fun setAdvancedHdrMode(mode: String?, source: MpvSource): Boolean {
        val normalized =
            when (mode?.trim()?.lowercase(Locale.US)) {
                "sdr_map" -> "sdr_map"
                "conservative" -> "conservative"
                "enhanced" -> "enhanced"
                else -> "auto"
            }
        val changed = advancedHdrMode != normalized
        advancedHdrMode = normalized
        // 用户显式要求 HDR 增强（直通）= 推翻自动学到的降级，清除会话 sticky，重新尝试直通。
        if (normalized == "enhanced") {
            sessionForceHdrTonemapForUltraHd = false
            forcedColorPipeline = null
        }
        if (changed && surfaceReady && surfaceAttached && currentSurfaceValid()) {
            ensureVideoOutputReady(
                initialized = mpv.isCreated(),
                available = mpv.isAvailable(),
                source = source,
            )
        }
        return changed
    }

    /**
     * 色调映射算法偏好（仅 HDR→SDR 映射管线生效）。改变后若当前正走映射管线，直接热更新
     * mpv `tone-mapping` 属性（无需重配整条管线）。
     */
    fun setToneMappingPreference(preference: String?): Boolean {
        val normalized = normalizeToneMapping(preference)
        val changed = toneMappingPreference != normalized
        toneMappingPreference = normalized
        if (changed && activeColorPipeline == VideoColorPipeline.HDR_TONEMAP_SDR) {
            runCatching { mpv.setPropertyString("tone-mapping", resolvedToneMapping()) }
        }
        return changed
    }

    private fun normalizeToneMapping(preference: String?): String =
        when (preference?.trim()?.lowercase(Locale.US)) {
            "bt2390", "bt.2390" -> "bt2390"
            "mobius" -> "mobius"
            "hable" -> "hable"
            "reinhard" -> "reinhard"
            else -> "auto"
        }

    /** 偏好 → mpv `tone-mapping` 值。auto 沿用原默认 bt.2390，保持既有观感不变。 */
    private fun resolvedToneMapping(): String =
        when (toneMappingPreference) {
            "mobius" -> "mobius"
            "hable" -> "hable"
            "reinhard" -> "reinhard"
            else -> VIDEO_TONE_MAPPING
        }

    fun setCompatibilityProfile(profile: String?): Boolean {
        val normalized =
            when (profile?.trim()?.lowercase(Locale.US)) {
                "conservative" -> "conservative"
                "software_fallback" -> "software_fallback"
                else -> "default"
            }
        val changed = compatibilityProfile != normalized
        compatibilityProfile = normalized
        return changed
    }

    fun setFilterCompatibleFramesRequired(required: Boolean): Boolean {
        val changed = filterCompatibleFramesRequired != required
        filterCompatibleFramesRequired = required
        return changed
    }

    fun shouldForceSourceReloadAfterSurfaceRestore(source: MpvSource): Boolean {
        return shouldPreferHwdecCopy(source)
    }

    fun shouldBypassHeavyVideoFilters(source: MpvSource): Boolean {
        if (!deviceProfile.isLikelyMali) return false
        return source.isHevcLike() && source.isUltraHighResolution()
    }

    fun restoreVideoTrackAfterSurfaceReady(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        if (!videoTrackSuspended) return true
        lastErrorMessage = null
        return runCatching {
            mpv.setPropertyString("vid", "auto")
            videoTrackSuspended = false
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("video track restore", error)
        }.getOrDefault(false)
    }

    fun ensureVideoTrackSelected(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        lastErrorMessage = null
        return runCatching {
            mpv.setPropertyString("vid", "auto")
            videoTrackSuspended = false
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("video track selection", error)
        }.getOrDefault(false)
    }

    fun enableListenVideoMode(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        lastErrorMessage = null
        return runCatching {
            mpv.setPropertyString("vid", "no")
            setVideoOutputProperty(VIDEO_OUTPUT_NONE)
            videoTrackSuspended = true
            videoOutputReady = false
            applyWindowColorMode(VideoColorPipeline.SDR)
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("listen video mode", error)
        }.getOrDefault(false)
    }

    fun disableListenVideoMode(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        lastErrorMessage = null
        return runCatching {
            mpv.setPropertyString("vid", "auto")
            videoTrackSuspended = false
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("video playback mode", error)
        }.getOrDefault(false)
    }

    fun ensureVideoOutputReady(
        initialized: Boolean,
        available: Boolean,
        source: MpvSource,
    ): Boolean {
        if (!initialized || !available) return false
        if (!hasUsableVideoOutputTarget()) return false
        lastErrorMessage = null
        val targetHwdecMode = preferredHwdecMode(source)
        val targetColorPipeline = preferredColorPipeline(source)
        return runCatching {
            if (activeHwdecMode != targetHwdecMode) {
                mpv.setPropertyString("hwdec", targetHwdecMode)
                activeHwdecMode = targetHwdecMode
            }
            applyColorPipeline(targetColorPipeline)
            applyWindowColorMode(targetColorPipeline)
            setVideoOutputProperty(VIDEO_OUTPUT_GPU)
            setForceWindowProperty(true)
            applyDisplayAspectRatioMode()
            videoOutputReady = true
            Log.i(
                VIDEO_OUTPUT_TAG,
                "video pipeline hwdec=$activeHwdecMode colorPipeline=$activeColorPipeline hdr=${source.isHdrLikely()} mali=${deviceProfile.isLikelyMali} displayHdr=${displayProfile.supportsHdr} source=[${source.debugSummary()}]",
            )
            true
        }.onFailure { error ->
            videoOutputReady = false
            lastErrorMessage = formatNativePlaybackError(
                action = "video output configuration",
                error = error,
                fallbackReason = "hwdec=$targetHwdecMode colorPipeline=$targetColorPipeline",
            )
        }.getOrDefault(false)
    }

    fun recoverVideoOutputOnly(
        reason: String,
        initialized: Boolean,
        available: Boolean,
    ) {
        if (!initialized || !available) return
        if (!surfaceReady || !currentSurfaceValid()) {
            Log.w(VIDEO_OUTPUT_TAG, "skip video output recovery reason=$reason surfaceReady=$surfaceReady")
            return
        }
        val currentSurface = videoOutputTarget.currentSurface()
        if (currentSurface == null || !currentSurface.isValid) {
            Log.w(VIDEO_OUTPUT_TAG, "skip video output recovery reason=$reason surfaceMissing=true")
            return
        }
        lastErrorMessage = null
        runCatching {
            rebindSurface(currentSurface, "recover:$reason", latestSurfaceGeneration)
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError(
                action = "video output recovery",
                error = error,
                fallbackReason = reason,
            )
        }
    }

    fun maybeTriggerHdrHwdecFallback(source: MpvSource, lowerMessage: String): Boolean {
        if (!isRiskyBufferFormatMessage(lowerMessage)) return false
        if (shouldPreferHwdecCopy(source) && preferredHwdecMode(source) != VIDEO_HWDEC_HDR_COPY) {
            forcedHwdecMode = VIDEO_HWDEC_HDR_COPY
            Log.w(
                VIDEO_OUTPUT_TAG,
                "forcing video hwdec fallback to $forcedHwdecMode after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
            )
            return true
        }
        if (!source.isHdrLikely()) return false
        if (preferredHwdecMode(source) != VIDEO_HWDEC_HDR_COPY) {
            forcedHwdecMode = VIDEO_HWDEC_HDR_COPY
            Log.w(
                VIDEO_OUTPUT_TAG,
                "forcing hdr hwdec fallback to $forcedHwdecMode after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
            )
            return true
        }
        if (preferredColorPipeline(source) != VideoColorPipeline.HDR_TONEMAP_SDR) {
            forcedColorPipeline = VideoColorPipeline.HDR_TONEMAP_SDR
            Log.w(
                VIDEO_OUTPUT_TAG,
                "forcing hdr color fallback to $forcedColorPipeline after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
            )
            return true
        }
        return false
    }

    fun maybeTriggerSoftwareDecoderFallback(source: MpvSource, lowerMessage: String): Boolean {
        if (preferredHwdecMode(source) == VIDEO_HWDEC_DISABLED) return false
        val hardwareDecodeFailure =
            (lowerMessage.contains("mediacodec") &&
                (
                    lowerMessage.contains("failed") ||
                        lowerMessage.contains("error") ||
                        lowerMessage.contains("unsupported") ||
                        lowerMessage.contains("invalid")
                )) ||
                lowerMessage.contains("hardware decoding failed") ||
                lowerMessage.contains("failed to initialize decoder") ||
                lowerMessage.contains("failed to configure codec") ||
                lowerMessage.contains("codec type is not supported by mediacodec") ||
                lowerMessage.contains("hwdec") && lowerMessage.contains("failed")
        if (!hardwareDecodeFailure) return false
        userHwdecMode = VIDEO_HWDEC_DISABLED
        forcedHwdecMode = null
        Log.w(
            VIDEO_OUTPUT_TAG,
            "forcing software decoder fallback after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
        )
        return true
    }

    /**
     * 反应式性能阶梯最后一档（方案 D）：4K HDR 在弱 GPU（如 Adreno 732）上，HDR 直通的
     * 10bit/fp16 交换链 + libplacebo 大纹理分配会卡死（实测 slab 339ms slow）→ 解码输入饿死
     * 数秒 → 音频欠载 → 主线程 binder 超时 → ANR 闪退。前两档（降画质 / 压弹幕）救不了，因为
     * 瓶颈是显存/带宽不是缩放。这里把 HDR 直通降为 HDR→SDR 映射：输出 8bit（窗口退出
     * COLOR_MODE_HDR）+ 关掉逐帧峰值检测的额外 compute，显著削减交换链与中间纹理开销。
     *
     * 仅当前正走 HDR 直通才有意义；SDR / 已是映射管线返回 false（瓶颈在别处，不做无谓改动）。
     * 设 forcedColorPipeline 以便后续 surface 重挂/重配时维持映射，不回弹到直通。
     */
    fun escalateColorPipelineToTonemap(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        if (activeColorPipeline != VideoColorPipeline.HDR_DIRECT) return false
        forcedColorPipeline = VideoColorPipeline.HDR_TONEMAP_SDR
        // 记住本设备扛不住 4K HDR 直通：后续同类内容/重载直接从映射起步（见 preferredColorPipeline）。
        sessionForceHdrTonemapForUltraHd = true
        return runCatching {
            applyColorPipeline(VideoColorPipeline.HDR_TONEMAP_SDR)
            applyWindowColorMode(VideoColorPipeline.HDR_TONEMAP_SDR)
            // 弱 GPU 应急：关掉逐帧 HDR 峰值检测，省下额外 compute（映射观感影响极小）。
            runCatching { mpv.setPropertyString("hdr-compute-peak", "no") }
            Log.w(
                VIDEO_OUTPUT_TAG,
                "perf escalate color pipeline HDR_DIRECT -> HDR_TONEMAP_SDR (weak GPU 4K HDR)",
            )
            true
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("hdr tonemap escalation", error)
        }.getOrDefault(false)
    }

    fun currentWindowColorMode(): String {
        val activity = hostActivity ?: return "unknown"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        return when (activity.window.colorMode) {
            ActivityInfo.COLOR_MODE_DEFAULT -> "DEFAULT"
            ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT -> "WIDE_COLOR_GAMUT"
            ActivityInfo.COLOR_MODE_HDR -> "HDR"
            else -> activity.window.colorMode.toString()
        }
    }

    private fun currentSurfaceValid(): Boolean {
        return videoOutputTarget.isSurfaceValid()
    }

    private fun rebindSurface(
        surface: Surface,
        reason: String,
        generation: Long,
    ) {
        val nextSurfaceIdentity = System.identityHashCode(surface)
        if (!surface.isValid) {
            surfaceAttached = false
            videoOutputReady = false
            attachedSurfaceGeneration = -1L
            attachedSurfaceIdentity = 0
            activeVideoOutputName = VIDEO_OUTPUT_NONE
            error("invalid surface for $reason")
        }
        if (
            surfaceAttached &&
            attachedSurfaceGeneration == generation &&
            attachedSurfaceIdentity == nextSurfaceIdentity &&
            currentSurfaceValid()
        ) {
            return
        }
        if (surfaceAttached) {
            runCatching {
                detachAttachedSurface("stale:$reason")
            }.onFailure { error ->
                Log.w(VIDEO_OUTPUT_TAG, "detach stale surface failed reason=$reason", error)
            }
        }
        synchronized(SURFACE_BIND_LOCK) {
            mpv.attachSurface(surface)
            globalSurfaceOwnerId = controllerInstanceId
            surfaceAttached = true
            attachedSurfaceGeneration = generation
            attachedSurfaceIdentity = nextSurfaceIdentity
            videoOutputReady = false
        }
    }

    private fun detachAttachedSurface(reason: String) {
        if (!surfaceAttached) return
        synchronized(SURFACE_BIND_LOCK) {
            if (globalSurfaceOwnerId != controllerInstanceId) {
                Log.d(
                    VIDEO_OUTPUT_TAG,
                    "skip stale surface detach reason=$reason owner=$globalSurfaceOwnerId controller=$controllerInstanceId",
                )
            } else {
                setVideoOutputProperty(VIDEO_OUTPUT_NONE)
                mpv.detachSurface()
                globalSurfaceOwnerId = 0L
            }
            resetSurfaceAttachmentState()
        }
    }

    private fun resetSurfaceAttachmentState() {
        surfaceAttached = false
        attachedSurfaceGeneration = -1L
        attachedSurfaceIdentity = 0
        activeVideoOutputName = VIDEO_OUTPUT_NONE
        videoOutputReady = false
    }

    private fun clearGlobalSurfaceOwnerIfOwned() {
        synchronized(SURFACE_BIND_LOCK) {
            if (globalSurfaceOwnerId == controllerInstanceId) {
                globalSurfaceOwnerId = 0L
            }
        }
    }

    private fun setVideoOutputProperty(nextValue: String) {
        if (activeVideoOutputName == nextValue) {
            return
        }
        mpv.setPropertyString("vo", nextValue)
        activeVideoOutputName = nextValue
    }

    private fun setForceWindowProperty(enabled: Boolean) {
        if (forceWindowEnabled == enabled) {
            return
        }
        mpv.setPropertyBoolean("force-window", enabled)
        forceWindowEnabled = enabled
    }

    private fun applyWindowColorMode(targetColorPipeline: VideoColorPipeline) {
        val activity = hostActivity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val colorMode = when (targetColorPipeline) {
            VideoColorPipeline.HDR_DIRECT -> ActivityInfo.COLOR_MODE_HDR
            VideoColorPipeline.HDR_TONEMAP_SDR ->
                if (displayProfile.supportsWideColorGamut) {
                    ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT
                } else {
                    ActivityInfo.COLOR_MODE_DEFAULT
                }
            VideoColorPipeline.SDR -> ActivityInfo.COLOR_MODE_DEFAULT
        }
        runOnMainThread {
            runCatching {
                if (activity.window.colorMode != colorMode) {
                    activity.window.colorMode = colorMode
                    Log.i(VIDEO_OUTPUT_TAG, "window colorMode=$colorMode pipeline=$targetColorPipeline")
                }
            }.onFailure { error ->
                Log.w(VIDEO_OUTPUT_TAG, "applyWindowColorMode failed pipeline=$targetColorPipeline", error)
            }
        }
    }

    private fun applyDisplayAspectRatioMode() {
        when (displayAspectRatioMode) {
            VIDEO_ASPECT_MODE_FILL -> {
                setAspectProperties(
                    aspectOverride = VIDEO_ASPECT_OVERRIDE_NONE,
                    panscan = 1.0,
                )
            }
            VIDEO_ASPECT_MODE_4X3,
            VIDEO_ASPECT_MODE_16X9,
            VIDEO_ASPECT_MODE_21X9 -> {
                setAspectProperties(
                    aspectOverride = displayAspectRatioMode,
                    panscan = 0.0,
                )
            }
            else -> {
                setAspectProperties(
                    aspectOverride = VIDEO_ASPECT_OVERRIDE_NONE,
                    panscan = 0.0,
                )
            }
        }
    }

    private fun setAspectProperties(
        aspectOverride: String,
        panscan: Double,
    ) {
        if (activeAspectOverride != aspectOverride) {
            mpv.setPropertyString("video-aspect-override", aspectOverride)
            activeAspectOverride = aspectOverride
        }
        if (activePanscan != panscan) {
            mpv.setPropertyDouble("panscan", panscan)
            activePanscan = panscan
        }
    }

    companion object {
        private val NEXT_CONTROLLER_INSTANCE_ID = AtomicLong(1L)
        private val SURFACE_BIND_LOCK = Any()

        @Volatile
        private var globalSurfaceOwnerId = 0L

        private fun nextControllerInstanceId(): Long {
            return NEXT_CONTROLLER_INSTANCE_ID.getAndIncrement()
        }
    }

    private fun applyColorPipeline(targetColorPipeline: VideoColorPipeline) {
        if (activeColorPipeline == targetColorPipeline) return
        when (targetColorPipeline) {
            VideoColorPipeline.SDR -> {
                mpv.setPropertyString("target-prim", "auto")
                mpv.setPropertyString("target-trc", "auto")
                mpv.setPropertyString("target-colorspace-hint", "auto")
                mpv.setPropertyString("tone-mapping", "auto")
                mpv.setPropertyString("gamut-mapping-mode", "auto")
            }
            VideoColorPipeline.HDR_DIRECT -> {
                mpv.setPropertyString("target-prim", "auto")
                mpv.setPropertyString("target-trc", "auto")
                mpv.setPropertyString("target-colorspace-hint", "yes")
                mpv.setPropertyString("tone-mapping", "auto")
                mpv.setPropertyString("gamut-mapping-mode", "auto")
            }
            VideoColorPipeline.HDR_TONEMAP_SDR -> {
                mpv.setPropertyString("target-colorspace-hint", "auto")
                mpv.setPropertyString("target-prim", VIDEO_TARGET_PRIM_SDR)
                mpv.setPropertyString("target-trc", VIDEO_TARGET_TRC_SDR)
                mpv.setPropertyString("tone-mapping", resolvedToneMapping())
                mpv.setPropertyString("gamut-mapping-mode", "clip")
            }
        }
        activeColorPipeline = targetColorPipeline
    }

    private fun shouldPreferHwdecCopy(source: MpvSource): Boolean {
        if (!deviceProfile.isLikelyMali) return false
        if (source.isHdrLikely()) return true
        return source.isHevcLike() && source.isUltraHighResolution()
    }

    /** 疑似 DV Profile 5 且设备无 DV 解码器 → 强制映射管线（绿/紫屏特判）。 */
    private fun shouldForceDolbyVisionTonemap(source: MpvSource): Boolean {
        if (!source.isDolbyVisionProfile5Like()) return false
        return !deviceHasDolbyVisionDecoder
    }

    private val deviceHasDolbyVisionDecoder: Boolean by lazy {
        runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                !info.isEncoder &&
                    info.supportedTypes.any { it.equals("video/dolby-vision", ignoreCase = true) }
            }
        }.getOrDefault(false).also {
            Log.d(VIDEO_OUTPUT_TAG, "deviceHasDolbyVisionDecoder=$it")
        }
    }

    private fun isRiskyBufferFormatMessage(lowerMessage: String): Boolean {
        return lowerMessage.contains("unsupported format") ||
            lowerMessage.contains("invalid base format")
    }
}
