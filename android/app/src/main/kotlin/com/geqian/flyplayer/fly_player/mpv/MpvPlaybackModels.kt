package com.geqian.flyplayer.fly_player.mpv

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import java.util.Locale

data class MpvSource(
    val itemGuid: String,
    val mediaGuid: String,
    val videoGuid: String,
    val url: String,
    val headers: Map<String, String>,
    val title: String,
    val startPositionMs: Long,
    val audioTrackIndex: Int?,
    val subtitleTrackIndex: Int?,
    val audioTrackGuid: String?,
    val subtitleTrackGuid: String?,
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
    val reliableSeek: Boolean,
    val seekProbeSummary: String?,
    val playbackSpeed: Double,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): MpvSource {
            @Suppress("UNCHECKED_CAST")
            val rawHeaders = map["headers"] as? Map<String, Any?> ?: emptyMap()
            return MpvSource(
                itemGuid = map["itemGuid"]?.toString().orEmpty(),
                mediaGuid = map["mediaGuid"]?.toString().orEmpty(),
                videoGuid = map["videoGuid"]?.toString().orEmpty(),
                url = map["url"]?.toString().orEmpty(),
                headers = rawHeaders.mapValues { it.value?.toString().orEmpty() }
                    .filterValues { it.isNotEmpty() },
                title = map["title"]?.toString().orEmpty(),
                startPositionMs = map["startPositionMs"].toLongValue(),
                audioTrackIndex = map["audioTrackIndex"].toIntValue(),
                subtitleTrackIndex = map["subtitleTrackIndex"].toIntValue(),
                audioTrackGuid = map["audioTrackGuid"]?.toString(),
                subtitleTrackGuid = map["subtitleTrackGuid"]?.toString(),
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
                reliableSeek = map["reliableSeek"] as? Boolean ?: true,
                seekProbeSummary = map["seekProbeSummary"]?.toString(),
                playbackSpeed = map["playbackSpeed"].toDoubleValue() ?: 1.0,
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

    fun debugSummary(): String {
        return "codec=$videoCodecName profile=$videoProfile bitDepth=$bitDepth colorSpace=$colorSpace transfer=$colorTransfer primaries=$colorPrimaries"
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

data class MpvPlayerState(
    val ready: Boolean = false,
    val nativeLibLoaded: Boolean = false,
    val paused: Boolean = true,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val statusText: String = "Preparing player",
    val error: String? = null,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "ready" to ready,
            "nativeLibLoaded" to nativeLibLoaded,
            "paused" to paused,
            "positionMs" to positionMs,
            "durationMs" to durationMs,
            "statusText" to statusText,
            "error" to error,
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
