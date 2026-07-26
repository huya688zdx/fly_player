package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.os.SystemClock
import android.util.Log

private const val ADVANCED_SETTINGS_TAG = "FlyPlayerMpv"
private const val ADVANCED_SETTINGS_DUPLICATE_APPLY_WINDOW_MS = 1500L

class MpvAdvancedSettingsController(
    private val mpv: MpvFacade,
    private val videoOutputController: VideoOutputController,
    private val context: Context,
) {
    private var settings: Map<String, String> = emptyMap()
    private var automaticFilterFallbackActive = false
    // 性能阶梯第 1 级（视频）：剥离增强后仍掉帧时置位，把缩放强制到最省的 bilinear。
    // balanced 的 spline36 chroma 在 4K60 HDR 上正是中端 GPU 撑不住的元凶。
    private var adaptiveScaleDowngradeActive = false
    // 会话级性能学习：触发过缩放降挡后记住——之后超高清内容直接从 bilinear 起步，
    // 避免重载（恢复/seek 重解析）后又回 balanced→再卡→再降，重复 climb。仅控制器销毁随之消失，
    // resetTransientOverrides（每次 load 都调）不清它，故能跨重载存活。
    private var sessionScaleDowngradeForUltraHd = false
    // 位流直通初始化失败后置位：本次播放强制走解码（apply 里 passthrough 让位给软件链）。
    private var audioPassthroughFallbackActive = false
    private var lastApplyFingerprint: String = ""
    private var lastApplyUptimeMs: Long = 0L
    private var lastApplySucceeded = false

    fun update(settings: Map<String, Any?>): MpvAdvancedSettingsUpdate {
        val normalized = buildMap<String, String> {
            val rawSettings = settings["settings"]
            if (rawSettings is Map<*, *>) {
                for ((rawKey, rawValue) in rawSettings) {
                    val key = rawKey?.toString()?.trim().orEmpty()
                    val value = rawValue?.toString()?.trim().orEmpty()
                    if (key.isNotEmpty() && value.isNotEmpty()) {
                        put(key, value)
                    }
                }
            }
        }
        val previous = this.settings
        this.settings = normalized
        val requiresReload =
            previous["hdr_mode"] != normalized["hdr_mode"] ||
                previous["compatibility_profile"] != normalized["compatibility_profile"]
        return MpvAdvancedSettingsUpdate(
            changed = previous != normalized,
            requiresReload = requiresReload,
        )
    }

    fun apply(initialized: Boolean, available: Boolean, source: MpvSource): Boolean {
        if (!initialized || !available || !mpv.isAvailable()) return false
        val fingerprint = buildApplyFingerprint(source)
        val nowUptimeMs = SystemClock.uptimeMillis()
        if (
            fingerprint == lastApplyFingerprint &&
            nowUptimeMs - lastApplyUptimeMs <= ADVANCED_SETTINGS_DUPLICATE_APPLY_WINDOW_MS
        ) {
            Log.d(
                ADVANCED_SETTINGS_TAG,
                "skip duplicate mpv advanced settings apply fingerprint=$fingerprint lastSuccess=$lastApplySucceeded source=[${source.debugSummary()}]",
            )
            return true
        }
        val adaptiveFilterBypass = automaticFilterFallbackActive
        var success = true
        success = applyDeband(adaptiveFilterBypass) && success
        success = applyVideoFilters(adaptiveFilterBypass) && success
        success = applyScaleProfile(adaptiveFilterBypass, source) && success
        success = applyFrameInterpolation(adaptiveFilterBypass, source) && success
        success = applyVideoSync(adaptiveFilterBypass, source) && success
        success = applyCacheProfile(source) && success
        success = applyAudioProcessing() && success
        success = applyHdrMode(source) && success
        success = applyCompatibilityProfile() && success
        lastApplyFingerprint = fingerprint
        lastApplyUptimeMs = nowUptimeMs
        lastApplySucceeded = success
        Log.d(
            ADVANCED_SETTINGS_TAG,
            "applied mpv advanced settings success=$success automaticFilterFallbackActive=$automaticFilterFallbackActive settings=$settings source=[${source.debugSummary()}]",
        )
        return success
    }

    fun snapshot(): Map<String, Any?> = settings.toMap()

    fun resetTransientOverrides() {
        automaticFilterFallbackActive = false
        adaptiveScaleDowngradeActive = false
        audioPassthroughFallbackActive = false
    }

    /** 当前是否处于位流直通输出（on 强制，或 auto 且设备支持，且未触发失败回退）。 */
    fun isAudioPassthroughActive(): Boolean {
        if (audioPassthroughFallbackActive) return false
        return resolvePassthroughCodecs().isNotEmpty()
    }

    /**
     * 直通初始化失败回退：置位后下次 apply 走解码链。仅在「当前应直通」时才算触发，返回是否变更。
     * 由 [MpvPlaybackController] 的日志钩子在探测到 spdif/AudioTrack 初始化失败时调用。
     */
    fun triggerAudioPassthroughFallback(): Boolean {
        if (audioPassthroughFallbackActive) return false
        if (resolvePassthroughCodecs().isEmpty()) return false
        audioPassthroughFallbackActive = true
        Log.w(ADVANCED_SETTINGS_TAG, "audio passthrough init failed → fallback to decoded output")
        return true
    }

    /** 解析当前应下发的 spdif 编码集（off / 设备不支持 / 已回退 → 空串）。 */
    private fun resolvePassthroughCodecs(): String {
        if (audioPassthroughFallbackActive) return ""
        return when (settings["audio_passthrough"] ?: "off") {
            "on" -> AudioPassthroughSupport.ALL_CODECS
            "auto" -> AudioPassthroughSupport.supportedSpdifCodecs(context)
            else -> ""
        }
    }

    private fun buildApplyFingerprint(source: MpvSource): String {
        val normalizedSettings =
            settings.entries
                .sortedBy { it.key }
                .joinToString(separator = "&") { (key, value) -> "$key=$value" }
        return listOf(
            normalizedSettings,
            automaticFilterFallbackActive.toString(),
            adaptiveScaleDowngradeActive.toString(),
            sessionScaleDowngradeForUltraHd.toString(),
            audioPassthroughFallbackActive.toString(),
            source.isRemoteHttpSource().toString(),
            source.isUltraHighResolution().toString(),
            source.bitrate.toString(),
            source.videoWidth.toString(),
            source.videoHeight.toString(),
            source.isHdrLikely().toString(),
            source.listenVideoModeEnabled.toString(),
            source.extremePlaybackEnabled.toString(),
        ).joinToString(separator = "|")
    }

    fun canTriggerAutomaticFilterFallback(source: MpvSource): Boolean {
        if (automaticFilterFallbackActive) return false
        return hasHeavyVideoEnhancementsEnabled(source)
    }

    fun triggerAutomaticFilterFallback(
        initialized: Boolean,
        available: Boolean,
        source: MpvSource,
    ): Boolean {
        if (!canTriggerAutomaticFilterFallback(source)) return false
        automaticFilterFallbackActive = true
        val applied = apply(initialized, available, source)
        return applied || automaticFilterFallbackActive
    }

    /** 视频性能阶梯是否还有可降的空间（增强未全剥离，或缩放还没降到 fast）。 */
    fun canEscalateVideoPerformanceFallback(): Boolean =
        !automaticFilterFallbackActive || !adaptiveScaleDowngradeActive

    /**
     * 性能阶梯（视频级，对应方案 B）：检测到持续掉帧时一次性把渲染降到最省——剥离全部
     * 增强（deband/sharpen/denoise/插帧/quality 缩放）并把缩放强制 bilinear。这是 4K/高码率
     * HDR 在中端 GPU 上唯一能救回实时性的杠杆，不依赖 [hasHeavyVideoEnhancementsEnabled]
     * （默认 balanced 也要能降）。返回是否产生了实际变化。
     */
    fun escalateVideoPerformanceFallback(
        initialized: Boolean,
        available: Boolean,
        source: MpvSource,
    ): Boolean {
        if (!canEscalateVideoPerformanceFallback()) return false
        automaticFilterFallbackActive = true
        adaptiveScaleDowngradeActive = true
        // 记住缩放降挡，跨重载存活（仅对超高清内容生效，见 applyScaleProfile）。
        if (source.isUltraHighResolution()) sessionScaleDowngradeForUltraHd = true
        // 返回"是否真的改了渲染状态"(标志由 false→true),而非 apply 的聚合成功值——后者会
        // 被无关子步骤(如 vf 下发)拉成 false，误报成"没降级"。缩放降挡是无条件下发的。
        apply(initialized, available, source)
        return true
    }

    private fun applyDeband(adaptiveFilterBypass: Boolean): Boolean {
        val level = if (adaptiveFilterBypass) "off" else (settings["deband"] ?: "off")
        val enabled = level != "off"
        val iterations =
            when (level) {
                "low" -> 1L
                "high" -> 4L
                "medium" -> 3L
                else -> 3L
            }
        return runCatching {
            mpv.setPropertyBoolean("deband", enabled)
            if (enabled) {
                mpv.setPropertyInt("deband-iterations", iterations)
            }
            true
        }.getOrDefault(false)
    }

    private fun applyVideoFilters(adaptiveFilterBypass: Boolean): Boolean {
        val filters = mutableListOf<String>()
        if (!adaptiveFilterBypass) {
            when (settings["sharpen"]) {
                "low" -> filters += "lavfi=[unsharp=3:3:0.35:3:3:0.0]"
                "medium" -> filters += "lavfi=[unsharp=5:5:0.45:5:5:0.0]"
                "high" -> filters += "lavfi=[unsharp=7:7:0.55:7:7:0.0]"
            }
            when (settings["denoise"]) {
                "low" -> filters += "lavfi=[hqdn3d=1.5:1.5:6:6]"
                "medium" -> filters += "lavfi=[hqdn3d=3:2:9:7]"
            }
        }
        val requestedDeinterlace = settings["deinterlace"] ?: "auto"
        val deinterlace =
            if (adaptiveFilterBypass && requestedDeinterlace == "force") {
                "auto"
            } else {
                requestedDeinterlace
            }
        val deinterlaceSuccess =
            runCatching {
                mpv.setPropertyString(
                    "deinterlace",
                    when (deinterlace) {
                        "force" -> "yes"
                        "off" -> "no"
                        else -> "auto"
                    },
                )
            }.getOrDefault(false)
        videoOutputController.setFilterCompatibleFramesRequired(filters.isNotEmpty())
        val vfSuccess =
            runCatching {
                mpv.setPropertyString("vf", filters.joinToString(","))
            }.getOrDefault(filters.isEmpty())
        return deinterlaceSuccess && vfSuccess
    }

    private fun applyScaleProfile(adaptiveFilterBypass: Boolean, source: MpvSource): Boolean {
        val requestedProfile = settings["scale_profile"] ?: "balanced"
        val profile =
            when {
                // 性能阶梯第 1 级：强制最省缩放（即便用户选的是 balanced/quality）。
                adaptiveScaleDowngradeActive -> "fast"
                // 会话已学到的降挡：重载后超高清内容仍直接走最省缩放，不重新 climb。
                sessionScaleDowngradeForUltraHd && source.isUltraHighResolution() -> "fast"
                adaptiveFilterBypass && requestedProfile == "quality" -> "balanced"
                else -> requestedProfile
            }
        val scale =
            when (profile) {
                "fast" -> Triple("bilinear", "bilinear", "bilinear")
                "quality" -> Triple("ewa_lanczossharp", "spline64", "mitchell")
                else -> Triple("spline36", "spline36", "mitchell")
            }
        return runCatching {
            mpv.setPropertyString("scale", scale.first)
            mpv.setPropertyString("cscale", scale.second)
            mpv.setPropertyString("dscale", scale.third)
            true
        }.getOrDefault(false)
    }

    private fun applyHdrMode(source: MpvSource): Boolean {
        // 色调映射算法（仅 HDR→SDR 映射管线生效）。先于 HDR 模式下发，setAdvancedHdrMode 内部
        // 若触发重配会一并用上新偏好。
        videoOutputController.setToneMappingPreference(settings["tone_mapping"])
        videoOutputController.setAdvancedHdrMode(settings["hdr_mode"], source)
        return true
    }

    private fun applyFrameInterpolation(adaptiveFilterBypass: Boolean, source: MpvSource): Boolean {
        val enabled = isFrameInterpolationEnabled(adaptiveFilterBypass, source)
        return runCatching {
            mpv.setPropertyBoolean("interpolation", enabled)
            mpv.setPropertyString(
                "tscale",
                if (enabled) {
                    "oversample"
                } else {
                    "mitchell"
                },
            )
            Log.d(
                ADVANCED_SETTINGS_TAG,
                "frame interpolation enabled=$enabled tscale=${if (enabled) "oversample" else "mitchell"}",
            )
            true
        }.getOrDefault(false)
    }

    private fun applyVideoSync(adaptiveFilterBypass: Boolean, source: MpvSource): Boolean {
        val interpolationEnabled = isFrameInterpolationEnabled(adaptiveFilterBypass, source)
        val requestedMode =
            if (adaptiveFilterBypass && settings["video_sync"] == "smooth") {
                "auto"
            } else {
                settings["video_sync"] ?: "auto"
            }
        val mode =
            if (interpolationEnabled) {
                "display-resample"
            } else {
                when (requestedMode) {
                    "auto" -> "display-resample"
                    "audio" -> "audio"
                    "display" -> "display-resample"
                    "smooth" -> "display-tempo"
                    else -> "display-resample"
                }
            }
        return runCatching {
            mpv.setPropertyString("video-sync", mode)
            Log.d(
                ADVANCED_SETTINGS_TAG,
                "video sync requested=$requestedMode applied=$mode interpolation=$interpolationEnabled",
            )
            true
        }.getOrDefault(false)
    }

    private fun applyCacheProfile(source: MpvSource): Boolean {
        val requestedProfile = settings["cache_profile"] ?: "default"
        val profile =
            if (requestedProfile == "default" && source.isRemoteHttpSource()) {
                if (source.isUltraHighResolution() || source.bitrate >= 8_000_000) {
                    "network"
                } else {
                    "stable"
                }
            } else {
                requestedProfile
            }
        val cacheEnabled = profile != "low_latency"
        val maxBytes =
            when (profile) {
                "stable" -> 128L * 1024L * 1024L
                "network" -> 256L * 1024L * 1024L
                "low_latency" -> 32L * 1024L * 1024L
                else -> 64L * 1024L * 1024L
            }
        val readahead =
            when (profile) {
                "stable" -> 20.0
                "network" -> 30.0
                "low_latency" -> 5.0
                else -> 10.0
            }
        val configuredCacheSizeMb = settings["cache_size_mb"]?.toLongOrNull()
        val effectiveMaxBytes =
            if (configuredCacheSizeMb != null && configuredCacheSizeMb > 0L) {
                configuredCacheSizeMb * 1024L * 1024L
            } else {
                maxBytes
            }
        val safeMaxBytes = effectiveMaxBytes.coerceAtMost(Int.MAX_VALUE.toLong())
        return runCatching {
            mpv.setPropertyBoolean("cache", cacheEnabled)
            mpv.setPropertyInt("demuxer-max-bytes", safeMaxBytes)
            mpv.setPropertyDouble("demuxer-readahead-secs", readahead)
            true
        }.getOrDefault(false)
    }

    private fun applyAudioProcessing(): Boolean {
        // 位流直通（杜比/DTS）：与软件滤镜/EQ/混音互斥——清空 af、声道交给功放、volume 还原 100，
        // 由功放/电视解码。off / 设备不支持 / 已回退时为空串，走下方常规解码链。
        val passthroughCodecs = resolvePassthroughCodecs()
        if (passthroughCodecs.isNotEmpty()) {
            return runCatching {
                mpv.setPropertyString("audio-spdif", passthroughCodecs)
                mpv.setPropertyString("af", "")
                mpv.setPropertyString("audio-channels", "auto")
                mpv.setPropertyInt("volume-max", 100L)
                mpv.setPropertyInt("volume", 100L)
                Log.d(ADVANCED_SETTINGS_TAG, "audio passthrough active spdif=$passthroughCodecs")
                true
            }.getOrDefault(false)
        }
        // 非直通：确保清空 spdif（从直通切回 / 回退时），再走软件解码 + 滤镜链。
        runCatching { mpv.setPropertyString("audio-spdif", "") }
        val highFidelityEnabled = (settings["audio_high_fidelity"] ?: "off") == "on"
        // 手机端杜比全景声/空间音频：用户没强制立体声时，若系统 Spatializer 可用，输出原生多声道
        // （降级链 7.1→5.1→stereo），让 Android 把 Atmos 声床虚拟化到喇叭/耳机。否则系统拿到的是
        // 提前下混的立体声，空间音频无声床可虚拟化。
        val spatialMultichannel =
            settings["channel_mix"] != "stereo" &&
                AudioSpatializerSupport.prefersMultichannelOutput(context)
        val channelMix =
            when {
                spatialMultichannel -> "7.1,5.1,stereo"
                highFidelityEnabled -> "auto-safe"
                settings["channel_mix"] == "stereo" -> "stereo"
                settings["channel_mix"] == "surround" -> "5.1"
                else -> "auto-safe"
            }
        val volumeMax =
            if (highFidelityEnabled) {
                100L
            } else {
                (settings["volume_gain"] ?: "100").toLongOrNull() ?: 100L
            }
        val afFilters = mutableListOf<String>()
        if (!highFidelityEnabled) {
            appendAudioEqFilters(afFilters, settings["audio_eq"] ?: "off")
            appendBassBoostFilters(afFilters, settings["audio_bass_boost"] ?: "off")
            appendVoiceEnhanceFilters(afFilters, settings["audio_voice_enhance"] ?: "off")
            when (settings["dynamic_range"]) {
                "low" -> afFilters += "lavfi=[acompressor=threshold=-20dB:ratio=2.0:attack=20:release=250]"
                "medium" -> afFilters += "lavfi=[acompressor=threshold=-24dB:ratio=3.0:attack=15:release=220]"
            }
            appendLimiterFilters(afFilters, settings["audio_limiter"] ?: "off")
        }
        return runCatching {
            mpv.setPropertyString("audio-channels", channelMix)
            mpv.setPropertyInt("volume-max", volumeMax)
            mpv.setPropertyInt("volume", volumeMax)
            mpv.setPropertyString("af", afFilters.joinToString(","))
            if (spatialMultichannel) {
                Log.d(ADVANCED_SETTINGS_TAG, "spatial audio: multichannel output channels=$channelMix")
            }
            true
        }.getOrDefault(false)
    }

    private fun appendAudioEqFilters(filters: MutableList<String>, profile: String) {
        when (profile) {
            "soft" -> {
                filters += "lavfi=[equalizer=f=120:t=q:w=1.0:g=1.2]"
                filters += "lavfi=[equalizer=f=2400:t=q:w=1.0:g=1.0]"
            }
            "clarity" -> {
                filters += "lavfi=[equalizer=f=160:t=q:w=1.0:g=-1.0]"
                filters += "lavfi=[equalizer=f=2800:t=q:w=1.1:g=2.4]"
                filters += "lavfi=[equalizer=f=6800:t=q:w=1.1:g=1.4]"
            }
            "cinema" -> {
                filters += "lavfi=[equalizer=f=90:t=q:w=1.0:g=1.4]"
                filters += "lavfi=[equalizer=f=2200:t=q:w=1.0:g=1.2]"
                filters += "lavfi=[equalizer=f=5600:t=q:w=1.0:g=0.8]"
            }
            "custom" -> {
                appendCustomAudioEqFilters(filters)
            }
        }
    }

    private fun appendCustomAudioEqFilters(filters: MutableList<String>) {
        val bands =
            listOf(
                "audio_eq_band_60" to 60,
                "audio_eq_band_170" to 170,
                "audio_eq_band_310" to 310,
                "audio_eq_band_1000" to 1000,
                "audio_eq_band_6000" to 6000,
            )
        for ((key, frequency) in bands) {
            val gain = settings[key]?.toDoubleOrNull() ?: 0.0
            if (kotlin.math.abs(gain) < 0.05) continue
            filters += "lavfi=[equalizer=f=$frequency:t=q:w=1.0:g=${gain.toString()}]"
        }
    }

    private fun appendLimiterFilters(filters: MutableList<String>, level: String) {
        when (level) {
            "light" -> filters += "lavfi=[alimiter=limit=0.95:attack=5:release=45]"
            "strong" -> filters += "lavfi=[alimiter=limit=0.90:attack=3:release=60]"
        }
    }

    private fun appendBassBoostFilters(filters: MutableList<String>, level: String) {
        when (level) {
            "low" -> filters += "lavfi=[bass=g=3:f=110:w=0.6]"
            "medium" -> filters += "lavfi=[bass=g=5:f=105:w=0.7]"
        }
    }

    private fun appendVoiceEnhanceFilters(filters: MutableList<String>, level: String) {
        when (level) {
            "low" -> {
                filters += "lavfi=[highpass=f=120]"
                filters += "lavfi=[equalizer=f=2600:t=q:w=1.1:g=1.8]"
                filters += "lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.0]"
            }
            "medium" -> {
                filters += "lavfi=[highpass=f=140]"
                filters += "lavfi=[equalizer=f=2600:t=q:w=1.0:g=2.6]"
                filters += "lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.5]"
            }
        }
    }

    private fun applyCompatibilityProfile(): Boolean {
        videoOutputController.setCompatibilityProfile(settings["compatibility_profile"])
        return true
    }

    private fun hasHeavyVideoEnhancementsEnabled(source: MpvSource): Boolean {
        val debandEnabled = (settings["deband"] ?: "off") != "off"
        val sharpenEnabled = (settings["sharpen"] ?: "off") != "off"
        val denoiseEnabled = (settings["denoise"] ?: "off") != "off"
        val forcedDeinterlaceEnabled = (settings["deinterlace"] ?: "auto") == "force"
        val interpolationEnabled =
            isFrameInterpolationEnabled(
                adaptiveFilterBypass = false,
                source = source,
            )
        val qualityScaleEnabled = (settings["scale_profile"] ?: "balanced") == "quality"
        val smoothSyncEnabled = (settings["video_sync"] ?: "auto") == "smooth"
        return debandEnabled ||
            sharpenEnabled ||
            denoiseEnabled ||
            forcedDeinterlaceEnabled ||
            interpolationEnabled ||
            qualityScaleEnabled ||
            smoothSyncEnabled
    }

    private fun isFrameInterpolationEnabled(adaptiveFilterBypass: Boolean, source: MpvSource): Boolean {
        val value = if (adaptiveFilterBypass) "off" else (settings["frame_interpolation"] ?: "off")
        return when (value) {
            "on" -> true
            "auto" -> shouldEnableAutomaticFrameInterpolation(source)
            else -> false
        }
    }

    private fun shouldEnableAutomaticFrameInterpolation(source: MpvSource): Boolean {
        if (source.isHdrLikely()) return false
        if (source.bitDepth >= 10) return false
        if (source.isUltraHighResolution()) return false
        if (source.videoWidth > 1920 || source.videoHeight > 1080) return false
        if (source.isRemoteHttpSource()) return false
        if (source.isHevcLike() && source.bitrate >= 8_000_000) return false
        if (source.bitrate >= 12_000_000) return false
        return true
    }
}

data class MpvAdvancedSettingsUpdate(
    val changed: Boolean,
    val requiresReload: Boolean,
)
