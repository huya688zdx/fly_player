package com.geqian.flyplayer.fly_player.mpv

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.os.Build
import java.util.Locale

private val RESOLUTION_DIGIT_PATTERN = Regex("(\\d{3,4})")

data class MpvSource(
    val loadNonce: Int,
    val itemGuid: String,
    val seasonGuid: String,
    val posterPath: String,
    val mediaGuid: String,
    val mediaType: String,
    val ancestorName: String,
    val videoGuid: String,
    val url: String,
    val headers: Map<String, String>,
    val title: String,
    val seriesTitle: String,
    val seasonNumber: Int,
    val tmdbId: String,
    val episodeNumber: Int,
    val startPositionMs: Long,
    val startPaused: Boolean,
    val audioTrackIndex: Int?,
    val subtitleTrackIndex: Int?,
    val audioTrackGuid: String?,
    val subtitleTrackGuid: String?,
    val videoWidth: Int,
    val videoHeight: Int,
    val resolution: String,
    val bitrate: Int,
    val durationSeconds: Int,
    val videoCodecName: String,
    val videoProfile: String,
    val colorSpace: String,
    val colorTransfer: String,
    val colorPrimaries: String,
    val bitDepth: Int,
    val preferExternalSubtitle: Boolean,
    val forceNativeProxy: Boolean,
    val extremePlaybackEnabled: Boolean,
    val reliableSeek: Boolean,
    val seekProbeSummary: String?,
    val playbackSpeed: Double,
    val listenVideoModeEnabled: Boolean,
    val videoOutputBackend: String,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): MpvSource {
            @Suppress("UNCHECKED_CAST")
            val rawHeaders = map["headers"] as? Map<String, Any?> ?: emptyMap()
            return MpvSource(
                loadNonce = map["loadNonce"].toIntValue() ?: 0,
                itemGuid = map["itemGuid"]?.toString().orEmpty(),
                seasonGuid = map["seasonGuid"]?.toString().orEmpty(),
                posterPath = map["posterPath"]?.toString().orEmpty(),
                mediaGuid = map["mediaGuid"]?.toString().orEmpty(),
                mediaType = map["mediaType"]?.toString().orEmpty(),
                ancestorName = map["ancestorName"]?.toString().orEmpty(),
                videoGuid = map["videoGuid"]?.toString().orEmpty(),
                url = map["url"]?.toString().orEmpty(),
                headers = rawHeaders.mapValues { it.value?.toString().orEmpty() }
                    .filterValues { it.isNotEmpty() },
                title = map["title"]?.toString().orEmpty(),
                seriesTitle = map["seriesTitle"]?.toString().orEmpty(),
                seasonNumber = map["seasonNumber"].toIntValue() ?: 0,
                tmdbId = map["tmdbId"]?.toString().orEmpty(),
                episodeNumber = map["episodeNumber"].toIntValue() ?: 0,
                startPositionMs = map["startPositionMs"].toLongValue(),
                startPaused = map["startPaused"] as? Boolean ?: false,
                audioTrackIndex = map["audioTrackIndex"].toIntValue(),
                subtitleTrackIndex = map["subtitleTrackIndex"].toIntValue(),
                audioTrackGuid = map["audioTrackGuid"]?.toString(),
                subtitleTrackGuid = map["subtitleTrackGuid"]?.toString(),
                videoWidth = map["videoWidth"].toIntValue() ?: 0,
                videoHeight = map["videoHeight"].toIntValue() ?: 0,
                resolution = map["resolution"]?.toString().orEmpty(),
                bitrate = map["bitrate"].toIntValue() ?: 0,
                durationSeconds = map["durationSeconds"].toIntValue() ?: 0,
                videoCodecName = map["videoCodecName"]?.toString().orEmpty(),
                videoProfile = map["videoProfile"]?.toString().orEmpty(),
                colorSpace = map["colorSpace"]?.toString().orEmpty(),
                colorTransfer = map["colorTransfer"]?.toString().orEmpty(),
                colorPrimaries = map["colorPrimaries"]?.toString().orEmpty(),
                bitDepth = map["bitDepth"].toIntValue() ?: 0,
                preferExternalSubtitle = map["preferExternalSubtitle"] as? Boolean ?: false,
                forceNativeProxy = map["forceNativeProxy"] as? Boolean ?: false,
                extremePlaybackEnabled = map["extremePlaybackEnabled"] as? Boolean ?: false,
                reliableSeek = map["reliableSeek"] as? Boolean ?: true,
                seekProbeSummary = map["seekProbeSummary"]?.toString(),
                playbackSpeed = map["playbackSpeed"].toDoubleValue() ?: 1.0,
                listenVideoModeEnabled = map["listenVideoModeEnabled"] as? Boolean ?: false,
                videoOutputBackend =
                    VideoOutputBackend.fromValue(map["videoOutputBackend"]?.toString()).wireValue,
            )
        }
    }

    fun isHdrLikely(): Boolean {
        val codec = videoCodecName.lowercase(Locale.US)
        val profile = videoProfile.lowercase(Locale.US)
        val space = colorSpace.lowercase(Locale.US)
        val transfer = colorTransfer.lowercase(Locale.US)
        val primaries = colorPrimaries.lowercase(Locale.US)
        val hdrTransfer =
            transfer.contains("pq") ||
                transfer.contains("2084") ||
                transfer.contains("smpte2084") ||
                transfer.contains("hlg") ||
                transfer.contains("arib-std-b67")
        val hdrGamut =
            space.contains("2020") ||
                space.contains("2100") ||
                primaries.contains("2020") ||
                primaries.contains("2100")
        val dolbyVisionLike =
            codec.contains("dovi") ||
                codec.contains("dvhe") ||
                codec.contains("dvh1") ||
                profile.contains("dolby vision") ||
                profile.contains("dolbyvision")
        val bitDepth10Plus = bitDepth >= 10
        if (dolbyVisionLike) return true
        if (hdrTransfer && bitDepth10Plus) return true
        return hdrGamut && bitDepth10Plus
    }

    /**
     * 疑似 Dolby Vision Profile 5（无 HDR10 兼容层，IPTPQc2）。这类在无 DV 解码器的设备上
     * mediacodec 直出会绿/紫屏。从 codec/profile 串判断：含 DV 标识且 profile 标 5。
     */
    fun isDolbyVisionProfile5Like(): Boolean {
        val codec = videoCodecName.lowercase(Locale.US)
        val profile = videoProfile.lowercase(Locale.US)
        val dolbyVisionLike =
            codec.contains("dovi") ||
                codec.contains("dvhe") ||
                codec.contains("dvh1") ||
                profile.contains("dolby vision") ||
                profile.contains("dolbyvision")
        if (!dolbyVisionLike) return false
        // Profile 5 标识：dvhe.05 / dvh1.05 / "profile 5" / 单独的 ".05."。
        return profile.contains("dvhe.05") ||
            profile.contains("dvh1.05") ||
            profile.contains(".05.") ||
            profile.contains("profile 5") ||
            profile.contains("profile5") ||
            codec.contains("dvhe.05") ||
            codec.contains("dvh1.05")
    }

    fun isHevcLike(): Boolean {
        val codec = videoCodecName.lowercase(Locale.US)
        return codec.contains("hevc") ||
            codec.contains("h265") ||
            codec.contains("hev1") ||
            codec.contains("hvc1") ||
            codec.contains("x265")
    }

    fun isUltraHighResolution(): Boolean {
        if (videoWidth >= 3840 || videoHeight >= 2160) return true
        val normalized = resolution.lowercase(Locale.US)
        if (normalized.contains("2160")) return true
        val firstResolutionToken =
            RESOLUTION_DIGIT_PATTERN.find(normalized)?.groupValues?.getOrNull(1)?.toIntOrNull()
        return (firstResolutionToken ?: 0) >= 2160
    }

    fun isRemoteHttpSource(): Boolean {
        val parsed = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        val scheme = parsed.scheme?.lowercase(Locale.US).orEmpty()
        if (scheme != "http" && scheme != "https") return false
        val host = parsed.host?.trim().orEmpty()
        if (host.isEmpty() || host == "127.0.0.1" || host == "localhost") {
            return false
        }
        val lowerHost = host.lowercase(Locale.US)
        if (lowerHost.endsWith(".local")) return false
        val ipv4Parts = lowerHost.split(".")
        if (ipv4Parts.size == 4 && ipv4Parts.all { it.toIntOrNull() != null }) {
            val octets = ipv4Parts.map { it.toInt() }
            val first = octets[0]
            val second = octets[1]
            return !(first == 10 ||
                first == 127 ||
                (first == 192 && second == 168) ||
                (first == 172 && second in 16..31))
        }
        return true
    }

    fun debugSummary(): String {
        return "codec=$videoCodecName profile=$videoProfile size=${videoWidth}x$videoHeight resolution=$resolution bitDepth=$bitDepth colorSpace=$colorSpace transfer=$colorTransfer primaries=$colorPrimaries"
    }
}

data class DeviceProfile(
    val isLikelyMali: Boolean,
    val summary: String,
)

data class DisplayProfile(
    val supportsHdr: Boolean,
    val supportsWideColorGamut: Boolean,
    val summary: String,
)

enum class VideoColorPipeline {
    SDR,
    HDR_DIRECT,
    HDR_TONEMAP_SDR,
}

enum class MpvPlaybackPhase(
    val wireValue: String,
) {
    IDLE("idle"),
    PREPARING("preparing"),
    BUFFERING("buffering"),
    PLAYING("playing"),
    PAUSED("paused"),
    SEEKING("seeking"),
    ENDED("ended"),
    ERROR("error"),
}

data class MpvPlayerState(
    val loadNonce: Int = 0,
    val ready: Boolean = false,
    val nativeLibLoaded: Boolean = false,
    val visualPlaybackReady: Boolean = false,
    val paused: Boolean = true,
    val playbackPhase: String = MpvPlaybackPhase.IDLE.wireValue,
    val buffering: Boolean = false,
    val positionMs: Long = 0L,
    val bufferedPositionMs: Long = 0L,
    val durationMs: Long = 0L,
    val weakNetworkMode: Boolean = false,
    val networkSpeedBytesPerSecond: Long = 0L,
    val rebufferTargetMs: Long = 0L,
    val estimatedResumeWaitMs: Long? = null,
    val listenVideoModeEnabled: Boolean = false,
    val statusText: String = "Preparing player",
    val error: String? = null,
    val nativeProxySessionId: String? = null,
    val cacheResourceKey: String? = null,
    val positionSampleTimeNs: Long = 0L,
    val speed: Double = 1.0,
    // 自适应性能阶梯当前级别：0=未降级，1=视频已降画质（方案 B），2=并已请求压弹幕（方案 C）。
    // 宿主据此 toast 提醒用户、并在 >=2 时降低弹幕负载。
    val performanceFallbackLevel: Int = 0,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "loadNonce" to loadNonce,
            "ready" to ready,
            "nativeLibLoaded" to nativeLibLoaded,
            "visualPlaybackReady" to visualPlaybackReady,
            "paused" to paused,
            "playbackPhase" to playbackPhase,
            "buffering" to buffering,
            "positionMs" to positionMs,
            "bufferedPositionMs" to bufferedPositionMs,
            "durationMs" to durationMs,
            "weakNetworkMode" to weakNetworkMode,
            "networkSpeedBytesPerSecond" to networkSpeedBytesPerSecond,
            "rebufferTargetMs" to rebufferTargetMs,
            "estimatedResumeWaitMs" to estimatedResumeWaitMs,
            "listenVideoModeEnabled" to listenVideoModeEnabled,
            "statusText" to statusText,
            "error" to error,
            "nativeProxySessionId" to nativeProxySessionId,
            "cacheResourceKey" to cacheResourceKey,
            "speed" to speed,
            "performanceFallbackLevel" to performanceFallbackLevel,
        )
    }
}

fun interface MpvPlaybackStateListener {
    fun onStateChanged(state: MpvPlayerState, overlayText: String)
}

fun findActivity(context: Context): Activity? {
    var current: Context? = context
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

fun detectDeviceProfile(): DeviceProfile {
    val rawValues = listOf(
        Build.MANUFACTURER,
        Build.BRAND,
        Build.MODEL,
        Build.DEVICE,
        Build.PRODUCT,
        Build.HARDWARE,
        Build.BOARD,
        readSystemProperty("ro.hardware.egl"),
        readSystemProperty("ro.hardware.vulkan"),
        readSystemProperty("ro.board.platform"),
        readSystemProperty("ro.hardware"),
        readSystemProperty("ro.gfx.driver.0"),
    ).map { it.trim() }.filter { it.isNotEmpty() }
    val normalized = rawValues.joinToString(" | ").lowercase(Locale.US)
    return DeviceProfile(
        isLikelyMali = normalized.contains("mali"),
        summary = rawValues.distinct().joinToString(" | "),
    )
}

fun detectDisplayProfile(context: Context): DisplayProfile {
    val hdrSupported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        runCatching {
            val display = context.display
            val hdrTypes = display?.hdrCapabilities?.supportedHdrTypes ?: IntArray(0)
            hdrTypes.isNotEmpty()
        }.getOrDefault(false)
    } else {
        false
    }
    val wideColorGamutSupported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        runCatching {
            context.resources.configuration.isScreenWideColorGamut
        }.getOrDefault(false)
    } else {
        false
    }
    val summaryParts = mutableListOf<String>()
    summaryParts += "hdr=$hdrSupported"
    summaryParts += "wideColor=$wideColorGamutSupported"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        val hdrTypes = runCatching {
            context.display?.hdrCapabilities?.supportedHdrTypes?.joinToString(",").orEmpty()
        }.getOrDefault("")
        if (hdrTypes.isNotEmpty()) {
            summaryParts += "hdrTypes=$hdrTypes"
        }
    }
    return DisplayProfile(
        supportsHdr = hdrSupported,
        supportsWideColorGamut = wideColorGamutSupported,
        summary = summaryParts.joinToString(" | "),
    )
}

private fun readSystemProperty(name: String): String {
    return runCatching {
        val clazz = Class.forName("android.os.SystemProperties")
        val getter = clazz.getMethod("get", String::class.java, String::class.java)
        getter.invoke(null, name, "")?.toString().orEmpty()
    }.getOrDefault("")
}
