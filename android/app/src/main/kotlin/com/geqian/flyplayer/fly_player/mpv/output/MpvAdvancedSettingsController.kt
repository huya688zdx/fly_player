package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock
import android.util.Log

private const val ADVANCED_SETTINGS_TAG = "FlyPlayerMpv"
private const val ADVANCED_SETTINGS_DUPLICATE_APPLY_WINDOW_MS = 1500L

class MpvAdvancedSettingsController(
    private val mpv: MpvFacade,
    private val videoOutputController: VideoOutputController,
) {
    private var settings: Map<String, String> = emptyMap()
    private var automaticFilterFallbackActive = false
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
        success = applyScaleProfile(adaptiveFilterBypass) && success
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
    }

    private fun buildApplyFingerprint(source: MpvSource): String {
        val normalizedSettings =
            settings.entries
                .sortedBy { it.key }
                .joinToString(separator = "&") { (key, value) -> "$key=$value" }
        return listOf(
            normalizedSettings,
            automaticFilterFallbackActive.toString(),
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

    private fun applyScaleProfile(adaptiveFilterBypass: Boolean): Boolean {
        val requestedProfile = settings["scale_profile"] ?: "balanced"
        val profile =
            if (adaptiveFilterBypass && requestedProfile == "quality") {
                "balanced"
            } else {
                requestedProfile
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
        val highFidelityEnabled = (settings["audio_high_fidelity"] ?: "off") == "on"
        val channelMix =
            when {
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
