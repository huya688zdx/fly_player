package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
import android.graphics.drawable.LayerDrawable
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.util.Rational
import android.util.Log
import android.util.TypedValue
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.SeekBar
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.geqian.flyplayer.fly_player.mpv.AudioSpatializerSupport
import com.geqian.flyplayer.fly_player.mpv.MpvPlaybackPhase
import com.geqian.flyplayer.fly_player.mpv.MpvPlayerState
import com.geqian.flyplayer.fly_player.mpv.NativePlayerReverseBridge
import com.geqian.flyplayer.fly_player.mpv.NativePlayerSurface
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.bitmap.CenterCrop
import com.bumptech.glide.load.resource.bitmap.RoundedCorners
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs

private val nativePanelLanguageNameMap = mapOf(
    "ara" to "阿拉伯语", "ar" to "阿拉伯语",
    "bul" to "保加利亚语", "bg" to "保加利亚语",
    "cat" to "加泰罗尼亚语", "ca" to "加泰罗尼亚语",
    "ces" to "捷克语", "cze" to "捷克语", "cs" to "捷克语",
    "jpn" to "日语", "ja" to "日语", "jp" to "日语",
    "chi" to "中文", "zho" to "中文", "zh" to "中文", "cmn" to "中文",
    "eng" to "英语", "en" to "英语",
    "dan" to "丹麦语", "da" to "丹麦语",
    "nld" to "荷兰语", "dut" to "荷兰语", "nl" to "荷兰语",
    "ell" to "希腊语", "gre" to "希腊语", "el" to "希腊语",
    "est" to "爱沙尼亚语", "et" to "爱沙尼亚语",
    "fin" to "芬兰语", "fi" to "芬兰语",
    "fra" to "法语", "fre" to "法语", "fr" to "法语",
    "heb" to "希伯来语", "he" to "希伯来语",
    "hin" to "印地语", "hi" to "印地语",
    "hrv" to "克罗地亚语", "hr" to "克罗地亚语",
    "hun" to "匈牙利语", "hu" to "匈牙利语",
    "ind" to "印尼语", "id" to "印尼语",
    "ita" to "意大利语", "it" to "意大利语",
    "kor" to "韩语", "ko" to "韩语",
    "lav" to "拉脱维亚语", "lv" to "拉脱维亚语",
    "lit" to "立陶宛语", "lt" to "立陶宛语",
    "msa" to "马来语", "may" to "马来语", "ms" to "马来语",
    "nob" to "挪威语", "nno" to "挪威语", "nor" to "挪威语",
    "nb" to "挪威语", "nn" to "挪威语", "no" to "挪威语",
    "pol" to "波兰语", "pl" to "波兰语",
    "por" to "葡萄牙语", "pt" to "葡萄牙语",
    "ron" to "罗马尼亚语", "rum" to "罗马尼亚语", "ro" to "罗马尼亚语",
    "rus" to "俄语", "ru" to "俄语",
    "slk" to "斯洛伐克语", "slo" to "斯洛伐克语", "sk" to "斯洛伐克语",
    "slv" to "斯洛文尼亚语", "sl" to "斯洛文尼亚语",
    "spa" to "西班牙语", "es" to "西班牙语",
    "srp" to "塞尔维亚语", "sr" to "塞尔维亚语",
    "swe" to "瑞典语", "sv" to "瑞典语",
    "tha" to "泰语", "th" to "泰语",
    "tur" to "土耳其语", "tr" to "土耳其语",
    "ukr" to "乌克兰语", "uk" to "乌克兰语",
    "vie" to "越南语", "vi" to "越南语",
    "deu" to "德语", "ger" to "德语", "de" to "德语",
    "mul" to "多种语言", "multi" to "多种语言",
)

internal fun nativePanelLanguageName(raw: String): String {
    val key = raw.trim().lowercase()
    if (key.isEmpty() || key == "zz-unknow" || key == "unknown" || key == "und") return "未知"
    return nativePanelLanguageNameMap[key] ?: "未知"
}

internal fun nativePanelTrackLabel(track: Map<String, Any?>): String {
    val title = track["title"]?.toString()?.trim().orEmpty()
    val language = nativePanelLanguageName(track["language"]?.toString().orEmpty())
        .takeUnless { it == "未知" }
        .orEmpty()
    val fallback = track["index"]?.toString()?.trim().orEmpty()
    return when {
        title.isNotEmpty() && language.isNotEmpty() -> "$title · $language"
        title.isNotEmpty() -> title
        language.isNotEmpty() -> language
        fallback.isNotEmpty() -> "轨道 $fallback"
        else -> "轨道"
    }
}

internal fun nativePanelAudioSummary(
    tracks: List<Map<String, Any?>>,
    selectedGuid: String,
): String {
    val selected = tracks.firstOrNull { it["guid"]?.toString().orEmpty() == selectedGuid }
    return selected?.let(::nativePanelTrackLabel) ?: "默认"
}

internal fun nativePanelSubtitleSummary(
    tracks: List<Map<String, Any?>>,
    selectedGuid: String,
): String {
    if (selectedGuid.isEmpty()) return "关闭"
    val selected = tracks.firstOrNull { it["guid"]?.toString().orEmpty() == selectedGuid }
    return selected?.let(::nativePanelTrackLabel) ?: "未选择"
}

internal fun nativePanelSubtitleCanRemove(track: Map<String, Any?>): Boolean {
    val guid = track["guid"]?.toString()?.trim()?.lowercase().orEmpty()
    return guid.startsWith("local:") ||
        nativePanelTruthy(track["isExternal"]) ||
        nativePanelTruthy(track["extraFile"])
}

/**
 * 决定某条字幕轨该走「内嵌轨选择」(setSubtitleTrack) 还是「外挂文件 sub-add」
 * (setExternalSubtitleFile)。
 *
 * 关键：位图字幕（PGS/SUP/VobSub）在 mpv 里**只能作为内嵌轨播放**——服务端即便把它额外
 * 抽取并标成 isExternal/extraFile，resolveSubtitleFile 也无法把位图变成可 sub-add 的文本
 * .ass。因此位图判断必须**优先于** isExternal/extraFile 标志，否则手动切到 SUP/PGS 会误走
 * 外挂路径下发错误字幕（表现为切 SUP 失败、或切回 SUP 掉成别的字幕）。
 * 用户「+添加」的本地字幕（local: guid）则始终走外挂文件。
 */
internal fun nativeSubtitleUsesExternalFile(track: Map<String, Any?>): Boolean {
    val guid = track["guid"]?.toString()?.trim()?.lowercase().orEmpty()
    if (guid.startsWith("local:")) return true
    val format = track["format"]?.toString()?.trim()?.lowercase().orEmpty()
    val codec = track["codecName"]?.toString()?.trim()?.lowercase().orEmpty()
    val isBitmapLike = nativePanelTruthy(track["isBitmap"]) ||
        format.contains("pgs") ||
        format.contains("sup") ||
        codec.contains("pgs") ||
        codec.contains("sup") ||
        codec.contains("hdmv_pgs") ||
        codec.contains("dvd_subtitle") ||
        codec.contains("vobsub")
    if (isBitmapLike) return false
    return nativePanelTruthy(track["isExternal"]) || nativePanelTruthy(track["extraFile"])
}

internal fun nativePanelSubtitleDisplayTitle(track: Map<String, Any?>): String {
    val rawLanguage = track["language"]?.toString().orEmpty()
    val language = nativePanelLanguageName(rawLanguage)
        .takeUnless { it == "未知" }
        .orEmpty()
    val title = track["title"]?.toString()?.trim().orEmpty()
    val base = when {
        language.isNotEmpty() -> language
        title.isNotEmpty() -> title
        else -> "字幕"
    }
    val suffix = when {
        nativePanelSubtitleCanRemove(track) -> "外挂"
        nativePanelTruthy(track["isDefault"]) -> "默认"
        else -> ""
    }
    return if (suffix.isNotEmpty()) "$base-$suffix" else base
}

internal fun nativePanelSubtitleDisplaySubtitle(track: Map<String, Any?>): String {
    val format = (
        track["format"]?.toString()?.trim()
            ?: ""
        ).ifEmpty { track["codecName"]?.toString()?.trim().orEmpty() }
        .uppercase()
    val language = nativePanelLanguageName(track["language"]?.toString().orEmpty())
        .takeUnless { it == "未知" }
        .orEmpty()
    val parts = listOf(format, language).filter { it.isNotEmpty() }
    return parts.joinToString("  ").ifEmpty {
        track["title"]?.toString()?.trim().orEmpty()
    }
}

private fun nativePanelTruthy(value: Any?): Boolean {
    return when (value) {
        is Boolean -> value
        is Number -> value.toInt() == 1
        is String -> value == "1" || value.equals("true", ignoreCase = true)
        else -> false
    }
}

internal fun nativePanelQualitySummary(
    playbackMode: String?,
    currentResolution: String?,
): String {
    if (playbackMode == "originalQuality") return "原画"
    val resolution = currentResolution?.trim().orEmpty()
    val vertical = Regex("""(?:^|x)(\d{3,4})(?:p)?$""", RegexOption.IGNORE_CASE)
        .find(resolution)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    return if (vertical != null && vertical > 0) "${vertical}P" else "原画"
}

/**
 * 画质档位等级：把分辨率（可为 "4k"/"4K HDR"/"1080P"/"1920x1080" 等）归一到竖直像素档。
 * 主面板据此把同档位合并（4k 与 4K HDR 同为 2160 档收成一张卡）、按档位排序与高亮。
 * 无法识别返回 0。
 */
internal fun nativePanelQualityTierRank(resolution: String?): Int {
    val raw = resolution?.trim().orEmpty()
    if (raw.isEmpty()) return 0
    val lower = raw.lowercase()
    // 形如 1920x1080 / 3840×2160：取较小一侧作为竖直分辨率。
    Regex("""(\d{2,5})\s*[x×]\s*(\d{2,5})""").find(lower)?.let { m ->
        val a = m.groupValues[1].toIntOrNull() ?: 0
        val b = m.groupValues[2].toIntOrNull() ?: 0
        if (a > 0 && b > 0) return minOf(a, b)
    }
    Regex("""(\d{3,4})""").find(lower)?.value?.toIntOrNull()?.let { return it }
    return when {
        lower.contains("8k") || lower.contains("4320") -> 4320
        lower.contains("4k") || lower.contains("2160") -> 2160
        lower.contains("2k") || lower.contains("1440") -> 1440
        else -> 0
    }
}

/** 档位等级 → 主面板卡片显示名：2160→"4k"、4320→"8k"、1440→"2k"，其余 "<rank>P"，未知为空。 */
internal fun nativePanelQualityTierLabel(rank: Int): String {
    return when {
        rank >= 4320 -> "8k"
        rank == 2160 -> "4k"
        rank in 1430..1450 -> "2k"
        rank > 0 -> "${rank}P"
        else -> ""
    }
}

internal data class NativeEpisodeVersionEntry(
    val sourceIndex: Int,
    val mediaGuid: String,
    val quality: Map<String, Any?>,
)

internal fun nativePanelEpisodeVersionEntries(
    qualities: List<Map<String, Any?>>,
): List<NativeEpisodeVersionEntry> {
    val bestByMediaGuid = LinkedHashMap<String, NativeEpisodeVersionEntry>()
    for ((index, quality) in qualities.withIndex()) {
        val mediaGuid = quality["mediaGuid"]?.toString()?.trim().orEmpty()
        if (mediaGuid.isEmpty()) continue
        val current = NativeEpisodeVersionEntry(index, mediaGuid, quality)
        val existing = bestByMediaGuid[mediaGuid]
        if (existing == null || nativePanelPreferEpisodeVersionQuality(current.quality, existing.quality)) {
            bestByMediaGuid[mediaGuid] = current
        }
    }
    return bestByMediaGuid.values.toList().takeIf { it.size > 1 }.orEmpty()
}

/** 版本卡标题：优先源文件名，缺失时回退「版本 N」。 */
internal fun nativePanelEpisodeVersionTitle(quality: Map<String, Any?>, index: Int): String {
    val fileName = quality["fileName"]?.toString()?.trim().orEmpty()
    return fileName.ifEmpty { "版本 ${index + 1}" }
}

internal fun nativePanelBitrateLabel(bitrateBitsPerSecond: Long): String {
    if (bitrateBitsPerSecond <= 0L) return ""
    val mbps = BigDecimal.valueOf(bitrateBitsPerSecond)
        .divide(BigDecimal.valueOf(1_000_000L), 2, RoundingMode.DOWN)
        .stripTrailingZeros()
        .toPlainString()
    return "${if (mbps == "0") "<0.01" else mbps} Mbps"
}

/** 版本卡副标题：分辨率 · 视频时长 · 码率（不再写来源「转码/原画」）。 */
internal fun nativePanelEpisodeVersionSummary(
    quality: Map<String, Any?>,
    durationLabel: String = "",
): String {
    val resolution = quality["resolution"]?.toString()?.trim().orEmpty()
        .ifEmpty { nativePanelQualityTierLabel(nativePanelQualityTierRank(quality["resolution"]?.toString())) }
        .ifEmpty { "版本" }
    val bitrate = nativePanelQualityBitrate(quality).takeIf { it > 0 }?.let {
        nativePanelBitrateLabel(it)
    }.orEmpty()
    return listOf(resolution, durationLabel.trim(), bitrate).filter { it.isNotEmpty() }.joinToString(" · ")
}

private fun nativePanelPreferEpisodeVersionQuality(
    candidate: Map<String, Any?>,
    current: Map<String, Any?>,
): Boolean {
    val candidateDefault = nativePanelTruthy(candidate["isDefault"])
    val currentDefault = nativePanelTruthy(current["isDefault"])
    if (candidateDefault != currentDefault) return candidateDefault
    val candidateOriginal = candidate["source"]?.toString() == "originalProxy"
    val currentOriginal = current["source"]?.toString() == "originalProxy"
    if (candidateOriginal != currentOriginal) return candidateOriginal
    return nativePanelQualityBitrate(candidate) > nativePanelQualityBitrate(current)
}

internal data class NativeWeakNetworkQualityRecommendation(
    val qualityIndex: Int,
    val qualityLabel: String,
    val details: String,
)

internal fun nativePanelRecommendWeakNetworkQuality(
    qualities: List<Map<String, Any?>>,
    currentQuality: Map<String, Any?>,
    networkSpeedBytesPerSecond: Long,
    estimatedResumeWaitMs: Long? = null,
): NativeWeakNetworkQualityRecommendation? {
    if (qualities.isEmpty()) return null
    val sorted = qualities.withIndex().sortedWith { left, right ->
        nativePanelCompareQualityPreference(left.value, right.value)
    }
    val target = nativePanelBestWeakNetworkTarget(
        sorted = sorted,
        currentQuality = currentQuality,
        networkSpeedBytesPerSecond = networkSpeedBytesPerSecond,
    ) ?: return null
    if (nativePanelSameQuality(target.value, currentQuality)) return null

    val currentBitrate = nativePanelQualityBitrate(currentQuality)
    val targetBitrate = nativePanelQualityBitrate(target.value)
    if (currentBitrate <= 0 || targetBitrate <= 0) return null
    if (targetBitrate > (currentBitrate * 0.8).toLong()) return null

    return NativeWeakNetworkQualityRecommendation(
        qualityIndex = target.index,
        qualityLabel = nativePanelWeakNetworkQualityLabel(target.value),
        details = nativePanelWeakNetworkDetails(
            networkSpeedBytesPerSecond = networkSpeedBytesPerSecond,
            estimatedResumeWaitMs = estimatedResumeWaitMs,
        ),
    )
}

internal fun nativePanelShouldStartAutoNextCountdown(
    autoPlayEnabled: Boolean,
    hasNextEpisode: Boolean,
    episodeSwitchInFlight: Boolean = false,
    suppressedForCurrent: Boolean = false,
): Boolean = autoPlayEnabled &&
    hasNextEpisode &&
    !episodeSwitchInFlight &&
    !suppressedForCurrent

internal fun nativePanelShouldShowCompletedOverlay(
    autoPlayEnabled: Boolean,
    hasNextEpisode: Boolean,
    playbackEnded: Boolean,
    insideCompletionWindow: Boolean,
    positionMs: Long,
    durationMs: Long,
): Boolean {
    if (playbackEnded) return true
    if (autoPlayEnabled && hasNextEpisode) return false
    if (durationMs <= 0L || positionMs <= 0L) return false
    val endThresholdMs = (durationMs - 1_000L).coerceAtLeast(0L)
    return positionMs >= endThresholdMs
}

internal fun nativePanelLoadArgsForEpisodeSwitch(
    loadArgs: Map<String, Any?>,
    autoPlayAfterLoad: Boolean,
): Map<String, Any?> {
    if (!autoPlayAfterLoad) return loadArgs
    return LinkedHashMap(loadArgs).apply {
        this["startPaused"] = false
    }
}

private fun nativePanelBestWeakNetworkTarget(
    sorted: List<IndexedValue<Map<String, Any?>>>,
    currentQuality: Map<String, Any?>,
    networkSpeedBytesPerSecond: Long,
): IndexedValue<Map<String, Any?>>? {
    if (networkSpeedBytesPerSecond > 0) {
        val maxSafeBitrateBitsPerSecond = (networkSpeedBytesPerSecond * 8 * 0.9).toLong()
        for (entry in sorted) {
            val bitrate = nativePanelQualityBitrate(entry.value)
            if (bitrate <= 0 || bitrate > maxSafeBitrateBitsPerSecond) continue
            return if (nativePanelSameQuality(entry.value, currentQuality)) null else entry
        }
    }

    val currentIndex = sorted.indexOfFirst { nativePanelSameQuality(it.value, currentQuality) }
    val currentBitrate = nativePanelQualityBitrate(currentQuality)
    if (currentIndex >= 0) {
        for (index in currentIndex + 1 until sorted.size) {
            val candidate = sorted[index]
            val bitrate = nativePanelQualityBitrate(candidate.value)
            if (bitrate <= 0) continue
            if (currentBitrate > 0 && bitrate >= currentBitrate) continue
            return candidate
        }
    }
    if (currentBitrate > 0) {
        return sorted.firstOrNull {
            val bitrate = nativePanelQualityBitrate(it.value)
            bitrate > 0 && bitrate < currentBitrate
        }
    }
    return sorted.asReversed().firstOrNull {
        nativePanelQualityBitrate(it.value) > 0 &&
            !nativePanelSameQuality(it.value, currentQuality)
    }
}

private fun nativePanelCompareQualityPreference(
    left: Map<String, Any?>,
    right: Map<String, Any?>,
): Int {
    val leftBitrate = nativePanelQualityBitrate(left)
    val rightBitrate = nativePanelQualityBitrate(right)
    if (leftBitrate != rightBitrate) return rightBitrate.compareTo(leftBitrate)

    val leftRank = nativePanelQualityTierRank(left["resolution"]?.toString())
    val rightRank = nativePanelQualityTierRank(right["resolution"]?.toString())
    if (leftRank != rightRank) return rightRank.compareTo(leftRank)

    val leftOriginal = left["source"]?.toString() == "originalProxy"
    val rightOriginal = right["source"]?.toString() == "originalProxy"
    if (leftOriginal != rightOriginal) return if (leftOriginal) -1 else 1

    val leftDefault = nativePanelTruthy(left["isDefault"])
    val rightDefault = nativePanelTruthy(right["isDefault"])
    if (leftDefault != rightDefault) return if (rightDefault) 1 else -1

    return left["resolution"]?.toString().orEmpty()
        .compareTo(right["resolution"]?.toString().orEmpty())
}

private fun nativePanelSameQuality(
    left: Map<String, Any?>,
    right: Map<String, Any?>,
): Boolean {
    return left["source"]?.toString().orEmpty() == right["source"]?.toString().orEmpty() &&
        left["mediaGuid"]?.toString().orEmpty() == right["mediaGuid"]?.toString().orEmpty() &&
        left["videoGuid"]?.toString().orEmpty() == right["videoGuid"]?.toString().orEmpty() &&
        left["resolution"]?.toString().orEmpty() == right["resolution"]?.toString().orEmpty() &&
        nativePanelQualityBitrate(left) == nativePanelQualityBitrate(right) &&
        nativePanelNullableInt(left["directLinkQualityIndex"]) ==
            nativePanelNullableInt(right["directLinkQualityIndex"])
}

private fun nativePanelWeakNetworkQualityLabel(quality: Map<String, Any?>): String {
    val rank = nativePanelQualityTierRank(quality["resolution"]?.toString())
    return nativePanelQualityTierLabel(rank).ifEmpty {
        quality["resolution"]?.toString()?.trim().orEmpty().ifEmpty { "较低画质" }
    }
}

private fun nativePanelWeakNetworkDetails(
    networkSpeedBytesPerSecond: Long,
    estimatedResumeWaitMs: Long?,
): String {
    val speed = nativePanelSpeedLabel(networkSpeedBytesPerSecond)
    if (estimatedResumeWaitMs == null) return "当前网速 $speed"
    val seconds = ((estimatedResumeWaitMs.coerceAtLeast(1L) + 999L) / 1000L).coerceAtLeast(1L)
    return "当前网速 $speed · 预计恢复 ${seconds}秒"
}

private fun nativePanelSpeedLabel(bytesPerSecond: Long): String {
    if (bytesPerSecond <= 0) return "-- KB/s"
    val kb = 1024.0
    val mb = kb * 1024.0
    if (bytesPerSecond >= mb.toLong()) {
        val value = bytesPerSecond / mb
        val digits = if (value >= 10) 0 else 1
        return "${String.format("%.${digits}f", value)} MB/s"
    }
    val value = bytesPerSecond / kb
    val digits = if (value >= 100) 0 else 1
    return "${String.format("%.${digits}f", value)} KB/s"
}

private fun nativePanelQualityBitrate(quality: Map<String, Any?>): Long {
    return when (val raw = quality["bitrate"]) {
        is Number -> raw.toLong()
        is String -> raw.toLongOrNull() ?: 0L
        else -> 0L
    }
}

private fun nativePanelNullableInt(value: Any?): Int? {
    return when (value) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }
}

internal fun nativePanelResolveImageUrl(path: String?, videoUrl: String?): String {
    val rawPath = path?.trim().orEmpty()
    if (rawPath.isEmpty()) return ""
    if (
        rawPath.startsWith("http://", ignoreCase = true) ||
        rawPath.startsWith("https://", ignoreCase = true) ||
        rawPath.startsWith("file://", ignoreCase = true) ||
        rawPath.startsWith("content://", ignoreCase = true)
    ) {
        return rawPath
    }
    val sourceUrl = videoUrl?.trim().orEmpty()
    if (sourceUrl.isEmpty()) return ""
    val origin = runCatching {
        val uri = java.net.URI(sourceUrl)
        val scheme = uri.scheme.orEmpty()
        val host = uri.host.orEmpty()
        if (scheme.isEmpty() || host.isEmpty()) return@runCatching ""
        val port = if (uri.port != -1) ":${uri.port}" else ""
        "$scheme://$host$port"
    }.getOrNull().orEmpty()
    if (origin.isEmpty()) return ""
    val normalizedPath = if (rawPath.startsWith("/")) rawPath else "/$rawPath"
    return "$origin/v/api/v1/sys/img$normalizedPath?w=320"
}

internal fun nativePanelEpisodeLabel(episode: Map<String, Any?>): String {
    val number = (episode["episodeNumber"] as? Number)?.toInt() ?: 0
    val title = episode["title"]?.toString()?.trim().orEmpty()
    val shortLabel = episode["shortLabel"]?.toString()?.trim().orEmpty()
    val prefix = when {
        number > 0 -> "第${number}集"
        shortLabel.isNotEmpty() -> shortLabel
        else -> ""
    }
    return when {
        prefix.isNotEmpty() && title.isNotEmpty() && title != prefix ->
            "$prefix  $title"
        title.isNotEmpty() -> title
        prefix.isNotEmpty() -> prefix
        else -> "未命名"
    }
}

/**
 * 渐进原生化阶段 1 的纯原生播放壳 Activity。
 *
 * 视频(SurfaceView) + 弹幕(原生 Canvas) + 控制层(传统 View) 全在原生层级，没有
 * Flutter overlay → 没有 Hybrid Composition → 弹幕丝滑、控制/二级界面不卡。
 *
 * source 解析与弹幕拉取仍由 Flutter 编排层负责，结果通过 Intent 喂进来：
 *  - extra "loadArgs"        : JSON，controller.load 入参（至少含 url）
 *  - extra "danmakuPayload"  : JSON，可选，弹幕数据（格式同 NativeDanmakuOverlayView.setPayload）
 *
 * 也支持 adb 直接拉起测试（绕过 Flutter）：
 *   adb shell am start -n com.geqian.flyplayer.fly_player/.NativePlayerActivity \
 *     --es loadArgs '{"url":"<可直接播放的URL>","startPositionMs":0,"loadNonce":1}'
 */
internal const val NATIVE_EPISODE_VIEW_MODE_LIST = 0
internal const val NATIVE_EPISODE_VIEW_MODE_GRID = 1
internal const val NATIVE_PLAYER_AUTO_ROTATE_PREF_KEY = "flutter.player_auto_rotate_enabled"
internal const val NATIVE_PLAYER_AUTO_PLAY_PREF_KEY = "flutter.player_auto_play_enabled"
internal const val NATIVE_PLAYER_NEXT_EPISODE_PRELOAD_PREF_KEY =
    "flutter.player_next_episode_preload_enabled"

internal fun nativePanelEpisodeViewModeFromType(viewType: String?): Int {
    return if (viewType?.trim() == "button") {
        NATIVE_EPISODE_VIEW_MODE_GRID
    } else {
        NATIVE_EPISODE_VIEW_MODE_LIST
    }
}

internal fun nativePanelPlaylistViewTypeFromEpisodeMode(mode: Int): String {
    return if (mode == NATIVE_EPISODE_VIEW_MODE_GRID) "button" else "card"
}

internal fun nativePanelCanPreloadNextEpisode(
    autoPlayEnabled: Boolean,
    nextEpisodePreloadEnabled: Boolean,
): Boolean = autoPlayEnabled && nextEpisodePreloadEnabled

internal data class NativeEpisodePickerData(
    val selectedSeasonGuid: String,
    val viewMode: Int,
    val seasons: List<Map<String, Any?>>,
    val episodes: List<Map<String, Any?>>,
)

internal fun nativePanelEpisodePickerData(
    selectedSeasonGuid: String,
    viewType: String?,
    seasons: List<Map<String, Any?>>,
    episodes: List<Map<String, Any?>>,
    fallbackEpisodes: List<Map<String, Any?>>,
): NativeEpisodePickerData {
    val resolvedEpisodes = if (episodes.isNotEmpty()) episodes else fallbackEpisodes
    val explicitSeasonGuid = selectedSeasonGuid.trim()
    val fallbackSeasonGuid = resolvedEpisodes.firstOrNull()?.let {
        (it["seasonGuid"] ?: it["parentGuid"])?.toString()?.trim().orEmpty()
    }.orEmpty()
    val resolvedSeasonGuid = explicitSeasonGuid.ifEmpty { fallbackSeasonGuid }
    val normalizedSeasons = seasons.map { season ->
        val guid = (season["seasonGuid"] ?: season["guid"])?.toString()?.trim().orEmpty()
        LinkedHashMap<String, Any?>(season).apply {
            this["seasonGuid"] = guid
            this["selected"] = guid.isNotEmpty() && guid == resolvedSeasonGuid
        }
    }
    return NativeEpisodePickerData(
        selectedSeasonGuid = resolvedSeasonGuid,
        viewMode = nativePanelEpisodeViewModeFromType(viewType),
        seasons = normalizedSeasons,
        episodes = resolvedEpisodes,
    )
}

class NativePlayerActivity : Activity(), NativeMediaCommandCoordinator.Handler {

    companion object {
        const val TAG = "NativePlayerActivity"
        const val EXTRA_LOAD_ARGS = "loadArgs"
        const val EXTRA_DANMAKU_PAYLOAD = "danmakuPayload"
        const val EXTRA_DANMAKU_FILE = "danmakuFile"
        const val EXTRA_DANMAKU_TEST = "danmakuTest"
        const val REQUEST_PICK_DANMAKU = 4201
        const val REQUEST_PICK_SUBTITLE = 4202
        // 弹幕「从文件导入」只接受弹幕评论文件（弹弹/B站 XML、JSON）。
        val DANMAKU_IMPORT_EXTENSIONS = setOf("xml", "json")
        // 外挂字幕导入仅接受 mpv 能直接 sub-add 的文本字幕格式。
        val SUBTITLE_IMPORT_EXTENSIONS = setOf("srt", "ass", "ssa", "vtt", "sub", "ttml")
        const val CONTROLS_AUTO_HIDE_MS = 3500L
        const val CHROME_FADE_MS = 220L
        const val TRANSIENT_HINT_MS = 1200L
        // 持续提示（showCenterHint）的兜底自动消失：任何异步路径漏掉 hideCenterHint 时，
        // 不至于让「正在加载字幕…」「正在切换…」等常驻屏幕。
        const val CENTER_HINT_WATCHDOG_MS = 15000L
        // 弱网：服务端重载（切画质/音轨/字幕/选集）超过该时长仍未完成，升级提示文案。
        const val WEAK_NET_ESCALATE_MS = 6000L

        // 配色对齐 app 主题（默认蓝 accent，与 Flutter 播放器进度条同色）。
        // 含符号位的 ARGB 字面量是 Long，须 .toInt()，故用 val 而非 const val。
        private val ACCENT = 0xFF3A82F7.toInt()
        private val SCRIM_TOP = 0x8A000000.toInt() // 顶部信息栏渐变起点
        private val SCRIM_BOTTOM = 0xD6000000.toInt() // 底部控制条渐变终点
        private val PILL_BG = 0xB0060A10.toInt() // 中央提示/状态药丸底色
        private const val GLASS_BG = 0x66081018 // 毛玻璃按钮底色（~40% 深蓝黑）
        private const val GLASS_STROKE = 0x2EFFFFFF // 毛玻璃按钮描边
        private const val TRACK_BG = 0x24FFFFFF // 进度条底槽
        private const val TRACK_BUFFERED = 0x52FFFFFF // 缓冲进度
        private val TEXT_DIM = 0xB8FFFFFF.toInt() // 次要文字
        private val ACCENT_SOFT = 0x333A82F7
        private val PANEL_BG = 0xCC000000.toInt()
        private val ITEM_SELECTED_BG = 0x333A82F7.toInt()
        // 与 Flutter shared_preferences 共享的播放列表视图偏好键（plugin 自带 `flutter.` 前缀）。
        private const val SHARED_PLAYLIST_VIEW_TYPE_KEY = "flutter.playlist_view_type"
        // 截图保存设置同样与 Flutter 端共享同一份偏好，避免两端各存一套漂移。
        private const val SHARED_SCREENSHOT_SAVE_MODE_KEY = "flutter.screenshot_save_path_mode"
        private const val SHARED_SCREENSHOT_INCLUDE_SUBTITLES_KEY =
            "flutter.screenshot_include_subtitles"
        private const val SCREENSHOT_DEFAULT_SAVE_MODE = "pictures"
    }

    private lateinit var playerSurface: NativePlayerSurface
    private lateinit var rootContainer: FrameLayout
    private lateinit var topBar: View
    private lateinit var bottomBar: View
    private lateinit var titleLabel: TextView
    private lateinit var playPauseButton: ImageButton
    private lateinit var positionLabel: TextView
    private lateinit var durationLabel: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var statusLabel: TextView
    private lateinit var speedButton: TextView
    private lateinit var qualityButton: TextView
    private lateinit var episodeEntryButton: TextView
    private var episodeEntryDivider: View? = null
    // 竖屏精简：以下控件随朝向显隐（顶栏次要图标 + 底栏溢出入口），见 applyOrientationToControls()。
    private var pipButton: View? = null
    private var screenshotButton: View? = null
    private var danmakuQuickButton: View? = null
    private var audioEntryButton: TextView? = null
    private var subtitleEntryButton: TextView? = null
    private var audioEntrySpacer: View? = null
    private var subtitleEntrySpacer: View? = null
    private var qualityEntrySpacer: View? = null
    private lateinit var displayModeButton: ImageButton

    private lateinit var panelContainer: FrameLayout
    private lateinit var panelScrollView: MaxHeightScrollView
    private lateinit var panelContent: LinearLayout
    private lateinit var panelTitle: TextView
    private lateinit var panelSeasonSelector: TextView
    private lateinit var panelBackButton: ImageButton
    private lateinit var panelHeaderActions: LinearLayout
    private val panelStack = ArrayDeque<PanelPage>()
    private var panelVisible = false
    private var panelIsSheet = false
    private var currentEpisodeRangeIndex = -1
    private var episodeViewMode = NATIVE_EPISODE_VIEW_MODE_LIST
    // 用户本次会话手动切过宫格/列表：置位后不再让在途 loadEpisodePickerData 回包覆盖该选择，
    // 避免「确认前手动切换→确认完成后被服务端旧值改回」的跳变。换源时复位。
    private var episodeViewModeUserDirty = false
    private var episodePanelLoading = false
    private var episodePanelSelectedSeasonGuid = ""
    private var episodePanelSeriesTitle = ""
    private var episodePanelEpisodes: List<Map<String, Any?>> = emptyList()
    private var episodePanelSeasons: List<Map<String, Any?>> = emptyList()
    private var episodePanelLoadToken = 0
    // 选集面板按季缓存（seasonGuid → 该季剧集）：起播后台预取填充，切季时命中即瞬时切换。
    private val seasonEpisodesCache = HashMap<String, List<Map<String, Any?>>>()
    // 单次预取守卫：每路 source（applyLoadArgs）只在首帧后启动一次全季预取。
    private var episodePickerPrefetchStarted = false
    // 已成功落地过一次完整的选集数据（季列表/视图/剧集）。此后 loadEpisodePickerData 的回包
    // 只做增量（同步当前季观看状态），不再整包覆盖，从源头规避「在途回包改回本地状态」竞态。
    private var episodePickerLoadedOnce = false
    private var customQualityTabTitle = ""
    private var expandedEpisodeVersionGuid: String? = null

    private var controlsVisible = true
    private var userSeeking = false
    private var lastDurationMs = 0L
    private var mediaTitle = ""
    private var loadArgsMap: Map<String, Any?> = emptyMap()
    // 当前实际选中的音轨/字幕 guid（飞牛侧 guid 命名空间，与 loadArgs["subtitleTracks"]
    // 里的 guid 同源）。loadArgs 里的字段只是「启动时」的初值，用户在面板里切换后必须更新
    // 这里，否则面板高亮固定、续播也会回写成旧轨。字幕空串表示「关闭」。
    private var selectedAudioGuid: String = ""
    private var selectedSubtitleGuid: String = ""
    // 每次换源后置 true，待 visualPlaybackReady 时把 loadArgs 给出的初始字幕真正套用一次
    // （内置走 sid、外挂/本地走文件加载）。否则外挂初始字幕没人加载，mpv 退回默认内置轨。
    private var pendingInitialSubtitle = false
    private var lastRecordedTs = -1L
    private val progressReportRunnable = object : Runnable {
        override fun run() {
            if (!isPeriodicReportRunning) return
            if (this@NativePlayerActivity::playerSurface.isInitialized &&
                playerSurface.state.nativeLibLoaded
            ) {
                reportProgress(periodic = true)
            }
            if (this@NativePlayerActivity::bottomBar.isInitialized) {
                bottomBar.postDelayed(this, 3000L)
            }
        }
    }
    private var isPeriodicReportRunning = false
    private val hideControlsRunnable = Runnable { setControlsVisible(false) }

    private lateinit var centerHint: TextView
    private lateinit var audioManager: AudioManager
    private lateinit var gestureDetector: GestureDetector
    private val transientHintHide = Runnable { hideCenterHint() }
    private val centerHintWatchdog = Runnable { hideCenterHint() }
    private val weakNetEscalate = Runnable {
        if (this::centerHint.isInitialized && centerHint.visibility == View.VISIBLE) {
            centerHint.text = "网络较慢，仍在加载…"
        }
    }
    // 手势状态：0 无 / 1 横拖 seek / 2 左侧亮度 / 3 右侧音量
    private var gestureMode = 0
    private var gestureSeekStartMs = 0L
    private var gestureSeekTargetMs = 0L
    private var gestureBrightnessStart = 0.5f
    private var gestureVolumeStart = 0
    private var speedBoosting = false
    // 「点空白关面板」期间吞掉整段手势：DOWN 关面板后，剩余 MOVE/UP 不能漏给手势识别器，
    // 否则会带着上一段手势的陈旧 e1 触发 seek（表现为进度条左右波动）。
    private var swallowingPanelDismiss = false
    private val touchSlop by lazy { ViewConfiguration.get(this).scaledTouchSlop }

    // ---- 系统媒体集成（音频焦点 + MediaSession 前台服务 + PIP 增强，Phase 1） ----
    private lateinit var audioFocus: NativePlaybackAudioFocusController
    // duck 前缓存的 mpv 输出音量，焦点恢复时还原。
    private var duckSavedVolume = 100.0
    // 划走自动进 PIP 开关（video_misc 持久化），API31+ setAutoEnterEnabled / <31 onUserLeaveHint。
    // 默认关：离开应用不自动进小窗，只有手动点小窗按钮才进；用户可在设置里开启「划走自动小窗」。
    private var pipAutoEnter = false
    private var mediaSessionStarted = false
    // 仅在播放态/标题/可切集变化时刷新会话/通知，避免每帧重建前台通知；进度按 ~1s 节流刷新。
    private var lastMediaPlaying: Boolean? = null
    private var lastMediaTitle: String = ""
    private var lastMediaCanNext: Boolean = false
    private var lastMediaPushElapsedMs = 0L

    private var isLocked = false
    private lateinit var lockButton: ImageButton
    private lateinit var freezeFrameView: ImageView
    private val hideFreezeRunnable = Runnable { hideFreezeFrame() }

    private var batteryLevel = -1
    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            batteryLevel = intent?.getIntExtra("level", -1) ?: -1
            updateSystemInfo()
        }
    }
    private lateinit var batteryLabel: TextView
    private lateinit var networkLabel: TextView
    private var batteryReceiverRegistered = false
    // OnBackInvokedCallback（API 33+）；用 Any? 持有，避免旧设备类加载该 API 类型。
    private var backInvokedCallback: Any? = null
    private var inPipMode = false

    private var danmakuEnabled = true
    private lateinit var danmakuToggleButton: TextView
    private var isAudioOnly = false
    private lateinit var listenButton: View
    private var listenLayer: FrameLayout? = null
    private lateinit var listenBackdropImage: ImageView
    private lateinit var listenPosterImage: ImageView
    private lateinit var listenTitleLabel: TextView
    private lateinit var listenSubtitleLabel: TextView

    private var screenshotIncludeSubtitles = false
    private var screenshotSaveMode = SCREENSHOT_DEFAULT_SAVE_MODE

    private lateinit var abButton: View
    private var abRepeatMode = 0
    private var abLoopStartMs = 0L
    private var abLoopEndMs = 0L
    private lateinit var loadingSpinner: View
    private lateinit var promptLayer: FrameLayout
    private lateinit var resumeCard: LinearLayout
    private lateinit var resumeText: TextView
    private lateinit var autoNextCard: LinearLayout
    private lateinit var autoNextText: TextView
    private lateinit var weakNetCard: LinearLayout
    private lateinit var weakNetTitle: TextView
    private lateinit var weakNetSubtitle: TextView
    private var offlineBanner: View? = null
    private lateinit var completedOverlay: FrameLayout
    private lateinit var completedPosterImage: ImageView
    private lateinit var completedTitle: TextView
    private lateinit var completedNextButton: TextView
    private var networkOffline = false
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var offlineBannerDismissed = false
    private val resumeHideRunnable = Runnable { hideResumePrompt() }
    private var autoNextTicker: Runnable? = null
    private var autoNextSeconds = 0
    private var autoNextActive = false
    private var autoNextSuppressedItemGuid = ""
    private var completionActive = false
    private var episodeSwitchInFlight = false
    // 蠢措施兜底：只要进度真在往前走（位置推进+未暂停未缓冲），就认定已开播，不再死等内核的
    // visualPlaybackReady——切集原地换源时该标志偶发漏报，会把中间 loading 卡死。每次换源/重载复位。
    private var lastProgressPositionMs = -1L
    private var playbackProgressing = false
    private var nextEpisodePreloadGuid = ""
    private var nextEpisodePreloadInFlight = false
    private var nextEpisodePreloadResult: Any? = null
    private var weakNetDismissed = false
    private var weakNetSuggestedQualityIndex: Int? = null
    private var weakNetSuggestedQualityLabel = ""
    private var autoRotateEnabled = true
    private var autoPlayEnabled = true
    private var nextEpisodePreloadEnabled = false
    private var introOutroEnabled = true
    private var introMaxMin = 3
    private var outroMaxMin = 4
    private var skipCountdownSec = 5
    private var introSkipDismissed = false
    private var outroSkipDismissed = false
    private lateinit var skipCard: LinearLayout
    private lateinit var skipText: TextView
    private var skipAction: (() -> Unit)? = null
    private val bookmarks = mutableListOf<Bookmark>()
    private var markerView: ProgressMarkerView? = null
    private var chapterPositionsMs: List<Long> = emptyList()
    private var chaptersFetched = false
    private var chapterList: List<Map<String, Any?>> = emptyList()
    private var chapterFetchAttempt = 0
    private var inferredIntroStartMs = 0L
    private var inferredIntroEndMs = 0L
    private var inferredOutroStartMs = 0L

    private data class PanelItem(
        val title: String,
        val subtitle: String? = null,
        val selected: Boolean = false,
        val action: () -> Unit,
    )

    private data class PanelPage(
        val title: String,
        val headerActions: () -> List<View> = { emptyList() },
        // 标题旁的可点击「选季」chip 文案（返回 null 隐藏）。用 lambda 以便每次 render
        // 反映最新选中季（预取/切季后自动更新）。
        val seasonSelectorLabel: () -> String? = { null },
        // 点击季 chip 的回调，入参为 chip 视图，作为下拉窗锚点。
        val onSeasonSelectorClick: ((View) -> Unit)? = null,
        val build: () -> Unit,
    )

    private data class QualityPanelEntry(
        val sourceIndex: Int,
        val quality: Map<String, Any?>,
    )

    private data class Bookmark(val ts: Long, val note: String)

    /** 顶级入口：清栈并展示一页；同一页再次点击则收起。 */
    private fun togglePanel(page: PanelPage) {
        if (panelVisible && panelStack.size == 1 && panelStack.lastOrNull()?.title == page.title) {
            hidePanel()
            return
        }
        panelStack.clear()
        panelStack.addLast(page)
        renderTopPanel()
        showPanelContainer()
    }

    /** 进入子页，保留返回栈。 */
    private fun pushPanel(page: PanelPage) {
        panelStack.addLast(page)
        if (panelVisible) {
            renderTopPanel(animateDir = 1)
        } else {
            renderTopPanel()
            showPanelContainer()
        }
    }

    private fun popPanel() {
        if (panelStack.size <= 1) {
            hidePanel()
            return
        }
        panelStack.removeLast()
        renderTopPanel(animateDir = -1)
    }

    private fun renderTopPanel(animateDir: Int = 0) {
        val page = panelStack.lastOrNull() ?: return
        if (this::panelTitle.isInitialized) panelTitle.text = page.title
        if (this::panelSeasonSelector.isInitialized) {
            // 仅在非子页（无返回栈）展示季 chip；子页（如多版本）退栈语义不应叠加选季。
            val label = if (panelStack.size == 1) page.seasonSelectorLabel() else null
            if (label != null) {
                panelSeasonSelector.text = seasonSelectorSpan(label)
                panelSeasonSelector.visibility = View.VISIBLE
                panelSeasonSelector.setOnClickListener { view ->
                    page.onSeasonSelectorClick?.invoke(view)
                }
            } else {
                panelSeasonSelector.visibility = View.GONE
                panelSeasonSelector.setOnClickListener(null)
            }
        }
        if (this::panelBackButton.isInitialized) {
            panelBackButton.visibility = if (panelStack.size > 1) View.VISIBLE else View.GONE
        }
        if (this::panelHeaderActions.isInitialized) {
            panelHeaderActions.removeAllViews()
            val actions = page.headerActions()
            panelHeaderActions.visibility = if (actions.isEmpty()) View.GONE else View.VISIBLE
            for ((index, action) in actions.withIndex()) {
                panelHeaderActions.addView(
                    action,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        if (index > 0) leftMargin = dp(10)
                    },
                )
            }
        }
        if (!this::panelContent.isInitialized) return
        panelContent.removeAllViews()
        page.build()
        if (animateDir != 0) {
            panelContent.animate().cancel()
            panelContent.translationX = panelWidthPx().toFloat() * if (animateDir > 0) 1f else -1f
            panelContent.animate()
                .translationX(0f)
                .setDuration(CHROME_FADE_MS)
                .start()
        } else {
            panelContent.translationX = 0f
        }
    }

    private fun panelWidthPx(): Int {
        val screenWidth = window.decorView.width.coerceAtLeast(dp(400))
        return (screenWidth * 0.45f).toInt().coerceIn(dp(360), dp(520))
    }

    /** 竖屏底部弹窗高度上限：不超过屏高 82%，长面板（设置）封顶后内部滚动。 */
    private fun panelSheetCapPx(): Int =
        (window.decorView.height * 0.82f).toInt().coerceAtLeast(dp(280))

    /** 竖屏底部弹窗背景：顶部圆角的深色卡片。 */
    private fun bottomSheetBackground(): GradientDrawable = GradientDrawable().apply {
        setColor(0xF2141414.toInt())
        val r = dp(18).toFloat()
        cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
    }

    private fun showPanelContainer() {
        if (!this::panelContainer.isInitialized) return
        setControlsVisible(false)
        panelVisible = true
        panelContainer.visibility = View.VISIBLE
        val lp = panelContainer.layoutParams as FrameLayout.LayoutParams
        if (isPortrait()) {
            // 竖屏：底部弹窗，高度随内容自适应（限高后滚动），从屏幕下沿上滑。
            val cap = panelSheetCapPx()
            // 限高扣掉标题栏与内边距，使整窗（含 chrome）大致落在 cap 内。
            panelScrollView.maxHeightPx = (cap - dp(108)).coerceAtLeast(dp(160))
            panelScrollView.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            lp.width = FrameLayout.LayoutParams.MATCH_PARENT
            lp.height = FrameLayout.LayoutParams.WRAP_CONTENT
            lp.gravity = Gravity.BOTTOM
            panelContainer.layoutParams = lp
            panelContainer.background = bottomSheetBackground()
            panelContainer.requestLayout()
            panelContainer.translationX = 0f
            // 高度此刻未测得，用 cap 作为起始下移量保证完全在屏外起滑。
            panelContainer.translationY = cap.toFloat()
            panelContainer.animate().translationY(0f).setDuration(CHROME_FADE_MS).start()
        } else {
            // 横屏：右侧面板按权重铺满全高（不限高），从屏幕右沿左滑。
            panelScrollView.maxHeightPx = Int.MAX_VALUE
            panelScrollView.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f,
            )
            val w = panelWidthPx()
            lp.width = w
            lp.height = FrameLayout.LayoutParams.MATCH_PARENT
            lp.gravity = Gravity.END
            panelContainer.layoutParams = lp
            panelContainer.background = android.graphics.drawable.ColorDrawable(0xF2141414.toInt())
            panelContainer.requestLayout()
            panelContainer.translationY = 0f
            panelContainer.translationX = w.toFloat()
            panelContainer.animate().translationX(0f).setDuration(CHROME_FADE_MS).start()
        }
    }

    private fun hidePanel() {
        if (!panelVisible || !this::panelContainer.isInitialized) return
        panelVisible = false
        panelStack.clear()
        val anim = panelContainer.animate()
            .setDuration(CHROME_FADE_MS)
            .withEndAction { panelContainer.visibility = View.GONE }
        if (isPortrait()) {
            anim.translationY(panelContainer.height.toFloat())
        } else {
            anim.translationX(panelContainer.width.toFloat())
        }
        anim.start()
        scheduleControlsAutoHide()
    }

    private fun panelSectionHeader(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(4), dp(16), dp(4), dp(8))
        }
    }

    private fun panelNavRow(label: String, value: String = "", onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = itemRippleBackground()
            setPadding(dp(16), dp(16), dp(16), dp(16))
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            addView(
                TextView(context).apply {
                    text = label
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            if (value.isNotEmpty()) {
                addView(TextView(context).apply {
                    text = value
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                })
            }
            addView(TextView(context).apply {
                text = "›"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setPadding(dp(8), 0, 0, 0)
            })
            setOnClickListener { onClick() }
        }
    }

    private fun panelTileBackground(selected: Boolean = false): GradientDrawable {
        return GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(if (selected) ITEM_SELECTED_BG else 0x1FFFFFFF)
            setStroke(dp(1), if (selected) ACCENT else GLASS_STROKE)
        }
    }

    private fun versionGroupBackground(): GradientDrawable {
        return GradientDrawable().apply {
            cornerRadius = dp(16).toFloat()
            setColor(0xB01C1C1C.toInt())
            setStroke(dp(1), 0x22FFFFFF)
        }
    }

    private fun versionCardBackground(selected: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            cornerRadius = dp(13).toFloat()
            setColor(if (selected) 0x263A82F7 else 0x12FFFFFF)
            setStroke(dp(if (selected) 2 else 1), if (selected) 0xCC3A82F7.toInt() else 0x18FFFFFF)
        }
    }

    private fun versionAccentBar(selected: Boolean): View {
        return View(this).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(2).toFloat()
                setColor(if (selected) ACCENT else Color.TRANSPARENT)
            }
        }
    }

    private fun versionSelectedBadge(): View {
        return TextView(this).apply {
            text = "✓"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(ACCENT)
            }
        }
    }

    private fun panelPrimaryTile(
        title: String,
        subtitle: String = "",
        trailing: String = "",
        selected: Boolean = false,
        onClick: () -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = panelTileBackground(selected)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )

            val textColumn = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
            }
            textColumn.addView(TextView(context).apply {
                text = title
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            if (subtitle.isNotEmpty()) {
                textColumn.addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, dp(3), 0, 0)
                })
            }
            addView(
                textColumn,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            if (trailing.isNotEmpty()) {
                addView(TextView(context).apply {
                    text = trailing
                    setTextColor(if (selected) Color.WHITE else TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(dp(12), 0, 0, 0)
                })
            }
            addView(TextView(context).apply {
                text = "›"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setPadding(dp(8), 0, 0, 0)
            })
            setOnClickListener { onClick() }
        }
    }

    private fun panelOptionTile(
        title: String,
        subtitle: String = "",
        selected: Boolean = false,
        onClick: () -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = panelTileBackground(selected)
            setPadding(dp(14), dp(11), dp(14), dp(11))
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            val textColumn = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }
            textColumn.addView(TextView(context).apply {
                text = title
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            if (subtitle.isNotEmpty()) {
                textColumn.addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, dp(3), 0, 0)
                })
            }
            addView(textColumn, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (selected) {
                addView(TextView(context).apply {
                    text = "✓"
                    setTextColor(ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                })
            }
            setOnClickListener { onClick() }
        }
    }

    private fun panelEmptyState(text: String): View {
        return TextView(this).apply {
            this.text = text
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            background = panelTileBackground()
            setPadding(dp(14), dp(24), dp(14), dp(24))
        }
    }

    private fun panelSpacer(heightDp: Int): View {
        return View(this).apply {
            minimumHeight = dp(heightDp)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(heightDp),
            )
        }
    }

    private fun panelCardGroup(rows: List<View>): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(0xD92A2A2A.toInt())
                setStroke(dp(1), 0x1FFFFFFF)
            }
            clipToOutline = false
            for ((index, row) in rows.withIndex()) {
                addView(row)
                if (index != rows.lastIndex) {
                    addView(View(context).apply {
                        setBackgroundColor(0x22FFFFFF)
                    }, LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        dp(1),
                    ).apply {
                        leftMargin = dp(18)
                        rightMargin = dp(18)
                    })
                }
            }
        }
    }

    private fun panelMenuItem(
        title: String,
        trailing: String = "",
        onClick: () -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(17), dp(18), dp(17))
            isClickable = true
            background = itemRippleBackground()
            addView(TextView(context).apply {
                text = title
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (trailing.isNotEmpty()) {
                addView(TextView(context).apply {
                    text = trailing
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    gravity = Gravity.END
                }, LinearLayout.LayoutParams(dp(86), LinearLayout.LayoutParams.WRAP_CONTENT))
            }
            addView(TextView(context).apply {
                text = "›"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(dp(24), LinearLayout.LayoutParams.WRAP_CONTENT))
            setOnClickListener { onClick() }
        }
    }

    private fun panelSlider(
        label: String,
        min: Float,
        max: Float,
        value: Float,
        steps: Int = 100,
        format: (Float) -> String = { String.format("%.0f", it) },
        onCommit: ((Float) -> Unit)? = null,
        onChange: (Float) -> Unit,
    ): View {
        val span = (max - min).takeIf { it > 0f } ?: 1f
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = itemRippleBackground()
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            setPadding(dp(16), dp(14), dp(16), dp(14))
            val valueLabel = TextView(context).apply {
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                text = format(value)
            }
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    TextView(context).apply {
                        text = label
                        setTextColor(Color.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(valueLabel)
            })
            addView(
                SeekBar(context).apply {
                    this.max = steps
                    progressDrawable = buildPanelSliderTrack()
                    thumb = buildPanelSliderThumb()
                    splitTrack = false
                    thumbOffset = dp(10)
                    setPadding(dp(10), dp(12), dp(10), dp(4))
                    progress = (((value - min) / span) * steps).toInt().coerceIn(0, steps)
                    setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                        override fun onProgressChanged(sb: SeekBar, p: Int, fromUser: Boolean) {
                            val real = min + (p.toFloat() / steps) * span
                            valueLabel.text = format(real)
                            if (fromUser) onChange(real)
                        }

                        override fun onStartTrackingTouch(sb: SeekBar) {
                            cancelControlsAutoHide()
                        }

                        override fun onStopTrackingTouch(sb: SeekBar) {
                            onCommit?.invoke(min + (sb.progress.toFloat() / steps) * span)
                        }
                    })
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
    }

    private fun panelToggle(
        label: String,
        value: Boolean,
        subtitle: String? = null,
        enabled: Boolean = true,
        onChange: (Boolean) -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = if (enabled) itemRippleBackground() else null
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            alpha = if (enabled) 1f else 0.45f
            setPadding(dp(16), dp(12), dp(16), dp(12))
            val textContainer = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(context).apply {
                    text = label
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                })
                if (subtitle != null) {
                    addView(TextView(context).apply {
                        text = subtitle
                        setTextColor(TEXT_DIM)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                        setPadding(0, dp(4), 0, 0)
                    })
                }
            }
            addView(textContainer, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            var state = value
            // 自绘滑动开关：44x24 圆角轨道（白描边，开 ACCENT / 关半透明）+ 16dp 白色圆点滑 END/START。
            val track = View(context).apply {
                background = GradientDrawable().apply {
                    cornerRadius = dp(12).toFloat()
                    setStroke(dp(2), Color.WHITE)
                    setColor(if (state) ACCENT else 0x44FFFFFF)
                }
            }
            val thumb = View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.WHITE)
                }
            }
            val toggleBox = FrameLayout(context).apply {
                layoutParams = LinearLayout.LayoutParams(dp(44), dp(24)).apply { marginStart = dp(16) }
                addView(
                    track,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
                addView(
                    thumb,
                    FrameLayout.LayoutParams(dp(16), dp(16)).apply {
                        gravity = (if (state) Gravity.END else Gravity.START) or Gravity.CENTER_VERTICAL
                        leftMargin = dp(4)
                        rightMargin = dp(4)
                    },
                )
                isEnabled = enabled
                setOnClickListener {
                    if (!enabled) return@setOnClickListener
                    state = !state
                    (track.background as GradientDrawable).setColor(if (state) ACCENT else 0x44FFFFFF)
                    (thumb.layoutParams as FrameLayout.LayoutParams).gravity =
                        (if (state) Gravity.END else Gravity.START) or Gravity.CENTER_VERTICAL
                    thumb.requestLayout()
                    onChange(state)
                }
            }
            addView(toggleBox)
            isClickable = enabled
            isEnabled = enabled
            setOnClickListener { toggleBox.performClick() }
        }
    }

    private fun panelSegment(
        label: String,
        options: List<String>,
        selectedIndex: Int,
        onSelect: (Int) -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            addView(TextView(context).apply {
                text = label
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPadding(0, 0, 0, dp(10))
            })
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), dp(4), dp(4), dp(4))
                background = GradientDrawable().apply {
                    cornerRadius = dp(8).toFloat()
                    setColor(0xFF3A3A3A.toInt())
                }
            }
            options.forEachIndexed { i, opt ->
                row.addView(TextView(context).apply {
                    text = opt
                    gravity = Gravity.CENTER
                    setTextColor(if (i == selectedIndex) Color.WHITE else TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    typeface = if (i == selectedIndex) {
                        android.graphics.Typeface.DEFAULT_BOLD
                    } else {
                        android.graphics.Typeface.DEFAULT
                    }
                    background = if (i == selectedIndex) {
                        GradientDrawable().apply {
                            cornerRadius = dp(7).toFloat()
                            setColor(0xFF707070.toInt())
                            setStroke(dp(1), 0x26FFFFFF)
                        }
                    } else {
                        android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
                    }
                    setPadding(dp(8), dp(8), dp(8), dp(8))
                    isClickable = true
                    setOnClickListener { onSelect(i) }
                }, LinearLayout.LayoutParams(0, dp(40), 1f))
            }
            addView(row)
        }
    }

    private fun setIconActive(btn: View, active: Boolean) {
        val color = if (active) ACCENT else Color.WHITE
        when (btn) {
            is ImageButton -> btn.setColorFilter(color)
            is TextView -> {
                btn.setTextColor(color)
                if (this::danmakuToggleButton.isInitialized && btn === danmakuToggleButton) {
                    btn.background = subtlePressBackground()
                }
            }
        }
    }

    private fun updateSystemInfo() {
        if (this::batteryLabel.isInitialized) {
            batteryLabel.text = if (batteryLevel >= 0) "$batteryLevel%" else "--%"
        }
        updateNetworkInfo()
    }

    /** 顶栏右上角网络状态：WiFi / 移动网络 / 以太网 / 无网络。 */
    private fun updateNetworkInfo() {
        if (!this::networkLabel.isInitialized) return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val caps = cm?.activeNetwork?.let { cm.getNetworkCapabilities(it) }
        val hasInternet = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        networkLabel.text = when {
            caps == null || !hasInternet -> "无网络"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "移动网络"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "以太网"
            else -> "已连接"
        }
    }

    private fun applyFullscreenOrientation() {
        requestedOrientation =
            if (autoRotateEnabled) {
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            } else {
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
    }

    private fun isTablet(): Boolean = resources.configuration.smallestScreenWidthDp >= 600

    private fun isPortrait(): Boolean =
        resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT

    /**
     * 按朝向显隐控制层的次要入口：竖屏窄屏空间有限，精简顶栏次要图标（小窗/截图/AB/弹幕设置）
     * 与底栏溢出入口（音轨/字幕/画质，竖屏改从「更多」设置进入），避免拥挤与裁剪。横屏全显。
     */
    private fun applyOrientationToControls() {
        val secondaryVis = if (isPortrait()) View.GONE else View.VISIBLE
        pipButton?.visibility = secondaryVis
        screenshotButton?.visibility = secondaryVis
        danmakuQuickButton?.visibility = secondaryVis
        if (this::abButton.isInitialized) abButton.visibility = secondaryVis
        audioEntrySpacer?.visibility = secondaryVis
        audioEntryButton?.visibility = secondaryVis
        subtitleEntrySpacer?.visibility = secondaryVis
        subtitleEntryButton?.visibility = secondaryVis
        qualityEntrySpacer?.visibility = secondaryVis
        if (this::qualityButton.isInitialized) qualityButton.visibility = secondaryVis
    }

    private fun splitSupported(): Boolean {
        if (Build.VERSION.SDK_INT < 32) return false
        // 手机（smallestWidth < 600dp）即使系统报 SPLIT_AVAILABLE 也不该分屏：屏太窄，
        // ActivityEmbedding 会把副栏盖满、把播放器挤到后台。手机上按钮退化为横竖屏切换。
        if (!isTablet()) return false
        return runCatching {
            androidx.window.embedding.SplitController.getInstance(this).splitSupportStatus ==
                androidx.window.embedding.SplitController.SplitSupportStatus.SPLIT_AVAILABLE
        }.getOrDefault(false)
    }

    private fun isCurrentlySplit(): Boolean =
        runCatching {
            androidx.window.embedding.ActivityEmbeddingController.getInstance(this)
                .isActivityEmbedded(this)
        }.getOrDefault(ParallelWindowCoordinator.isNativeSplitPlayerVisible())

    private fun syncSplitFlagFromWindow() {
        if (inPipMode) return
        val embedded = isCurrentlySplit()
        if (ParallelWindowCoordinator.isNativeSplitPlayerVisible() != embedded) {
            ParallelWindowCoordinator.setNativeSplitPlayerVisible(embedded)
            ParallelWindowCoordinator.setLastNativePlaybackSplit(this, embedded)
            Log.d("NativePlayerSplit", "syncSplitFlagFromWindow embedded=$embedded")
        }
    }

    private fun toggleOrientation() {
        val current = resources.configuration.orientation
        requestedOrientation =
            if (current == Configuration.ORIENTATION_LANDSCAPE) {
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            } else {
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
        setControlsVisible(true)
    }

    private fun refreshDisplayModeButton() {
        if (!this::displayModeButton.isInitialized) return
        displayModeButton.setImageResource(
            when {
                !splitSupported() -> R.drawable.ic_player_rotate
                isCurrentlySplit() -> R.drawable.ic_player_fullscreen
                else -> R.drawable.ic_player_split
            },
        )
    }

    private fun onDisplayModeButtonClick() {
        if (!splitSupported()) {
            toggleOrientation()
            refreshDisplayModeButton()
        } else {
            captureAndFreeze {
                toggleSplitMode()
                refreshDisplayModeButton()
                scheduleFreezeHide()
            }
        }
        scheduleControlsAutoHide()
    }

    private fun captureAndFreeze(after: () -> Unit) {
        if (!this::freezeFrameView.isInitialized) {
            after()
            return
        }
        playerSurface.captureFreezeFrame { bmp ->
            runOnUiThread {
                if (bmp != null) {
                    freezeFrameView.removeCallbacks(hideFreezeRunnable)
                    freezeFrameView.setImageBitmap(bmp)
                    freezeFrameView.visibility = View.VISIBLE
                }
                after()
            }
        }
    }

    private fun scheduleFreezeHide() {
        if (!this::freezeFrameView.isInitialized || freezeFrameView.visibility != View.VISIBLE) return
        freezeFrameView.removeCallbacks(hideFreezeRunnable)
        freezeFrameView.postDelayed(hideFreezeRunnable, 90L)
    }

    private fun hideFreezeFrame() {
        if (!this::freezeFrameView.isInitialized) return
        freezeFrameView.animate().cancel()
        freezeFrameView.animate()
            .alpha(0f)
            .setDuration(240L)
            .withEndAction {
                freezeFrameView.visibility = View.GONE
                freezeFrameView.setImageBitmap(null)
                freezeFrameView.alpha = 1f
            }
            .start()
    }

    private fun toggleSplitMode() {
        if (!splitSupported()) {
            toggleOrientation()
            return
        }
        if (isCurrentlySplit()) exitSplitMode() else enterSplitMode()
    }

    private fun enterSplitMode() {
        ParallelWindowCoordinator.setNativeSplitPlayerVisible(true)
        syncOcclusionWithSplitState()
        ActivityEmbeddingInstaller.install(this, force = true)
        requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        val itemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val route = if (itemGuid.isNotEmpty()) "/detail/item?itemGuid=$itemGuid" else "/"
        val detailIntent = DetailActivity.createSplitIntent(this, route)
        runCatching { startActivity(detailIntent) }
            .onFailure {
                ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
                syncOcclusionWithSplitState()
                showTransientHint("分屏启动失败")
                Log.w("NativePlayerSplit", "enterSplitMode startActivity failed", it)
            }
        ParallelWindowCoordinator.setLastNativePlaybackSplit(this, true)
        refreshDisplayModeButton()
    }

    private fun exitSplitMode() {
        ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
        ParallelWindowCoordinator.currentSplitDetailHost()?.let { host ->
            runCatching { host.finish() }
        }
        applyFullscreenOrientation()
        ParallelWindowCoordinator.setLastNativePlaybackSplit(this, false)
        syncOcclusionWithSplitState()
        refreshDisplayModeButton()
    }

    private fun collapseSplitForPip() {
        val host = ParallelWindowCoordinator.currentSplitDetailHost()
        if (host == null && !ParallelWindowCoordinator.isNativeSplitPlayerVisible()) return
        host?.let { runCatching { it.finish() } }
        ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
        ParallelWindowCoordinator.setLastNativePlaybackSplit(this, false)
        syncOcclusionWithSplitState()
        Log.d("NativePlayerSplit", "collapseSplitForPip finished detail pane")
    }

    private fun playNextEpisode(autoPlayAfterLoad: Boolean = true) {
        val nextGuid = nextEpisodeGuidOrNull()
        if (nextGuid != null) {
            requestEpisode(nextGuid, autoPlayAfterLoad = autoPlayAfterLoad)
        } else {
            showTransientHint("已经是最后一集了")
        }
    }

    private fun nextEpisodeGuidOrNull(): String? {
        val episodes = episodeList()
        val currentGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val currentIndex = episodes.indexOfFirst { it["itemGuid"]?.toString() == currentGuid }
        if (currentIndex == -1 || currentIndex >= episodes.size - 1) return null
        return episodes[currentIndex + 1]["itemGuid"]?.toString()?.takeIf { it.isNotEmpty() }
    }

    private fun setDanmakuEnabled(enabled: Boolean) {
        danmakuEnabled = enabled
        danmakuSettings["enabled"] = enabled
        if (this::playerSurface.isInitialized) playerSurface.setDanmakuVisible(enabled)
        if (this::danmakuToggleButton.isInitialized) setIconActive(danmakuToggleButton, enabled)
        showTransientHint(if (enabled) "弹幕已开启" else "弹幕已关闭")
    }

    private fun isServerManagedPlayback(): Boolean {
        return when (val v = loadArgsMap["serverPlaybackManaged"]) {
            is Boolean -> v
            is Number -> v.toInt() == 1
            is String -> v == "1" || v.equals("true", ignoreCase = true)
            else -> false
        }
    }

    private fun qualityResNum(q: Map<String, Any?>): Int {
        val res = q["resolution"]?.toString().orEmpty()
        return Regex("(\\d{3,4})").find(res)?.value?.toIntOrNull() ?: -1
    }

    private fun applySubtitleByGuid(guid: String) {
        if (isServerManagedPlayback()) {
            selectedSubtitleGuid = guid
            Log.d(TAG, "applySubtitleByGuid serverManaged reload guid=$guid")
            requestServerReload(selectedAudioGuid, guid, null, "正在切换字幕...")
            return
        }
        if (guid.isEmpty()) {
            selectedSubtitleGuid = ""
            Log.d(TAG, "applySubtitleByGuid off (sid=no)")
            playerSurface.setSubtitleTrack(null, null)
            return
        }
        var embeddedSid = 0
        for (track in trackList("subtitleTracks")) {
            val useExternal = subtitleShouldUseExternalFile(track)
            val sid = if (!useExternal) ++embeddedSid else -1
            if (track["guid"]?.toString() != guid) continue
            selectedSubtitleGuid = guid
            Log.d(
                TAG,
                "applySubtitleByGuid match guid=$guid useExternal=$useExternal sid=$sid " +
                    "isBitmap=${subtitleIntFlag(track, "isBitmap")} " +
                    "isExternal=${subtitleIntFlag(track, "isExternal")} " +
                    "extraFile=${subtitleIntFlag(track, "extraFile")} " +
                    "format=${track["format"]} codec=${track["codecName"]}",
            )
            if (useExternal) {
                selectExternalSubtitle(track)
            } else {
                playerSurface.setSubtitleTrack(sid, guid)
            }
            return
        }
        Log.w(TAG, "applySubtitleByGuid no track matched guid=$guid")
    }

    private fun subtitleIntFlag(track: Map<String, Any?>, key: String): Boolean {
        return when (val v = track[key]) {
            is Boolean -> v
            is Number -> v.toInt() == 1
            is String -> v == "1" || v.equals("true", ignoreCase = true)
            else -> false
        }
    }

    private fun subtitleShouldUseExternalFile(track: Map<String, Any?>): Boolean =
        nativeSubtitleUsesExternalFile(track)

    @Suppress("UNCHECKED_CAST")
    private fun localSubtitleFilePath(guid: String): String? {
        if (guid.isEmpty()) return null
        val map = loadArgsMap["localSubtitleFiles"] as? Map<String, Any?> ?: return null
        return map[guid]?.toString()?.takeIf { it.isNotEmpty() }
    }

    private fun selectExternalSubtitle(track: Map<String, Any?>) {
        val guid = track["guid"]?.toString().orEmpty()
        val localPath = localSubtitleFilePath(guid)
        if (!localPath.isNullOrEmpty()) {
            playerSurface.setExternalSubtitleFile(localPath)
            return
        }
        if (guid.isEmpty()) {
            showTransientHint("字幕加载失败")
            return
        }
        val format = track["format"]?.toString()?.takeIf { it.isNotEmpty() }
            ?: track["codecName"]?.toString().orEmpty()
        showCenterHint("正在加载字幕...")
        NativePlayerReverseBridge.dispatch(
            method = "resolveSubtitleFile",
            args = mapOf("guid" to guid, "format" to format),
            onResult = { result ->
                runOnUiThread {
                    val path = result?.toString()?.takeIf { it.isNotEmpty() }
                    if (path != null) {
                        playerSurface.setExternalSubtitleFile(path)
                    } else {
                        showTransientHint("字幕加载失败")
                    }
                }
            },
            onError = {
                runOnUiThread { showTransientHint("字幕加载失败") }
            },
        )
    }

    private fun resolveImageUrl(path: String?): String {
        val videoUrl = loadArgsMap["url"]?.toString().orEmpty()
        return nativePanelResolveImageUrl(path, videoUrl)
    }

    private fun currentArtwork(): Pair<String, String> {
        val localPoster = loadArgsMap["posterLocalPath"]?.toString()?.trim().orEmpty()
        if (localPoster.isNotEmpty()) return localPoster to ""
        val guid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val ep = episodeList().firstOrNull { it["itemGuid"]?.toString() == guid }
        val epPoster = resolveImageUrl(ep?.get("poster")?.toString())
        if (epPoster.isNotEmpty()) {
            return epPoster to ep?.get("imageAuth")?.toString().orEmpty()
        }
        val poster = resolveImageUrl(loadArgsMap["posterPath"]?.toString())
        val auth = episodeList()
            .firstNotNullOfOrNull { it["imageAuth"]?.toString()?.takeIf { s -> s.isNotEmpty() } }
            .orEmpty()
        return poster to auth
    }

    private fun artworkGlideModel(artUrl: String, artAuth: String): Any {
        return if (artAuth.isNotEmpty()) {
            com.bumptech.glide.load.model.GlideUrl(
                artUrl,
                com.bumptech.glide.load.model.LazyHeaders.Builder()
                    .addHeader("Authorization", artAuth)
                    .addHeader("Trim-MC-token", artAuth)
                    .build(),
            )
        } else {
            artUrl
        }
    }

    private fun refreshListenArtwork() {
        if (!this::listenPosterImage.isInitialized || !this::listenBackdropImage.isInitialized) return
        val (artUrl, artAuth) = currentArtwork()
        listenTitleLabel.text = mediaTitle.ifEmpty { loadArgsMap["seriesTitle"]?.toString().orEmpty() }
        listenSubtitleLabel.text = mediaSubtitle()
        if (artUrl.isEmpty()) return
        val model = artworkGlideModel(artUrl, artAuth)
        Glide.with(this).load(model).transform(CenterCrop(), RoundedCorners(dp(12))).into(listenPosterImage)
        Glide.with(this).load(model).centerCrop().into(listenBackdropImage)
    }

    private fun updateProgressMarkers() {
        val view = markerView ?: return
        if (!chaptersFetched && this::playerSurface.isInitialized && playerSurface.state.visualPlaybackReady) {
            chaptersFetched = true
            chapterPositionsMs = playerSurface.getChapters()
                .mapNotNull { (it["timeMs"] as? Number)?.toLong() }
        }
        view.invalidate()
    }

    /**
     * 可限高的 ScrollView：内容矮时按内容自适应高度，超过 [maxHeightPx] 才封顶并滚动。
     * 竖屏底部弹窗用它让面板高度随内容收缩（短面板不再留大片空白），同时设上限避免占满全屏。
     * maxHeightPx 为 [Int.MAX_VALUE] 时不限高（横屏右侧面板按权重铺满，行为同普通 ScrollView）。
     */
    private class MaxHeightScrollView(context: Context) : android.widget.ScrollView(context) {
        var maxHeightPx: Int = Int.MAX_VALUE
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val spec = if (maxHeightPx in 1 until Int.MAX_VALUE) {
                MeasureSpec.makeMeasureSpec(maxHeightPx, MeasureSpec.AT_MOST)
            } else {
                heightMeasureSpec
            }
            super.onMeasure(widthMeasureSpec, spec)
        }
    }

    private inner class ProgressMarkerView(context: Context) : View(context) {
        private val tickPaint = android.graphics.Paint().apply {
            isAntiAlias = true
            color = 0xCCFFFFFF.toInt()
        }
        private val abPaint = android.graphics.Paint().apply {
            isAntiAlias = true
            color = (0x66 shl 24) or (ACCENT and 0xFFFFFF)
        }
        private val bookmarkPaint = android.graphics.Paint().apply {
            isAntiAlias = true
            color = ACCENT
        }

        override fun onDraw(canvas: android.graphics.Canvas) {
            val dur = lastDurationMs
            if (dur <= 0) return
            val left = paddingLeft.toFloat()
            val right = (width - paddingRight).toFloat()
            val span = right - left
            if (span <= 0f) return
            val cy = height / 2f
            fun xFor(ms: Long): Float = left + span * (ms.coerceIn(0L, dur).toFloat() / dur)

            if (abRepeatMode == 2 && abLoopEndMs > abLoopStartMs) {
                canvas.drawRect(xFor(abLoopStartMs), cy - dp(3), xFor(abLoopEndMs), cy + dp(3), abPaint)
            }
            val tickHalf = dp(4).toFloat()
            val halfW = (dp(1).coerceAtLeast(1)) / 2f
            for (ms in chapterPositionsMs) {
                if (ms <= 0 || ms >= dur) continue
                val x = xFor(ms)
                canvas.drawRect(x - halfW, cy - tickHalf, x + halfW, cy + tickHalf, tickPaint)
            }
            val r = dp(3).toFloat()
            val by = cy - dp(9)
            for (bm in bookmarks) {
                canvas.drawCircle(xFor(bm.ts), by, r, bookmarkPaint)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Manifest 已去掉 screenOrientation（为分屏 resize 让路），全屏态用运行时锁横屏维持原观感。
        applyFullscreenOrientation()

        val loadArgs = parseJsonExtra(EXTRA_LOAD_ARGS) ?: simpleUrlLoadArgs()
        if (loadArgs == null || (loadArgs["url"]?.toString().isNullOrEmpty())) {
            Log.e(TAG, "missing or invalid loadArgs; finishing")
            finish()
            return
        }
        mediaTitle = resolveTitle(loadArgs)
        loadArgsMap = loadArgs
        // 弹幕优先走文件（Flutter 拉好后落临时文件，避开 Intent 的 TransactionTooLarge），
        // 其次直接 JSON extra（小量/调试）。
        val danmakuPayload =
            parseJsonExtra(EXTRA_DANMAKU_PAYLOAD) ?: parseJsonFile(EXTRA_DANMAKU_FILE)

        // creationParams = loadArgs 超集 + 原生壳标志（surface 后端 + 原生弹幕）。
        val creationParams = HashMap<String, Any?>(loadArgs).apply {
            put("videoOutputBackend", "surface")
            put("enableNativeDanmakuRenderer", true)
        }

        playerSurface = NativePlayerSurface(
            context = this,
            creationParams = creationParams,
            onStateChanged = { state -> runOnUiThread { applyState(state) } },
        )

        settingsStore = NativePlayerSettingsStore(this)
        restorePersistedSettings()
        // 选集视图模式本地优先：开播即按上次偏好（宫格/列表）渲染，不必等服务端 viewType 回包，
        // 消除「点开是列表、过一会跳成宫格」的视图跳变。读的是与 Flutter 共享的同一份本地缓存
        // （FlutterSharedPreferences 文件），三端（原生壳/Flutter 播放器/详情页）统一、不漂移。
        episodeViewMode = nativePanelEpisodeViewModeFromType(loadSharedPlaylistViewType())

        // 系统媒体集成：音频焦点 + 拔耳机暂停 + 命令路由（命令直达 playerSurface，不经 Flutter）。
        audioFocus = NativePlaybackAudioFocusController(
            context = this,
            onShouldPause = { playerSurface.pause() },
            onMayResume = { playWithFocus() },
            onDuck = {
                duckSavedVolume = playerSurface.getPlaybackVolume()
                playerSurface.setPlaybackVolume(30.0)
            },
            onRestoreFromDuck = { playerSurface.setPlaybackVolume(duckSavedVolume) },
        )
        audioFocus.registerBecomingNoisy()
        NativeMediaCommandCoordinator.attach(this)

        setContentView(buildContentView())
        enableImmersiveMode()
        // 网络监听放在视图构建之后：回调里 post 到 rootContainer，避免早于 rootContainer 初始化。
        registerNetworkMonitor()

        applyLoadArgs(loadArgs, danmakuPayload)
        scheduleControlsAutoHide()
        registerBackHandler()
        maybeAutoEnterSplit()
    }

    /**
     * 进入播放时按设置决定是否自动进分屏。仅支持分屏时生效。
     * **只看显式设置 defaultPlaybackFullscreen**：默认全屏(设置默认值)。早期还叠加了
     * 「记住上次分屏」，但它会让一次分屏后每次播放都强制分屏(用户实测困扰)，且与卡死循环
     * 纠缠，故移除——分屏始终由用户用切换按钮手动开，除非显式把默认设为分屏。
     */
    private fun maybeAutoEnterSplit() {
        if (!splitSupported()) return
        if (isCurrentlySplit()) return
        val wantSplit = !ParallelWindowCoordinator.defaultPlaybackFullscreen()
        if (wantSplit) {
            // 等布局稳定后再进分屏，避免 onCreate 期 startActivity 与 surface 初始化交叠。
            rootContainer.post { enterSplitMode() }
        }
    }

    /**
     * singleTask 复用：选集后 host 用同一 Intent 启动方式再次 startActivity，会走这里而非
     * 新建实例。重读 loadArgs + 弹幕，原地换源（不重建 Activity / surface / 控制层）。
     */
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) setIntent(intent)
        val loadArgs = parseJsonExtra(EXTRA_LOAD_ARGS) ?: simpleUrlLoadArgs()
        if (loadArgs == null || loadArgs["url"]?.toString().isNullOrEmpty()) {
            Log.w(TAG, "onNewIntent missing/invalid loadArgs; keeping current playback")
            return
        }
        // 副栏点到「正在播放的同一集」时不重载（自己播自己）。换别的集才换源。
        val newGuid = loadArgs["itemGuid"]?.toString().orEmpty()
        val currentGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        if (newGuid.isNotEmpty() && newGuid == currentGuid) {
            Log.d(TAG, "onNewIntent same item=$newGuid already playing; skip reload")
            setControlsVisible(true)
            return
        }
        val danmakuPayload =
            parseJsonExtra(EXTRA_DANMAKU_PAYLOAD) ?: parseJsonFile(EXTRA_DANMAKU_FILE)
        applyLoadArgs(loadArgs, danmakuPayload)
        setControlsVisible(true)
    }

    override fun onResume() {
        super.onResume()
        // 前台恢复（从设置页/Flutter 播放器等返回）时主动拉一次 Flutter 全局 MPV 设置，
        // 让「只在启动注入」之外的外部改动也即时生效。带 diff 守卫，无变化不重下发内核。
        pullGlobalMpvSettingsOnResume()
        // 前台期间每 3s 周期回写一次播放进度（飞牛/Emby 共用），退出时再补一次。
        startPeriodicReport()
    }

    /** 启动 3s 周期进度上报循环；幂等，重复调用不会叠加 runnable。 */
    private fun startPeriodicReport() {
        if (isPeriodicReportRunning) return
        if (!this::bottomBar.isInitialized) return
        isPeriodicReportRunning = true
        bottomBar.postDelayed(progressReportRunnable, 3000L)
    }

    /** 停止周期进度上报循环（切后台/退出）。 */
    private fun stopPeriodicReport() {
        if (!isPeriodicReportRunning) return
        isPeriodicReportRunning = false
        if (this::bottomBar.isInitialized) {
            bottomBar.removeCallbacks(progressReportRunnable)
        }
    }

    private fun pullGlobalMpvSettingsOnResume() {
        if (!this::playerSurface.isInitialized) return
        NativePlayerReverseBridge.dispatch(
            method = "loadPlayerGlobalSettings",
            args = emptyMap(),
            onResult = { res -> runOnUiThread { applyPulledMpvSettings(res) } },
            onError = {},
        )
    }

    /** 套用恢复时拉到的全局 MPV/画面设置；仅在与当前镜像有差异时下发内核 + 落盘。 */
    private fun applyPulledMpvSettings(res: Any?) {
        if (!this::playerSurface.isInitialized) return
        val map = res as? Map<*, *> ?: return
        var mpvChanged = false
        (map["mpvAdvancedSettings"] as? Map<*, *>)?.let { s ->
            for ((k, v) in s) {
                val key = k?.toString() ?: continue
                if (v != null && mpvAdvanced.containsKey(key) && mpvAdvanced[key] != v.toString()) {
                    mpvAdvanced[key] = v.toString(); mpvChanged = true
                }
            }
        }
        var vaChanged = false
        (map["videoAdjustments"] as? Map<*, *>)?.let { va ->
            for ((k, v) in va) {
                val key = k?.toString() ?: continue
                if (v is Number && videoAdjust.containsKey(key) && videoAdjust[key] != v.toDouble()) {
                    videoAdjust[key] = v.toDouble(); vaChanged = true
                }
            }
        }
        if (mpvChanged) {
            playerSurface.setMpvAdvancedSettings(mapOf("settings" to mpvAdvanced)); persistMpvAdvanced()
        }
        if (vaChanged) {
            playerSurface.setVideoAdjustments(mapOf("settings" to videoAdjust)); persistVideoAdjust()
        }
    }

    /** onCreate 与 onNewIntent 共用：装载（或换）一路 source + 弹幕，并刷新标题/上下文。 */
    private fun applyLoadArgs(loadArgs: Map<String, Any?>, danmakuPayload: Map<String, Any?>?) {
        // 捕获换源前的集身份：用于判断是否「真的切了集」（vs 同集切画质/版本/音轨字幕重载）。
        // 必须在 loadArgsMap 被覆盖前取。
        val previousItemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        reportProgress() // 切集前先把上一集进度写回（首次 onCreate 时 duration=0 自动跳过）
        mediaTitle = resolveTitle(loadArgs)
        loadArgsMap = loadArgs
        // 换源/切集后，当前选中轨道复位为新一集 loadArgs 给出的初值。
        selectedAudioGuid = loadArgs["audioTrackGuid"]?.toString().orEmpty()
        selectedSubtitleGuid = loadArgs["subtitleTrackGuid"]?.toString().orEmpty()
        pendingInitialSubtitle = true
        pendingPersistedSettings = true // 换源后首帧就绪时重套已存的 mpv/画面/字幕样式设置
        refreshRateApplied = false // 换源后按新片 fps 重新匹配刷新率
        // 换源/切集后选集预取作废：清空按季缓存、复位守卫，待新片首帧后重新预取。
        seasonEpisodesCache.clear()
        episodePickerPrefetchStarted = false
        episodePickerLoadedOnce = false // 换源：新内容需重新完整落地选集数据
        episodeViewModeUserDirty = false // 换源：新内容按服务端/本地偏好重新决定视图
        lastRecordedTs = -1L
        resetPlaybackProgressTracking() // 换源后重置「已开播」兜底，让 loading 重新从切换态开始
        flutterDanmakuSources = null // 切集后 Flutter 弹幕源列表作废，进面板时按新集重拉
        if (this::titleLabel.isInitialized) titleLabel.text = mediaTitle
        // 切画质/换源后刷新画质入口按钮文案（之前只在构建时设一次，切完不变）。
        if (this::qualityButton.isInitialized) qualityButton.text = currentQualityLabel()
        refreshEpisodeEntryButton()
        playerSurface.load(loadArgs)
        val effectiveDanmaku = danmakuPayload
            ?: if (intent?.getBooleanExtra(EXTRA_DANMAKU_TEST, false) == true) {
                buildTestDanmakuPayload()
            } else {
                null
            }
        if (effectiveDanmaku != null) {
            captureDanmakuSettings(effectiveDanmaku) // 同步镜像，供弹幕设置子页初值/后续整集发送
            applyPersistedDanmakuPrefs() // 原生持久化的显示偏好优先于 payload 自带设置
            // 单次推送（comments + 偏好合并）：二次 settings 推送会 bump generation 把弹幕丢掉。
            playerSurface.setDanmakuPayload(payloadWithPersistedDanmakuPrefs(effectiveDanmaku))
        } else if (previousItemGuid.isNotEmpty() &&
            loadArgs["itemGuid"]?.toString().orEmpty().let { it.isNotEmpty() && it != previousItemGuid }
        ) {
            // 真的切了集、但这一集没取到弹幕（自动匹配失败/该入口未回传 danmakuFile 等）：
            // 必须清掉上一集的弹幕，否则旧集弹幕会一直串台到新集（看完下一集/跳集仍是旧弹幕）。
            danmakuSettings["sourceKey"] = ""
            playerSurface.clearDanmaku()
        }
        // 换源后复位叠层/循环态/章节缓存，并按起播位置弹续播提示。
        abRepeatMode = 0
        abLoopStartMs = 0L
        abLoopEndMs = 0L
        if (this::abButton.isInitialized) {
            (abButton as? TextView)?.text = "AB"
            setIconActive(abButton, false)
        }
        weakNetDismissed = false
        weakNetSuggestedQualityIndex = null
        weakNetSuggestedQualityLabel = ""
        autoNextSuppressedItemGuid = ""
        clearNextEpisodePreload()
        chaptersFetched = false
        chapterFetchAttempt = 0
        chapterPositionsMs = emptyList()
        chapterList = emptyList()
        inferredIntroStartMs = -1
        inferredIntroEndMs = -1
        inferredOutroStartMs = -1
        loadBookmarksForCurrent() // 换集重载当前条目的书签（按 itemGuid::mediaGuid 分组）
        introSkipDismissed = false
        outroSkipDismissed = false
        clearCompletion()
        maybeShowResumePrompt(loadArgs)
        // 清掉切集时的「正在切换…」提示（换源已完成）。
        if (this::centerHint.isInitialized) hideCenterHint()
        // 纯听模式下换集刷新封面/标题。
        if (isAudioOnly && listenLayer?.visibility == View.VISIBLE) refreshListenArtwork()
        // 换集后立刻刷新媒体会话标题/封面（播停态可能不变，不能只靠 applyState 的态变门控）。
        if (this::audioFocus.isInitialized && mediaSessionStarted) {
            updateMediaSession(playerSurface.state)
        }
    }

    // ---- 沉浸式（隐藏系统栏，content 铺满，看齐 Flutter 播放器全屏观感） ----

    private fun enableImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enableImmersiveMode()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // 分屏/全屏 resize 或旋转后：把全局标志校准到真实嵌入态（供 FlutterHostActivity 决定
        // 同栈复用/新建 task），再刷新切换按钮图标语义，并重申沉浸式（系统栏隐藏）。
        syncSplitFlagFromWindow()
        refreshDisplayModeButton()
        enableImmersiveMode()
        // 分屏→全屏 bounds 变化在此落地：回全屏后恢复遮罩（分屏期间已暂挂）。
        syncOcclusionWithSplitState()
        // 旋转后按新朝向精简/恢复控制层次要入口。
        applyOrientationToControls()
        // 面板开着时旋转：按新朝向重新锚定（竖屏底部/横屏右侧），内容保留。
        if (panelVisible) showPanelContainer()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPipMode = isInPictureInPictureMode
        // 进入小窗：收掉分屏副栏(系统 API31+ 自动进小窗也走这里) + 收起控制层/面板，只留画面。
        if (isInPictureInPictureMode) {
            collapseSplitForPip()
            hidePanel()
            setControlsVisible(false)
        }
        updatePipParams()
    }

    // ---- UI 构建（代码构建 + 少量矢量 drawable，无 XML layout） ----

    private fun buildContentView(): View {
        rootContainer = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        rootContainer.addView(
            playerSurface,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 定格图覆盖层：分屏/全屏切换时盖住 SurfaceView 重排的黑闪（叠在视频之上、其余层之下）。
        freezeFrameView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
        }
        rootContainer.addView(
            freezeFrameView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 听视频（纯音频）覆盖层：模糊背景 + 居中海报 + 标题。默认隐藏，isAudioOnly 时显示。
        listenLayer = buildListenLayer()
        rootContainer.addView(
            listenLayer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 透明手势层
        val gestureView = View(this).apply { isClickable = true }
        rootContainer.addView(
            gestureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 居中加载层：手绘 12 辐条转圈 + 状态文字（缓冲/未就绪时整列居中显示）。
        val customSpinner = object : View(this) {
            private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = dp(3).toFloat()
                strokeCap = android.graphics.Paint.Cap.ROUND
                setShadowLayer(dp(3).toFloat(), 0f, 0f, PILL_BG)
            }
            private var tick = 0
            private val ticker = object : Runnable {
                override fun run() {
                    tick = (tick + 1) % 12
                    invalidate()
                    postDelayed(this, 80L)
                }
            }

            override fun onAttachedToWindow() {
                super.onAttachedToWindow()
                post(ticker)
            }

            override fun onDetachedFromWindow() {
                super.onDetachedFromWindow()
                removeCallbacks(ticker)
            }

            override fun onDraw(canvas: android.graphics.Canvas) {
                val cx = width / 2f
                val cy = height / 2f
                val rOuter = minOf(cx, cy) - dp(2)
                val rInner = rOuter - dp(5)
                for (i in 0 until 12) {
                    paint.alpha = 255 - (((12 - i) + tick) % 12) * 21
                    val angle = Math.toRadians(((i * 30) - 90).toDouble())
                    val startX = (Math.cos(angle).toFloat() * rInner) + cx
                    val startY = (Math.sin(angle).toFloat() * rInner) + cy
                    val endX = (Math.cos(angle).toFloat() * rOuter) + cx
                    val endY = (Math.sin(angle).toFloat() * rOuter) + cy
                    canvas.drawLine(startX, startY, endX, endY, paint)
                }
            }
        }
        loadingSpinner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(20), dp(24), dp(20))
            visibility = View.GONE
            addView(
                customSpinner,
                LinearLayout.LayoutParams(dp(36), dp(36)).apply { bottomMargin = dp(12) },
            )
            statusLabel = TextView(context).apply {
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setShadowLayer(dp(4).toFloat(), 0f, dp(1).toFloat(), PANEL_BG)
                text = "准备中…"
                gravity = Gravity.CENTER
            }
            addView(
                statusLabel,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        rootContainer.addView(
            loadingSpinner,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER },
        )

        // 顶部居中提示（toast 风格，下移 140dp 避开顶栏）。
        centerHint = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            background = pillBackground()
            setPadding(dp(18), dp(10), dp(18), dp(10))
            visibility = View.GONE
        }
        rootContainer.addView(
            centerHint,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(140)
            },
        )

        topBar = buildTopBar()
        rootContainer.addView(
            topBar,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.TOP },
        )

        bottomBar = buildBottomBar()
        rootContainer.addView(
            bottomBar,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )

        // 侧边锁定按钮
        lockButton = ImageButton(this).apply {
            background = subtlePressBackground()
            setImageResource(R.drawable.ic_player_lock_open)
            setColorFilter(Color.WHITE)
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setOnClickListener { toggleLock() }
        }
        rootContainer.addView(
            lockButton,
            FrameLayout.LayoutParams(dp(44), dp(44)).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                rightMargin = dp(24)
            },
        )

        // 叠层提示区（续播/连播/完成/弱网）。非 clickable 容器，空白处不挡手势。

        promptLayer = buildPromptLayer()
        rootContainer.addView(
            promptLayer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 侧边面板
        panelContainer = buildPanelContainer()
        rootContainer.addView(
            panelContainer,
            FrameLayout.LayoutParams(
                dp(280), // 固定宽度 280dp
                FrameLayout.LayoutParams.MATCH_PARENT,
            ).apply { gravity = Gravity.END },
        )

        // 系统栏 inset
        ViewCompat.setOnApplyWindowInsetsListener(rootContainer) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            // 只取稳定的刘海/挖孔 inset。导航栏 inset 在全屏↔分屏 resize 过渡里会瞬时跳变(出现又被
            // 沉浸式隐藏)，若底栏跟它走，进度条就会上下抖一下；播放器本就隐藏系统栏，故底栏改用 cutout。
            val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
            // 横屏单侧刘海会把控制层整体推向另一侧（"太偏右"）。两侧统一取最大值对称留白，
            // 控制层始终居中对称；竖屏 cutout.left/right 通常为 0，不受影响。
            val sideInset = maxOf(cutout.left, cutout.right)
            topBar.setPadding(dp(18) + sideInset, dp(12) + cutout.top, dp(18) + sideInset, dp(18))
            bottomBar.setPadding(
                dp(22) + sideInset,
                dp(14),
                dp(22) + sideInset,
                dp(18) + cutout.bottom,
            )
            // 面板补齐安全区：竖屏底部弹窗补底部，横屏右侧面板补右侧 cutout。
            if (isPortrait()) {
                panelContainer.setPadding(0, 0, 0, bars.bottom)
            } else {
                panelContainer.setPadding(0, 0, bars.right, 0)
            }
            insets
        }

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        gestureDetector = GestureDetector(this, GestureListener())
        gestureView.setOnTouchListener { _, event ->
            if (isLocked) {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    toggleControls() // 锁定状态下点击屏幕只显示/隐藏锁定按钮
                }
                return@setOnTouchListener true
            }
            if (panelVisible || swallowingPanelDismiss) {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        hidePanel()
                        swallowingPanelDismiss = true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                        swallowingPanelDismiss = false
                }
                return@setOnTouchListener true
            }
            gestureDetector.onTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
            ) {
                onGestureEnd()
            }
            true
        }
        // 首次按当前朝向精简控制层（顶栏/底栏次要入口）。
        applyOrientationToControls()
        return rootContainer
    }

    private fun buildTopBar(): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = scrimBackground(GradientDrawable.Orientation.TOP_BOTTOM, SCRIM_TOP)
            setPadding(dp(18), dp(12), dp(18), dp(18))
            isClickable = true
        }

        // --- 1. 系统信息行 (顶部) ---
        val sysInfoRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), 0, dp(2), 0)
        }

        val timeView = android.widget.TextClock(this).apply {
            format12Hour = "HH:mm"
            format24Hour = "HH:mm"
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
        }
        sysInfoRow.addView(timeView)

        val sysSpacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, 0, 1f)
        }
        sysInfoRow.addView(sysSpacer)

        networkLabel = TextView(this).apply {
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            includeFontPadding = false
            setPadding(dp(6), 0, 0, 0)
        }
        sysInfoRow.addView(networkLabel)

        batteryLabel = TextView(this).apply {
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            includeFontPadding = false
            setPadding(dp(10), 0, 0, 0)
        }
        sysInfoRow.addView(batteryLabel)
        updateSystemInfo()

        container.addView(sysInfoRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        // 间距
        container.addView(View(this), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(10)))

        // --- 2. 标题与操作栏 (底部) ---
        val mainRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val backButton = ImageButton(this).apply {
            background = subtlePressBackground()
            setImageResource(R.drawable.ic_player_arrow_back)
            setColorFilter(Color.WHITE)
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setOnClickListener { finish() }
        }
        mainRow.addView(backButton, LinearLayout.LayoutParams(dp(42), dp(42)))

        // 状态标签组
        val statusLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), 0, 0, 0)
        }

        // "已下载" 标签 (如果适用)
        if (loadArgsMap["isDownloadedFile"] == true) {
            val chip = TextView(this).apply {
                text = "已下载"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                includeFontPadding = false
                background = GradientDrawable().apply {
                    setColor(ACCENT_SOFT)
                    cornerRadius = dp(999).toFloat()
                }
                setPadding(dp(8), dp(3), dp(8), dp(3))
            }
            statusLayout.addView(chip)
            statusLayout.addView(View(this), dp(8), 1)
        }

        titleLabel = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            includeFontPadding = false

            // 构建标题：剧集名 + 季 + 集
            val sTitle = loadArgsMap["seriesTitle"]?.toString().orEmpty()
            val sNum = (loadArgsMap["seasonNumber"] as? Number)?.toInt() ?: 0
            val eNum = (loadArgsMap["episodeNumber"] as? Number)?.toInt() ?: 0
            val fullTitle = StringBuilder().apply {
                if (sTitle.isNotEmpty()) append(sTitle).append(" ")
                if (sNum > 0) append("第${sNum}季 ")
                if (eNum > 0) append("第${eNum}集")
                if (isEmpty()) append(mediaTitle)
            }.toString()
            text = fullTitle
        }
        statusLayout.addView(titleLabel, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        mainRow.addView(statusLayout, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        // 右侧功能图标区
        val iconActions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, 0, 0)
        }

        // 小窗（画中画）：仅手机显示，平板隐藏；系统不支持 PIP 也隐藏。竖屏再隐藏（见下）。
        if (pipSupported() && !isTablet()) {
            pipButton = makeIconButton("小窗") { enterPip() }.also { iconActions.addView(it) }
        }
        listenButton = makeIconButton("听视频") { toggleAudioMode() }
        iconActions.addView(listenButton)
        screenshotButton = makeIconButton("截图") { takeScreenshot() }.also { iconActions.addView(it) }
        abButton = makeIconButton("AB") { toggleAbRepeat() }
        iconActions.addView(abButton)
        // 弹幕设置：Flutter 顶栏即有的直达入口（不止在设置抽屉里）。
        danmakuQuickButton = makeIconButton("弹幕设置") {
            togglePanel(PanelPage("弹幕设置") { buildDanmakuSettingsPage() })
        }.also { iconActions.addView(it) }
        iconActions.addView(makeIconButton("更多") { showSettingsRoot() })

        mainRow.addView(iconActions)

        container.addView(mainRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        return container
    }

    private fun buildBottomBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = scrimBackground(GradientDrawable.Orientation.BOTTOM_TOP, SCRIM_BOTTOM)
            setPadding(dp(22), dp(14), dp(22), dp(18))
            isClickable = true
        }

        // 第一行：进度条 + 时间
        val progressRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        positionLabel = makeTimeLabel("00:00", Color.WHITE)
        progressRow.addView(positionLabel)

        seekBar = SeekBar(this).apply {
            max = 1000
            progressDrawable = buildSeekBarTrack()
            thumb = buildSeekBarThumb()
            splitTrack = false
            thumbOffset = dp(8)
            setPadding(dp(12), dp(14), dp(12), dp(14))
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar, progress: Int, fromUser: Boolean) {
                    if (fromUser && lastDurationMs > 0) {
                        positionLabel.text = formatTime(lastDurationMs * progress / 1000)
                    }
                }
                override fun onStartTrackingTouch(sb: SeekBar) {
                    userSeeking = true
                    cancelControlsAutoHide()
                }
                override fun onStopTrackingTouch(sb: SeekBar) {
                    userSeeking = false
                    if (lastDurationMs > 0) {
                        val targetMs = lastDurationMs * sb.progress / 1000
                        playerSurface.seek(targetMs)
                    }
                    scheduleControlsAutoHide()
                }
            })
        }
        // 进度条 + 标记叠层（章节线 / AB 区间 / 书签点）。标记层在上但不拦触摸。
        markerView = ProgressMarkerView(this).apply {
            setPadding(dp(12), 0, dp(12), 0) // 与 seekBar 水平 padding 对齐，使刻度落在轨道上
            isClickable = false
        }
        // 固定高度容器：避免 markerView 的 MATCH_PARENT 在 WRAP 容器里把高度撑满，
        // 进而把整条底栏顶到屏幕中央、控制行挤出屏外（即「播放位置不对」根因）。
        val seekWrap = FrameLayout(this).apply {
            addView(
                seekBar,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                markerView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        progressRow.addView(
            seekWrap,
            LinearLayout.LayoutParams(0, dp(44), 1f),
        )

        durationLabel = makeTimeLabel("00:00", Color.WHITE)
        progressRow.addView(durationLabel)

        // 全屏/分屏（或横竖屏）切换按钮：紧贴时长右侧。
        displayModeButton = ImageButton(this).apply {
            background = subtlePressBackground()
            setColorFilter(Color.WHITE)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(9), dp(9), dp(9), dp(9))
            setOnClickListener { onDisplayModeButtonClick() }
        }
        progressRow.addView(
            displayModeButton,
            LinearLayout.LayoutParams(dp(38), dp(38)).apply { leftMargin = dp(8) },
        )
        refreshDisplayModeButton()

        bar.addView(progressRow)

        // 第二行：控制按钮
        val controlRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(2), 0, 0)
        }

        // 播放按钮
        playPauseButton = ImageButton(this).apply {
            background = subtlePressBackground()
            setImageResource(R.drawable.ic_player_play)
            setColorFilter(ACCENT)
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setOnClickListener { togglePlayPause() }
        }
        controlRow.addView(playPauseButton, LinearLayout.LayoutParams(dp(50), dp(50)))

        // 下一集按钮
        val nextButton = ImageButton(this).apply {
            background = subtlePressBackground()
            setImageResource(R.drawable.ic_player_next)
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            setColorFilter(Color.WHITE)
            setPadding(dp(9), dp(9), dp(9), dp(9))
            setOnClickListener { playNextEpisode() }
        }
        controlRow.addView(nextButton, LinearLayout.LayoutParams(dp(42), dp(42)).apply { leftMargin = dp(8) })

        // 弹幕开关 (对应截图底栏左侧图标)
        danmakuToggleButton = TextView(this).apply {
            text = "弹幕"
            setTextColor(if (danmakuEnabled) ACCENT else Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            gravity = Gravity.CENTER
            background = subtlePressBackground()
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            setOnClickListener { setDanmakuEnabled(!danmakuEnabled) }
        }
        controlRow.addView(
            danmakuToggleButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = dp(10) },
        )

        // 占位撑开
        controlRow.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))

        // 右侧功能键：统一收进一条轻量控制条，避免一排独立胶囊抢画面。
        val actionStrip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = null
            setPadding(0, 0, 0, 0)
        }
        val episodeSpacer = controlActionSpacer()
        episodeEntryDivider = episodeSpacer
        fun addActionButton(view: TextView) {
            if (actionStrip.childCount > 0) {
                actionStrip.addView(controlActionSpacer())
            }
            actionStrip.addView(view)
        }

        addActionButton(makeEntryButton("重载") { reloadCurrentSource() })
        // 选集/多版本入口：多集→「选集」；单集(电影)有多版本→「多版本」；单集单版本→隐藏。
        episodeEntryButton = makeEntryButton("选集") { onEpisodeEntryClick() }
        actionStrip.addView(episodeSpacer)
        actionStrip.addView(episodeEntryButton)
        refreshEpisodeEntryButton()

        speedButton = makeEntryButton("1.0x") { showSpeedPicker() }
        addActionButton(speedButton)

        // 音轨/字幕/画质：横屏常驻底栏；竖屏窄屏放不下且会被裁，改为隐藏并从「更多」设置进入。
        // 显式持有按钮与其前置分隔，竖屏整段连同间距一起收起（避免遗留空白）。
        audioEntrySpacer = controlActionSpacer().also { actionStrip.addView(it) }
        audioEntryButton = makeEntryButton("音轨") { showAudioPanel() }.also { actionStrip.addView(it) }
        subtitleEntrySpacer = controlActionSpacer().also { actionStrip.addView(it) }
        subtitleEntryButton = makeEntryButton("字幕") { showSubtitlePanel() }.also { actionStrip.addView(it) }
        qualityEntrySpacer = controlActionSpacer().also { actionStrip.addView(it) }
        qualityButton = makeEntryButton(currentQualityLabel()) { showQualityPanel() }
        actionStrip.addView(qualityButton)
        controlRow.addView(actionStrip)

        bar.addView(
            controlRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(2) },
        )

        return bar
    }

    // ==== 以下为从 06-13 删除前聊天记录恢复的视图构建/控制方法 ====

    private fun toggleLock() {
        isLocked = !isLocked
        lockButton.setImageResource(
            if (isLocked) R.drawable.ic_player_lock else R.drawable.ic_player_lock_open,
        )
        showTransientHint(if (isLocked) "屏幕已锁定" else "屏幕已解锁")
        setControlsVisible(true) // 切换后显示一下，方便看到变化
    }

    private fun buildPanelContainer(): FrameLayout {
        return FrameLayout(this).apply {
            visibility = View.GONE
            background = android.graphics.drawable.ColorDrawable(0xF2141414.toInt())
            isClickable = true

            val layout = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(20), dp(20), dp(20), dp(20))
            }

            // 标题行：返回箭头（多级时显示） + 标题
            val header = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 0, 0, dp(16))
            }
            panelBackButton = ImageButton(context).apply {
                background = null
                setImageResource(R.drawable.ic_player_arrow_back)
                setColorFilter(Color.WHITE)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setPadding(0, 0, dp(10), 0)
                visibility = View.GONE
                setOnClickListener { popPanel() }
            }
            header.addView(panelBackButton, LinearLayout.LayoutParams(dp(34), dp(28)))
            // 标题改为 wrap_content + 单行省略，让出空间给紧邻的「选季」chip。
            panelTitle = TextView(context).apply {
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                isSingleLine = true
                ellipsize = android.text.TextUtils.TruncateAt.END
                maxWidth = (panelWidthPx() * 0.55f).toInt()
            }
            header.addView(
                panelTitle,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            // 标题旁的「选季」chip：低饱和强调色药丸 + 细描边 + ▾ 下拉三角，克制而明确可点；
            // 默认隐藏，仅多季时显示。
            panelSeasonSelector = TextView(context).apply {
                setTextColor(0xFFEAF1FF.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(5), dp(11), dp(5))
                background = GradientDrawable().apply {
                    cornerRadius = dp(13).toFloat()
                    setColor(0x1F3A82F7) // ~12% 强调色填充，低调
                    setStroke(dp(1), 0x593A82F7) // ~35% 强调色细描边
                }
                isClickable = true
                visibility = View.GONE
            }
            header.addView(
                panelSeasonSelector,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { leftMargin = dp(8) },
            )
            // 撑开，把右侧功能键推到边缘。
            header.addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
            panelHeaderActions = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                visibility = View.GONE
            }
            header.addView(
                panelHeaderActions,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            layout.addView(header)

            val scrollView = MaxHeightScrollView(context).apply {
                isVerticalScrollBarEnabled = false
            }
            panelScrollView = scrollView
            panelContent = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }
            scrollView.addView(panelContent)
            // 初始按横屏权重铺满；竖屏在 showPanelContainer 改为限高自适应。
            layout.addView(scrollView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

            addView(layout)
        }
    }

    private fun makeIconButton(text: String, onClick: () -> Unit): View {
        val iconRes = when (text) {
            "小窗" -> R.drawable.ic_player_pip
            "听视频" -> R.drawable.ic_player_listen_video
            "截图" -> R.drawable.ic_player_screenshot
            "弹幕设置" -> R.drawable.ic_player_danmaku_settings
            "更多" -> R.drawable.ic_player_more
            else -> 0
        }
        if (iconRes != 0) {
            return ImageButton(this).apply {
                contentDescription = text
                background = subtlePressBackground()
                setImageResource(iconRes)
                setColorFilter(Color.WHITE)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setPadding(dp(9), dp(9), dp(9), dp(9))
                isClickable = true
                layoutParams = LinearLayout.LayoutParams(dp(38), dp(38)).apply {
                    leftMargin = dp(8)
                }
                setOnClickListener { onClick() }
            }
        }
        return TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            gravity = Gravity.CENTER
            background = subtlePressBackground()
            setPadding(dp(11), dp(8), dp(11), dp(8))
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(38),
            ).apply { leftMargin = dp(8) }
            setOnClickListener { onClick() }
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** 进入画中画（小窗）。比例取视频宽高，回退 16:9。 */
    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // 进小窗前先收掉分屏：小窗是“单一播放窗”，分屏副栏不应残留(只有全屏应用才开分屏)。
        collapseSplitForPip()
        runCatching {
            // 比例须在 [1/2.39, 2.39] 内（currentPipRatio 已兜底），并带上播放控制 RemoteAction。
            enterPictureInPictureMode(buildPipParams())
        }.onFailure { showTransientHint("小窗启动失败") }
    }

    private fun toggleAudioMode() {
        val target = !isAudioOnly
        val result = playerSurface.setListenVideoMode(target)
        // controller 回 {success,enabled,message}；以 enabled 为准，失败则不改 UI 态。
        val enabled = (result["enabled"] as? Boolean) ?: target
        isAudioOnly = enabled
        if (this::listenButton.isInitialized) setIconActive(listenButton, enabled)
        updateListenLayer()
        val message = result["message"]?.toString()
        showTransientHint(
            message?.takeIf { it.isNotEmpty() }
                ?: if (enabled) "已开启听视频模式" else "已关闭听视频模式",
        )
    }

    private fun updateListenLayer() {
        val layer = listenLayer ?: return
        if (isAudioOnly) {
            refreshListenArtwork()
            layer.visibility = View.VISIBLE
        } else {
            layer.visibility = View.GONE
        }
    }

    /** 纯音频「听视频」覆盖层：高斯模糊背景图 + 暗化遮罩 + 居中圆角海报/标题/副标题。 */
    private fun buildListenLayer(): FrameLayout {
        val layer = FrameLayout(this).apply {
            visibility = View.GONE
            setBackgroundColor(-16117992) // 深底色 #FF0A0F18
        }
        listenBackdropImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            if (Build.VERSION.SDK_INT >= 31) {
                setRenderEffect(
                    android.graphics.RenderEffect.createBlurEffect(
                        48f,
                        48f,
                        android.graphics.Shader.TileMode.CLAMP,
                    ),
                )
            }
        }
        layer.addView(
            listenBackdropImage,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        // 暗化遮罩，提升前景对比度。
        layer.addView(
            View(this).apply { setBackgroundColor(-1442840576) }, // #AA000000
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(32), 0, dp(32), 0)
        }
        listenPosterImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            clipToOutline = true
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
            background = GradientDrawable().apply {
                setColor(-15064528) // 海报占位底色
                cornerRadius = dp(14).toFloat()
            }
        }
        column.addView(listenPosterImage, LinearLayout.LayoutParams(dp(230), dp(132)))
        listenTitleLabel = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        column.addView(
            listenTitleLabel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(18) },
        )
        listenSubtitleLabel = TextView(this).apply {
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            text = "正在收听"
        }
        column.addView(
            listenSubtitleLabel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(6) },
        )
        layer.addView(
            column,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER },
        )
        return layer
    }

    private fun takeScreenshot() {
        // 走 captureFrame：mpv screenshot-to-file + 按设置(含字幕/保存位置)落盘并回 path。
        val result = playerSurface.captureFrame(
            mapOf(
                "includeSubtitles" to screenshotIncludeSubtitles,
                "savePathMode" to screenshotSaveMode,
            ),
        )
        if (result["success"] == true) {
            // 截图后只提示是否保存，不再进入预览/分享页面。
            showTransientHint("已保存截图")
        } else {
            showTransientHint(
                when (result["code"]?.toString()) {
                    "custom_directory_required", "custom_directory_unavailable" -> "请先在设置里选择截图目录"
                    else -> "截图失败"
                },
            )
        }
    }

    private fun toggleAbRepeat() {
        abRepeatMode = (abRepeatMode + 1) % 3
        when (abRepeatMode) {
            1 -> {
                abLoopStartMs = playerSurface.state.positionMs
                showTransientHint("已设起点 A ${formatTime(abLoopStartMs)}")
            }
            2 -> {
                abLoopEndMs = playerSurface.state.positionMs
                if (abLoopEndMs <= abLoopStartMs) {
                    abRepeatMode = 1 // 终点无效，退回「仅设起点」
                    abLoopEndMs = 0L
                    showTransientHint("终点需晚于起点 A")
                } else {
                    showTransientHint("AB 循环 ${formatTime(abLoopStartMs)} - ${formatTime(abLoopEndMs)}")
                }
            }
            else -> {
                abLoopStartMs = 0L
                abLoopEndMs = 0L
                showTransientHint("已关闭 AB 循环")
            }
        }
        if (this::abButton.isInitialized) {
            (abButton as? TextView)?.text = when (abRepeatMode) {
                1 -> "A"
                2 -> "A-B"
                else -> "AB"
            }
            setIconActive(abButton, abRepeatMode > 0)
        }
        updateAbMarkers()
    }

    private fun updateAbMarkers() {
        markerView?.invalidate()
    }

    private fun reloadCurrentSource() {
        val url = loadArgsMap["url"]?.toString()
        if (url.isNullOrEmpty()) {
            showTransientHint("无法重载")
            return
        }
        val args = HashMap<String, Any?>(loadArgsMap).apply {
            put("startPositionMs", playerSurface.state.positionMs)
        }
        pendingInitialSubtitle = true // 重载后重新套用当前字幕，避免回退默认轨
        resetPlaybackProgressTracking() // 重载期间先回到「未开播」，等新进度推进再收 loading
        showTransientHint("重新载入中…")
        playerSurface.load(args)
        scheduleControlsAutoHide()
    }

    private fun showEpisodePanel() {
        episodePanelEpisodes = episodeList()
        episodePanelSelectedSeasonGuid = loadArgsMap["seasonGuid"]?.toString().orEmpty()
        episodePanelSeriesTitle = loadArgsMap["seriesTitle"]?.toString().orEmpty()
        val title = episodePanelTitle()
        if (panelVisible && panelStack.size == 1 && panelStack.lastOrNull()?.title == title) {
            hidePanel()
            return
        }
        currentEpisodeRangeIndex = -1 // 每次打开按当前集重算分页
        expandedEpisodeVersionGuid = null
        togglePanel(
            PanelPage(
                title = title,
                headerActions = { buildEpisodePanelHeaderActions() },
                seasonSelectorLabel = {
                    if (episodePanelSeasons.size > 1) currentSeasonLabel() else null
                },
                onSeasonSelectorClick = { anchor -> showSeasonDropdown(anchor) },
            ) { buildEpisodePanelContent() },
        )
        // 已预取则不再显示 loading（避免跳变）；仍做一次静默刷新以更新观看状态等。
        val prefetched = episodePickerPrefetchStarted &&
            (episodePanelSeasons.isNotEmpty() || seasonEpisodesCache.isNotEmpty())
        requestEpisodePickerData(
            seasonGuid = null,
            showLoading = !prefetched && episodePanelEpisodes.isEmpty(),
        )
    }

    /** 当前选中季的展示文案（无季信息时回退 loadArgs 的季号）。 */
    private fun currentSeasonLabel(): String {
        val current = episodePanelSeasons.firstOrNull {
            it["seasonGuid"]?.toString().orEmpty() == episodePanelSelectedSeasonGuid
        }
        return current?.let { nativePanelSeasonLabel(it) }
            ?: (loadArgsMap["seasonNumber"] as? Number)?.toInt()?.takeIf { it > 0 }
                ?.let { "第${it}季" }
            ?: "选季"
    }

    private fun episodePanelTitle(): String {
        val sTitle = episodePanelSeriesTitle.ifEmpty { loadArgsMap["seriesTitle"]?.toString().orEmpty() }
        if (sTitle.isEmpty()) return "选集"
        // 多季时季由标题旁的 chip 展示，标题只保留系列名，避免重复。
        if (episodePanelSeasons.size > 1) return sTitle
        val selectedSeason = episodePanelSeasons.firstOrNull {
            it["seasonGuid"]?.toString().orEmpty() == episodePanelSelectedSeasonGuid
        }
        val sLabel = selectedSeason?.let { nativePanelSeasonLabel(it) }.orEmpty()
        val sNum = (loadArgsMap["seasonNumber"] as? Number)?.toInt() ?: 0
        return when {
            sLabel.isNotEmpty() -> "$sTitle · $sLabel"
            sNum > 0 -> "$sTitle · 第${sNum}季"
            else -> sTitle
        }
    }

    /** 季 chip 文案：季名 + 文末略小、降透明度的 ▾ 下拉三角（作可点指示）。 */
    private fun seasonSelectorSpan(label: String): CharSequence {
        val full = "$label  ▾"
        return android.text.SpannableString(full).apply {
            setSpan(
                android.text.style.RelativeSizeSpan(0.82f),
                label.length,
                full.length,
                android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            setSpan(
                android.text.style.ForegroundColorSpan(0xCC9DC0FF.toInt()),
                label.length,
                full.length,
                android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
    }

    /** 入口模式：0=选集(多集)，1=多版本(单集且有>1版本)，2=隐藏(单集且≤1版本)。 */
    private fun buildEpisodePanelHeaderActions(): List<View> {
        // 选季已移到标题旁的 chip；右上角只保留宫格/列表视图切换。
        return listOf(buildEpisodeModeToggleButton())
    }

    private fun buildEpisodeModeToggleButton(): View {
        return ImageButton(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(0x33000000)
            }
            setPadding(dp(7), dp(7), dp(7), dp(7))
            setImageResource(
                if (episodeViewMode == NATIVE_EPISODE_VIEW_MODE_GRID) {
                    R.drawable.ic_player_episode_list
                } else {
                    R.drawable.ic_player_episode_grid
                },
            )
            setColorFilter(Color.WHITE)
            isClickable = true
            contentDescription = if (episodeViewMode == NATIVE_EPISODE_VIEW_MODE_GRID) "切换为列表" else "切换为宫格"
            setOnClickListener {
                val previous = episodeViewMode
                episodeViewMode = if (episodeViewMode == NATIVE_EPISODE_VIEW_MODE_GRID) {
                    NATIVE_EPISODE_VIEW_MODE_LIST
                } else {
                    NATIVE_EPISODE_VIEW_MODE_GRID
                }
                episodeViewModeUserDirty = true // 锁定用户选择，挡掉在途回包的覆盖
                currentEpisodeRangeIndex = -1
                expandedEpisodeVersionGuid = null
                renderTopPanel()
                persistEpisodeViewMode(previous, episodeViewMode)
            }
        }
    }

    /** 点击标题旁季 chip：在其正下方弹出锚定下拉窗选季（取代旧的二级面板）。 */
    private fun showSeasonDropdown(anchor: View) {
        if (episodePanelSeasons.size <= 1) return
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(0xF21E1E1E.toInt())
                setStroke(dp(1), 0x24FFFFFF)
            }
        }
        val popup = PopupWindow(
            column,
            (anchor.width.coerceAtLeast(dp(200))).coerceAtMost(panelWidthPx() - dp(24)),
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply {
            isFocusable = true // 点外部关闭
            isOutsideTouchable = true
            elevation = dp(8).toFloat()
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
        }
        for (season in episodePanelSeasons) {
            val guid = season["seasonGuid"]?.toString().orEmpty()
            val selected = guid.isNotEmpty() && guid == episodePanelSelectedSeasonGuid
            val row = TextView(this).apply {
                text = nativePanelSeasonLabel(season) + if (selected) "    ✓" else ""
                setTextColor(if (selected) ACCENT else Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                typeface = if (selected) {
                    android.graphics.Typeface.DEFAULT_BOLD
                } else {
                    android.graphics.Typeface.DEFAULT
                }
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(12), dp(16), dp(12))
                background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(if (selected) ITEM_SELECTED_BG else Color.TRANSPARENT)
                }
                isClickable = true
                setOnClickListener {
                    popup.dismiss()
                    if (guid.isNotEmpty() && guid != episodePanelSelectedSeasonGuid) {
                        switchSeason(guid)
                    }
                }
            }
            column.addView(
                row,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { if (column.childCount > 0) topMargin = dp(4) },
            )
        }
        popup.showAsDropDown(anchor, 0, dp(4))
    }

    /**
     * 就地切季：命中按季缓存则**同步**切换、零等待；未命中用轻量接口拉该季剧集（单次请求），
     * 乐观切换 + 短暂加载态，返回后落地并缓存。
     */
    private fun switchSeason(seasonGuid: String) {
        // 作废任何在途的 loadEpisodePickerData（如打开面板时的静默刷新）：它只用 token 守卫，
        // 不 bump 的话其回调会把 selectedSeasonGuid 重置回正在播放季 → 切季后"跳回去"。
        ++episodePanelLoadToken
        val cached = seasonEpisodesCache[seasonGuid]
        if (cached != null && cached.isNotEmpty()) {
            episodePanelLoading = false
            applySeasonEpisodesToPanel(seasonGuid, cached)
            return
        }
        // 未缓存：乐观切到目标季并显示加载，用轻量接口（单次 getEpisodeList）拉取。
        episodePanelLoading = true
        episodePanelSelectedSeasonGuid = seasonGuid
        episodePanelEpisodes = emptyList()
        currentEpisodeRangeIndex = -1
        expandedEpisodeVersionGuid = null
        if (panelVisible && panelStack.size == 1) {
            val page = panelStack.removeLast()
            panelStack.addLast(page.copy(title = episodePanelTitle()))
        }
        if (panelVisible) renderTopPanel()
        dispatchSeasonEpisodes(seasonGuid) { episodes ->
            if (episodes.isNotEmpty()) seasonEpisodesCache[seasonGuid] = episodes
            // 用户可能在等待期间又切了别的季：只在仍停留在本季时落地。
            if (episodePanelSelectedSeasonGuid != seasonGuid) return@dispatchSeasonEpisodes
            episodePanelLoading = false
            if (episodes.isEmpty()) {
                if (panelVisible) renderTopPanel()
                showTransientHint("无选集信息")
                return@dispatchSeasonEpisodes
            }
            applySeasonEpisodesToPanel(seasonGuid, episodes)
        }
    }

    /** 把某季剧集应用到可见面板（更新选中季、列表、标题/chip；切到播放季时回写 loadArgs）。 */
    private fun applySeasonEpisodesToPanel(
        seasonGuid: String,
        episodes: List<Map<String, Any?>>,
    ) {
        episodePanelSelectedSeasonGuid = seasonGuid
        episodePanelEpisodes = episodes
        currentEpisodeRangeIndex = -1
        expandedEpisodeVersionGuid = null
        // 仅当切到正在播放季时才回写 loadArgs 的剧集列表（保持上一集/下一集语义），
        // 与 applyEpisodePickerData 的守卫一致；浏览其它季不动播放上下文。
        if (seasonGuid == loadArgsMap["seasonGuid"]?.toString().orEmpty() && episodes.isNotEmpty()) {
            loadArgsMap = HashMap(loadArgsMap).apply { put("episodes", episodes) }
        }
        if (panelVisible && panelStack.size == 1) {
            val page = panelStack.removeLast()
            panelStack.addLast(page.copy(title = episodePanelTitle()))
        }
        if (panelVisible) renderTopPanel()
    }

    private fun nativePanelSeasonLabel(season: Map<String, Any?>): String {
        val name = season["seasonName"]?.toString()?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        val label = season["seasonLabel"]?.toString()?.trim().orEmpty()
        if (label.isNotEmpty()) return label
        val number = (season["seasonNumber"] as? Number)?.toInt() ?: 0
        return if (number > 0) "第${number}季" else "季"
    }

    private fun requestEpisodePickerData(seasonGuid: String?, showLoading: Boolean) {
        val token = ++episodePanelLoadToken
        if (showLoading) {
            episodePanelLoading = true
            if (panelVisible) renderTopPanel()
        }
        val args = mutableMapOf<String, Any?>(
            "loadArgs" to JSONObject(loadArgsMap).toString(),
        )
        if (!seasonGuid.isNullOrEmpty()) {
            args["seasonGuid"] = seasonGuid
        }
        NativePlayerReverseBridge.dispatch(
            method = "loadEpisodePickerData",
            args = args,
            onResult = { result -> runOnUiThread { applyEpisodePickerData(result, token) } },
            onError = {
                runOnUiThread {
                    if (token != episodePanelLoadToken) return@runOnUiThread
                    episodePanelLoading = false
                    if (episodePanelEpisodes.isEmpty()) showTransientHint("无选集信息")
                    if (panelVisible) renderTopPanel()
                }
            },
        )
    }

    /**
     * 起播后台预取：首帧后启动一次。
     *
     * 第一步用 `loadEpisodePickerData` 拉**当前季**完整数据（viewType + 季列表 + 当前季剧集）
     * → 点开「选集」即就绪、季 chip 可用、无跳变。返回拿到季列表后，第二步用**轻量**接口
     * `loadSeasonEpisodes`（单次 getEpisodeList）**并行**预取其它季剧集，只写缓存 → 切季近乎即时。
     *
     * 轻量接口避免了旧「全季预取」每季都重复拉 viewType/季列表的冗余，所以这次并行预取很快、
     * 不再是长耗时网络风暴。
     */
    private fun prefetchEpisodePickerData() {
        // 守卫 episodePickerPrefetchStarted 由排程处置位；这里只判内容是否需要预取。
        if (episodeList().size <= 1) return // 单集/电影无需预取
        val token = ++episodePanelLoadToken
        val args = mutableMapOf<String, Any?>(
            "loadArgs" to JSONObject(loadArgsMap).toString(),
        )
        NativePlayerReverseBridge.dispatch(
            method = "loadEpisodePickerData",
            args = args,
            onResult = { result ->
                runOnUiThread {
                    applyEpisodePickerData(result, token)
                    prefetchOtherSeasonsLight()
                }
            },
            // 预取失败静默：用户点开时仍会按需请求。
            onError = {},
        )
    }

    /** 季列表已知后，用轻量接口并行预取其它未缓存季的剧集，只写缓存。 */
    private fun prefetchOtherSeasonsLight() {
        if (episodePanelSeasons.size <= 1) return
        for (season in episodePanelSeasons) {
            val guid = season["seasonGuid"]?.toString()?.takeIf { it.isNotEmpty() } ?: continue
            if (guid in seasonEpisodesCache) continue
            dispatchSeasonEpisodes(guid) { episodes ->
                if (episodes.isNotEmpty()) seasonEpisodesCache[guid] = episodes
            }
        }
    }

    /** 轻量拉取某季剧集（单次 getEpisodeList），结果回到 UI 线程交给 [onLoaded]。 */
    private fun dispatchSeasonEpisodes(
        seasonGuid: String,
        onLoaded: (List<Map<String, Any?>>) -> Unit,
    ) {
        NativePlayerReverseBridge.dispatch(
            method = "loadSeasonEpisodes",
            args = mapOf("seasonGuid" to seasonGuid),
            onResult = { result ->
                runOnUiThread {
                    val map = result as? Map<*, *>
                    onLoaded(parseNativePanelMaps(map?.get("episodes")))
                }
            },
            onError = { runOnUiThread { onLoaded(emptyList()) } },
        )
    }

    private fun applyEpisodePickerData(result: Any?, token: Int) {
        if (token != episodePanelLoadToken) return
        val map = result as? Map<*, *>
        val data = nativePanelEpisodePickerData(
            selectedSeasonGuid = map?.get("selectedSeasonGuid")?.toString().orEmpty(),
            viewType = map?.get("viewType")?.toString(),
            seasons = parseNativePanelMaps(map?.get("seasons")),
            episodes = parseNativePanelMaps(map?.get("episodes")),
            fallbackEpisodes = episodePanelEpisodes.ifEmpty { episodeList() },
        )
        episodePanelLoading = false
        // 已完整落地过一次：本次回包仅做增量（同步当前季观看状态），不覆盖用户可能已改的
        // 选中季 / 视图 / 分页 / 展开等状态——从源头规避「在途回包改回本地状态」整类竞态。
        if (episodePickerLoadedOnce) {
            applyEpisodePickerRefresh(data)
            return
        }
        episodePickerLoadedOnce = true
        episodePanelSelectedSeasonGuid = data.selectedSeasonGuid
        episodePanelSeriesTitle = map?.get("seriesTitle")?.toString()?.takeIf { it.isNotEmpty() }
            ?: episodePanelSeriesTitle
        // 用户本次已手动切过视图：尊重本地选择，不被（可能更早发出的）回包改回。
        if (!episodeViewModeUserDirty) {
            episodeViewMode = data.viewMode
            persistEpisodeViewModeLocal(data.viewMode) // 与服务端偏好对齐，下次开播即时恢复
        }
        episodePanelSeasons = data.seasons
        episodePanelEpisodes = data.episodes
        // 顺带把当前季剧集写入按季缓存，供后续切季瞬时命中（懒加载已访问季的复用）。
        if (data.selectedSeasonGuid.isNotEmpty() && data.episodes.isNotEmpty()) {
            seasonEpisodesCache[data.selectedSeasonGuid] = data.episodes
        }
        currentEpisodeRangeIndex = -1
        expandedEpisodeVersionGuid = null
        if (data.selectedSeasonGuid == loadArgsMap["seasonGuid"]?.toString().orEmpty() && data.episodes.isNotEmpty()) {
            loadArgsMap = HashMap(loadArgsMap).apply { put("episodes", data.episodes) }
        }
        refreshEpisodeEntryButton()
        if (panelVisible && panelStack.size == 1) {
            val page = panelStack.removeLast()
            panelStack.addLast(page.copy(title = episodePanelTitle()))
        }
        if (panelVisible) renderTopPanel()
    }

    /**
     * 增量刷新：仅把回包里**当前季**的观看状态合并进现有列表，其余一概不动。
     * 回包对应"正在播放季"；若用户已切去浏览别的季（季不匹配）则不合并，仅重绘。
     */
    private fun applyEpisodePickerRefresh(data: NativeEpisodePickerData) {
        if (data.episodes.isEmpty() ||
            data.selectedSeasonGuid != episodePanelSelectedSeasonGuid
        ) {
            if (panelVisible) renderTopPanel()
            return
        }
        val watchedByGuid = HashMap<String, Any?>()
        for (ep in data.episodes) {
            val guid = ep["itemGuid"]?.toString().orEmpty()
            if (guid.isNotEmpty()) watchedByGuid[guid] = ep["watched"]
        }
        var changed = false
        val merged = episodePanelEpisodes.map { ep ->
            val guid = ep["itemGuid"]?.toString().orEmpty()
            if (watchedByGuid.containsKey(guid) && ep["watched"] != watchedByGuid[guid]) {
                changed = true
                HashMap(ep).apply { this["watched"] = watchedByGuid[guid] }
            } else {
                ep
            }
        }
        if (changed) {
            episodePanelEpisodes = merged
            seasonEpisodesCache[data.selectedSeasonGuid] = merged
            if (data.selectedSeasonGuid == loadArgsMap["seasonGuid"]?.toString().orEmpty()) {
                loadArgsMap = HashMap(loadArgsMap).apply { put("episodes", merged) }
            }
        }
        if (panelVisible) renderTopPanel()
    }

    private fun parseNativePanelMaps(raw: Any?): List<Map<String, Any?>> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            @Suppress("UNCHECKED_CAST")
            item as? Map<String, Any?>
        }
    }

    private fun persistEpisodeViewMode(previous: Int, next: Int) {
        if (previous == next) return
        persistEpisodeViewModeLocal(next) // 本地镜像即时落盘，下次开播秒级恢复
        NativePlayerReverseBridge.dispatch(
            method = "setEpisodePickerViewType",
            args = mapOf("viewType" to nativePanelPlaylistViewTypeFromEpisodeMode(next)),
        )
    }

    /**
     * 把当前视图模式写入与 Flutter 共享的本地缓存（FlutterSharedPreferences 文件，
     * 键 `flutter.playlist_view_type`），三端共用一份、不漂移；同时各路径仍写穿服务端。
     */
    private fun persistEpisodeViewModeLocal(mode: Int) {
        saveSharedPlaylistViewType(nativePanelPlaylistViewTypeFromEpisodeMode(mode))
    }

    private val flutterSharedPrefs by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    /** 读 Flutter shared_preferences 写入的播放列表视图偏好（card/button），无则 null。 */
    private fun loadSharedPlaylistViewType(): String? =
        runCatching { flutterSharedPrefs.getString(SHARED_PLAYLIST_VIEW_TYPE_KEY, null) }
            .getOrNull()

    private fun saveSharedPlaylistViewType(viewType: String) {
        runCatching {
            flutterSharedPrefs.edit().putString(SHARED_PLAYLIST_VIEW_TYPE_KEY, viewType).apply()
        }
    }

    private fun loadSharedBoolean(key: String, defaultValue: Boolean): Boolean =
        runCatching {
            if (flutterSharedPrefs.contains(key)) {
                flutterSharedPrefs.getBoolean(key, defaultValue)
            } else {
                defaultValue
            }
        }.getOrDefault(defaultValue)

    private fun saveSharedBoolean(key: String, value: Boolean) {
        runCatching { flutterSharedPrefs.edit().putBoolean(key, value).apply() }
    }

    private val screenshotDirectoryController by lazy {
        ScreenshotDirectoryAccessController(this)
    }

    /** 读 Flutter 端写入的截图保存位置（pictures/dcim/app_pictures/custom），无则默认相册。 */
    private fun loadSharedScreenshotSaveMode(): String =
        runCatching { flutterSharedPrefs.getString(SHARED_SCREENSHOT_SAVE_MODE_KEY, null) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: SCREENSHOT_DEFAULT_SAVE_MODE

    private fun loadSharedScreenshotIncludeSubtitles(): Boolean =
        runCatching {
            flutterSharedPrefs.getBoolean(SHARED_SCREENSHOT_INCLUDE_SUBTITLES_KEY, false)
        }.getOrDefault(false)

    private fun saveSharedScreenshotSaveMode(mode: String) {
        runCatching {
            flutterSharedPrefs.edit().putString(SHARED_SCREENSHOT_SAVE_MODE_KEY, mode).apply()
        }
    }

    private fun saveSharedScreenshotIncludeSubtitles(value: Boolean) {
        runCatching {
            flutterSharedPrefs.edit()
                .putBoolean(SHARED_SCREENSHOT_INCLUDE_SUBTITLES_KEY, value)
                .apply()
        }
    }

    private fun screenshotCustomDirectoryConfigured(): Boolean =
        runCatching { screenshotDirectoryController.hasConfiguredDirectory() }
            .getOrDefault(false)

    private fun episodeEntryMode(): Int {
        if (episodeList().size > 1) return 0
        return if (nativePanelEpisodeVersionEntries(qualityList()).size > 1) 1 else 2
    }

    private fun onEpisodeEntryClick() {
        when (episodeEntryMode()) {
            0 -> showEpisodePanel()
            1 -> showVersionPanel()
            else -> {}
        }
    }

    /** 按当前剧集/版本情况刷新控制栏入口按钮的文案与显隐。 */
    private fun refreshEpisodeEntryButton() {
        if (!this::episodeEntryButton.isInitialized) return
        when (episodeEntryMode()) {
            0 -> {
                episodeEntryButton.text = "选集"
                episodeEntryButton.visibility = View.VISIBLE
                episodeEntryDivider?.visibility = View.VISIBLE
            }
            1 -> {
                episodeEntryButton.text = "多版本"
                episodeEntryButton.visibility = View.VISIBLE
                episodeEntryDivider?.visibility = View.VISIBLE
            }
            else -> {
                episodeEntryButton.visibility = View.GONE
                episodeEntryDivider?.visibility = View.GONE
            }
        }
    }

    /** 单集(电影)多版本时的独立「多版本」面板。 */
    private fun showVersionPanel() {
        val versions = nativePanelEpisodeVersionEntries(qualityList())
        if (versions.size <= 1) {
            showTransientHint("无多版本")
            return
        }
        val title = "多版本"
        if (panelVisible && panelStack.size == 1 && panelStack.lastOrNull()?.title == title) {
            hidePanel()
            return
        }
        expandedEpisodeVersionGuid = null
        togglePanel(PanelPage(title) { buildVersionPanelContent(versions) })
    }

    private fun buildVersionPanelContent(entries: List<NativeEpisodeVersionEntry>) {
        val durationLabel = formatTime(currentEpisodeDurationMs())
        addPanelRow(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(4), dp(6), dp(4), 0)
                addView(buildVersionGroup(entries, durationLabel))
            },
        )
    }

    private fun currentEpisodeDurationMs(): Long {
        val currentGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val ep = episodeList().firstOrNull { it["itemGuid"]?.toString() == currentGuid }
        val seconds = (ep?.get("duration") as? Number)?.toLong()
            ?: (loadArgsMap["durationSeconds"] as? Number)?.toLong()
            ?: 0L
        return seconds * 1000
    }

    private fun buildEpisodePanelContent() {
        val episodes = episodePanelEpisodes.ifEmpty { episodeList() }
        val currentGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()

        // 切季/首拉进行中（已清空当前列表）显示加载态；用 episodePanelEpisodes 本身判空，
        // 不走 episodeList() 回退，避免切季时误显示"正在播放季"的旧列表。
        if (episodePanelLoading && episodePanelEpisodes.isEmpty()) {
            panelContent.addView(
                TextView(this).apply {
                    text = "加载中..."
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(180),
                ),
            )
            return
        }

        if (episodes.isEmpty()) {
            panelContent.addView(
                TextView(this).apply {
                    text = "无选集信息"
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(180),
                ),
            )
            return
        }

        val rangeSize = 30
        val rangeCount = (episodes.size + rangeSize - 1) / rangeSize

        if (currentEpisodeRangeIndex < 0) {
            val currentIndex = episodes.indexOfFirst { it["itemGuid"]?.toString() == currentGuid }.coerceAtLeast(0)
            currentEpisodeRangeIndex = currentIndex / rangeSize
        }

        if (rangeCount > 1) {
            val tabScroll = android.widget.HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                overScrollMode = View.OVER_SCROLL_NEVER
            }
            val tabLayout = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(16), dp(0), dp(16), dp(16))
            }

            for (i in 0 until rangeCount) {
                val start = i * rangeSize + 1
                val end = ((i + 1) * rangeSize).coerceAtMost(episodes.size)
                val tabText = "$start-$end"
                val isTabSelected = i == currentEpisodeRangeIndex

                val tabBtn = TextView(this).apply {
                    text = tabText
                    setTextColor(if (isTabSelected) ACCENT else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    background = GradientDrawable().apply {
                        setColor(if (isTabSelected) 0xFF333333.toInt() else 0xFF222222.toInt())
                        cornerRadius = dp(8).toFloat()
                    }
                    setPadding(dp(18), dp(8), dp(18), dp(8))
                    isClickable = true
                }

                val params = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    if (i > 0) leftMargin = dp(10)
                }

                tabBtn.setOnClickListener {
                    currentEpisodeRangeIndex = i
                    expandedEpisodeVersionGuid = null
                    renderTopPanel()
                }
                tabLayout.addView(tabBtn, params)
            }
            tabScroll.addView(tabLayout)
            panelContent.addView(tabScroll)
        }

        val listContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        val startIdx = currentEpisodeRangeIndex * rangeSize
        val endIdx = ((currentEpisodeRangeIndex + 1) * rangeSize).coerceAtMost(episodes.size)
        val visibleEpisodes = episodes.subList(startIdx, endIdx)
        if (episodeViewMode == NATIVE_EPISODE_VIEW_MODE_GRID) {
            panelContent.addView(buildEpisodeGridContent(visibleEpisodes, currentGuid))
            return
        }
        val versionEntries = nativePanelEpisodeVersionEntries(qualityList())

        for (episode in visibleEpisodes) {
            val guid = episode["itemGuid"]?.toString().orEmpty()
            val isSelected = guid == currentGuid
            val canExpandVersions = isSelected && versionEntries.isNotEmpty()
            val versionsExpanded = expandedEpisodeVersionGuid == guid && canExpandVersions

            val itemView = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(16), dp(8), dp(16), dp(8))
                background = if (isSelected) {
                    GradientDrawable().apply {
                        setColor(0xFF222222.toInt())
                        cornerRadius = dp(10).toFloat()
                    }
                } else {
                    null
                }
                isClickable = true
                setOnClickListener {
                    if (expandedEpisodeVersionGuid != null) {
                        expandedEpisodeVersionGuid = null
                        renderTopPanel()
                        return@setOnClickListener
                    }
                    if (guid != currentGuid) {
                        requestEpisode(guid)
                        hidePanel()
                    }
                }
            }

            val thumbnail = ImageView(this).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
                outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
                background = GradientDrawable().apply {
                    setColor(0xFF111111.toInt())
                    cornerRadius = dp(8).toFloat()
                }
            }
            val thumbWidth = dp(140)
            val thumbHeight = (thumbWidth * 9 / 16)
            itemView.addView(thumbnail, LinearLayout.LayoutParams(thumbWidth, thumbHeight))

            val posterUrl = resolveImageUrl(episode["poster"]?.toString())
            if (posterUrl.isNotEmpty()) {
                val imageAuth = episode["imageAuth"]?.toString().orEmpty()
                val model: Any = if (imageAuth.isNotEmpty()) {
                    com.bumptech.glide.load.model.GlideUrl(
                        posterUrl,
                        com.bumptech.glide.load.model.LazyHeaders.Builder()
                            .addHeader("Authorization", imageAuth)
                            .addHeader("Trim-MC-token", imageAuth)
                            .build(),
                    )
                } else {
                    posterUrl
                }
                Glide.with(this)
                    .load(model)
                    .transform(CenterCrop(), RoundedCorners(dp(8)))
                    .into(thumbnail)
            }

            val infoLayout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), 0, 0, 0)
            }

            val epTitle = TextView(this).apply {
                text = episodeLabel(episode)
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            // 标题行铺满：标题占满左侧，「多版本」按钮上移到右上角与标题同排。
            val titleRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    epTitle,
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                if (canExpandVersions) {
                    addView(
                        buildVersionToggleButton(versionsExpanded, guid),
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ).apply { leftMargin = dp(8) },
                    )
                }
            }
            infoLayout.addView(
                titleRow,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )

            val durationText = formatTime((episode["duration"] as? Number)?.toLong()?.times(1000) ?: 0L)
            infoLayout.addView(
                TextView(this).apply {
                    text = durationText
                    setTextColor(0xFFAAAAAA.toInt())
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = dp(6) },
            )

            val watched = (episode["watched"] as? Number)?.toInt() ?: 0
            val statusStr = if (isSelected) "播放中.." else if (watched == 1) "已观看" else ""
            if (statusStr.isNotEmpty()) {
                val statusText = TextView(this).apply {
                    text = statusStr
                    setTextColor(ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    gravity = Gravity.END
                }
                // 不用竖直权重：窄屏标题占两行时权重会把状态文字压成 0 高导致被裁。
                infoLayout.addView(statusText, LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = dp(6) })
            }

            // infoLayout 高度随内容自适应，行高由标题+时长+状态决定，缩略图较矮时不撑高。
            itemView.addView(infoLayout, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            listContainer.addView(itemView)
            if (versionsExpanded) {
                listContainer.addView(buildEpisodeVersionExpansion(versionEntries, durationText))
            }
            listContainer.addView(View(this), LinearLayout.LayoutParams(1, dp(4)))
        }
        panelContent.addView(listContainer)
    }

    private fun buildEpisodeGridContent(
        episodes: List<Map<String, Any?>>,
        currentGuid: String,
    ): View {
        // 列数随面板宽度自适应：手机窄面板少列(避免裁剪)、平板宽面板多列(避免一行太空)。
        // 单元格用 0 宽 + 列权重(FILL) 均分整行，无论列数估算是否精确都不会溢出裁剪。
        val gridPadding = dp(16)
        // 竖屏底部弹窗为全屏宽（扣面板内边距 20+20）；横屏取右侧面板宽。
        val sheetInnerWidth = if (isPortrait()) window.decorView.width - dp(40) else panelWidthPx()
        val available = (sheetInnerWidth - gridPadding * 2).coerceAtLeast(dp(200))
        val columns = (available / dp(64)).coerceIn(4, 8)
        val grid = android.widget.GridLayout(this).apply {
            columnCount = columns
            setPadding(gridPadding, dp(2), gridPadding, dp(16))
            // 必须铺满面板宽度，列权重才有可分配的余量(WRAP_CONTENT 会使权重列塌缩为 0 宽)。
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        for ((index, episode) in episodes.withIndex()) {
            val guid = episode["itemGuid"]?.toString().orEmpty()
            val selected = guid.isNotEmpty() && guid == currentGuid
            val watched = (episode["watched"] as? Number)?.toInt() == 1
            val tile = TextView(this).apply {
                text = episodeGridLabel(episode, index)
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                maxLines = 1
                background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(if (selected) ITEM_SELECTED_BG else 0x1AFFFFFF)
                    if (selected) setStroke(dp(1), ACCENT)
                }
            }
            // 单元格用 FrameLayout 承载：底图 tile + 右下角「已观看」小勾（播放中不叠勾）。
            val cell = FrameLayout(this).apply {
                addView(
                    tile,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
                if (watched && !selected) {
                    addView(
                        buildWatchedBadge(),
                        FrameLayout.LayoutParams(
                            dp(16),
                            dp(16),
                            Gravity.BOTTOM or Gravity.END,
                        ).apply {
                            bottomMargin = dp(5)
                            rightMargin = dp(5)
                        },
                    )
                }
                isClickable = true
                setOnClickListener {
                    if (guid.isNotEmpty() && guid != currentGuid) {
                        requestEpisode(guid)
                        hidePanel()
                    }
                }
            }
            grid.addView(
                cell,
                android.widget.GridLayout.LayoutParams().apply {
                    width = 0 // 由列权重 FILL 均分整行宽度
                    height = dp(54)
                    columnSpec = android.widget.GridLayout.spec(
                        android.widget.GridLayout.UNDEFINED,
                        android.widget.GridLayout.FILL,
                        1f,
                    )
                    setMargins(dp(4), dp(4), dp(4), dp(8))
                },
            )
        }
        return grid
    }

    /** 宫格单元格右下角的「已观看」小勾徽标。 */
    private fun buildWatchedBadge(): View {
        return TextView(this).apply {
            text = "✓"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            includeFontPadding = false
            background = GradientDrawable().apply {
                cornerRadius = dp(5).toFloat()
                setColor(ACCENT)
            }
        }
    }

    private fun episodeGridLabel(episode: Map<String, Any?>, index: Int): String {
        val shortLabel = episode["shortLabel"]?.toString()?.trim().orEmpty()
        if (shortLabel.isNotEmpty()) {
            val number = Regex("\\d+").find(shortLabel)?.value
            return number ?: shortLabel.take(3)
        }
        val number = (episode["episodeNumber"] as? Number)?.toInt() ?: 0
        return if (number > 0) number.toString() else (index + 1).toString()
    }

    /** 「多版本」切换按钮：展开/收起共用同一文案「多版本」（不再切成「收起」）。 */
    private fun buildVersionToggleButton(expanded: Boolean, guid: String): View {
        return TextView(this).apply {
            text = "多版本"
            setTextColor(ACCENT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(10), dp(4), dp(10), dp(4))
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(if (expanded) 0x243A82F7 else Color.TRANSPARENT)
                setStroke(dp(1), ACCENT)
            }
            isClickable = true
            setOnClickListener {
                expandedEpisodeVersionGuid = if (expanded) null else guid
                renderTopPanel()
            }
        }
    }

    private fun buildEpisodeVersionExpansion(
        entries: List<NativeEpisodeVersionEntry>,
        durationLabel: String,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // 铺满整行（与剧集行同样 16dp 边距），不再缩进到缩略图右侧。
            setPadding(dp(16), dp(8), dp(16), dp(14))
            addView(buildVersionGroup(entries, durationLabel))
        }
    }

    /** 版本卡：标题为源文件名（过长跑马灯滚动），副标题为 分辨率·时长·码率；点击切换该版本。 */
    private fun buildVersionGroup(
        entries: List<NativeEpisodeVersionEntry>,
        durationLabel: String,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = versionGroupBackground()
            setPadding(dp(10), dp(10), dp(10), dp(10))
            for ((index, entry) in entries.withIndex()) {
                addView(
                    buildVersionCard(entry, index, durationLabel),
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        if (index > 0) topMargin = dp(10)
                    },
                )
            }
        }
    }

    private fun buildVersionCard(
        entry: NativeEpisodeVersionEntry,
        index: Int,
        durationLabel: String,
    ): View {
        val selected = qualityMatchesCurrentPlayback(entry.quality)
        val marqueeTargets = mutableListOf<TextView>()
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = versionCardBackground(selected)
            minimumHeight = dp(72)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            isClickable = true
            setOnClickListener {
                expandedEpisodeVersionGuid = null
                if (selected) {
                    renderTopPanel()
                } else {
                    hidePanel()
                    // 切版本要按该版本 mediaGuid 重解析（原画 + 该版本字幕），不能在当前流里切转码档。
                    requestVersion(entry.mediaGuid)
                }
            }
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> marqueeTargets.forEach { it.isSelected = true }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> marqueeTargets.forEach { it.isSelected = false }
                }
                false
            }
            addView(
                versionAccentBar(selected),
                LinearLayout.LayoutParams(dp(3), dp(42)).apply {
                    rightMargin = dp(12)
                },
            )
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(context).apply {
                        text = nativePanelEpisodeVersionTitle(entry.quality, index)
                        setTextColor(Color.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                        typeface = android.graphics.Typeface.DEFAULT_BOLD
                        // 源文件名过长时跑马灯横向滚动。
                        setSingleLine(true)
                        ellipsize = android.text.TextUtils.TruncateAt.MARQUEE
                        marqueeRepeatLimit = -1
                        setHorizontallyScrolling(true)
                        isSelected = false
                        marqueeTargets += this
                    })
                    addView(TextView(context).apply {
                        text = nativePanelEpisodeVersionSummary(entry.quality, durationLabel)
                        setTextColor(if (selected) 0xFFD6E6FF.toInt() else TEXT_DIM)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                        maxLines = 1
                        ellipsize = android.text.TextUtils.TruncateAt.END
                        setPadding(0, dp(4), 0, 0)
                    })
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            if (selected) {
                addView(
                    versionSelectedBadge(),
                    LinearLayout.LayoutParams(dp(24), dp(24)).apply {
                        leftMargin = dp(12)
                    },
                )
            }
        }
    }

    private fun showSpeedPicker() {
        val speeds = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 3.0f)
        val current = playerSurface.state.speed
        val items = speeds.map { s ->
            PanelItem("${s}x", selected = abs(s.toDouble() - current) < 0.01) {
                playerSurface.setSpeed(s.toDouble())
                pushDanmakuPlaybackSpeed(s.toDouble())
                hidePanel()
            }
        }
        showUnifiedPanel("倍速", items)
    }

    private fun showUnifiedPanel(title: String, items: List<PanelItem>, headerActionLabel: String? = null, headerActionOnClick: (() -> Unit)? = null) {
        togglePanel(
            PanelPage(
                title = title,
                build = { buildItemList(items) },
                headerActions = {
                    if (headerActionLabel != null && headerActionOnClick != null) {
                        listOf(panelHeaderTextButton(headerActionLabel) { headerActionOnClick() })
                    } else {
                        emptyList()
                    }
                },
            ),
        )
    }

    private fun buildItemList(items: List<PanelItem>) {
        val views = items.map { makeListItem(it) }.toTypedArray()
        panelContent.addView(panelCardGroup(*views))
    }

    private fun makeListItem(item: PanelItem): View {
        val subtitle = item.subtitle?.trim().orEmpty()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(if (subtitle.isNotEmpty()) 66 else 56)
            setPadding(dp(18), dp(12), dp(18), dp(12))
            background = itemRippleBackground()
            isClickable = true
            setOnClickListener { item.action() }
            addView(TextView(context).apply {
                text = item.title
                setTextColor(if (item.selected) ACCENT else Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15.5f)
                typeface = if (item.selected) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            if (subtitle.isNotEmpty()) {
                addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, dp(5), 0, 0)
                })
            }
        }
    }

    private fun panelCardGroup(vararg items: View): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(0xFF242424.toInt()) // Modern card background
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(16) }
            clipToOutline = true

            items.forEachIndexed { index, child ->
                addView(child)
                if (index < items.size - 1) {
                    addView(View(context).apply {
                        background = android.graphics.drawable.ColorDrawable(0x12FFFFFF)
                        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply {
                            marginStart = dp(16); marginEnd = dp(16)
                        }
                    })
                }
            }
        }
    }

    private fun itemRippleBackground(): android.graphics.drawable.Drawable {
        return android.graphics.drawable.StateListDrawable().apply {
            val pressed = GradientDrawable().apply { setColor(0x1AFFFFFF) }
            val normal = android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
            addState(intArrayOf(android.R.attr.state_pressed), pressed)
            addState(intArrayOf(), normal)
        }
    }

    /** 面板滑块轨道：纤细 6dp 圆角，底槽半透明 + ACCENT 进度。 */
    private fun buildPanelSliderTrack(): android.graphics.drawable.LayerDrawable {
        val trackH = dp(6)
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(3).toFloat()
            setColor(0x1AFFFFFF)
        }
        val progressShape = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(3).toFloat()
            setColor(ACCENT)
        }
        val progress = android.graphics.drawable.ClipDrawable(
            progressShape,
            Gravity.START,
            android.graphics.drawable.ClipDrawable.HORIZONTAL,
        )
        val layer = android.graphics.drawable.LayerDrawable(
            arrayOf<android.graphics.drawable.Drawable>(bg, progress),
        )
        layer.setId(0, android.R.id.background)
        layer.setId(1, android.R.id.progress)
        for (i in 0 until layer.numberOfLayers) {
            layer.setLayerHeight(i, trackH)
            layer.setLayerGravity(i, Gravity.CENTER_VERTICAL)
        }
        return layer
    }

    /** 面板滑块拇指：20dp 白色实心圆。 */
    private fun buildPanelSliderThumb(): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(Color.WHITE)
        setSize(dp(20), dp(20))
    }

    private fun makeTimeLabel(text: String, color: Int): TextView {
        return TextView(this).apply {
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            minWidth = dp(44)
            gravity = Gravity.CENTER
            this.text = text
        }
    }

    /** 选集/音轨/字幕/画质 等二级入口。onClick 默认占位，已接功能的传入真实回调。 */
    private fun makeEntryButton(
        label: String,
        onClick: () -> Unit = {
            showTransientHint("「$label」即将支持")
            scheduleControlsAutoHide()
        },
    ): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            gravity = Gravity.CENTER
            background = subtlePressBackground()
            minWidth = dp(48)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(34),
            )
            setOnClickListener { onClick() }
        }
    }

    // ---- 音轨/字幕选择（纯原生：轨道在 loadArgs，切换走 NativePlayerSurface 接口） ----

    private fun selectedAudioGuidForPanel(): String {
        return selectedAudioGuid.ifEmpty { loadArgsMap["audioTrackGuid"]?.toString().orEmpty() }
    }

    private fun selectedSubtitleGuidForPanel(): String {
        return selectedSubtitleGuid
    }

    // 切集按序号继承轨道（Bug B）：把「当前正在播放的是第几条轨道」带给 Flutter，下一集取
    // 同序号，越界/找不到则回退默认。序号取自当前集 audioTracks/subtitleTracks 列表下标，与
    // Flutter 用 playbackStream 构造的候选顺序同源，故跨集对齐。

    /** 当前音轨序号（0 基）；选不到则返回 null（不继承，Flutter 回退默认）。 */
    private fun inheritAudioTrackIndex(): Int? {
        val guid = selectedAudioGuidForPanel()
        if (guid.isEmpty()) return null
        val idx = trackList("audioTracks").indexOfFirst { it["guid"]?.toString() == guid }
        return idx.takeIf { it >= 0 }
    }

    /** 当前字幕序号：关闭=-1（继承「关闭」）；设备本地字幕/找不到=null（不继承，回退默认）。 */
    private fun inheritSubtitleTrackIndex(): Int? {
        val guid = selectedSubtitleGuidForPanel()
        if (guid.isEmpty()) return -1
        if (guid.startsWith("local:")) return null
        val idx = trackList("subtitleTracks").indexOfFirst { it["guid"]?.toString() == guid }
        return if (idx >= 0) idx else null
    }

    /** 切集 resolvePlayback 入参：itemGuid + 当前音轨/字幕序号 + 当前分辨率（用于跨集继承）。 */
    private fun episodeResolveArgs(itemGuid: String): Map<String, Any?> {
        val args = HashMap<String, Any?>()
        args["itemGuid"] = itemGuid
        inheritAudioTrackIndex()?.let { args["audioTrackIndex"] = it }
        inheritSubtitleTrackIndex()?.let { args["subtitleTrackIndex"] = it }
        // 画质继承：仅转码态带上当前分辨率，下一集选同分辨率转码档（找不到回默认）。原画/直链
        // 态不带——Flutter 默认画质梯度本就偏向直链/原画，避免误把原画错配成转码档。
        if (isServerManagedPlayback()) {
            val res = loadArgsMap["resolution"]?.toString()?.trim().orEmpty()
            if (res.isNotEmpty()) args["preferredQualityResolution"] = res
        }
        return args
    }

    private fun currentAudioSummary(): String {
        return nativePanelAudioSummary(trackList("audioTracks"), selectedAudioGuidForPanel())
    }

    private fun currentSubtitleSummary(): String {
        return nativePanelSubtitleSummary(trackList("subtitleTracks"), selectedSubtitleGuidForPanel())
    }

    private fun currentQualitySummary(): String {
        return nativePanelQualitySummary(
            playbackMode = loadArgsMap["playbackMode"]?.toString(),
            currentResolution = loadArgsMap["resolution"]?.toString(),
        )
    }

    private fun currentQualityForWeakNetwork(): Map<String, Any?> {
        qualityList().firstOrNull { qualityMatchesCurrentPlayback(it) }?.let { return it }
        return mapOf(
            "mediaGuid" to loadArgsMap["mediaGuid"],
            "videoGuid" to loadArgsMap["videoGuid"],
            "resolution" to loadArgsMap["resolution"],
            "bitrate" to loadArgsMap["bitrate"],
            "directLinkQualityIndex" to loadArgsMap["directLinkQualityIndex"],
        )
    }

    private fun qualityMatchesCurrentPlayback(quality: Map<String, Any?>): Boolean {
        val qualityDirectIndex = nativePanelNullableInt(quality["directLinkQualityIndex"])
        val currentDirectIndex = nativePanelNullableInt(loadArgsMap["directLinkQualityIndex"])
        if (qualityDirectIndex != null && currentDirectIndex != null) {
            return qualityDirectIndex == currentDirectIndex
        }

        val qualityMediaGuid = quality["mediaGuid"]?.toString()?.trim().orEmpty()
        val currentMediaGuid = loadArgsMap["mediaGuid"]?.toString()?.trim().orEmpty()
        val qualityVideoGuid = quality["videoGuid"]?.toString()?.trim().orEmpty()
        val currentVideoGuid = loadArgsMap["videoGuid"]?.toString()?.trim().orEmpty()
        if (qualityMediaGuid.isNotEmpty() && currentMediaGuid.isNotEmpty() &&
            qualityVideoGuid.isNotEmpty() && currentVideoGuid.isNotEmpty()
        ) {
            return qualityMediaGuid == currentMediaGuid && qualityVideoGuid == currentVideoGuid
        }

        val qualityResolution = quality["resolution"]?.toString()?.trim().orEmpty()
        val currentResolution = loadArgsMap["resolution"]?.toString()?.trim().orEmpty()
        if (qualityResolution.isEmpty() || currentResolution.isEmpty()) return false
        val sameResolution =
            nativePanelQualityTierRank(qualityResolution) == nativePanelQualityTierRank(currentResolution)
        if (!sameResolution) return false
        val currentBitrate = nativePanelQualityBitrate(loadArgsMap)
        return currentBitrate <= 0L || nativePanelQualityBitrate(quality) == currentBitrate
    }

    private fun showPlaybackControlPanel() {
        togglePanel(PanelPage("播放控制") { buildPlaybackControlRootPage() })
    }

    private fun buildPlaybackControlRootPage() {
        addPanelRow(panelSectionHeader("常用"))
        addPanelRow(
            panelPrimaryTile(
                title = "字幕",
                subtitle = "选择内嵌或外挂字幕，也可以关闭字幕",
                trailing = currentSubtitleSummary(),
            ) {
                showSubtitlePanel()
            },
        )
        addPanelRow(
            panelPrimaryTile(
                title = "音轨",
                subtitle = "切换多语言或多声道音轨",
                trailing = currentAudioSummary(),
            ) {
                showAudioPanel()
            },
        )
        addPanelRow(
            panelPrimaryTile(
                title = "视频质量",
                subtitle = "切换原画或服务端转码清晰度",
                trailing = currentQualitySummary(),
            ) {
                pushPanel(PanelPage("视频质量") { buildQualityPanelPage() })
            },
        )
        addPanelRow(
            panelCardGroup(
                panelToggle(
                    label = "自动旋转",
                    value = autoRotateEnabled,
                    subtitle = "跟随系统方向自动切换",
                ) { enabled ->
                    autoRotateEnabled = enabled
                    persistPlaybackBehavior()
                    applyFullscreenOrientation()
                    renderTopPanel()
                },
                panelToggle(
                    label = "自动连播",
                    value = autoPlayEnabled,
                    subtitle = if (autoPlayEnabled) {
                        "当前集结束前 5 秒提示并自动进入下一集"
                    } else {
                        "关闭后播放完成停留当前集"
                    },
                ) { enabled ->
                    autoPlayEnabled = enabled
                    persistPlaybackBehavior()
                    if (!enabled) {
                        cancelAutoNext()
                        clearNextEpisodePreload()
                    }
                    renderTopPanel()
                },
                panelToggle(
                    label = "下一级预加载",
                    value = nativePanelCanPreloadNextEpisode(
                        autoPlayEnabled,
                        nextEpisodePreloadEnabled,
                    ),
                    subtitle = if (autoPlayEnabled) {
                        if (nextEpisodePreloadEnabled) "提前准备下一集，减少切集等待"
                        else "关闭后保持原本的自动连播切集方式"
                    } else {
                        "需先开启自动连播"
                    },
                    enabled = autoPlayEnabled,
                ) { enabled ->
                    nextEpisodePreloadEnabled = enabled
                    persistPlaybackBehavior()
                    if (!enabled) clearNextEpisodePreload()
                    renderTopPanel()
                },
            ),
        )
        addPanelRow(
            panelPrimaryTile(
                title = "弹幕",
                subtitle = "显示开关、透明度、字号与 AI 遮挡",
                trailing = if (danmakuEnabled) "已开启" else "已关闭",
                selected = danmakuEnabled,
            ) {
                pushPanel(PanelPage("弹幕设置") { buildDanmakuSettingsPage() })
            },
        )
        addPanelRow(panelSectionHeader("更多"))
        when (episodeEntryMode()) {
            0 -> addPanelRow(
                panelPrimaryTile(
                    title = "选集",
                    subtitle = "在当前季内切换剧集",
                    trailing = episodePanelTitle(),
                ) {
                    pushPanel(PanelPage(episodePanelTitle()) { buildEpisodePanelContent() })
                },
            )
            1 -> {
                val versions = nativePanelEpisodeVersionEntries(qualityList())
                addPanelRow(
                    panelPrimaryTile(
                        title = "多版本",
                        subtitle = "切换该视频的不同版本",
                        trailing = "${versions.size} 个版本",
                    ) {
                        pushPanel(PanelPage("多版本") { buildVersionPanelContent(versions) })
                    },
                )
            }
            // 2 -> 单集单版本：不展示该入口
        }
        addPanelRow(
            panelPrimaryTile(
                title = "高级设置",
                subtitle = "画面、字幕样式、音频、解码和信息",
            ) {
                pushPanel(PanelPage("高级设置") { buildSettingsRoot() })
            },
        )
    }

    private fun showAudioPanel() {
        val tracks = trackList("audioTracks")
        if (tracks.isEmpty()) {
            showTransientHint("无可用音轨")
            return
        }
        val current = selectedAudioGuidForPanel()
        val items = tracks.mapIndexed { i, track ->
            val guid = track["guid"]?.toString().orEmpty()
            PanelItem(
                nativePanelTrackLabel(track),
                subtitle = trackPanelSubtitle(track),
                selected = guid.isNotEmpty() && guid == current,
            ) {
                selectAudioFromPanel(i + 1, guid)
            }
        }
        // 顶部「调节」入口 → 音频延迟 / 均衡器页（对齐原版 showUnifiedPanel）。
        showUnifiedPanel("音轨", items, "调节") {
            pushPanel(PanelPage("音频调节") { buildAudioPage() })
        }
    }

    private fun selectAudioFromPanel(index: Int, guid: String) {
        selectedAudioGuid = guid
        // 轨道变了：已预取的下一集是按旧序号解析的，清掉让其按新序号重取（Bug B 序号继承）。
        clearNextEpisodePreload()
        if (isServerManagedPlayback()) {
            hidePanel()
            requestServerReload(guid, selectedSubtitleGuidForPanel(), null, "正在切换音轨...")
        } else {
            playerSurface.setAudioTrack(index, guid)
            hidePanel()
            scheduleControlsAutoHide()
        }
    }

    private fun showSubtitlePanel() {
        togglePanel(
            PanelPage(
                title = "字幕",
                build = { buildSubtitlePanelPage() },
                headerActions = {
                    listOf(
                        panelHeaderTextButton("⚙  调整") {
                            pushPanel(PanelPage("字幕调节") { buildSubtitleStylePage() })
                        },
                        panelHeaderTextButton("+  添加", filled = true) {
                            pickLocalSubtitleFile()
                        },
                    )
                },
            ),
        )
    }

    private fun buildSubtitlePanelPage() {
        addPanelRow(panelSectionHeader("字幕列表"))
        val rows = mutableListOf<View>()
        rows +=
            subtitlePanelTrackRow(
                title = "关闭",
                subtitle = "",
                selected = selectedSubtitleGuidForPanel().isEmpty(),
                removable = false,
                onClick = { selectSubtitleFromPanel("") },
            )
        for (track in trackList("subtitleTracks")) {
            val guid = track["guid"]?.toString().orEmpty()
            val selected = guid.isNotEmpty() && guid == selectedSubtitleGuidForPanel()
            rows +=
                subtitlePanelTrackRow(
                    title = nativePanelSubtitleDisplayTitle(track),
                    subtitle = nativePanelSubtitleDisplaySubtitle(track),
                    selected = selected,
                    removable = nativePanelSubtitleCanRemove(track),
                    onClick = { selectSubtitleFromPanel(guid) },
                    onRemove = if (isLocalSubtitleGuid(guid)) {
                        { removeLocalSubtitle(guid) }
                    } else {
                        null
                    },
                )
        }
        addPanelRow(panelCardGroup(*rows.toTypedArray()))
    }

    private fun panelHeaderTextButton(
        label: String,
        filled: Boolean = false,
        onClick: () -> Unit,
    ): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(if (filled) Color.WHITE else ACCENT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minHeight = dp(36)
            setPadding(dp(13), dp(8), dp(13), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(11).toFloat()
                setColor(if (filled) 0xCC2F74D8.toInt() else 0x143A82F7)
                setStroke(dp(1), if (filled) 0x333A82F7 else 0x443A82F7)
            }
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun subtitlePanelTrackRow(
        title: String,
        subtitle: String,
        selected: Boolean,
        removable: Boolean,
        onClick: () -> Unit,
        onRemove: (() -> Unit)? = null,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = itemRippleBackground()
            minimumHeight = dp(if (subtitle.isNotEmpty()) 66 else 56)
            setPadding(dp(18), dp(12), dp(16), dp(12))
            isClickable = true
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(context).apply {
                    text = title
                    setTextColor(if (selected) ACCENT else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15.5f)
                    typeface = if (selected) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                })
                if (subtitle.isNotEmpty()) {
                    addView(TextView(context).apply {
                        text = subtitle
                        setTextColor(TEXT_DIM)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                        maxLines = 1
                        ellipsize = android.text.TextUtils.TruncateAt.END
                        setPadding(0, dp(5), 0, 0)
                    })
                }
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            if (removable) {
                addView(ImageButton(context).apply {
                    setImageResource(android.R.drawable.ic_menu_delete)
                    setColorFilter(TEXT_DIM)
                    background = itemRippleBackground()
                    setPadding(dp(8), dp(8), dp(8), dp(8))
                    setOnClickListener {
                        if (onRemove != null) onRemove() else showTransientHint("字幕删除待接入")
                    }
                }, LinearLayout.LayoutParams(dp(42), dp(42)).apply {
                    leftMargin = dp(10)
                })
            }
        }
    }

    private fun selectSubtitleFromPanel(guid: String) {
        selectedSubtitleGuid = guid
        // 轨道变了：清掉按旧序号预取的下一集，使其按新选择重取（Bug B 序号继承）。
        clearNextEpisodePreload()
        // 本地外挂字幕走 mpv sub-add，与转码流无关——即便服务端托管也直接本地加载，
        // 不能丢给 requestServerReload（飞牛侧不认识 local: guid）。
        if (isServerManagedPlayback() && !isLocalSubtitleGuid(guid)) {
            hidePanel()
            requestServerReload(selectedAudioGuidForPanel(), guid, null, "正在切换字幕...")
        } else {
            applySubtitleByGuid(guid)
            hidePanel()
            scheduleControlsAutoHide()
        }
    }

    private fun isLocalSubtitleGuid(guid: String): Boolean =
        guid.trim().lowercase().startsWith("local:sub:")

    /** 外挂字幕「+添加」：SAF 选字幕文件 → 校验格式 → 拷到缓存 → 注入轨道列表并加载。 */
    private fun pickLocalSubtitleFile() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/x-subrip", "text/vtt", "text/plain", "*/*"),
            )
        }
        runCatching { startActivityForResult(intent, REQUEST_PICK_SUBTITLE) }
            .onFailure { showTransientHint("无法打开文件选择器") }
    }

    private fun importSubtitleFromUri(uri: android.net.Uri) {
        val name = queryDisplayName(uri) ?: "subtitle.srt"
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext !in SUBTITLE_IMPORT_EXTENSIONS) {
            showTransientHint("仅支持 SRT / ASS / SSA / VTT / SUB 字幕")
            return
        }
        runCatching {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        showCenterHint("导入字幕中…")
        Thread {
            val path = copyUriToCache(uri)
            runOnUiThread {
                hideCenterHint()
                if (path == null) {
                    showTransientHint("读取文件失败")
                    return@runOnUiThread
                }
                addLocalSubtitleTrack(label = name.substringBeforeLast('.', name), format = ext, path = path)
            }
        }.start()
    }

    @Suppress("UNCHECKED_CAST")
    private fun addLocalSubtitleTrack(label: String, format: String, path: String) {
        val guid = "local:sub:${System.currentTimeMillis()}"
        val track = mapOf<String, Any?>(
            "guid" to guid,
            "title" to label,
            "format" to format,
            "isExternal" to true,
        )
        val tracks = (loadArgsMap["subtitleTracks"] as? List<*>)?.toMutableList() ?: mutableListOf()
        tracks.add(track)
        val files = (loadArgsMap["localSubtitleFiles"] as? Map<String, Any?>)?.toMutableMap()
            ?: mutableMapOf()
        files[guid] = path
        loadArgsMap = HashMap(loadArgsMap).apply {
            put("subtitleTracks", tracks)
            put("localSubtitleFiles", files)
        }
        selectedSubtitleGuid = guid
        playerSurface.setExternalSubtitleFile(path)
        renderTopPanel()
        showTransientHint("字幕已加载")
    }

    @Suppress("UNCHECKED_CAST")
    private fun removeLocalSubtitle(guid: String) {
        val tracks = (loadArgsMap["subtitleTracks"] as? List<*>)
            ?.mapNotNull { it as? Map<String, Any?> }
            ?.filterNot { it["guid"]?.toString() == guid }
            ?: emptyList()
        val files = (loadArgsMap["localSubtitleFiles"] as? Map<String, Any?>)
            ?.filterKeys { it != guid }
            ?: emptyMap()
        loadArgsMap = HashMap(loadArgsMap).apply {
            put("subtitleTracks", tracks)
            put("localSubtitleFiles", files)
        }
        if (selectedSubtitleGuid == guid) {
            selectedSubtitleGuid = ""
            playerSurface.setSubtitleTrack(null, null)
        }
        renderTopPanel()
        showTransientHint("已删除字幕")
    }

    private fun showQualityPanel() {
        togglePanel(PanelPage("视频质量") { buildQualityPanelPage() })
    }

    private fun buildQualityPanelPage() {
        val visible = visibleQualityEntries()
        if (visible.isEmpty()) {
            addPanelRow(panelEmptyState("暂无可用画质"))
            return
        }
        val currentRes = loadArgsMap["resolution"]?.toString()?.trim().orEmpty()
        // 主面板按档位合并：4k 与 4K HDR 同档收成一张卡（对齐官方，4K HDR 仅在自定义里）。
        val entries = qualityMainTierEntries(visible)
        if (visible.size > entries.size) {
            addPanelRow(buildQualityCustomEntryRow())
        }
        addPanelRow(
            buildQualityGrid(
                entries,
                selectedOf = { qualityTierMatchesCurrent(it.quality, currentRes) },
                titleOf = { qualityTierCardTitle(it.quality) },
            ),
        )
    }

    /**
     * 当前播放模式下应展示的画质档（保留原始下标，切档要用 `sourceIndex`）：
     * 直链模式丢服务端转码档，其余模式丢直链档（对齐 Flutter visibleQualityOptionsForCurrentMode），
     * originalProxy 原画两种模式都保留。过滤后为空则回退全部，避免误删到空列表。
     */
    private fun visibleQualityEntries(): List<QualityPanelEntry> {
        val all = qualityList().mapIndexed { index, quality -> QualityPanelEntry(index, quality) }
        // 只保留当前版本（同 mediaGuid）这个文件的画质：其它版本（不同 mediaGuid，来自 trackData 合并）
        // 交给「多版本」选择器，别把别的版本的码率混进画质面板。空 mediaGuid 是当前流的转码档，保留。
        val currentMediaGuid = loadArgsMap["mediaGuid"]?.toString()?.trim().orEmpty()
        val currentVersion = if (currentMediaGuid.isEmpty()) {
            all
        } else {
            all.filter { entry ->
                val guid = entry.quality["mediaGuid"]?.toString()?.trim().orEmpty()
                guid.isEmpty() || guid == currentMediaGuid
            }.ifEmpty { all }
        }
        val directLinkMode = loadArgsMap["playbackMode"]?.toString() == "directLinkQuality"
        val filtered = currentVersion.filter { entry ->
            when (entry.quality["source"]?.toString()) {
                "serverSession" -> !directLinkMode
                "directLink" -> directLinkMode
                else -> true
            }
        }
        return filtered.ifEmpty { currentVersion }
    }

    /**
     * 同 tab 内按码率去重：同码率多档（原画直链 vs 转码）只留一张，去掉“两张一模一样”的卡。
     * 优先保留当前正在播的那一档（保证它在列表里且能高亮），否则按 原画>原画代理>码率 取首选。
     */
    private fun dedupQualityEntriesByBitrate(entries: List<QualityPanelEntry>): List<QualityPanelEntry> {
        val best = LinkedHashMap<Int, QualityPanelEntry>()
        for (entry in entries) {
            val key = qualityBitrateValue(entry.quality)
            val existing = best[key]
            if (existing == null) {
                best[key] = entry
                continue
            }
            val entryCurrent = qualityMatchesCurrentPlayback(entry.quality)
            val existingCurrent = qualityMatchesCurrentPlayback(existing.quality)
            val prefer = if (entryCurrent != existingCurrent) {
                entryCurrent
            } else {
                shouldPreferQualityCard(entry.quality, existing.quality)
            }
            if (prefer) best[key] = entry
        }
        return best.values.toList()
    }

    private fun buildQualityCustomEntryRow(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(18))
            addView(TextView(context).apply {
                text = "⚙  自定义"
                setTextColor(ACCENT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                setPadding(dp(12), dp(7), dp(12), dp(7))
                background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(0x143A82F7)
                    setStroke(dp(1), 0x443A82F7)
                }
                isClickable = true
                setOnClickListener {
                    customQualityTabTitle = ""
                    pushPanel(PanelPage("视频质量") { buildCustomQualityPanelPage() })
                }
            })
        }
    }

    private fun buildCustomQualityPanelPage() {
        val visible = visibleQualityEntries()
        if (visible.isEmpty()) {
            addPanelRow(panelEmptyState("暂无可用画质"))
            return
        }
        // 自定义页按归一化档位分标签（4k 与 4K HDR 仍是两个独立 tab，但同档 SDR 变体合一），按真实档位降序（4k 最前）。
        val byRes = visible.groupBy { qualityTabKey(it.quality) }
        val resTitles = byRes.keys.sortedWith(
            compareByDescending<String> { nativePanelQualityTierRank(it) }.thenBy { it },
        )
        if (resTitles.isEmpty()) {
            addPanelRow(panelEmptyState("暂无可用画质"))
            return
        }
        val currentRes = loadArgsMap["resolution"]?.toString()?.trim().orEmpty()
        val currentTierRank = nativePanelQualityTierRank(currentRes)
        // tab 身份用标题字符串本身，避免 "4k" 与 "4K HDR" 数字档相同而互相抢选。
        if (customQualityTabTitle.isEmpty() || resTitles.none { it == customQualityTabTitle }) {
            customQualityTabTitle = resTitles.firstOrNull {
                currentTierRank > 0 && nativePanelQualityTierRank(it) == currentTierRank
            } ?: resTitles.first()
        }
        val selectedTitle = customQualityTabTitle
        addPanelRow(buildQualityTabRow(resTitles, selectedTitle))
        addPanelRow(panelSpacer(42))
        // 同码率去重后按码率降序：原画(最高码率)在前，去掉重复的同码率卡。
        val selectedEntries = dedupQualityEntriesByBitrate(byRes[selectedTitle].orEmpty())
            .sortedByDescending { qualityBitrateValue(it.quality) }
        addPanelRow(
            buildQualityGrid(
                selectedEntries,
                // 精确定位当前档：同分辨率/同码率有多档（原画直链 vs 转码），只比 resolution 会多张高亮。
                selectedOf = { qualityMatchesCurrentPlayback(it.quality) },
                // 卡片标题用归一化档位键，同一档内多码率卡靠副标题（X Mbps）区分，避免 "1080p" 大小写不一致。
                titleOf = { qualityTabKey(it.quality) },
            ),
        )
    }

    private fun buildQualityTabRow(
        resTitles: List<String>,
        selectedTitle: String,
    ): View {
        val scrollView = android.widget.HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            clipToPadding = false
            setPadding(0, 0, dp(6), 0)
        }
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        for ((index, title) in resTitles.withIndex()) {
            row.addView(
                qualityTabButton(title, title == selectedTitle) {
                    customQualityTabTitle = title
                    renderTopPanel()
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    if (index < resTitles.lastIndex) rightMargin = dp(24)
                },
            )
        }
        scrollView.addView(row)
        return scrollView
    }

    private fun qualityTabButton(
        title: String,
        selected: Boolean,
        onClick: () -> Unit,
    ): TextView {
        return TextView(this).apply {
            text = title
            setTextColor(if (selected) Color.WHITE else TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = if (selected) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
            gravity = Gravity.CENTER
            minHeight = dp(50)
            minWidth = dp(116)
            setPadding(dp(22), dp(12), dp(22), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(if (selected) ACCENT else 0x22FFFFFF)
                setStroke(dp(1), if (selected) 0x663A82F7 else 0x1FFFFFFF)
            }
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    /** 主面板条目：按档位（竖直分辨率）合并，每档取原画/最高码率那一档，并按档位降序（4k 最前）。 */
    private fun qualityMainTierEntries(entries: List<QualityPanelEntry>): List<QualityPanelEntry> {
        val bestByTier = LinkedHashMap<Int, QualityPanelEntry>()
        for (entry in entries) {
            val rank = nativePanelQualityTierRank(entry.quality["resolution"]?.toString())
            val existing = bestByTier[rank]
            if (existing == null || shouldPreferQualityCard(entry.quality, existing.quality)) {
                bestByTier[rank] = entry
            }
        }
        return bestByTier.values.sortedByDescending {
            nativePanelQualityTierRank(it.quality["resolution"]?.toString())
        }
    }

    /** 主面板卡片标题：档位名（2160→"4k"），无法识别时回退到原始分辨率标签。 */
    private fun qualityTierCardTitle(quality: Map<String, Any?>): String {
        val rank = nativePanelQualityTierRank(quality["resolution"]?.toString())
        return nativePanelQualityTierLabel(rank).ifEmpty { qualityDisplayTitle(quality) }
    }

    private fun shouldPreferQualityCard(
        candidate: Map<String, Any?>,
        current: Map<String, Any?>,
    ): Boolean {
        // 原画(isDefault) > 原画代理(originalProxy) > 高码率，保证同码率去重时留下「原画」那一档。
        val candDefault = candidate["isDefault"] == true
        val curDefault = current["isDefault"] == true
        if (candDefault != curDefault) return candDefault
        val candOriginal = candidate["source"]?.toString() == "originalProxy"
        val curOriginal = current["source"]?.toString() == "originalProxy"
        if (candOriginal != curOriginal) return candOriginal
        return qualityBitrateValue(candidate) > qualityBitrateValue(current)
    }

    private fun buildQualityGrid(
        entries: List<QualityPanelEntry>,
        selectedOf: (QualityPanelEntry) -> Boolean,
        titleOf: (QualityPanelEntry) -> String,
    ): View {
        val rows = entries.chunked(2)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            for ((rowIndex, rowEntries) in rows.withIndex()) {
                val row = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                for ((index, entry) in rowEntries.withIndex()) {
                    row.addView(
                        qualityGridCard(
                            entry = entry,
                            selected = selectedOf(entry),
                            title = titleOf(entry),
                        ),
                        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                            if (index % 2 == 1) leftMargin = dp(24)
                        },
                    )
                }
                if (rowEntries.size == 1) {
                    row.addView(
                        View(context),
                        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                            leftMargin = dp(24)
                        },
                    )
                }
                addView(
                    row,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        // 行间距比列间距略大，避免上下两行卡片贴太紧；最后一行不留尾部空白。
                        if (rowIndex < rows.lastIndex) bottomMargin = dp(30)
                    },
                )
            }
        }
    }

    private fun qualityGridCard(
        entry: QualityPanelEntry,
        selected: Boolean,
        title: String,
    ): View {
        val quality = entry.quality
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = qualityCardBackground(selected)
            minimumHeight = dp(104)
            setPadding(dp(20), dp(22), dp(20), dp(22))
            addView(TextView(context).apply {
                text = title
                setTextColor(if (selected) ACCENT else Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            addView(TextView(context).apply {
                text = qualityDisplaySubtitle(quality)
                setTextColor(if (selected) 0xFF8EB7FF.toInt() else TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(0, dp(9), 0, 0)
            })
        }
        // 整卡套一层 FrameLayout：点击挂在外层，「原画」浮标 isClickable=false 不抢事件，
        // 确保每张卡（含原画 4k）都能稳定点中——修原 4k 卡点击无反应。
        return FrameLayout(this).apply {
            isClickable = true
            addView(
                content,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            if (quality["isDefault"] == true) {
                addView(
                    qualityOriginalBadge(),
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        gravity = Gravity.TOP or Gravity.END
                        topMargin = dp(8)
                        rightMargin = dp(8)
                    },
                )
            }
            setOnClickListener {
                hidePanel()
                // 点当前档只关面板（对齐官方），切换才走重载。
                if (!selected) requestQuality(entry.sourceIndex)
            }
        }
    }

    /** 画质卡背景：比通用 tile 更圆润(10dp)，选中时蓝色填充 + 2dp 强调描边。 */
    private fun qualityCardBackground(selected: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            cornerRadius = dp(16).toFloat()
            setColor(if (selected) 0x243A82F7 else 0x18FFFFFF)
            setStroke(dp(if (selected) 2 else 1), if (selected) ACCENT else 0x22FFFFFF)
        }
    }

    /** 「原画」浮标徽章：卡片右上角小圆角标签，不参与点击。 */
    private fun qualityOriginalBadge(): View {
        return TextView(this).apply {
            text = "原画"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            gravity = Gravity.CENTER
            isClickable = false
            setPadding(dp(7), dp(3), dp(7), dp(3))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(0xD9141414.toInt())
                setStroke(dp(1), 0x2AFFFFFF)
            }
        }
    }

    /** 主面板高亮：按档位（竖直分辨率）匹配当前播放分辨率，"3840x2160"/"4k" 都归到 2160 档。 */
    private fun qualityTierMatchesCurrent(quality: Map<String, Any?>, currentRes: String): Boolean {
        if (currentRes.isEmpty()) return false
        val curRank = nativePanelQualityTierRank(currentRes)
        val qRank = nativePanelQualityTierRank(quality["resolution"]?.toString())
        return curRank > 0 && curRank == qRank
    }

    /**
     * 自定义页 tab 归并键：同一档位（同竖直分辨率）合成一个标签，
     * 只有 HDR/HDR10/HDR10+/DV(杜比视界) 这类动态范围才单列；SDR/普通一律收进基础档。
     * 这样同一个 1080p SDR 文件被三处造出的 "1080"/"1080p"/"1080P SDR" 会合成一个 "1080P" 标签，
     * 避免出现三个一样的 1080 tab（对齐官方）。
     */
    private fun qualityTabKey(quality: Map<String, Any?>): String {
        val resolution = quality["resolution"]?.toString()?.trim().orEmpty()
        val tierLabel = nativePanelQualityTierLabel(nativePanelQualityTierRank(resolution))
            .ifEmpty { qualityDisplayTitle(quality) }
        val lower = resolution.lowercase()
        val dynamicRange = when {
            lower.contains("dolby") || Regex("""\bdv\b""").containsMatchIn(lower) -> "DV"
            lower.contains("hdr10+") -> "HDR10+"
            lower.contains("hdr10") -> "HDR10"
            lower.contains("hdr") -> "HDR"
            else -> ""
        }
        return if (dynamicRange.isEmpty()) tierLabel else "$tierLabel $dynamicRange"
    }

    /** 自定义页标题/标签：WxH→竖直P，文字标签（4k/4K HDR/1080P）保留原文以区分，纯数字补 P。 */
    private fun qualityDisplayTitle(quality: Map<String, Any?>): String {
        val resolution = quality["resolution"]?.toString()?.trim().orEmpty()
        if (resolution.isEmpty()) return "画质"
        val lower = resolution.lowercase()
        Regex("""(\d{2,5})\s*[x×]\s*(\d{2,5})""").find(lower)?.let { m ->
            val a = m.groupValues[1].toIntOrNull() ?: 0
            val b = m.groupValues[2].toIntOrNull() ?: 0
            if (a > 0 && b > 0) return "${minOf(a, b)}P"
        }
        if (resolution.any { it.isLetter() }) return resolution
        return "${resolution}P"
    }

    private fun qualityBitrateValue(quality: Map<String, Any?>): Int {
        return (quality["bitrate"] as? Number)?.toInt()
            ?: quality["bitrate"]?.toString()?.toIntOrNull()
            ?: 0
    }

    private fun qualityDisplaySubtitle(quality: Map<String, Any?>): String {
        // 「原画」已移到浮标徽章，副标题只保留码率。
        val bitrate = qualityBitrateValue(quality)
        if (bitrate > 0) {
            return nativePanelBitrateLabel(bitrate.toLong())
        }
        return qualityPanelSubtitle(quality)
    }

    private fun trackPanelSubtitle(track: Map<String, Any?>): String {
        val parts = listOf(
            track["codec"]?.toString()?.trim().orEmpty(),
            track["channelLayout"]?.toString()?.trim().orEmpty(),
            track["type"]?.toString()?.trim().orEmpty(),
        ).filter { it.isNotEmpty() }
        return parts.joinToString(" · ")
    }

    private fun qualityPanelSubtitle(quality: Map<String, Any?>): String {
        val parts = listOf(
            quality["bitrate"]?.toString()?.trim().orEmpty().takeIf { it.isNotEmpty() }?.let { "$it kbps" }.orEmpty(),
            quality["container"]?.toString()?.trim().orEmpty(),
            quality["codec"]?.toString()?.trim().orEmpty(),
        ).filter { it.isNotEmpty() }
        return parts.joinToString(" · ")
    }

    private fun showAudioPicker() {
        val tracks = trackList("audioTracks")
        if (tracks.isEmpty()) {
            showTransientHint("无可用音轨")
            scheduleControlsAutoHide()
            return
        }
        showTrackPicker("音轨", tracks, includeOff = false) { index, guid ->
            playerSurface.setAudioTrack(index, guid)
        }
    }

    private fun showSubtitlePicker() {
        val tracks = trackList("subtitleTracks")
        showTrackPicker("字幕", tracks, includeOff = true) { index, guid ->
            playerSurface.setSubtitleTrack(index, guid)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun trackList(key: String): List<Map<String, Any?>> {
        val raw = loadArgsMap[key] as? List<*> ?: return emptyList()
        return raw.mapNotNull { it as? Map<String, Any?> }
    }

    private fun showTrackPicker(
        title: String,
        tracks: List<Map<String, Any?>>,
        includeOff: Boolean,
        onPick: (Int?, String?) -> Unit,
    ) {
        val labels = ArrayList<String>()
        val actions = ArrayList<Pair<Int?, String?>>()
        if (includeOff) {
            labels.add("关闭")
            actions.add(null to null)
        }
        // 用列表 1-based 位置作为 mpv SID（mpv 音轨/字幕 SID 从 1 开始）。
        // track["index"] 来自 NAS API（0-based），直接传 0 会被 resolveRequestedTrackId
        // 的 takeIf { it > 0 } 过滤成 null → mpv 设置 sid="no" 关掉轨道——Bug 3 根因。
        for ((i, track) in tracks.withIndex()) {
            labels.add(trackLabel(track))
            val mpvSid = i + 1 // 1-based position ≈ mpv SID for sequential tracks
            actions.add(mpvSid to (track["guid"]?.toString()))
        }
        cancelControlsAutoHide()
        AlertDialog.Builder(this)
            .setTitle(title)
            .setItems(labels.toTypedArray()) { _, which ->
                val action = actions[which]
                onPick(action.first, action.second)
            }
            .setOnDismissListener {
                enableImmersiveMode()
                scheduleControlsAutoHide()
            }
            .show()
    }

    // ---- 选集（数据来自 loadArgs["episodes"]，切换走反向通道回 Flutter 解析） ----

    @Suppress("UNCHECKED_CAST")
    private fun episodeList(): List<Map<String, Any?>> {
        val raw = loadArgsMap["episodes"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { it as? Map<String, Any?> }
    }

    private fun showEpisodePicker() {
        val episodes = episodeList()
        if (episodes.isEmpty()) {
            showTransientHint("无选集信息")
            scheduleControlsAutoHide()
            return
        }
        val currentGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val labels = episodes.map { episodeLabel(it) }.toTypedArray()
        val checked = episodes.indexOfFirst {
            (it["itemGuid"]?.toString().orEmpty()) == currentGuid
        }
        cancelControlsAutoHide()
        AlertDialog.Builder(this)
            .setTitle("选集")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                dialog.dismiss()
                val guid = episodes[which]["itemGuid"]?.toString().orEmpty()
                if (guid.isNotEmpty() && guid != currentGuid) {
                    requestEpisode(guid)
                }
            }
            .setOnDismissListener {
                enableImmersiveMode()
                scheduleControlsAutoHide()
            }
            .show()
    }

    private fun episodeLabel(episode: Map<String, Any?>): String {
        return nativePanelEpisodeLabel(episode)
    }

    /**
     * 选集：把意图投递回 Flutter，**只解析**新一集并回传 loadArgs(+弹幕文件)，在本壳同一
     * mpv 实例上 `applyLoadArgs` 原地换源。不走 startActivity——singleTask 跨 task 重启会
     * 重建 Activity（onDestroy+releaseMpv+重建 mpv），连续切集时 mpv/surface 交叠会闪退。
     */
    private fun requestEpisode(itemGuid: String, autoPlayAfterLoad: Boolean = true) {
        expandedEpisodeVersionGuid = null
        episodeSwitchInFlight = true
        clearCompletion()
        if (itemGuid == nextEpisodePreloadGuid && nextEpisodePreloadResult != null) {
            val result = nextEpisodePreloadResult
            clearNextEpisodePreload()
            applyEpisodeResult(result, autoPlayAfterLoad = autoPlayAfterLoad)
            setControlsVisible(true)
            return
        }
        showNetworkLoadingHint("正在切换…")
        cancelControlsAutoHide()
        NativePlayerReverseBridge.dispatch(
            method = "resolvePlayback",
            args = episodeResolveArgs(itemGuid),
            onResult = { result ->
                runOnUiThread {
                    applyEpisodeResult(result, autoPlayAfterLoad = autoPlayAfterLoad)
                }
            },
            onError = {
                runOnUiThread {
                    episodeSwitchInFlight = false
                    showTransientHint("切换失败，请返回重试")
                    scheduleControlsAutoHide()
                }
            },
        )
    }

    /**
     * 切版本：按版本 mediaGuid 走 resolvePlayback 重新解析该版本媒体（原画 + 该版本字幕/音轨），
     * 保留当前播放位置。不能走 reloadServerSession——那条只在当前流的 qualities 里按转码档切，
     * 切到别版本会播转码且沿用旧版本字幕。
     */
    private fun requestVersion(mediaGuid: String, hint: String = "正在切换版本…") {
        val itemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        if (itemGuid.isEmpty() || mediaGuid.isEmpty()) {
            showTransientHint("无法切换版本")
            scheduleControlsAutoHide()
            return
        }
        expandedEpisodeVersionGuid = null
        showNetworkLoadingHint(hint)
        cancelControlsAutoHide()
        NativePlayerReverseBridge.dispatch(
            method = "resolvePlayback",
            args = mapOf(
                "itemGuid" to itemGuid,
                "qualityMediaGuid" to mediaGuid,
                "startPositionMs" to playerSurface.state.positionMs,
            ),
            onResult = { result -> runOnUiThread { applyEpisodeResult(result) } },
            onError = {
                runOnUiThread {
                    episodeSwitchInFlight = false
                    showTransientHint("切换失败，请返回重试")
                    scheduleControlsAutoHide()
                }
            },
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyEpisodeResult(result: Any?, autoPlayAfterLoad: Boolean = false) {
        val map = result as? Map<String, Any?>
        val loadArgs = (map?.get("loadArgs") as? String)
            ?.let { runCatching { jsonObjectToMap(JSONObject(it)) }.getOrNull() }
        if (loadArgs == null || loadArgs["url"]?.toString().isNullOrEmpty()) {
            episodeSwitchInFlight = false
            showTransientHint("切换失败，请返回重试")
            scheduleControlsAutoHide()
            return
        }
        val danmakuPayload = (map["danmakuFile"] as? String)
            ?.takeIf { it.isNotEmpty() }
            ?.let {
                runCatching {
                    jsonObjectToMap(JSONObject(java.io.File(it).readText()))
                }.getOrNull()
            }
        val effectiveLoadArgs = nativePanelLoadArgsForEpisodeSwitch(loadArgs, autoPlayAfterLoad)
        applyLoadArgs(effectiveLoadArgs, danmakuPayload)
        if (autoPlayAfterLoad) playWithFocus()
        setControlsVisible(true)
    }

    // ---- 画质（数据来自 loadArgs["qualities"]，切换走反向通道重解析当前集指定档） ----

    @Suppress("UNCHECKED_CAST")
    private fun qualityList(): List<Map<String, Any?>> {
        val raw = loadArgsMap["qualities"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { it as? Map<String, Any?> }
    }

    private fun showQualityPicker() {
        val qualities = qualityList()
        if (qualities.isEmpty()) {
            showTransientHint("无可用画质")
            scheduleControlsAutoHide()
            return
        }
        val currentRes = loadArgsMap["resolution"]?.toString()?.trim().orEmpty()
        val labels = qualities.map { qualityLabel(it) }.toTypedArray()
        val checked = qualities.indexOfFirst {
            currentRes.isNotEmpty() &&
                (it["resolution"]?.toString()?.trim().orEmpty()) == currentRes
        }
        cancelControlsAutoHide()
        AlertDialog.Builder(this)
            .setTitle("画质")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                dialog.dismiss()
                requestQuality(which)
            }
            .setOnDismissListener {
                enableImmersiveMode()
                scheduleControlsAutoHide()
            }
            .show()
    }

    /** 当前画质入口按钮文案：原画态显示「原画」，否则「<分辨率>P」。 */
    private fun currentQualityLabel(): String {
        if (loadArgsMap["playbackMode"]?.toString() == "originalQuality") return "原画"
        val resNum = qualityResNum(mapOf("resolution" to loadArgsMap["resolution"]))
        return if (resNum > 0) "${resNum}P" else "原画"
    }

    private fun qualityLabel(quality: Map<String, Any?>): String {
        val resolution = quality["resolution"]?.toString()?.trim().orEmpty()
        val isDefault = quality["isDefault"] == true
        val base = resolution.ifEmpty { "画质" }
        return if (isDefault) "$base  (默认)" else base
    }

    /** 切画质：重解析当前集的指定档，带当前播放位置保持进度，原地换源。 */
    private fun requestQuality(qualityIndex: Int, hint: String = "正在切换画质…") {
        val itemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        if (itemGuid.isEmpty()) {
            showTransientHint("无法切换画质")
            scheduleControlsAutoHide()
            return
        }
        Log.d(
            "FlyPlayerMpv",
            "TRKDBG requestQuality idx=$qualityIndex mode=${loadArgsMap["playbackMode"]} " +
                "serverManaged=${isServerManagedPlayback()} curRes=${loadArgsMap["resolution"]} " +
                "audioGuid=$selectedAudioGuid subGuid=$selectedSubtitleGuid",
        )
        // 一律走会话重载：reloadServerPlaySession 按 qualityIndex 取所选档（精确）、产出正确
        // 分辨率、清空陈旧 audioTrackIndex（转码流不再误设 aid 导致没声音），并保留当前音轨/字幕。
        // 旧的 resolvePlayback(_resolve 从头解析) 会按 mediaGuid 匹配到第一档(1080p) + 塞旧
        // audioTrackIndex → 选错档 + 没声音，已弃用。
        requestServerReload(
            selectedAudioGuid,
            selectedSubtitleGuid,
            qualityIndex,
            hint,
        )
    }

    /**
     * 服务端转码下切音轨/字幕：mpv 端切不动服务端切好的内嵌轨（会弹 mpv rejected），
     * 走反向通道让 Flutter 按所选音轨+字幕重新解析当前集（保持画质与进度），回传新
     * loadArgs 后原地换源。对齐 Flutter `_reloadServerPlaySession`。
     *
     * 关键：每次都把「当前音轨 + 当前字幕」两条都带上——只重载一条时另一条会回退到服务端
     * 默认轨（_resolve 用 playInfo.audioGuid/subtitleGuid），导致切音轨把字幕弄丢、反之亦然。
     * subtitleGuid 空串 = 关闭字幕；audioGuid 不会为空（音轨无"关闭"）。
     */
    private fun requestServerReload(
        audioGuid: String,
        subtitleGuid: String,
        qualityIndex: Int?,
        hint: String,
    ) {
        // 回传当前完整 loadArgs（含 mediaGuid/videoGuid/分辨率/qualities/轨道等），Flutter 据此
        // 重建快照走 reloadServerPlaySession：保留未指定项（切音轨不动画质、切画质保留音轨/字幕）。
        val loadArgsJson = runCatching { JSONObject(loadArgsMap).toString() }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
        if (loadArgsJson == null) {
            showTransientHint("无法切换")
            scheduleControlsAutoHide()
            return
        }
        showNetworkLoadingHint(hint)
        cancelControlsAutoHide()
        val args = HashMap<String, Any?>()
        args["loadArgs"] = loadArgsJson
        args["audioGuid"] = audioGuid
        // 带 subtitleGuid（含空串）即为字幕 override；空串=关闭。
        args["subtitleGuid"] = subtitleGuid
        args["startPositionMs"] = playerSurface.state.positionMs
        if (qualityIndex != null) args["qualityIndex"] = qualityIndex
        NativePlayerReverseBridge.dispatch(
            method = "reloadServerSession",
            args = args,
            onResult = { result -> runOnUiThread { applyEpisodeResult(result) } },
            onError = {
                runOnUiThread {
                    showTransientHint("切换失败，请返回重试")
                    scheduleControlsAutoHide()
                }
            },
        )
    }

    private fun trackLabel(track: Map<String, Any?>): String {
        val title = track["title"]?.toString()?.trim().orEmpty()
        val language = nativePanelLanguageName(track["language"]?.toString().orEmpty())
            .takeUnless { it == "未知" }
            .orEmpty()
        return when {
            title.isNotEmpty() && language.isNotEmpty() -> "$title  ·  $language"
            title.isNotEmpty() -> title
            language.isNotEmpty() -> language
            else -> "轨道 ${track["index"] ?: "?"}"
        }
    }

    // ---- 叠层提示（续播 / 自动连播 / 播放完成 / 弱网，对齐 Flutter overlay） ----

    private fun promptButton(label: String, color: Int, glass: Boolean, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            if (glass) {
                background = glassBackground()
                setPadding(dp(18), dp(9), dp(18), dp(9))
            } else {
                setPadding(dp(10), dp(2), dp(2), dp(2))
            }
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun buildPromptLayer(): FrameLayout {
        val layer = FrameLayout(this)

        // 续播提示（左下）
        resumeText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        }
        resumeCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBackground()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            visibility = View.GONE
            addView(resumeText)
            addView(promptButton("从头开始", ACCENT, false) {
                playerSurface.seek(0); hideResumePrompt()
            })
            addView(promptButton("✕", TEXT_DIM, false) { hideResumePrompt() })
        }
        layer.addView(
            resumeCard,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.BOTTOM or Gravity.START; leftMargin = dp(18); bottomMargin = dp(110) },
        )

        // 自动连播倒计时（右下）
        autoNextText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        }
        autoNextCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBackground()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            visibility = View.GONE
            addView(autoNextText)
            addView(promptButton("取消", ACCENT, false) { cancelAutoNext(suppressCurrentItem = true) })
        }
        layer.addView(
            autoNextCard,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.BOTTOM or Gravity.END; rightMargin = dp(18); bottomMargin = dp(110) },
        )

        // 弱网建议（左下，更高）
        weakNetTitle = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        weakNetSubtitle = TextView(this).apply {
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, dp(2), 0, 0)
        }
        weakNetCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBackground()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            visibility = View.GONE
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(weakNetTitle)
                addView(weakNetSubtitle)
            })
            addView(promptButton("切换", ACCENT, false) {
                weakNetSuggestedQualityIndex?.let { index ->
                    weakNetDismissed = true
                    weakNetCard.visibility = View.GONE
                    requestQuality(index, "网络较慢，正在切换到 $weakNetSuggestedQualityLabel…")
                }
            })
            addView(promptButton("忽略", TEXT_DIM, false) {
                weakNetDismissed = true; weakNetCard.visibility = View.GONE
            })
        }
        layer.addView(
            weakNetCard,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.BOTTOM or Gravity.START; leftMargin = dp(18); bottomMargin = dp(160) },
        )

        // 播放完成（全屏遮罩）
        completedPosterImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(0xFF171D28.toInt())
            }
        }
        completedTitle = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, dp(18), 0, 0)
        }
        completedNextButton = promptButton("下一集", Color.WHITE, true) {
            clearCompletion()
            playNextEpisode()
        }
        val completedCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            addView(FrameLayout(context).apply {
                addView(
                    completedPosterImage,
                    FrameLayout.LayoutParams(dp(232), dp(132)).apply {
                        gravity = Gravity.CENTER
                    },
                )
            })
            addView(completedTitle)
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                setPadding(0, dp(18), 0, 0)
                addView(promptButton("重播", ACCENT, true) {
                    clearCompletion(); playerSurface.seek(0); playWithFocus()
                })
                addView(View(context), LinearLayout.LayoutParams(dp(12), 1))
                addView(completedNextButton)
                addView(View(context), LinearLayout.LayoutParams(dp(12), 1))
                addView(promptButton("返回", Color.WHITE, true) { finish() })
            })
        }
        completedOverlay = FrameLayout(this).apply {
            setBackgroundColor(0xCC000000.toInt())
            isClickable = true
            visibility = View.GONE
            addView(
                completedCard,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                ).apply { gravity = Gravity.CENTER },
            )
        }
        layer.addView(
            completedOverlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // 片头/片尾跳过提示（右下，按设置时长在窗口内出现）
        skipText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        }
        skipCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBackground()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            visibility = View.GONE
            addView(skipText)
            addView(promptButton("跳过", ACCENT, false) { skipAction?.invoke() })
        }
        layer.addView(
            skipCard,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.BOTTOM or Gravity.END; rightMargin = dp(18); bottomMargin = dp(110) },
        )

        return layer
    }

    /** 片头片尾跳过：按设置时长窗口在 [updateOverlays] 里驱动显隐。 */
    private fun updateIntroOutroSkip(state: MpvPlayerState) {
        if (!this::skipCard.isInitialized) return
        val dur = state.durationMs
        if (!introOutroEnabled || dur <= 0 || completionActive) {
            if (skipCard.visibility == View.VISIBLE) skipCard.visibility = View.GONE
            return
        }
        val pos = state.positionMs
        // 有章节推断到的片头/片尾区间则精确跳转（跳到章节边界）；否则退回按设置时长上限的窗口。
        val introEndMs = if (inferredIntroEndMs > 0) inferredIntroEndMs else introMaxMin * 60_000L
        val introShowFromMs = if (inferredIntroStartMs >= 0) maxOf(2_000L, inferredIntroStartMs) else 2_000L
        val outroStartMs = if (inferredOutroStartMs >= 0) inferredOutroStartMs else dur - outroMaxMin * 60_000L
        when {
            // 片头窗口：起播 2s（或片头章节起点）后到片头结束边界内
            !introSkipDismissed && pos in introShowFromMs until introEndMs -> {
                skipText.text = "跳过片头"
                skipAction = {
                    introSkipDismissed = true
                    skipCard.visibility = View.GONE
                    playerSurface.seek(introEndMs)
                }
                if (skipCard.visibility != View.VISIBLE) skipCard.visibility = View.VISIBLE
            }
            // 片尾窗口：进入片尾上限后（且不在最后几秒触发完成前）
            !outroSkipDismissed && outroStartMs > introEndMs && pos >= outroStartMs -> {
                val hasNext = hasNextEpisode()
                skipText.text = if (hasNext) "跳过片尾，播放下一集" else "跳过片尾"
                skipAction = {
                    outroSkipDismissed = true
                    skipCard.visibility = View.GONE
                    if (hasNext) playNextEpisode() else playerSurface.seek(dur)
                }
                if (skipCard.visibility != View.VISIBLE) skipCard.visibility = View.VISIBLE
            }
            else -> if (skipCard.visibility == View.VISIBLE) skipCard.visibility = View.GONE
        }
    }

    /** 续播提示：换源后若起播位置 > 3s 弹出，6 秒后自动消失。 */
    private fun maybeShowResumePrompt(loadArgs: Map<String, Any?>) {
        if (!this::resumeCard.isInitialized) return
        val startMs = (loadArgs["startPositionMs"] as? Number)?.toLong() ?: 0L
        if (startMs <= 3000) {
            hideResumePrompt()
            return
        }
        resumeText.text = "已从 ${formatTime(startMs)} 继续播放"
        resumeCard.visibility = View.VISIBLE
        resumeCard.removeCallbacks(resumeHideRunnable)
        resumeCard.postDelayed(resumeHideRunnable, 6000)
    }

    private fun hideResumePrompt() {
        if (!this::resumeCard.isInitialized) return
        resumeCard.removeCallbacks(resumeHideRunnable)
        resumeCard.visibility = View.GONE
    }

    private fun hasNextEpisode(): Boolean {
        return nextEpisodeGuidOrNull() != null
    }

    private fun isInsideAutoNextPromptWindow(state: MpvPlayerState): Boolean {
        if (state.durationMs <= 0L || state.positionMs <= 0L) return false
        val remainingMs = state.durationMs - state.positionMs
        return remainingMs in 1L..5_000L
    }

    private fun startAutoNextCountdown() {
        autoNextActive = true
        autoNextSeconds = 5
        autoNextCard.visibility = View.VISIBLE
        val ticker = object : Runnable {
            override fun run() {
                if (!autoNextActive) return
                if (autoNextSeconds <= 0) {
                    cancelAutoNext()
                    playNextEpisode()
                    return
                }
                autoNextText.text = "${autoNextSeconds}秒后播放下一集"
                autoNextSeconds -= 1
                autoNextCard.postDelayed(this, 1000)
            }
        }
        autoNextTicker = ticker
        autoNextCard.post(ticker)
    }

    private fun cancelAutoNext(suppressCurrentItem: Boolean = false) {
        if (suppressCurrentItem) {
            autoNextSuppressedItemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        }
        autoNextActive = false
        autoNextTicker?.let { autoNextCard.removeCallbacks(it) }
        autoNextTicker = null
        if (this::autoNextCard.isInitialized) autoNextCard.visibility = View.GONE
    }

    private fun showCompletedOverlay() {
        completionActive = true
        completedTitle.text = mediaTitle.ifEmpty { loadArgsMap["seriesTitle"]?.toString().orEmpty() }
        completedNextButton.visibility =
            if (autoPlayEnabled && hasNextEpisode()) View.VISIBLE else View.GONE
        val (artUrl, artAuth) = currentArtwork()
        if (artUrl.isNotEmpty()) {
            Glide.with(this)
                .load(artworkGlideModel(artUrl, artAuth))
                .transform(CenterCrop(), RoundedCorners(dp(16)))
                .into(completedPosterImage)
        } else {
            completedPosterImage.setImageDrawable(null)
        }
        completedOverlay.visibility = View.VISIBLE
        loadingSpinner.visibility = View.GONE
    }

    private fun clearCompletion() {
        completionActive = false
        if (this::completedOverlay.isInitialized) completedOverlay.visibility = View.GONE
        cancelAutoNext()
    }

    private fun updateWeakNetworkSuggestion(state: MpvPlayerState) {
        if (!this::weakNetCard.isInitialized) return
        if (!state.weakNetworkMode || weakNetDismissed || completionActive || networkOffline) {
            weakNetSuggestedQualityIndex = null
            weakNetSuggestedQualityLabel = ""
            weakNetCard.visibility = View.GONE
            return
        }
        val recommendation = nativePanelRecommendWeakNetworkQuality(
            qualities = qualityList(),
            currentQuality = currentQualityForWeakNetwork(),
            networkSpeedBytesPerSecond = state.networkSpeedBytesPerSecond,
            estimatedResumeWaitMs = state.estimatedResumeWaitMs,
        )
        if (recommendation == null) {
            weakNetSuggestedQualityIndex = null
            weakNetSuggestedQualityLabel = ""
            weakNetCard.visibility = View.GONE
            return
        }
        weakNetSuggestedQualityIndex = recommendation.qualityIndex
        weakNetSuggestedQualityLabel = recommendation.qualityLabel
        weakNetTitle.text = "网络较慢，建议切换到 ${recommendation.qualityLabel}"
        weakNetSubtitle.text = recommendation.details
        weakNetCard.visibility = View.VISIBLE
    }

    /** 换源/重载时复位「已开播」兜底，让中间 loading 重新从切换态起算。 */
    private fun resetPlaybackProgressTracking() {
        lastProgressPositionMs = -1L
        playbackProgressing = false
    }

    /** 由 [applyState] 驱动：加载转圈 / 自动连播·完成 / 弱网建议。 */
    private fun updateOverlays(state: MpvPlayerState) {
        // 蠢措施：位置推进且未暂停未缓冲=画面真的在走，据此认定已开播。配合 visualPlaybackReady 一起收 loading，
        // 避免切集原地换源时内核漏报首帧导致中间转圈卡死、episodeSwitchInFlight 永不复位。
        if (!state.paused && !state.buffering && state.error == null &&
            lastProgressPositionMs in 0 until state.positionMs
        ) {
            playbackProgressing = true
        }
        lastProgressPositionMs = state.positionMs
        val effectivelyReady = state.visualPlaybackReady || playbackProgressing
        val showLoading = !state.nativeLibLoaded ||
            state.buffering ||
            (!effectivelyReady && state.error == null) ||
            state.error != null
        loadingSpinner.visibility = if (showLoading && !completionActive) View.VISIBLE else View.GONE
        val playbackEnded = state.playbackPhase == MpvPlaybackPhase.ENDED.wireValue

        if (episodeSwitchInFlight) {
            if (completionActive || autoNextActive) clearCompletion()
            if (state.error != null || (effectivelyReady && !state.buffering && !playbackEnded)) {
                episodeSwitchInFlight = false
            } else {
                return
            }
        }

        // 连续播放：最后 5 秒先弹倒计时；ENDED 仍做兜底，避免采样错过片尾窗口。
        val hasNext = hasNextEpisode()
        val currentItemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
        val autoNextSuppressedForCurrent =
            currentItemGuid.isNotEmpty() && currentItemGuid == autoNextSuppressedItemGuid
        val shouldAutoNext =
            nativePanelShouldStartAutoNextCountdown(
                autoPlayEnabled,
                hasNext,
                episodeSwitchInFlight = episodeSwitchInFlight,
                suppressedForCurrent = autoNextSuppressedForCurrent,
            )
        val insideCompletionWindow = isInsideAutoNextPromptWindow(state)
        val shouldShowAutoNext =
            shouldAutoNext && (insideCompletionWindow || playbackEnded)
        val shouldShowCompleted =
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = autoPlayEnabled,
                hasNextEpisode = hasNext,
                playbackEnded = playbackEnded,
                insideCompletionWindow = insideCompletionWindow,
                positionMs = state.positionMs,
                durationMs = state.durationMs,
            )
        when {
            shouldShowAutoNext -> {
                if (completionActive) completedOverlay.visibility = View.GONE
                completionActive = false
                preloadNextEpisodeIfNeeded()
                if (!autoNextActive) startAutoNextCountdown()
            }
            shouldShowCompleted -> {
                if (!completionActive) showCompletedOverlay()
            }
            completionActive || autoNextActive -> {
                clearCompletion()
            }
        }

        // 弱网建议
        updateWeakNetworkSuggestion(state)

        // 片头片尾跳过提示
        updateIntroOutroSkip(state)

        // 离线横幅（与弱网建议互斥优先：断网时网络已彻底断，弱网提示无意义）
        updateOfflineBanner()
    }

    // ---- 真刷新率切换（按视频 fps 选最接近的 display mode） ----

    private fun resolveActivityDisplay(): android.view.Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

    private fun applyPreferredDisplayMode(reason: String) {
        if (!refreshRateSwitch) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val disp = resolveActivityDisplay() ?: return
        val modes = disp.supportedModes
        if (modes.isEmpty()) return
        val fps = (playerSurface.getPlaybackDiagnostics()["containerFps"] as? Number)?.toDouble() ?: 0.0
        val target = if (fps > 1.0) {
            // 选 refreshRate 最接近 fps 整数倍的模式（24fps→48/72Hz、30fps→60Hz 等），消除判读抖动。
            modes.minByOrNull { m ->
                val multiple = Math.round(m.refreshRate / fps).toDouble().coerceAtLeast(1.0)
                Math.abs(m.refreshRate - fps * multiple)
            }
        } else {
            modes.maxByOrNull { it.refreshRate }
        } ?: return
        val params = window.attributes
        if (params.preferredDisplayModeId != target.modeId) {
            params.preferredDisplayModeId = target.modeId
            window.attributes = params
            Log.d(
                "NativePlayer",
                "applyPreferredDisplayMode reason=$reason fps=$fps modeHz=${target.refreshRate} modeId=${target.modeId}",
            )
        }
    }

    private fun restoreDefaultDisplayMode() {
        refreshRateApplied = false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val params = window.attributes
        if (params.preferredDisplayModeId != 0) {
            params.preferredDisplayModeId = 0
            window.attributes = params
        }
    }

    // ---- 离线状态感知 ----

    /** 注册网络监听：默认网络丢失/恢复时切回主线程更新断网横幅与联网入口可用性。 */
    private fun registerNetworkMonitor() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        // 初始态：当前是否有可用网络。
        networkOffline = !hasValidatedNetwork(cm)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = postNetworkState(false)
            override fun onLost(network: Network) {
                // onLost 针对单个网络；用 cm 复核是否还有其它可用网络，避免切换 WiFi/移动时误报。
                postNetworkState(!hasValidatedNetwork(cm))
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                postNetworkState(
                    !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                )
            }
        }
        networkCallback = callback
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        runCatching { cm.registerNetworkCallback(request, callback) }
    }

    private fun unregisterNetworkMonitor() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        networkCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        networkCallback = null
    }

    private fun hasValidatedNetwork(cm: ConnectivityManager): Boolean {
        val active = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(active) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun postNetworkState(offline: Boolean) {
        rootContainer.post {
            // 网络类型可能在仍联网时切换（WiFi↔移动），顶栏标签需无条件刷新。
            updateNetworkInfo()
            if (networkOffline == offline) return@post
            networkOffline = offline
            // 恢复联网时重置「已知道了」，下次断网横幅可再次出现。
            if (!offline) offlineBannerDismissed = false
            updateOfflineBanner()
        }
    }

    private fun updateOfflineBanner() {
        val show = networkOffline && !offlineBannerDismissed && !completionActive
        if (show) {
            val banner = offlineBanner ?: buildOfflineBanner().also { offlineBanner = it }
            banner.visibility = View.VISIBLE
            // 断网时弱网建议无意义，让位给离线横幅。
            if (this::weakNetCard.isInitialized) weakNetCard.visibility = View.GONE
        } else {
            offlineBanner?.visibility = View.GONE
        }
    }

    private fun buildOfflineBanner(): View {
        val banner = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBackground()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            visibility = View.GONE
            addView(TextView(context).apply {
                text = "已断网，正在播放本地内容"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            })
            addView(promptButton("知道了", ACCENT, false) {
                offlineBannerDismissed = true
                offlineBanner?.visibility = View.GONE
            })
        }
        // 叠在弱网建议同一位置（左下）。overlayLayer 由 buildOverlayLayer 提供，weakNetCard 已加入其中。
        (weakNetCard.parent as? FrameLayout)?.addView(
            banner,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.START
                leftMargin = dp(18)
                bottomMargin = dp(160)
            },
        )
        return banner
    }

    private fun formatSpeed(bytesPerSecond: Long): String {
        if (bytesPerSecond <= 0) return ""
        val mb = bytesPerSecond / 1024.0 / 1024.0
        return if (mb >= 1.0) String.format("%.1f MB/s", mb)
        else String.format("%.0f KB/s", bytesPerSecond / 1024.0)
    }

    // ---- 设置抽屉（顶栏「更多」→ 多级子页，复用右侧面板栈） ----

    // 各子页的「当前值」镜像：mpv 端无统一查询，UI 自己记着，change 时把完整集合发回去。
    private val videoAdjust = linkedMapOf<String, Any?>(
        "brightness" to 0.0, "contrast" to 0.0, "saturation" to 0.0, "gamma" to 0.0, "hue" to 0.0,
    )
    private var subDelaySec = 0.0
    private var subPosition = 100
    private var subScale = 1.0
    private var audioDelaySec = 0.0
    private var decoderHardware = true
    private var aspectMode = "fit"
    // 熄屏继续播放音频（video_misc 持久化，默认关）：开启后看视频熄屏/锁屏只停画面、不停声音。
    private var keepAudioWhenScreenOff = false
    // 真刷新率切换（video_misc 持久化，默认关）：按视频 fps 选最接近的 display mode，离开恢复。
    private var refreshRateSwitch = false
    private var refreshRateApplied = false
    // setMpvAdvancedSettings.update 是「整体替换」，每次必须发完整集合。键集与 Flutter
    // MpvSettingsCatalog.defaults 对齐——内核(MpvAdvancedSettingsController)已支持全部，
    // 此前原生 UI 只接了前 7 个视频键，音频处理/补帧/同步/缓存大小/自定义 EQ 都没接上。
    private val mpvAdvanced = linkedMapOf<String, Any?>(
        // 视频
        "deband" to "off", "sharpen" to "off", "denoise" to "off",
        "deinterlace" to "auto", "scale_profile" to "balanced", "hdr_mode" to "auto",
        "tone_mapping" to "auto",
        "frame_interpolation" to "off", "video_sync" to "auto",
        "cache_profile" to "default", "cache_size_mb" to "auto",
        "compatibility_profile" to "default",
        // 音频
        "volume_gain" to "100", "audio_high_fidelity" to "off",
        "audio_passthrough" to "off", "dynamic_range" to "off",
        "audio_eq" to "off", "audio_limiter" to "off", "audio_bass_boost" to "off",
        "audio_voice_enhance" to "off", "channel_mix" to "auto",
        // 自定义 EQ 各频段增益（dB，仅 audio_eq=custom 时内核读取）
        "audio_eq_band_60" to "0", "audio_eq_band_170" to "0", "audio_eq_band_310" to "0",
        "audio_eq_band_1000" to "0", "audio_eq_band_6000" to "0",
    )

    private val eqBands = listOf(
        "audio_eq_band_60" to "60", "audio_eq_band_170" to "170",
        "audio_eq_band_310" to "310", "audio_eq_band_1000" to "1K",
        "audio_eq_band_6000" to "6K",
    )

    // 设置持久化 + 首帧就绪后把已存设置套用一次（每次换源置 true 以重套）。
    private lateinit var settingsStore: NativePlayerSettingsStore
    private var pendingPersistedSettings = true

    private fun addPanelRow(view: View) {
        panelContent.addView(
            view,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun panelActionRow(label: String, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            setTextColor(ACCENT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            background = glassBackground()
            setPadding(dp(12), dp(10), dp(12), dp(10))
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun showSettingsRoot() {
        togglePanel(PanelPage("设置") { buildSettingsRoot() })
    }

    private fun buildSettingsRoot() {
        // 竖屏下底栏隐藏了音轨/字幕/画质入口，这里补一段直达，保证仍可访问。
        if (isPortrait()) {
            addPanelRow(panelSectionHeader("音画"))
            addPanelRow(
                panelCardGroup(
                    panelNavRow("音轨") { showAudioPanel() },
                    panelNavRow("字幕") { showSubtitlePanel() },
                    panelNavRow("画质", currentQualityLabel()) { showQualityPanel() },
                ),
            )
        }
        addPanelRow(panelSectionHeader("画面"))
        addPanelRow(
            panelCardGroup(
                panelNavRow("画面调整") {
                    pushPanel(PanelPage("画面调整") { buildVideoAdjustPage() })
                },
                panelNavRow("画质与解码") {
                    pushPanel(PanelPage("画质与解码") { buildAdvancedMpvPage() })
                },
            ),
        )
        addPanelRow(panelSectionHeader("弹幕"))
        addPanelRow(
            panelCardGroup(
                panelNavRow("弹幕设置") {
                    pushPanel(PanelPage("弹幕设置") { buildDanmakuSettingsPage() })
                },
                panelNavRow("弹幕源") {
                    pushPanel(PanelPage("弹幕源") { buildDanmakuSourcePage() })
                },
            ),
        )
        addPanelRow(panelSectionHeader("播放"))
        addPanelRow(
            panelCardGroup(
                panelNavRow("播放行为", playbackBehaviorSummary()) {
                    pushPanel(PanelPage("播放行为") { buildPlaybackBehaviorSettingsPage() })
                },
            ),
        )
        if (chapterList.isNotEmpty()) {
            addPanelRow(
                panelCardGroup(
                    panelNavRow("章节", chapterList.size.toString()) {
                        pushPanel(PanelPage("章节") { buildChapterPage() })
                    },
                ),
            )
        }
        addPanelRow(
            panelCardGroup(
                panelNavRow("片头片尾跳过") {
                    pushPanel(PanelPage("片头片尾跳过") { buildIntroOutroPage() })
                },
                panelNavRow("书签") {
                    pushPanel(PanelPage("书签") { buildBookmarkPage() })
                },
                panelNavRow("视频/轨道信息") {
                    pushPanel(PanelPage("视频/轨道信息") { buildTrackInfoPage() })
                },
            ),
        )
        addPanelRow(panelSectionHeader("工具"))
        addPanelRow(
            panelCardGroup(
                panelNavRow("截图设置") {
                    pushPanel(PanelPage("截图设置") { buildScreenshotSettingsPage() })
                },
            ),
        )
        addPanelRow(panelCardGroup(panelActionRow("切换到 Flutter 播放器") { switchToFlutterPlayer() }))
    }

    private fun playbackBehaviorSummary(): String {
        return if (autoPlayEnabled) "连播开" else "连播关"
    }

    private fun buildPlaybackBehaviorSettingsPage() {
        addPanelRow(
            panelCardGroup(
                panelToggle(
                    label = "自动旋转",
                    value = autoRotateEnabled,
                    subtitle = "跟随系统方向自动切换",
                ) { enabled ->
                    autoRotateEnabled = enabled
                    persistPlaybackBehavior()
                    applyFullscreenOrientation()
                    renderTopPanel()
                },
                panelToggle(
                    label = "自动连播",
                    value = autoPlayEnabled,
                    subtitle = if (autoPlayEnabled) {
                        "当前集结束前 5 秒提示并自动进入下一集"
                    } else {
                        "关闭后播放完成停留当前集"
                    },
                ) { enabled ->
                    autoPlayEnabled = enabled
                    persistPlaybackBehavior()
                    if (!enabled) {
                        cancelAutoNext()
                        clearNextEpisodePreload()
                    }
                    renderTopPanel()
                },
                panelToggle(
                    label = "下一级预加载",
                    value = nativePanelCanPreloadNextEpisode(
                        autoPlayEnabled,
                        nextEpisodePreloadEnabled,
                    ),
                    subtitle = if (autoPlayEnabled) {
                        if (nextEpisodePreloadEnabled) "提前准备下一集，减少切集等待"
                        else "关闭后保持原本的自动连播切集方式"
                    } else {
                        "需先开启自动连播"
                    },
                    enabled = autoPlayEnabled,
                ) { enabled ->
                    nextEpisodePreloadEnabled = enabled
                    persistPlaybackBehavior()
                    if (!enabled) clearNextEpisodePreload()
                    renderTopPanel()
                },
            ),
        )
    }

    private fun buildChapterPage() {
        if (chapterList.isEmpty()) {
            addPanelRow(panelEmptyState("当前视频没有章节信息"))
            return
        }
        val pos = playerSurface.state.positionMs
        val rows = chapterList.mapIndexed { index, chapter ->
            val startMs = (chapter["timeMs"] as? Number)?.toLong() ?: 0L
            val nextMs = (chapterList.getOrNull(index + 1)?.get("timeMs") as? Number)?.toLong() ?: Long.MAX_VALUE
            val selected = startMs <= pos && pos < nextMs
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(12), dp(12), dp(12))
                background = if (selected) {
                    GradientDrawable().apply {
                        cornerRadius = dp(10).toFloat()
                        setColor(ITEM_SELECTED_BG)
                    }
                } else {
                    itemRippleBackground()
                }
                isClickable = true
                setOnClickListener {
                    playerSurface.seek(startMs)
                    hidePanel()
                }
                addView(TextView(context).apply {
                    text = chapter["title"]?.toString()?.trim()?.takeIf { it.isNotEmpty() } ?: "章节 ${index + 1}"
                    setTextColor(if (selected) ACCENT else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                addView(TextView(context).apply {
                    text = formatTime(startMs)
                    setTextColor(if (selected) ACCENT else TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    setPadding(dp(8), 0, 0, 0)
                })
            }
        }
        addPanelRow(panelCardGroup(rows))
    }

    private fun switchToFlutterPlayer() {
        NativePlayerReverseBridge.dispatch(
            method = "setUseNativeRenderer",
            args = mapOf("enabled" to false),
            onResult = {
                runOnUiThread {
                    reportProgress()
                    showTransientHint("已切换到 Flutter 播放器，重新播放生效")
                    finish()
                }
            },
            onError = {
                runOnUiThread { showTransientHint("切换失败，请重试") }
            },
        )
    }

    private fun buildScreenshotSettingsPage() {
        // 选项与取值同 Flutter 端「截图设置」保持一致，确保两端相互映射。
        val saveOpts = listOf(
            "相册" to "pictures",
            "DCIM" to "dcim",
            "应用目录" to "app_pictures",
            "自定义" to "custom",
        )
        addPanelRow(
            panelCardGroup(
                panelSegment(
                    "保存位置",
                    saveOpts.map { it.first },
                    saveOpts.indexOfFirst { it.second == screenshotSaveMode }.coerceAtLeast(0),
                ) { index ->
                    val mode = saveOpts[index].second
                    // 自定义目录由 App 设置里授权选择，原生壳内无法新增授权，未配置时提示并回退。
                    if (mode == "custom" && !screenshotCustomDirectoryConfigured()) {
                        showTransientHint("请先在 App 设置里选择自定义截图目录")
                    } else {
                        screenshotSaveMode = mode
                        persistScreenshot()
                    }
                    renderTopPanel()
                },
                panelToggle(
                    "截图包含字幕",
                    screenshotIncludeSubtitles,
                    "开启则把当前字幕一并截入图片。",
                ) { enabled ->
                    screenshotIncludeSubtitles = enabled
                    persistScreenshot()
                },
            ),
        )
        addPanelRow(panelCardGroup(panelActionRow("立即截图") {
            hidePanel()
            takeScreenshot()
        }))
    }
    // ---- 设置持久化（恢复 / 首帧套用 / 落盘） ----

    private fun restorePersistedSettings() {
        settingsStore.loadMap(NativePlayerSettingsStore.KEY_MPV_ADVANCED, mpvAdvanced).let {
            mpvAdvanced.clear(); mpvAdvanced.putAll(it)
        }
        settingsStore.loadMap(NativePlayerSettingsStore.KEY_VIDEO_ADJUST, videoAdjust).let {
            videoAdjust.clear(); videoAdjust.putAll(it)
        }
        // Flutter「MPV播放器设置」页（含快速预设/保存预设的应用结果）是画质与画面调整的单一
        // 数据源：启动 payload 注入的值覆盖本地镜像并回写本地，使设置页改动直接在原生壳生效。
        // 白名单合并：只认 mpvAdvanced/videoAdjust 里已存在的 key（tone_mapping、audio_passthrough
        // 等原生独有键不在 Flutter 目录中，注入里没有 → 保留本地值，不被清掉）。
        applyInjectedMpvSettings()
        settingsStore.loadMap(NativePlayerSettingsStore.KEY_OCCLUSION, occlusionConfig).let {
            occlusionConfig.clear(); occlusionConfig.putAll(it)
        }
        val sub = settingsStore.loadMap(
            NativePlayerSettingsStore.KEY_SUBTITLE_STYLE,
            linkedMapOf("delay" to 0.0, "position" to 100, "scale" to 1.0),
        )
        subDelaySec = (sub["delay"] as? Number)?.toDouble() ?: 0.0
        subPosition = (sub["position"] as? Number)?.toInt() ?: 100
        subScale = (sub["scale"] as? Number)?.toDouble() ?: 1.0
        audioDelaySec = (settingsStore.loadMap(
            NativePlayerSettingsStore.KEY_AUDIO_ADJUST, linkedMapOf("delay" to 0.0),
        )["delay"] as? Number)?.toDouble() ?: 0.0
        val misc = settingsStore.loadMap(
            NativePlayerSettingsStore.KEY_VIDEO_MISC,
            linkedMapOf(
                "decoderHardware" to true, "aspect" to "fit",
                "pipAutoEnter" to false, "refreshRateSwitch" to false,
                "keepAudioWhenScreenOff" to false,
            ),
        )
        decoderHardware = (misc["decoderHardware"] as? Boolean) ?: true
        aspectMode = misc["aspect"]?.toString() ?: "fit"
        pipAutoEnter = (misc["pipAutoEnter"] as? Boolean) ?: false
        refreshRateSwitch = (misc["refreshRateSwitch"] as? Boolean) ?: false
        keepAudioWhenScreenOff = (misc["keepAudioWhenScreenOff"] as? Boolean) ?: false
        // 轻量标志，无需等内核就绪，立即下发（熄屏可能发生在首帧之前）。
        if (this::playerSurface.isInitialized) {
            playerSurface.setKeepAudioWhenScreenOff(keepAudioWhenScreenOff)
        }
        val behavior = settingsStore.loadMap(
            NativePlayerSettingsStore.KEY_PLAYBACK_BEHAVIOR,
            linkedMapOf("autoPlayEnabled" to true),
        )
        autoRotateEnabled = loadSharedBoolean(NATIVE_PLAYER_AUTO_ROTATE_PREF_KEY, true)
        autoPlayEnabled = loadSharedBoolean(
            NATIVE_PLAYER_AUTO_PLAY_PREF_KEY,
            (behavior["autoPlayEnabled"] as? Boolean) ?: true,
        )
        nextEpisodePreloadEnabled = loadSharedBoolean(
            NATIVE_PLAYER_NEXT_EPISODE_PRELOAD_PREF_KEY,
            false,
        )
        applyFullscreenOrientation()
        val io = settingsStore.loadMap(
            NativePlayerSettingsStore.KEY_INTRO_OUTRO,
            linkedMapOf(
                "enabled" to false, "introMaxMin" to 2, "outroMaxMin" to 2, "skipCountdownSec" to 5,
            ),
        )
        introOutroEnabled = (io["enabled"] as? Boolean) ?: false
        introMaxMin = (io["introMaxMin"] as? Number)?.toInt() ?: 2
        outroMaxMin = (io["outroMaxMin"] as? Number)?.toInt() ?: 2
        skipCountdownSec = (io["skipCountdownSec"] as? Number)?.toInt() ?: 5
        // 截图设置与 Flutter 端共享同一份偏好（FlutterSharedPreferences），两端互通不漂移。
        screenshotIncludeSubtitles = loadSharedScreenshotIncludeSubtitles()
        screenshotSaveMode = loadSharedScreenshotSaveMode()
        applyPersistedDanmakuPrefs()      // 先读本地缓存兜底
        applyInjectedDanmakuSettings()    // 再用 Flutter 注入覆盖（单一事实源）
    }

    private fun persistScreenshot() {
        saveSharedScreenshotSaveMode(screenshotSaveMode)
        saveSharedScreenshotIncludeSubtitles(screenshotIncludeSubtitles)
    }

    /** 首帧就绪后把已存设置真正下发内核（每次换源重套，因 mpv 重载会复位属性）。 */
    private fun pushPersistedSettings() {
        playerSurface.setMpvAdvancedSettings(mapOf("settings" to mpvAdvanced))
        playerSurface.setVideoAdjustments(mapOf("settings" to videoAdjust))
        playerSurface.setDecoderMode(if (decoderHardware) "hardware" else "software")
        playerSurface.setDisplayAspectRatioMode(aspectMode)
        if (subDelaySec != 0.0) playerSurface.setSubtitleDelay(subDelaySec)
        if (subPosition != 100) playerSurface.setSubtitlePosition(subPosition)
        if (subScale != 1.0) playerSurface.setSubtitleScale(subScale)
        if (audioDelaySec != 0.0) playerSurface.setAudioDelay(audioDelaySec)
        if (occlusionConfig["enabled"] == true) applyOcclusionConfig()
    }

    private fun persistMpvAdvanced() =
        settingsStore.saveMap(NativePlayerSettingsStore.KEY_MPV_ADVANCED, mpvAdvanced)

    private fun persistVideoAdjust() =
        settingsStore.saveMap(NativePlayerSettingsStore.KEY_VIDEO_ADJUST, videoAdjust)

    /** 启动注入的 Flutter 全局 MPV 设置 → 覆盖本地镜像并回写本地，使设置页改动在原生壳生效。 */
    private fun applyInjectedMpvSettings() {
        (loadArgsMap["mpvAdvancedSettings"] as? Map<*, *>)?.let { injected ->
            var changed = false
            for ((k, v) in injected) {
                val key = k?.toString() ?: continue
                if (v != null && mpvAdvanced.containsKey(key)) {
                    mpvAdvanced[key] = v.toString(); changed = true
                }
            }
            if (changed) persistMpvAdvanced()
        }
        (loadArgsMap["videoAdjustments"] as? Map<*, *>)?.let { injected ->
            var changed = false
            for ((k, v) in injected) {
                val key = k?.toString() ?: continue
                if (v is Number && videoAdjust.containsKey(key)) {
                    videoAdjust[key] = v.toDouble(); changed = true
                }
            }
            if (changed) persistVideoAdjust()
        }
    }

    /** mpv 高级设置改动后：下发内核(可选) + 本地落盘 + 回写 Flutter 全局设置（与设置页同步）。 */
    private fun commitMpvAdvanced(pushKernel: Boolean = true) {
        if (pushKernel) playerSurface.setMpvAdvancedSettings(mapOf("settings" to mpvAdvanced))
        persistMpvAdvanced()
        NativePlayerReverseBridge.dispatch("persistMpvAdvanced", mpvAdvanced.toMap())
    }

    /** 画面调整改动后：本地落盘 + 回写 Flutter（内核下发由调用方按需做，拖动时避免每帧回写）。 */
    private fun commitVideoAdjust() {
        persistVideoAdjust()
        NativePlayerReverseBridge.dispatch("persistVideoAdjustments", videoAdjust.toMap())
    }

    // ---- Flutter「保存预设」（画质/音频）：原生壳选择并套用，写入由 Flutter 全局完成 ----

    /** 拉取 Flutter 已保存预设并弹出选择子页。kind = "picture" | "audio"。 */
    private fun showSavedMpvPresetPicker(kind: String) {
        showCenterHint("加载预设…")
        NativePlayerReverseBridge.dispatch(
            method = "listSavedMpvPresets",
            args = mapOf("kind" to kind),
            onResult = { res ->
                runOnUiThread {
                    hideCenterHint()
                    val list = (res as? List<*>)?.mapNotNull { it as? Map<String, Any?> }
                        ?: emptyList()
                    if (list.isEmpty()) {
                        showTransientHint("暂无已保存预设，请先在设置页保存")
                        return@runOnUiThread
                    }
                    pushPanel(
                        PanelPage(if (kind == "audio") "音频预设" else "画质预设") {
                            buildSavedPresetListPage(kind, list)
                        },
                    )
                }
            },
            onError = { runOnUiThread { hideCenterHint(); showTransientHint("预设加载失败") } },
        )
    }

    private fun buildSavedPresetListPage(kind: String, list: List<Map<String, Any?>>) {
        addPanelRow(panelSectionHeader("已保存预设"))
        val rows = list.map { p ->
            val id = p["id"]?.toString().orEmpty()
            val name = p["name"]?.toString()?.takeIf { it.isNotEmpty() } ?: "预设"
            val desc = p["description"]?.toString().orEmpty()
            panelNavRow(name, desc) { applySavedMpvPreset(kind, id) }
        }
        addPanelRow(panelCardGroup(*rows.toTypedArray()))
    }

    private fun applySavedMpvPreset(kind: String, id: String) {
        if (id.isEmpty()) return
        showCenterHint("应用预设…")
        NativePlayerReverseBridge.dispatch(
            method = "applySavedMpvPreset",
            args = mapOf("kind" to kind, "id" to id),
            onResult = { res ->
                runOnUiThread {
                    hideCenterHint()
                    val bundle = res as? Map<String, Any?>
                    if (bundle == null) { showTransientHint("应用预设失败"); return@runOnUiThread }
                    applyPresetBundle(bundle)
                    popPanel() // 退出预设列表回到画质/音频页
                    showTransientHint("已应用预设")
                }
            },
            onError = { runOnUiThread { hideCenterHint(); showTransientHint("应用预设失败") } },
        )
    }

    /** 套用 Flutter 回传的预设 bundle 到本地镜像 + 内核 + 本地落盘。Flutter 已存全局，无需回写。 */
    private fun applyPresetBundle(bundle: Map<String, Any?>) {
        (bundle["settings"] as? Map<*, *>)?.let { s ->
            for ((k, v) in s) {
                val key = k?.toString() ?: continue
                if (v != null && mpvAdvanced.containsKey(key)) mpvAdvanced[key] = v.toString()
            }
        }
        (bundle["videoAdjustments"] as? Map<*, *>)?.let { va ->
            for ((k, v) in va) {
                val key = k?.toString() ?: continue
                if (v is Number && videoAdjust.containsKey(key)) videoAdjust[key] = v.toDouble()
            }
        }
        playerSurface.setMpvAdvancedSettings(mapOf("settings" to mpvAdvanced))
        playerSurface.setVideoAdjustments(mapOf("settings" to videoAdjust))
        persistMpvAdvanced()
        persistVideoAdjust()
    }

    private fun persistOcclusion() =
        settingsStore.saveMap(NativePlayerSettingsStore.KEY_OCCLUSION, occlusionConfig)

    private fun persistSubtitleStyle() = settingsStore.saveMap(
        NativePlayerSettingsStore.KEY_SUBTITLE_STYLE,
        linkedMapOf<String, Any?>("delay" to subDelaySec, "position" to subPosition, "scale" to subScale),
    )

    private fun persistAudioAdjust() = settingsStore.saveMap(
        NativePlayerSettingsStore.KEY_AUDIO_ADJUST, linkedMapOf<String, Any?>("delay" to audioDelaySec),
    )

    private fun persistVideoMisc() = settingsStore.saveMap(
        NativePlayerSettingsStore.KEY_VIDEO_MISC,
        linkedMapOf<String, Any?>(
            "decoderHardware" to decoderHardware,
            "aspect" to aspectMode,
            "pipAutoEnter" to pipAutoEnter,
            "refreshRateSwitch" to refreshRateSwitch,
            "keepAudioWhenScreenOff" to keepAudioWhenScreenOff,
        ),
    )

    private fun persistPlaybackBehavior() {
        saveSharedBoolean(NATIVE_PLAYER_AUTO_ROTATE_PREF_KEY, autoRotateEnabled)
        saveSharedBoolean(NATIVE_PLAYER_AUTO_PLAY_PREF_KEY, autoPlayEnabled)
        saveSharedBoolean(
            NATIVE_PLAYER_NEXT_EPISODE_PRELOAD_PREF_KEY,
            nextEpisodePreloadEnabled,
        )
        settingsStore.saveMap(
            NativePlayerSettingsStore.KEY_PLAYBACK_BEHAVIOR,
            linkedMapOf<String, Any?>("autoPlayEnabled" to autoPlayEnabled),
        )
    }

    private fun preloadNextEpisodeIfNeeded() {
        if (!nativePanelCanPreloadNextEpisode(autoPlayEnabled, nextEpisodePreloadEnabled)) return
        val nextGuid = nextEpisodeGuidOrNull() ?: return
        if (nextGuid == nextEpisodePreloadGuid && (nextEpisodePreloadInFlight || nextEpisodePreloadResult != null)) {
            return
        }
        nextEpisodePreloadGuid = nextGuid
        nextEpisodePreloadInFlight = true
        nextEpisodePreloadResult = null
        NativePlayerReverseBridge.dispatch(
            method = "resolvePlayback",
            // 预取也带当前序号，使自动连播命中预取时仍继承轨道。切轨时会清掉预取重取，避免序号过期。
            args = episodeResolveArgs(nextGuid),
            onResult = { result ->
                runOnUiThread {
                    if (nextEpisodePreloadGuid == nextGuid) {
                        nextEpisodePreloadResult = result
                        nextEpisodePreloadInFlight = false
                    }
                }
            },
            onError = {
                runOnUiThread {
                    if (nextEpisodePreloadGuid == nextGuid) clearNextEpisodePreload()
                }
            },
        )
    }

    private fun clearNextEpisodePreload() {
        nextEpisodePreloadGuid = ""
        nextEpisodePreloadInFlight = false
        nextEpisodePreloadResult = null
    }

    private fun persistIntroOutro() = settingsStore.saveMap(
        NativePlayerSettingsStore.KEY_INTRO_OUTRO,
        linkedMapOf<String, Any?>(
            "enabled" to introOutroEnabled, "introMaxMin" to introMaxMin,
            "outroMaxMin" to outroMaxMin, "skipCountdownSec" to skipCountdownSec,
        ),
    )

    private fun buildVideoAdjustPage() {
        val fields = listOf(
            "brightness" to "亮度", "contrast" to "对比度",
            "saturation" to "饱和度", "gamma" to "伽马", "hue" to "色相",
        )
        for ((key, label) in fields) {
            val cur = (videoAdjust[key] as? Number)?.toFloat() ?: 0f
            addPanelRow(panelSlider(
                label, -100f, 100f, cur, steps = 200, format = { String.format("%+.0f", it) },
                onCommit = { commitVideoAdjust() },
            ) { v ->
                videoAdjust[key] = v.toDouble()
                playerSurface.setVideoAdjustments(mapOf("settings" to videoAdjust))
            })
        }
        addPanelRow(panelActionRow("重置画面") {
            for (k in videoAdjust.keys.toList()) videoAdjust[k] = 0.0
            playerSurface.setVideoAdjustments(mapOf("settings" to videoAdjust))
            commitVideoAdjust()
            renderTopPanel()
        })
    }

    private fun buildSubtitleStylePage() {
        addPanelRow(panelSlider("字幕延迟", -10f, 10f, subDelaySec.toFloat(), steps = 200, format = { String.format("%+.1f s", it) }) { v ->
            subDelaySec = v.toDouble(); playerSurface.setSubtitleDelay(subDelaySec)
        })
        addPanelRow(panelSlider("垂直位置", 0f, 100f, subPosition.toFloat(), steps = 100) { v ->
            subPosition = v.toInt(); playerSurface.setSubtitlePosition(subPosition)
        })
        addPanelRow(panelSlider("字号缩放", 0.5f, 2.5f, subScale.toFloat(), steps = 200, format = { String.format("%.2fx", it) }) { v ->
            subScale = v.toDouble(); playerSurface.setSubtitleScale(subScale)
        })
        addPanelRow(panelActionRow("重置字幕样式") {
            subDelaySec = 0.0; subPosition = 100; subScale = 1.0
            playerSurface.resetSubtitleStyle(); renderTopPanel()
        })
    }

    private fun buildAudioPage() {
        addPanelRow(panelCardGroup(panelSlider("音频延迟", -10f, 10f, audioDelaySec.toFloat(), steps = 200, format = { String.format("%+.1f s", it) }) { v ->
            audioDelaySec = v.toDouble(); playerSurface.setAudioDelay(audioDelaySec); persistAudioAdjust()
        }))
        addPanelRow(panelSectionHeader("快速预设"))
        addPanelRow(panelCardGroup(panelNavRow("应用已保存的音频预设") {
            showSavedMpvPresetPicker("audio")
        }))
        addPanelRow(panelSectionHeader("直通输出"))
        addPanelRow(panelCardGroup(
            advancedSegment("直通输出(杜比/DTS)", "audio_passthrough", listOf("关" to "off", "自动" to "auto", "开" to "on")),
        ))
        val passthroughOn = mpvAdvanced["audio_passthrough"].let { it == "on" || it == "auto" }
        if (passthroughOn) {
            addPanelRow(panelCardGroup(TextView(this).apply {
                text = "直通中：音频由功放/电视解码，EQ 与音频增强已停用"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(16), dp(12), dp(16), dp(12))
            }))
        }
        addPanelRow(panelSectionHeader("音频处理"))
        addPanelRow(panelCardGroup(
            advancedSegment("音量增益", "volume_gain", listOf("100%" to "100", "150%" to "150", "200%" to "200"), passthroughOn),
            advancedSegment("高保真直通", "audio_high_fidelity", listOf("关" to "off", "开" to "on"), passthroughOn),
            advancedSegment("动态范围压缩", "dynamic_range", listOf("关" to "off", "低" to "low", "中" to "medium"), passthroughOn),
            advancedSegment("限制器", "audio_limiter", listOf("关" to "off", "轻" to "light", "强" to "strong"), passthroughOn),
            advancedSegment("低音增强", "audio_bass_boost", listOf("关" to "off", "低" to "low", "中" to "medium"), passthroughOn),
            advancedSegment("人声增强", "audio_voice_enhance", listOf("关" to "off", "低" to "low", "中" to "medium"), passthroughOn),
            advancedSegment("声道", "channel_mix", listOf("自动" to "auto", "立体声" to "stereo", "环绕" to "surround"), passthroughOn),
        ))
        addPanelRow(panelSectionHeader("均衡器 EQ"))
        addPanelRow(panelCardGroup(
            advancedSegment("EQ 预设", "audio_eq", listOf("关" to "off", "柔和" to "soft", "清晰" to "clarity", "影院" to "cinema", "自定义" to "custom"), passthroughOn),
            panelNavRow("自定义均衡器", if (mpvAdvanced["audio_eq"] == "custom") "已启用" else "") {
                if (passthroughOn) { showTransientHint("直通输出中，EQ 不可用"); return@panelNavRow }
                pushPanel(PanelPage("自定义均衡器") { buildEqualizerPage() })
            },
        ))
    }

    /** 3 级页：自定义均衡器。各频段增益写入 mpvAdvanced（audio_eq 自动置 custom）并下发内核。 */
    private fun buildEqualizerPage() {
        val sliders = eqBands.map { (key, label) ->
            val cur = (mpvAdvanced[key] as? String)?.toFloatOrNull() ?: 0f
            panelSlider(
                "${label}Hz", -12f, 12f, cur, steps = 48, format = { String.format("%+.1f dB", it) },
                onCommit = { commitMpvAdvanced(pushKernel = false) },
            ) { v ->
                val stepped = (Math.round(v / 0.5f) * 0.5f).coerceIn(-12f, 12f)
                mpvAdvanced[key] = String.format("%.1f", stepped)
                mpvAdvanced["audio_eq"] = "custom"
                playerSurface.setMpvAdvancedSettings(mapOf("settings" to mpvAdvanced))
            }
        }.toTypedArray()
        addPanelRow(panelCardGroup(*sliders))
        addPanelRow(panelCardGroup(panelActionRow("重置均衡器") {
            for ((key, _) in eqBands) mpvAdvanced[key] = "0"
            commitMpvAdvanced()
            renderTopPanel()
        }))
    }

    private fun buildAdvancedMpvPage() {
        val aspectOpts = listOf(
            "自适应" to "fit", "填充" to "fill", "4:3" to "4:3", "16:9" to "16:9", "21:9" to "21:9",
        )
        addPanelRow(panelSectionHeader("快速预设"))
        addPanelRow(panelCardGroup(panelNavRow("应用已保存的画质预设") {
            showSavedMpvPresetPicker("picture")
        }))
        addPanelRow(panelSectionHeader("解码 / 画面"))
        addPanelRow(
            panelCardGroup(
                panelSegment("解码方式", listOf("硬件", "软件"), if (decoderHardware) 0 else 1) { i ->
                    decoderHardware = i == 0
                    playerSurface.setDecoderMode(if (decoderHardware) "hardware" else "software")
                    renderTopPanel()
                },
                panelSegment("画面比例", aspectOpts.map { it.first }, aspectOpts.indexOfFirst { it.second == aspectMode }.coerceAtLeast(0)) { i ->
                    aspectMode = aspectOpts[i].second
                    playerSurface.setDisplayAspectRatioMode(aspectMode); renderTopPanel()
                },
                panelSegment("划走自动小窗", listOf("开", "关"), if (pipAutoEnter) 0 else 1) { i ->
                    pipAutoEnter = i == 0; persistVideoMisc()
                },
                panelSegment("熄屏继续播放音频", listOf("开", "关"), if (keepAudioWhenScreenOff) 0 else 1) { i ->
                    keepAudioWhenScreenOff = i == 0
                    playerSurface.setKeepAudioWhenScreenOff(keepAudioWhenScreenOff)
                    persistVideoMisc()
                },
                panelSegment("匹配刷新率", listOf("开", "关"), if (refreshRateSwitch) 0 else 1) { i ->
                    refreshRateSwitch = i == 0; persistVideoMisc()
                },
            ),
        )
        addPanelRow(panelSectionHeader("画质增强"))
        addPanelRow(
            panelCardGroup(
                advancedSegment("去隔行", "deinterlace", listOf("自动" to "auto", "强制" to "force", "关" to "off")),
                advancedSegment("去色带", "deband", listOf("关" to "off", "低" to "low", "中" to "medium", "高" to "high")),
                advancedSegment("锐化", "sharpen", listOf("关" to "off", "低" to "low", "中" to "medium", "高" to "high")),
                advancedSegment("降噪", "denoise", listOf("关" to "off", "低" to "low", "中" to "medium")),
                advancedSegment("缩放算法", "scale_profile", listOf("均衡" to "balanced", "高速" to "fast", "高质" to "quality")),
                advancedSegment("HDR", "hdr_mode", listOf("自动" to "auto", "映射SDR" to "sdr_map", "保守" to "conservative", "增强" to "enhanced")),
                advancedSegment("色调映射", "tone_mapping", listOf("自动" to "auto", "bt2390" to "bt2390", "mobius" to "mobius", "hable" to "hable", "reinhard" to "reinhard")),
                advancedSegment("补帧", "frame_interpolation", listOf("关" to "off", "自动" to "auto", "开" to "on")),
            ),
        )
        addPanelRow(panelSectionHeader("同步 / 缓存 / 兼容"))
        addPanelRow(
            panelCardGroup(
                advancedSegment("视频同步", "video_sync", listOf("自动" to "auto", "音频" to "audio", "刷新率" to "display", "平滑" to "smooth")),
                advancedSegment("缓存策略", "cache_profile", listOf("默认" to "default", "稳定" to "stable", "网络" to "network", "低延迟" to "low_latency")),
                advancedSegment("缓存大小", "cache_size_mb", listOf("自动" to "auto", "64M" to "64", "128M" to "128", "256M" to "256", "512M" to "512")),
                advancedSegment("兼容模式", "compatibility_profile", listOf("默认" to "default", "保守" to "conservative", "软解兜底" to "software_fallback")),
            ),
        )
    }

    private fun advancedSegment(label: String, key: String, opts: List<Pair<String, String>>, disabled: Boolean = false): View {
        val cur = mpvAdvanced[key] ?: opts.first().second
        val view = panelSegment(label, opts.map { it.first }, opts.indexOfFirst { it.second == cur }.coerceAtLeast(0)) { i ->
            if (disabled) {
                showTransientHint("直通输出中，该项不可用")
                return@panelSegment
            }
            mpvAdvanced[key] = opts[i].second
            commitMpvAdvanced()
            renderTopPanel()
        }
        if (disabled) view.alpha = 0.4f
        return view
    }

    private fun buildTrackInfoPage() {
        fun infoRow(label: String, value: String): View? {
            if (value.isBlank()) return null
            return LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(16), dp(12), dp(16), dp(12))
                addView(TextView(context).apply {
                    text = label; setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                }, LinearLayout.LayoutParams(dp(96), LinearLayout.LayoutParams.WRAP_CONTENT))
                addView(TextView(context).apply {
                    text = value; setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            }
        }
        val w = (loadArgsMap["videoWidth"] as? Number)?.toInt() ?: 0
        val h = (loadArgsMap["videoHeight"] as? Number)?.toInt() ?: 0
        val bitDepth = (loadArgsMap["bitDepth"] as? Number)?.toInt() ?: 0
        val bitrate = (loadArgsMap["bitrate"] as? Number)?.toLong() ?: 0L
        val videoRows = listOfNotNull(
            infoRow("分辨率", if (w > 0 && h > 0) "${w}x$h" else loadArgsMap["resolution"]?.toString().orEmpty()),
            infoRow("编码", loadArgsMap["videoCodecName"]?.toString().orEmpty()),
            infoRow("Profile", loadArgsMap["videoProfile"]?.toString().orEmpty()),
            infoRow("色彩空间", loadArgsMap["colorSpace"]?.toString().orEmpty()),
            infoRow("传递函数", loadArgsMap["colorTransfer"]?.toString().orEmpty()),
            infoRow("位深", if (bitDepth > 0) "${bitDepth}bit" else ""),
            infoRow("码率", if (bitrate > 0) "${bitrate / 1000} kbps" else ""),
        )
        if (videoRows.isNotEmpty()) {
            addPanelRow(panelSectionHeader("视频"))
            addPanelRow(panelCardGroup(*videoRows.toTypedArray()))
        }
        val audios = trackList("audioTracks")
        if (audios.isNotEmpty()) {
            val rows = audios.mapNotNull { infoRow("·", trackLabel(it).replace("\n", " ")) }
            addPanelRow(panelSectionHeader("音轨"))
            addPanelRow(panelCardGroup(*rows.toTypedArray()))
        }
        val subs = trackList("subtitleTracks")
        if (subs.isNotEmpty()) {
            val rows = subs.mapNotNull { infoRow("·", trackLabel(it).replace("\n", " ")) }
            addPanelRow(panelSectionHeader("字幕"))
            addPanelRow(panelCardGroup(*rows.toTypedArray()))
        }

        // 解码 / 输出诊断（从内核诊断 map 读取，空则整段跳过）
        val diag = runCatching { playerSurface.getPlaybackDiagnostics() }.getOrDefault(emptyMap())
        if (diag.isEmpty()) return
        val pipeline = when (val cp = diag["colorPipeline"]?.toString()) {
            "SDR" -> "SDR"
            "HDR_TONEMAP_SDR" -> "HDR→SDR 映射"
            "HDR_DIRECT" -> "HDR 直出"
            else -> cp.orEmpty()
        }
        val windowMode = diag["windowColorMode"]?.toString().orEmpty()
        val pipelineText = pipeline + if (windowMode.isNotEmpty()) " · 窗口 $windowMode" else ""
        val passthrough = diag["audioPassthrough"] == true
        val audioCodec = diag["audioCodec"]?.toString().orEmpty()
        val audioOutChannels = diag["audioOutChannels"]?.toString().orEmpty()
        val audioOut = if (passthrough) {
            "直通" + if (audioCodec.isNotEmpty()) "($audioCodec)" else ""
        } else {
            val fmt = diag["audioFormat"]?.toString().orEmpty()
            buildString {
                append("PCM 解码")
                if (fmt.isNotEmpty()) append(" · $fmt")
                if (audioOutChannels.isNotEmpty()) append(" · $audioOutChannels")
            }
        }
        val dropped = (diag["droppedFrames"] as? Number)?.toLong() ?: 0L
        val decDropped = (diag["decoderDroppedFrames"] as? Number)?.toLong() ?: 0L
        val containerFps = (diag["containerFps"] as? Number)?.toDouble() ?: 0.0
        val fallback = if (diag["fallbackTriggered"] == true) {
            diag["fallbackReason"]?.toString()?.takeIf { it.isNotBlank() } ?: "已触发"
        } else {
            "无"
        }
        val hwdec = diag["hwdecCurrent"]?.toString()?.takeIf { it.isNotEmpty() } ?: "软解"
        val spatial = AudioSpatializerSupport.probe(this).summary()
        val diagRows = listOfNotNull(
            infoRow("硬解", hwdec),
            infoRow("色彩管线", pipelineText),
            infoRow("自动回退", fallback),
            infoRow("音频输出", audioOut),
            infoRow("空间音频", spatial),
            infoRow("丢帧", "$dropped" + if (decDropped > 0) " (解码 $decDropped)" else ""),
            infoRow("帧率", if (containerFps > 0.0) String.format("%.3f fps", containerFps) else ""),
        )
        if (diagRows.isEmpty()) return
        addPanelRow(panelSectionHeader("解码 / 输出诊断"))
        addPanelRow(panelCardGroup(*diagRows.toTypedArray()))
    }

    // 弹幕显示设置镜像（顶层 key 同 NativeDanmakuOverlayView.preprocessPayload）。发送时必须
    // 带完整集合 + sourceKey（避免缺省关弹幕 / 触发时间线复位），playbackSpeed 取当前实速。
    private val danmakuSettings = linkedMapOf<String, Any?>(
        "enabled" to true,
        "opacity" to 0.85,
        "density" to 1.0,
        "fontScale" to 1.0,
        "fontThickness" to 1.0,
        "speed" to 0.85,
        "displayAreaRatio" to 0.5,
        "targetFrameRateHz" to 120,
        "scrollEnabled" to true,
        "topEnabled" to true,
        "bottomEnabled" to false,
        "colorEnabled" to true,
        "hideDuplicate" to true,
        "avoidSubtitleArea" to true,
        "playbackSpeed" to 1.0,
        "sourceKey" to "",
    )

    // 在线弹幕搜索（DanDanPlay）状态
    private var danmakuSearchKeyword = ""
    private var danmakuSearchResults: List<Map<String, Any?>> = emptyList()

    // AI 动态遮罩配置镜像（键同 DanmakuDynamicOcclusionConfig.fromMap）。
    private val occlusionConfig = linkedMapOf<String, Any?>(
        "enabled" to false,
        "sampleIntervalMs" to 300L,
        "inputWidth" to 256,
        "renderTargetFrameRateHz" to 60,
        // 蒙版跟随运动（采样间用估计的画面运动外推蒙版位置）。默认关：网络源截屏路径下
        // 外推偏移过强会让蒙版漂移；关掉则蒙版在两次采样间保持上次位置。
        "motionTrackingEnabled" to false,
    )

    // 弹幕「显示外观」偏好键集（持久化；不含 enabled/sourceKey/playbackSpeed 等会话/数据键）。
    private val danmakuPrefKeys = listOf(
        "opacity", "density", "fontScale", "fontThickness", "speed",
        "displayAreaRatio", "targetFrameRateHz", "scrollEnabled", "topEnabled",
        "bottomEnabled", "colorEnabled", "hideDuplicate", "avoidSubtitleArea",
    )

    /** 换源/切集时，把新一集弹幕 payload 里带的 settings/sourceKey 并入镜像。 */
    private fun captureDanmakuSettings(payload: Map<String, Any?>) {
        for (k in danmakuSettings.keys.toList()) {
            if (payload.containsKey(k)) danmakuSettings[k] = payload[k]
        }
    }

    /** 把已存的弹幕显示偏好覆盖回镜像（本地缓存，与 Flutter 经回写保持一致；启动注入未带时兜底）。 */
    private fun applyPersistedDanmakuPrefs() {
        val defaults = LinkedHashMap<String, Any?>()
        for (k in danmakuPrefKeys) defaults[k] = danmakuSettings[k]
        val saved = settingsStore.loadMap(NativePlayerSettingsStore.KEY_DANMAKU, defaults)
        for (k in danmakuPrefKeys) danmakuSettings[k] = saved[k]
    }

    /**
     * 启动注入的 Flutter 全局弹幕显示偏好 → 覆盖本地镜像并回写本地缓存，使设置页改动在原生
     * 壳生效。与 MPV 的 [applyInjectedMpvSettings] 同模式：Flutter 弹幕设置是单一事实源，
     * 原生壳内改动经反向通道回写，双向同步。白名单只认 danmakuPrefKeys。
     */
    private fun applyInjectedDanmakuSettings() {
        val injected = loadArgsMap["danmakuDisplaySettings"] as? Map<*, *> ?: return
        var changed = false
        for (k in danmakuPrefKeys) {
            val v = injected[k] ?: continue
            danmakuSettings[k] = v
            changed = true
        }
        if (changed) persistDanmakuSettings(writeBack = false) // 注入已是 Flutter 值，无需再回写
    }

    /**
     * 返回「带 comments 的 payload + 已存显示偏好」合并副本，用于**一次性** setDanmakuPayload。
     *
     * 关键：不能先 setDanmakuPayload(comments) 再 setDanmakuSettings(prefs)——后者是不带 comments
     * 的新一轮推送，会 ++payloadGeneration，把前一条仍在后台解析的「带 comments」任务作废
     * （NativeDanmakuOverlayView.setPayload 的 generation 校验），导致弹幕永远进不了 overlay。
     */
    private fun payloadWithPersistedDanmakuPrefs(payload: Map<String, Any?>): Map<String, Any?> {
        val merged = HashMap<String, Any?>(payload)
        for (k in danmakuPrefKeys) merged[k] = danmakuSettings[k]
        return merged
    }

    private fun persistDanmakuSettings(writeBack: Boolean = true) {
        val sub = LinkedHashMap<String, Any?>()
        for (k in danmakuPrefKeys) if (danmakuSettings.containsKey(k)) sub[k] = danmakuSettings[k]
        settingsStore.saveMap(NativePlayerSettingsStore.KEY_DANMAKU, sub)
        // 回写 Flutter 全局弹幕设置（单一事实源），使设置页/Flutter 播放器同步。
        if (writeBack) NativePlayerReverseBridge.dispatch("persistDanmakuSettings", sub)
    }

    private fun applyDanmakuSettings(persist: Boolean = true) {
        danmakuSettings["playbackSpeed"] = playerSurface.state.speed
        playerSurface.setDanmakuSettings(danmakuSettings)
        if (persist) persistDanmakuSettings()
    }

    /**
     * 倍速变更后把新播放速度推给弹幕，使弹幕一起加/减速（overlay 仅改 playbackSpeed 时走平滑
     * 重锚、不重建时间线）。不能复用 [applyDanmakuSettings]：它从 `state.speed` 取值，而
     * [NativePlayerSurface.setSpeed] 是异步落到播放线程的，调用点此刻读到的还是旧速度。
     */
    private fun pushDanmakuPlaybackSpeed(speed: Double) {
        if (!this::playerSurface.isInitialized) return
        danmakuSettings["playbackSpeed"] = speed
        playerSurface.setDanmakuSettings(danmakuSettings)
    }

    private fun applyOcclusionConfig() {
        playerSurface.setDanmakuOcclusionConfig(effectiveOcclusionConfig())
    }

    /**
     * 实际下发给分割管线的遮罩配置：**分屏期间一律强制 enabled=false**，回全屏才按
     * 用户真实偏好（[occlusionConfig]）下发。
     *
     * 原因：分屏后视频输出/管线被重配，分割会话 resize 失配（日志 MNN "Can't run session
     * because not resized" + concat shape error），每帧空跑产出空蒙版纯烧 CPU；半屏画面做
     * 人像抠像也没意义。把开关收敛到「下发口」而非「暂挂标志」，可同时覆盖**分屏中途打开**
     * 遮罩的情况（仍按 false 下发，不会在分屏里把管线带坏）。回全屏后再次 apply 时，
     * 管线先经 enabled=false 的 releaseRuntime 释放、再以 enabled=true 在全屏尺寸下重建
     * 运行时，从而清掉分屏遗留的坏会话。**不动 [occlusionConfig]/持久化**。
     */
    private fun effectiveOcclusionConfig(): Map<String, Any?> {
        val split = splitSupported() && isCurrentlySplit()
        // 性能阶梯 L1：AI 遮罩(MNN 分割)是重负载,持续掉帧时一并强制关(不动持久化,降级撤销即恢复)。
        val forceOff = (split || occlusionPerfDisabled) && occlusionConfig["enabled"] == true
        return if (forceOff) {
            LinkedHashMap(occlusionConfig).apply { put("enabled", false) }
        } else {
            occlusionConfig
        }
    }

    /** 分屏状态变化后按 effective 配置重新下发（进分屏强制关、回全屏让管线在全屏尺寸下重建）。 */
    private fun syncOcclusionWithSplitState() {
        if (!this::playerSurface.isInitialized) return
        Log.d(
            "NativePlayerSplit",
            "syncOcclusion split=${splitSupported() && isCurrentlySplit()} wantEnabled=${occlusionConfig["enabled"] == true}",
        )
        applyOcclusionConfig()
    }

    private fun danmakuBool(key: String) = danmakuSettings[key] as? Boolean ?: false
    private fun danmakuFloat(key: String) = (danmakuSettings[key] as? Number)?.toFloat() ?: 0f

    private fun buildDanmakuSettingsPage() {
        addPanelRow(panelSectionHeader("显示调节"))
        val fpsOpts = listOf("30fps" to 30, "60fps" to 60, "90fps" to 90, "120fps" to 120)
        val curFps = (danmakuSettings["targetFrameRateHz"] as? Number)?.toInt() ?: 120
        addPanelRow(
            panelCardGroup(
                panelSlider("显示区域", 0.25f, 1.0f, danmakuFloat("displayAreaRatio"), steps = 75, format = { "${(it * 100).toInt()}%" }) { v ->
                    danmakuSettings["displayAreaRatio"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSlider("不透明度", 0.2f, 1.0f, danmakuFloat("opacity"), steps = 80, format = { "${(it * 100).toInt()}%" }) { v ->
                    danmakuSettings["opacity"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSlider("弹幕密度", 0.2f, 1.0f, danmakuFloat("density"), steps = 80, format = { "${(it * 100).toInt()}%" }) { v ->
                    danmakuSettings["density"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSlider("字体大小", 0.6f, 1.4f, danmakuFloat("fontScale"), steps = 80, format = { String.format("%.2fx", it) }) { v ->
                    danmakuSettings["fontScale"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSlider("字体粗细", 0.8f, 1.4f, danmakuFloat("fontThickness"), steps = 60, format = { String.format("%.2f", it) }) { v ->
                    danmakuSettings["fontThickness"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSlider("弹幕速度", 0.4f, 1.6f, danmakuFloat("speed"), steps = 120, format = { String.format("%.2f", it) }) { v ->
                    danmakuSettings["speed"] = v.toDouble(); applyDanmakuSettings()
                },
                panelSegment("渲染帧率", fpsOpts.map { it.first }, fpsOpts.indexOfFirst { it.second == curFps }.coerceAtLeast(0)) { i ->
                    danmakuSettings["targetFrameRateHz"] = fpsOpts[i].second
                    applyDanmakuSettings()
                    renderTopPanel()
                },
            ),
        )
        addPanelRow(panelSectionHeader("按弹幕类型屏蔽"))
        addPanelRow(
            panelCardGroup(
                panelToggle("滚动弹幕", danmakuBool("scrollEnabled")) { v -> danmakuSettings["scrollEnabled"] = v; applyDanmakuSettings() },
                panelToggle("顶部弹幕", danmakuBool("topEnabled")) { v -> danmakuSettings["topEnabled"] = v; applyDanmakuSettings() },
                panelToggle("底部弹幕", danmakuBool("bottomEnabled")) { v -> danmakuSettings["bottomEnabled"] = v; applyDanmakuSettings() },
                panelToggle("彩色弹幕", danmakuBool("colorEnabled")) { v -> danmakuSettings["colorEnabled"] = v; applyDanmakuSettings() },
            ),
        )
        addPanelRow(panelSectionHeader("画面防遮挡"))
        addPanelRow(
            panelCardGroup(
                panelToggle("重复弹幕隐藏", danmakuBool("hideDuplicate"), "合并高频重复内容，减少同屏密集刷屏。") { v ->
                    danmakuSettings["hideDuplicate"] = v; applyDanmakuSettings()
                },
                panelToggle("底部字幕区域防遮挡", danmakuBool("avoidSubtitleArea"), "优先避开字幕所在区域，减少弹幕压住字幕。") { v ->
                    danmakuSettings["avoidSubtitleArea"] = v; applyDanmakuSettings()
                },
                panelToggle("主体穿透遮挡", occlusionConfig["enabled"] == true, "优先使用动态蒙版扣除人物区域内的弹幕，不可用时会恢复普通弹幕。") { v ->
                    occlusionConfig["enabled"] = v
                    applyOcclusionConfig()
                    persistOcclusion()
                    renderTopPanel()
                },
            ),
        )
        if (occlusionConfig["enabled"] == true) {
            addPanelRow(panelSectionHeader("动态遮罩参数"))
            val intervalOpts = listOf("200ms" to 200L, "300ms" to 300L, "400ms" to 400L, "500ms" to 500L)
            val curInterval = (occlusionConfig["sampleIntervalMs"] as? Number)?.toLong() ?: 300L
            val widthOpts = listOf("160" to 160, "256" to 256, "320" to 320, "512" to 512)
            val curWidth = (occlusionConfig["inputWidth"] as? Number)?.toInt() ?: 256
            val maskFpsOpts = listOf("30" to 30, "60" to 60, "90" to 90, "120" to 120)
            val curMaskFps = (occlusionConfig["renderTargetFrameRateHz"] as? Number)?.toInt() ?: 60
            addPanelRow(
                panelCardGroup(
                    panelSegment("采样间隔", intervalOpts.map { it.first }, intervalOpts.indexOfFirst { it.second == curInterval }.coerceAtLeast(0)) { i ->
                        occlusionConfig["sampleIntervalMs"] = intervalOpts[i].second
                        applyOcclusionConfig()
                        persistOcclusion()
                        renderTopPanel()
                    },
                    panelSegment("输入宽度", widthOpts.map { it.first }, widthOpts.indexOfFirst { it.second == curWidth }.coerceAtLeast(0)) { i ->
                        occlusionConfig["inputWidth"] = widthOpts[i].second
                        applyOcclusionConfig()
                        persistOcclusion()
                        renderTopPanel()
                    },
                    panelSegment("遮罩帧率", maskFpsOpts.map { it.first }, maskFpsOpts.indexOfFirst { it.second == curMaskFps }.coerceAtLeast(0)) { i ->
                        occlusionConfig["renderTargetFrameRateHz"] = maskFpsOpts[i].second
                        applyOcclusionConfig()
                        persistOcclusion()
                        renderTopPanel()
                    },
                ),
            )
        }
    }

    private fun buildDanmakuSourcePage() {
        addPanelRow(panelSectionHeader("当前源"))
        val sourceKey = danmakuSettings["sourceKey"]?.toString().orEmpty()
        addPanelRow(panelCardGroup(TextView(this).apply {
            text = if (sourceKey.isNotEmpty()) sourceKey else "无（由编排层注入）"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }))
        addPanelRow(panelSectionHeader("操作"))
        addPanelRow(panelCardGroup(
            panelNavRow(if (networkOffline) "搜索弹弹play（需联网）" else "搜索弹弹play") {
                if (networkOffline) { showTransientHint("已断网，无法在线搜索弹幕"); return@panelNavRow }
                danmakuSearchKeyword = ""
                danmakuSearchResults = emptyList()
                pushPanel(PanelPage("搜索弹幕") { buildDanmakuSearchPage() })
            },
            panelNavRow("从文件导入") { pickLocalDanmakuFile() },
        ))
        addPanelRow(panelSectionHeader("已保存来源"))
        ensureFlutterDanmakuSourcesLoaded()
        val saved = loadDanmakuSourcesForCurrent()
        // 原生源身份集合，用于去重 Flutter 侧重复的在线源（同 episodeId 的 dandan）。
        val nativeIdentities = saved
            .map { danmakuSourceIdentity(it.type, it.episodeId, it.uri) }
            .toHashSet()
        val flutterRows = (flutterDanmakuSources ?: emptyList())
            .filterNot { src ->
                // dandanplay 在线源去重：Flutter sourceKey="dandan:<id>"，与原生 identity 同形。
                val key = src["sourceKey"]?.toString().orEmpty()
                key.isNotEmpty() && nativeIdentities.contains(key)
            }
        val rows = mutableListOf<View>()
        rows += saved.map { danmakuSavedSourceRow(it) }
        rows += flutterRows.map { flutterDanmakuSourceRow(it) }
        if (rows.isEmpty()) {
            val loading = flutterDanmakuSourcesLoading
            addPanelRow(panelCardGroup(TextView(this).apply {
                text = if (loading) "加载中…" else "暂无已保存来源"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPadding(dp(16), dp(16), dp(16), dp(16))
            }))
            return
        }
        addPanelRow(panelCardGroup(*rows.toTypedArray()))
    }

    /** Flutter 弹幕源库的行：随片下载/在线/本地导入。点击经反向通道加载 payload 并应用。 */
    private fun flutterDanmakuSourceRow(src: Map<String, Any?>): View {
        val sourceKey = src["sourceKey"]?.toString().orEmpty()
        val type = src["type"]?.toString().orEmpty()
        val label = src["label"]?.toString()?.takeIf { it.isNotEmpty() } ?: "弹幕源"
        val active = src["active"] == true
        val count = (src["commentCount"] as? Number)?.toInt() ?: 0
        val typeText = when (type) {
            "downloadedFile" -> "随片下载"
            "danDanPlay" -> "弹弹play 在线"
            else -> "本地导入"
        }
        val subtitle = buildString {
            append(typeText)
            if (count > 0) append(" · $count 条")
            if (active) append(" · 当前生效")
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = itemRippleBackground()
            isClickable = true
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setOnClickListener { applyFlutterDanmakuSource(sourceKey) }
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(context).apply {
                    text = label
                    setTextColor(if (active) ACCENT else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                })
                addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setPadding(0, dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
    }

    private fun applyFlutterDanmakuSource(sourceKey: String) {
        if (sourceKey.isEmpty()) return
        showCenterHint("加载弹幕中…")
        NativePlayerReverseBridge.dispatch(
            method = "loadSavedDanmakuSource",
            args = HashMap(danmakuMediaArgs()).apply { put("sourceKey", sourceKey) },
            onResult = { res ->
                runOnUiThread {
                    // Flutter 源已在自家库登记，不重复写原生 prefs；清空缓存以便下次进页刷新 active。
                    pendingDanmakuSource = null
                    flutterDanmakuSources = null
                    applyDanmakuLoadResult(res)
                }
            },
            onError = {
                runOnUiThread { hideCenterHint(); showTransientHint("弹幕加载失败") }
            },
        )
    }

    /** 已保存弹幕源行：标题 + 来源类型判断（弹弹play 在线 / 本地文件），点击重应用、✖ 删除。 */
    private fun danmakuSavedSourceRow(rec: DanmakuSource): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = itemRippleBackground()
            isClickable = true
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setOnClickListener { reapplyDanmakuSource(rec) }
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(context).apply {
                    text = rec.label
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                })
                addView(TextView(context).apply {
                    text = if (rec.type == "dandan") "弹弹play 在线" else "本地文件"
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setPadding(0, dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(context).apply {
                text = "✖"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding(dp(12), dp(4), dp(4), dp(4))
                isClickable = true
                setOnClickListener { removeDanmakuSource(rec); renderTopPanel() }
            })
        }
    }

    /** 3 级页：在线弹幕搜索（DanDanPlay）。搜索/导入走反向通道，Flutter 侧已接入。 */
    /** 搜索框默认关键词归一化：剥离「第N季 / Season N」噪声，对齐解析器的搜索口径。 */
    private fun normalizeDanmakuKeyword(raw: String): String {
        var t = raw.trim()
        if (t.isEmpty()) return t
        t = t.replace(Regex("第\\s*\\d+\\s*季"), "")
        t = t.replace(Regex("(?i)Season\\s*\\d+"), "")
        return t.trim()
    }

    /** 从文本里解析集号：「第N话/第N集」优先，其次「EP/E/Episode N」；拿不到返回 0。 */
    private fun extractEpisodeNumber(text: String?): Int {
        if (text.isNullOrBlank()) return 0
        Regex("第\\s*0*(\\d{1,4})\\s*[话話集]").find(text)?.let {
            return it.groupValues[1].toIntOrNull() ?: 0
        }
        Regex("(?:EP|E|Episode)\\s*0*(\\d{1,4})", RegexOption.IGNORE_CASE)
            .find(text)?.let { return it.groupValues[1].toIntOrNull() ?: 0 }
        return 0
    }

    /** 当前正在播放的集号：优先 loadArgs 数字字段，缺失时从标题文本解析（旧下载记录没存集号）。 */
    private fun currentEpisodeNumber(): Int {
        val n = (loadArgsMap["episodeNumber"] as? Number)?.toInt() ?: 0
        if (n > 0) return n
        val fromTitle = extractEpisodeNumber(loadArgsMap["title"]?.toString())
        if (fromTitle > 0) return fromTitle
        return extractEpisodeNumber(loadArgsMap["seriesTitle"]?.toString())
    }

    /** 搜索结果项的集号：DanDanPlay 的 episodeNumber 常为 0，集号其实藏在「第N话」标题里。 */
    private fun resultEpisodeNumber(item: Map<String, Any?>): Int {
        val n = (item["episodeNumber"] as? Number)?.toInt() ?: 0
        if (n > 0) return n
        val fromEpTitle = extractEpisodeNumber(item["episodeTitle"]?.toString())
        if (fromEpTitle > 0) return fromEpTitle
        return extractEpisodeNumber(item["subtitle"]?.toString())
    }

    private fun buildDanmakuSearchPage() {
        val seriesTitle = loadArgsMap["seriesTitle"]?.toString().orEmpty()
        val initial = danmakuSearchKeyword.ifEmpty { normalizeDanmakuKeyword(seriesTitle) }
        val input = android.widget.EditText(this).apply {
            setText(initial)
            setSelection(text?.length ?: 0)
            hint = "输入番名 / 关键词"
            setTextColor(Color.WHITE)
            setHintTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            background = glassBackground()
            setPadding(dp(12), dp(10), dp(12), dp(10))
            maxLines = 1
        }
        addPanelRow(input)
        addPanelRow(panelActionRow("搜索") {
            val keyword = input.text.toString().trim()
            if (keyword.isEmpty()) {
                showTransientHint("请输入关键词")
                return@panelActionRow
            }
            danmakuSearchKeyword = keyword
            searchDanmaku(keyword)
        })
        addPanelRow(panelSectionHeader("结果"))
        if (danmakuSearchResults.isEmpty()) {
            addPanelRow(TextView(this).apply {
                text = "输入关键词后搜索"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(12), dp(10), dp(12), dp(10))
            })
        } else {
            for (item in danmakuSearchResults) addPanelRow(danmakuResultRow(item))
        }
    }

    /** 从文件导入弹幕：SAF 选文件 → 拷到可读缓存 → 反向通道交 Flutter 解析回 payload。 */
    private fun pickLocalDanmakuFile() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("text/xml", "application/xml", "application/json", "text/plain", "*/*"),
            )
        }
        runCatching { startActivityForResult(intent, REQUEST_PICK_DANMAKU) }
            .onFailure { showTransientHint("无法打开文件选择器") }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != Activity.RESULT_OK) return
        val uri = data?.data ?: return
        when (requestCode) {
            REQUEST_PICK_DANMAKU -> handlePickedDanmakuFile(uri)
            REQUEST_PICK_SUBTITLE -> importSubtitleFromUri(uri)
        }
    }

    private fun handlePickedDanmakuFile(uri: android.net.Uri) {
        // 格式校验：弹幕只认弹弹/B站 XML、JSON。其它文件（图片、视频、随便选的）直接拦下，
        // 不再丢给 Flutter 解析后退回误导性的"没有弹幕数据"。
        val name = queryDisplayName(uri) ?: ""
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext !in DANMAKU_IMPORT_EXTENSIONS) {
            showTransientHint("仅支持 XML / JSON 弹幕文件")
            return
        }
        // 取持久 URI 读权限，"已保存来源"重启后仍可重读该文件。
        runCatching {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val label = name.ifEmpty { "本地弹幕" }
        pendingDanmakuSource = DanmakuSource(
            mediaKey = danmakuMediaKey(), type = "local", label = label,
            episodeId = 0, animeTitle = "", episodeTitle = "", episodeNumber = 0,
            uri = uri.toString(), updatedAt = System.currentTimeMillis(),
        )
        importDanmakuFromUri(uri)
    }

    private fun importDanmakuFromUri(uri: android.net.Uri) {
        showCenterHint("导入弹幕中…")
        Thread {
            val tempPath = copyUriToCache(uri)
            runOnUiThread {
                if (tempPath == null) {
                    pendingDanmakuSource = null
                    hideCenterHint(); showTransientHint("读取文件失败"); return@runOnUiThread
                }
                NativePlayerReverseBridge.dispatch(
                    method = "importDanmakuFile",
                    args = mapOf("path" to tempPath),
                    onResult = { res -> runOnUiThread { applyDanmakuLoadResult(res) } },
                    onError = { runOnUiThread { pendingDanmakuSource = null; hideCenterHint(); showTransientHint("弹幕导入失败") } },
                )
            }
        }.start()
    }

    // ---- 已保存弹幕来源（本地持久化，按 mediaKey 分组；在线源重拉 / 本地源重读 URI） ----

    private data class DanmakuSource(
        val mediaKey: String,
        val type: String, // dandan | local
        val label: String,
        val episodeId: Int,
        val animeTitle: String,
        val episodeTitle: String,
        val episodeNumber: Int,
        val uri: String,
        val updatedAt: Long,
    )

    private var pendingDanmakuSource: DanmakuSource? = null

    // Flutter 弹幕源库（随片下载/在线自动匹配注册的源）的缓存：null=未拉取，非null=已拉到。
    // 与原生 prefs 的「已保存来源」分属两套存储，弹幕源面板合并展示二者。
    private var flutterDanmakuSources: List<Map<String, Any?>>? = null
    private var flutterDanmakuSourcesLoading = false

    /** 透传给 Flutter 的媒体身份（让 Flutter 用自己的 _buildMediaKey 算 mediaKey）。 */
    private fun danmakuMediaArgs(): Map<String, Any?> = mapOf(
        "itemGuid" to loadArgsMap["itemGuid"]?.toString().orEmpty(),
        "mediaGuid" to loadArgsMap["mediaGuid"]?.toString().orEmpty(),
        "seasonGuid" to loadArgsMap["seasonGuid"]?.toString().orEmpty(),
        "seasonNumber" to ((loadArgsMap["seasonNumber"] as? Number)?.toInt() ?: 0),
        // 用 loadArgs 原始集号：与 launcher 解析弹幕时算 mediaKey 的口径一致，
        // 不能用会回退到标题解析的 currentEpisodeNumber()，否则可能算出对不上的 key。
        "episodeNumber" to ((loadArgsMap["episodeNumber"] as? Number)?.toInt() ?: 0),
        "seriesTitle" to loadArgsMap["seriesTitle"]?.toString().orEmpty(),
    )

    /** 进弹幕源页时拉一次 Flutter 弹幕源库；拿到后仅当仍停在该页时刷新。 */
    private fun ensureFlutterDanmakuSourcesLoaded() {
        if (flutterDanmakuSources != null || flutterDanmakuSourcesLoading) return
        flutterDanmakuSourcesLoading = true
        NativePlayerReverseBridge.dispatch(
            method = "listSavedDanmakuSources",
            args = danmakuMediaArgs(),
            onResult = { res ->
                runOnUiThread {
                    flutterDanmakuSourcesLoading = false
                    flutterDanmakuSources = (res as? List<*>)
                        ?.mapNotNull { it as? Map<String, Any?> }
                        ?: emptyList()
                    if (panelStack.lastOrNull()?.title == "弹幕源") renderTopPanel()
                }
            },
            onError = {
                runOnUiThread {
                    flutterDanmakuSourcesLoading = false
                    flutterDanmakuSources = emptyList()
                }
            },
        )
    }

    private fun danmakuMediaKey(): String {
        val item = loadArgsMap["itemGuid"]?.toString()?.trim().orEmpty()
        if (item.isNotEmpty()) return item
        val series = loadArgsMap["seriesTitle"]?.toString()?.trim().orEmpty()
        val ep = (loadArgsMap["episodeNumber"] as? Number)?.toInt() ?: 0
        return if (series.isNotEmpty()) "$series::$ep" else ""
    }

    private fun danmakuSourceIdentity(type: String, episodeId: Int, uri: String): String =
        if (type == "dandan") "dandan:$episodeId" else "local:$uri"

    private fun jsonToDanmakuSource(o: JSONObject): DanmakuSource = DanmakuSource(
        mediaKey = o.optString("mediaKey"), type = o.optString("type"), label = o.optString("label"),
        episodeId = o.optInt("episodeId"), animeTitle = o.optString("animeTitle"),
        episodeTitle = o.optString("episodeTitle"), episodeNumber = o.optInt("episodeNumber"),
        uri = o.optString("uri"), updatedAt = o.optLong("updatedAt"),
    )

    private fun loadDanmakuSourcesForCurrent(): List<DanmakuSource> {
        val key = danmakuMediaKey()
        if (key.isEmpty()) return emptyList()
        val raw = settingsStore.loadString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            val out = ArrayList<DanmakuSource>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("mediaKey") == key) out.add(jsonToDanmakuSource(o))
            }
            out.sortedByDescending { it.updatedAt }
        }.getOrDefault(emptyList())
    }

    private fun saveDanmakuSource(rec: DanmakuSource) {
        if (rec.mediaKey.isEmpty()) return
        val raw = settingsStore.loadString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES)
        val existing = runCatching { if (raw != null) JSONArray(raw) else JSONArray() }
            .getOrDefault(JSONArray())
        val identity = danmakuSourceIdentity(rec.type, rec.episodeId, rec.uri)
        val kept = JSONArray()
        for (i in 0 until existing.length()) {
            val o = existing.optJSONObject(i) ?: continue
            val same = o.optString("mediaKey") == rec.mediaKey &&
                danmakuSourceIdentity(o.optString("type"), o.optInt("episodeId"), o.optString("uri")) == identity
            if (!same) kept.put(o) // 去重：同 mediaKey 同来源覆盖
        }
        kept.put(JSONObject().apply {
            put("mediaKey", rec.mediaKey); put("type", rec.type); put("label", rec.label)
            put("episodeId", rec.episodeId); put("animeTitle", rec.animeTitle)
            put("episodeTitle", rec.episodeTitle); put("episodeNumber", rec.episodeNumber)
            put("uri", rec.uri); put("updatedAt", rec.updatedAt)
        })
        settingsStore.saveString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES, kept.toString())
    }

    private fun removeDanmakuSource(rec: DanmakuSource) {
        val raw = settingsStore.loadString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES) ?: return
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return
        val identity = danmakuSourceIdentity(rec.type, rec.episodeId, rec.uri)
        val kept = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val same = o.optString("mediaKey") == rec.mediaKey &&
                danmakuSourceIdentity(o.optString("type"), o.optInt("episodeId"), o.optString("uri")) == identity
            if (!same) kept.put(o)
        }
        settingsStore.saveString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES, kept.toString())
    }

    private fun reapplyDanmakuSource(rec: DanmakuSource) {
        pendingDanmakuSource = rec.copy(updatedAt = System.currentTimeMillis())
        when (rec.type) {
            "dandan" -> {
                showCenterHint("加载弹幕中…")
                NativePlayerReverseBridge.dispatch(
                    method = "loadDanmakuEpisode",
                    args = mapOf(
                        "episodeId" to rec.episodeId,
                        "animeTitle" to rec.animeTitle,
                        "episodeTitle" to rec.episodeTitle,
                        "episodeNumber" to rec.episodeNumber,
                    ),
                    onResult = { res -> runOnUiThread { applyDanmakuLoadResult(res) } },
                    onError = { runOnUiThread { pendingDanmakuSource = null; hideCenterHint(); showTransientHint("弹幕加载失败") } },
                )
            }
            "local" -> {
                val uri = runCatching { android.net.Uri.parse(rec.uri) }.getOrNull()
                if (uri == null) {
                    pendingDanmakuSource = null
                    showTransientHint("弹幕文件不可用")
                    return
                }
                importDanmakuFromUri(uri)
            }
        }
    }

    private fun copyUriToCache(uri: android.net.Uri): String? = runCatching {
        val name = queryDisplayName(uri) ?: "danmaku.xml"
        val ext = name.substringAfterLast('.', "xml").ifEmpty { "xml" }
        val dest = java.io.File(cacheDir, "imported_danmaku_${System.currentTimeMillis()}.$ext")
        contentResolver.openInputStream(uri)?.use { input ->
            java.io.FileOutputStream(dest).use { output -> input.copyTo(output) }
        } ?: return@runCatching null
        dest.absolutePath
    }.getOrNull()

    private fun queryDisplayName(uri: android.net.Uri): String? = runCatching {
        contentResolver.query(
            uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }.getOrNull()

    private fun searchDanmaku(keyword: String) {
        showCenterHint("搜索中…")
        NativePlayerReverseBridge.dispatch(
            method = "searchDanmakuSource",
            args = mapOf(
                "keyword" to keyword,
                // 手动搜索故意不传集号：让接口返回整部全集，避免合季/双季集号对不上时翻不到正确
                // 的那一集。集号只在本地用于排序/高亮（见 onResult），不收窄结果。
                "episodeNumber" to 0,
                "tmdbId" to loadArgsMap["tmdbId"]?.toString().orEmpty(),
            ),
            onResult = { result ->
                runOnUiThread {
                    hideCenterHint()
                    // 自动定位当前集：把集号 == 正在播放集的结果排到最前（稳定排序保留其余顺序）。
                    val currentEp = currentEpisodeNumber()
                    val parsed = parseDanmakuResults(result)
                    danmakuSearchResults = if (currentEp > 0) {
                        parsed.sortedByDescending { resultEpisodeNumber(it) == currentEp }
                    } else {
                        parsed
                    }
                    if (danmakuSearchResults.isEmpty()) showTransientHint("没有找到弹幕")
                    if (panelVisible) renderTopPanel()
                }
            },
            onError = { runOnUiThread { hideCenterHint(); showTransientHint("弹幕搜索失败") } },
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseDanmakuResults(result: Any?): List<Map<String, Any?>> {
        val raw = result as? List<*> ?: return emptyList()
        return raw.mapNotNull { it as? Map<String, Any?> }
    }

    private fun danmakuResultRow(item: Map<String, Any?>): View {
        val title = item["title"]?.toString()?.takeIf { it.isNotEmpty() }
            ?: item["animeTitle"]?.toString().orEmpty()
        val subtitle = item["subtitle"]?.toString().orEmpty()
        // 优先判断：搜索结果集号 == 正在播放集号 → 标「当前集」徽章，帮用户一眼定位本集弹幕源。
        val currentEp = currentEpisodeNumber()
        val isCurrent = currentEp > 0 && resultEpisodeNumber(item) == currentEp
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            isClickable = true
            background = itemRippleBackground()
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(TextView(context).apply {
                    text = title
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                if (isCurrent) {
                    addView(TextView(context).apply {
                        text = "当前集"
                        setTextColor(ACCENT)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                        setPadding(dp(8), 0, 0, 0)
                    })
                }
            })
            if (subtitle.isNotEmpty() && subtitle != title) {
                addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    setPadding(0, dp(4), 0, 0)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                })
            }
            setOnClickListener { loadDanmakuFromResult(item) }
        }
    }

    private fun loadDanmakuFromResult(item: Map<String, Any?>) {
        val episodeId = (item["episodeId"] as? Number)?.toInt() ?: 0
        if (episodeId <= 0) {
            showTransientHint("无效的弹幕集")
            return
        }
        val animeTitle = item["animeTitle"]?.toString().orEmpty()
        val episodeTitle = item["episodeTitle"]?.toString().orEmpty()
        val episodeNumber = (item["episodeNumber"] as? Number)?.toInt() ?: 0
        val label = listOf(animeTitle, episodeTitle).filter { it.isNotEmpty() }.joinToString(" · ")
            .ifEmpty { item["title"]?.toString().orEmpty().ifEmpty { "弹弹play #$episodeId" } }
        // 成功后记入「已保存来源」（在线源可靠重拉）。
        pendingDanmakuSource = DanmakuSource(
            mediaKey = danmakuMediaKey(), type = "dandan", label = label,
            episodeId = episodeId, animeTitle = animeTitle, episodeTitle = episodeTitle,
            episodeNumber = episodeNumber, uri = "", updatedAt = System.currentTimeMillis(),
        )
        showCenterHint("加载弹幕中…")
        NativePlayerReverseBridge.dispatch(
            method = "loadDanmakuEpisode",
            args = mapOf(
                "episodeId" to episodeId,
                "animeTitle" to animeTitle,
                "episodeTitle" to episodeTitle,
                "episodeNumber" to episodeNumber,
            ),
            onResult = { res -> runOnUiThread { applyDanmakuLoadResult(res) } },
            onError = { runOnUiThread { pendingDanmakuSource = null; hideCenterHint(); showTransientHint("弹幕加载失败") } },
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyDanmakuLoadResult(res: Any?) {
        hideCenterHint()
        val map = res as? Map<String, Any?>
        val path = map?.get("danmakuFile")?.toString()?.takeIf { it.isNotEmpty() }
        if (path == null) {
            pendingDanmakuSource = null
            showTransientHint("没有弹幕数据")
            return
        }
        val payload = runCatching {
            jsonObjectToMap(JSONObject(java.io.File(path).readText()))
        }.getOrNull()
        if (payload == null) {
            pendingDanmakuSource = null
            showTransientHint("弹幕读取失败")
            return
        }
        captureDanmakuSettings(payload)
        applyPersistedDanmakuPrefs() // 手动加载的弹幕也套用持久化显示偏好
        // 单次推送（comments + 偏好合并）：二次 settings 推送会 bump generation 把弹幕丢掉。
        playerSurface.setDanmakuPayload(payloadWithPersistedDanmakuPrefs(payload))
        setDanmakuEnabled(true)
        // 记入「已保存来源」
        pendingDanmakuSource?.let { saveDanmakuSource(it.copy(updatedAt = System.currentTimeMillis())) }
        pendingDanmakuSource = null
        hidePanel()
        showTransientHint("弹幕已加载")
    }

    private fun buildIntroOutroPage() {
        addPanelRow(panelToggle("启用片头片尾跳过", introOutroEnabled) { v ->
            introOutroEnabled = v; renderTopPanel()
        })
        if (introOutroEnabled) {
            addPanelRow(panelSlider("片头时长上限", 1f, 4f, introMaxMin.toFloat(), steps = 3, format = { "${it.toInt()} 分钟" }) { v ->
                introMaxMin = v.toInt()
            })
            addPanelRow(panelSlider("片尾时长上限", 1f, 4f, outroMaxMin.toFloat(), steps = 3, format = { "${it.toInt()} 分钟" }) { v ->
                outroMaxMin = v.toInt()
            })
            addPanelRow(panelSlider("跳过倒计时", 2f, 10f, skipCountdownSec.toFloat(), steps = 8, format = { "${it.toInt()} 秒" }) { v ->
                skipCountdownSec = v.toInt()
            })
        }
        addPanelRow(panelSectionHeader("当前视频"))
        // TODO(数据接入)：片头片尾时间点暂无（待 loadArgs 带 intro/outro 或反向通道检测）。
        addPanelRow(TextView(this).apply {
            text = "未检测到片头/片尾信息"
            setTextColor(TEXT_DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(12), dp(10), dp(12), dp(10))
        })
    }

    /** 书签按 itemGuid::mediaGuid 分组持久化（对齐 Flutter BookmarkStore 的 identityKey）。 */
    private fun bookmarkIdentityKey(): String {
        val item = loadArgsMap["itemGuid"]?.toString()?.trim().orEmpty()
        val media = loadArgsMap["mediaGuid"]?.toString()?.trim().orEmpty()
        return when {
            item.isNotEmpty() && media.isNotEmpty() -> "$item::$media"
            item.isNotEmpty() -> item
            else -> media
        }
    }

    private fun loadBookmarksForCurrent() {
        bookmarks.clear()
        val key = bookmarkIdentityKey()
        if (key.isEmpty()) return
        val raw = settingsStore.loadString(NativePlayerSettingsStore.KEY_BOOKMARKS) ?: return
        runCatching {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("key") != key) continue
                bookmarks.add(Bookmark(o.optLong("ts"), o.optString("note")))
            }
            bookmarks.sortBy { it.ts }
        }
    }

    private fun persistBookmarks() {
        val key = bookmarkIdentityKey()
        if (key.isEmpty()) return
        val raw = settingsStore.loadString(NativePlayerSettingsStore.KEY_BOOKMARKS)
        val existing = runCatching { if (raw != null) JSONArray(raw) else JSONArray() }
            .getOrDefault(JSONArray())
        val kept = JSONArray()
        for (i in 0 until existing.length()) {
            val o = existing.optJSONObject(i) ?: continue
            if (o.optString("key") != key) kept.put(o) // 保留其他条目的书签
        }
        for (bm in bookmarks) {
            kept.put(JSONObject().apply { put("key", key); put("ts", bm.ts); put("note", bm.note) })
        }
        settingsStore.saveString(NativePlayerSettingsStore.KEY_BOOKMARKS, kept.toString())
    }

    private fun buildBookmarkPage() {
        addPanelRow(panelActionRow("在当前位置添加书签") {
            val ts = playerSurface.state.positionMs
            bookmarks.add(Bookmark(ts, "书签 ${formatTime(ts)}"))
            bookmarks.sortBy { it.ts }
            // TODO(反向通道)：recordBookmark 持久化到 NAS / 本地库。
            renderTopPanel()
        })
        if (bookmarks.isEmpty()) {
            addPanelRow(TextView(this).apply {
                text = "暂无书签"
                setTextColor(TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(12), dp(12), dp(12), dp(12))
            })
            return
        }
        for (bm in bookmarks.toList()) {
            addPanelRow(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(10), dp(12), dp(10))
                addView(TextView(context).apply {
                    text = "${formatTime(bm.ts)}  ${bm.note}"
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    isClickable = true
                    setOnClickListener { playerSurface.seek(bm.ts); hidePanel() }
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                addView(promptButton("删除", TEXT_DIM, false) {
                    bookmarks.remove(bm); renderTopPanel()
                })
            })
        }
    }

    // ---- drawable 工厂 ----

    private fun pillBackground(): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(16).toFloat()
        setColor(PILL_BG)
    }

    private fun glassBackground(
        cornerDp: Int = 14,
        fillColor: Int = GLASS_BG,
    ): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(cornerDp).toFloat()
        setColor(fillColor)
    }

    private fun controlActionSpacer(): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(12), 1)
        }
    }

    private fun subtlePressBackground(): android.graphics.drawable.Drawable {
        return android.graphics.drawable.StateListDrawable().apply {
            val pressed = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(0x22FFFFFF)
            }
            val normal = android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
            addState(intArrayOf(android.R.attr.state_pressed), pressed)
            addState(intArrayOf(), normal)
        }
    }

    private fun scrimBackground(
        orientation: GradientDrawable.Orientation,
        edgeColor: Int,
    ): GradientDrawable = GradientDrawable(
        orientation,
        intArrayOf(edgeColor, 0x66000000, Color.TRANSPARENT),
    )

    private fun trackPiece(color: Int): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(999).toFloat()
        setColor(color)
    }

    private fun buildSeekBarTrack(): LayerDrawable {
        val trackH = dp(3)
        val bg = trackPiece(TRACK_BG)
        val buffered = ClipDrawable(
            trackPiece(TRACK_BUFFERED),
            Gravity.START,
            ClipDrawable.HORIZONTAL,
        )
        val progress = ClipDrawable(trackPiece(ACCENT), Gravity.START, ClipDrawable.HORIZONTAL)
        val layer = LayerDrawable(arrayOf(bg, buffered, progress))
        layer.setId(0, android.R.id.background)
        layer.setId(1, android.R.id.secondaryProgress)
        layer.setId(2, android.R.id.progress)
        for (i in 0 until layer.numberOfLayers) {
            layer.setLayerHeight(i, trackH)
            layer.setLayerGravity(i, Gravity.CENTER_VERTICAL)
        }
        return layer
    }

    private fun buildSeekBarThumb(): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(Color.WHITE)
        setSize(dp(16), dp(16))
    }

    // ---- 状态 → UI ----

    // 上次已处理的性能阶梯级别 + 弹幕是否处于性能压制态（用于升级提示与降级恢复）。
    private var lastPerfFallbackLevel = 0
    private var danmakuPerfCapActive = false
    // L1 起临时强制关 AI 遮罩(不改用户开关、不持久化,降回 0 自动恢复)。
    private var occlusionPerfDisabled = false

    /**
     * 响应内核下发的性能阶梯级别（反应式，方案 B/C）：
     *  - 升到 1：视频已自动降画质，toast 告知用户。
     *  - 升到 1：视频已降画质 + 关视频滤镜(内核侧)，宿主再关 AI 遮罩(重负载)并 toast。
     *  - 升到 2：视频已最省仍掉帧，临时压低弹幕密度并 toast。
     *  - 升到 3：仍掉帧，内核已把 HDR 直通降为 SDR 映射，toast 告知。
     *  - 回落到 0（换源）：撤销弹幕压制、恢复 AI 遮罩，恢复用户设置。
     * 仅在级别**变化**时动作，避免重复 toast。
     */
    private fun handlePerformanceFallbackLevel(level: Int) {
        if (level == lastPerfFallbackLevel) return
        if (level > lastPerfFallbackLevel) {
            // L1 起就关掉 AI 遮罩(MNN 分割重负载)；幂等,跳级(如 0→2)也覆盖。
            if (level >= 1) disableOcclusionForPerformance()
            when (level) {
                1 -> showTransientHint("检测到持续卡顿，已自动降低画质、关闭 AI 遮罩以保流畅")
                2 -> {
                    capDanmakuForPerformance()
                    showTransientHint("卡顿仍持续，已临时降低弹幕密度")
                }
                3 -> showTransientHint("卡顿仍未缓解，已临时关闭 HDR 直通（转 SDR）以保流畅")
            }
        } else if (level == 0) {
            restoreDanmakuAfterPerformance()
            restoreOcclusionAfterPerformance()
        }
        lastPerfFallbackLevel = level
    }

    /** 方案 C：把弹幕密度临时压一半下发（不改内存设置、不持久化，换源自动恢复）。 */
    private fun capDanmakuForPerformance() {
        if (!this::playerSurface.isInitialized || danmakuPerfCapActive) return
        val current = (danmakuSettings["density"] as? Number)?.toDouble() ?: 1.0
        val capped = (current * 0.5).coerceAtLeast(0.2)
        if (capped >= current) return
        val transient = HashMap<String, Any?>(danmakuSettings)
        transient["density"] = capped
        transient["playbackSpeed"] = playerSurface.state.speed
        playerSurface.setDanmakuSettings(transient)
        danmakuPerfCapActive = true
    }

    /** 撤销弹幕性能压制，用未改动的用户设置重新下发（不持久化）。 */
    private fun restoreDanmakuAfterPerformance() {
        if (!danmakuPerfCapActive) return
        danmakuPerfCapActive = false
        if (this::playerSurface.isInitialized) applyDanmakuSettings(persist = false)
    }

    /** L1：临时强制关 AI 遮罩（经 effectiveOcclusionConfig 收敛，不改用户开关/不持久化）。 */
    private fun disableOcclusionForPerformance() {
        if (occlusionPerfDisabled) return
        occlusionPerfDisabled = true
        if (this::playerSurface.isInitialized && occlusionConfig["enabled"] == true) applyOcclusionConfig()
    }

    /** 撤销 AI 遮罩的性能强制关，按用户真实偏好重新下发。 */
    private fun restoreOcclusionAfterPerformance() {
        if (!occlusionPerfDisabled) return
        occlusionPerfDisabled = false
        if (this::playerSurface.isInitialized && occlusionConfig["enabled"] == true) applyOcclusionConfig()
    }

    private fun applyState(state: MpvPlayerState) {
        lastDurationMs = state.durationMs

        // 自适应性能阶梯反馈（级别由内核根据真实掉帧升降，强设备不掉帧则恒为 0）。
        handlePerformanceFallbackLevel(state.performanceFallbackLevel)
        // AB 循环：到达终点 B 即回跳起点 A。
        if (abRepeatMode == 2 && abLoopEndMs > abLoopStartMs &&
            state.positionMs >= abLoopEndMs
        ) {
            playerSurface.seek(abLoopStartMs)
        }
        playPauseButton.setImageResource(
            if (state.paused) R.drawable.ic_player_play else R.drawable.ic_player_pause,
        )
        durationLabel.text = formatTime(state.durationMs)
        seekBar.secondaryProgress =
            if (state.durationMs > 0) {
                (state.bufferedPositionMs * 1000 / state.durationMs).toInt().coerceIn(0, 1000)
            } else {
                0
            }
        if (!userSeeking) {
            positionLabel.text = formatTime(state.positionMs)
            seekBar.progress =
                if (state.durationMs > 0) {
                    (state.positionMs * 1000 / state.durationMs).toInt().coerceIn(0, 1000)
                } else {
                    0
                }
        }
        // statusLabel 始终可见，显隐交由父层 loadingSpinner 控制（与原版一致）；文本为空即无字。
        statusLabel.text = when {
            state.error != null -> "错误：${state.error}"
            !state.nativeLibLoaded -> state.statusText
            state.buffering -> {
                val speed = formatSpeed(state.networkSpeedBytesPerSecond)
                if (speed.isNotEmpty()) "缓冲中…  $speed" else "缓冲中…"
            }
            else -> ""
        }
        if (state.visualPlaybackReady && pendingInitialSubtitle) {
            pendingInitialSubtitle = false
            applyInitialSubtitleSelection()
        }
        if (state.visualPlaybackReady && pendingPersistedSettings) {
            pendingPersistedSettings = false
            pushPersistedSettings()
        }
        // 首帧就绪后按视频 fps 匹配刷新率（仅开启时；每源一次，此时 container-fps 已可读）。
        if (state.visualPlaybackReady && refreshRateSwitch && !refreshRateApplied) {
            refreshRateApplied = true
            applyPreferredDisplayMode("first-frame")
        }
        // 首帧后启动选集轻量预取（仅当前季一次请求）：略延迟让开播先稳定，但远短于旧的全季预取。
        // 标记位在此处置位（兼作"已排程"守卫，防止后续状态回调重复 post）。
        if (state.visualPlaybackReady && !episodePickerPrefetchStarted) {
            episodePickerPrefetchStarted = true
            bottomBar.postDelayed({ prefetchEpisodePickerData() }, 400L)
        }
        maybeUpdateMediaSession(state)
        updateOverlays(state)
        updateProgressMarkers()
    }

    /**
     * 把当前播放状态推给前台媒体服务（锁屏/通知栏/蓝牙线控控制）。
     * 节流：播停/标题/可切集变化即时推；其余仅每 ~1s 刷新一次进度，避免每帧重建前台通知。
     * 首帧就绪后才首次启动（startForegroundService 必须在前台发起，此时 Activity 仍可见）。
     */
    private fun maybeUpdateMediaSession(state: MpvPlayerState) {
        if (!mediaSessionStarted && !state.visualPlaybackReady) return
        if (!this::audioFocus.isInitialized) return
        val title = mediaTitle.ifEmpty { loadArgsMap["seriesTitle"]?.toString().orEmpty() }
        if (title.isEmpty()) return
        val canNext = hasNextEpisode()
        val now = android.os.SystemClock.elapsedRealtime()
        val changed = lastMediaPlaying != !state.paused ||
            lastMediaTitle != title ||
            lastMediaCanNext != canNext
        if (!mediaSessionStarted || changed || now - lastMediaPushElapsedMs >= 1000L) {
            lastMediaPlaying = !state.paused
            lastMediaTitle = title
            lastMediaCanNext = canNext
            lastMediaPushElapsedMs = now
            updateMediaSession(state)
        }
    }

    /**
     * 换源后首帧就绪时把初始字幕真正套用一次。内置轨虽然 controller.onFileLoaded 会按
     * subtitleTrackIndex 套，但外挂/本地初始字幕（preferExternalSubtitle 且无内置 sid）
     * 在那条路径上是空档——必须在这里主动加载，否则 mpv 退回默认内置轨（如内嵌 PGS）。
     */
    private fun applyInitialSubtitleSelection() {
        val guid = selectedSubtitleGuid
        if (guid.isEmpty()) return // 关闭/未选：交给 controller（sid=no 或默认轨）
        if (isServerManagedPlayback()) {
            // 服务端转码：内置/服务端字幕已由服务端烧录进流，不用动；但「外挂字幕」服务端不烧录
            // （reloadServerPlaySession 里 subtitleShouldUseExternalFile→空 subtitleGuid），
            // 必须在转码流上 sub-add 外挂文件，否则切到外挂字幕会「掉字幕」。
            val track = trackList("subtitleTracks")
                .firstOrNull { it["guid"]?.toString() == guid }
            if (track != null && subtitleShouldUseExternalFile(track)) {
                selectExternalSubtitle(track)
            }
            return
        }
        applySubtitleByGuid(guid)
    }

    // ---- 手势 ----

    private inner class GestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            toggleControls()
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            togglePlayPause()
            return true
        }

        override fun onLongPress(e: MotionEvent) {
            if (playerSurface.state.paused) return
            speedBoosting = true
            playerSurface.setSpeed(2.0)
            pushDanmakuPlaybackSpeed(2.0)
            showCenterHint("2x 倍速")
        }

        override fun onScroll(
            e1: MotionEvent?,
            e2: MotionEvent,
            distanceX: Float,
            distanceY: Float,
        ): Boolean {
            if (e1 == null || speedBoosting) return false
            handleScroll(e1, e2)
            return true
        }
    }

    private fun handleScroll(e1: MotionEvent, e2: MotionEvent) {
        val dx = e2.x - e1.x
        val dy = e2.y - e1.y
        val w = window.decorView.width.coerceAtLeast(1)
        val h = window.decorView.height.coerceAtLeast(1)
        if (gestureMode == 0) {
            if (abs(dx) < touchSlop && abs(dy) < touchSlop) return
            gestureMode = when {
                abs(dx) > abs(dy) -> {
                    gestureSeekStartMs = playerSurface.state.positionMs
                    cancelControlsAutoHide()
                    1
                }
                e1.x < w / 2f -> {
                    gestureBrightnessStart = currentBrightness()
                    2
                }
                else -> {
                    gestureVolumeStart =
                        audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                    3
                }
            }
        }
        when (gestureMode) {
            1 -> {
                val durationMs = lastDurationMs
                if (durationMs > 0) {
                    // 全屏宽对应 ±120 秒 seek 量。
                    val deltaMs = (dx / w * 120_000L).toLong()
                    gestureSeekTargetMs =
                        (gestureSeekStartMs + deltaMs).coerceIn(0L, durationMs)
                    showCenterHint(
                        "${formatTime(gestureSeekTargetMs)} / ${formatTime(durationMs)}",
                    )
                }
            }
            2 -> {
                val next = (gestureBrightnessStart - dy / h).coerceIn(0.01f, 1f)
                val lp = window.attributes
                lp.screenBrightness = next
                window.attributes = lp
                showCenterHint("亮度 ${(next * 100).toInt()}%")
            }
            3 -> {
                val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val next = (gestureVolumeStart - dy / h * max).toInt().coerceIn(0, max)
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0)
                showCenterHint("音量 ${next * 100 / max}%")
            }
        }
    }

    private fun onGestureEnd() {
        if (speedBoosting) {
            speedBoosting = false
            playerSurface.setSpeed(1.0)
            pushDanmakuPlaybackSpeed(1.0)
        }
        if (gestureMode == 1) {
            playerSurface.seek(gestureSeekTargetMs)
            scheduleControlsAutoHide()
        }
        gestureMode = 0
        hideCenterHint()
    }

    private fun currentBrightness(): Float {
        val value = window.attributes.screenBrightness
        return if (value >= 0f) value else 0.5f
    }

    private fun showCenterHint(text: String) {
        centerHint.removeCallbacks(transientHintHide)
        centerHint.removeCallbacks(centerHintWatchdog)
        centerHint.removeCallbacks(weakNetEscalate)
        centerHint.text = text
        centerHint.visibility = View.VISIBLE
        // 兜底：任何持续提示最多挂 15s，防止异步出口漏掉 hideCenterHint 导致常驻。
        centerHint.postDelayed(centerHintWatchdog, CENTER_HINT_WATCHDOG_MS)
    }

    private fun showTransientHint(text: String) {
        showCenterHint(text)
        centerHint.removeCallbacks(centerHintWatchdog)
        centerHint.postDelayed(transientHintHide, TRANSIENT_HINT_MS)
    }

    /** 网络加载型持续提示：弱网下超过 6s 仍未完成时自动升级文案，提示用户在等网络。 */
    private fun showNetworkLoadingHint(text: String) {
        showCenterHint(text)
        centerHint.postDelayed(weakNetEscalate, WEAK_NET_ESCALATE_MS)
    }

    private fun hideCenterHint() {
        centerHint.removeCallbacks(transientHintHide)
        centerHint.removeCallbacks(centerHintWatchdog)
        centerHint.removeCallbacks(weakNetEscalate)
        centerHint.visibility = View.GONE
    }

    // ---- 控制交互 ----

    private fun togglePlayPause() {
        if (playerSurface.state.paused) playWithFocus() else playerSurface.pause()
        scheduleControlsAutoHide()
    }

    /** 起播统一入口：先请求音频焦点再播，保证抢占/暂停恢复语义正确。 */
    private fun playWithFocus() {
        audioFocus.ensureFocus()
        playerSurface.play()
    }

    // ---- 系统媒体命令回调（来自 MediaSession/通知/PIP/蓝牙线控，已切回主线程） ----

    override fun onMediaPlay() = playWithFocus()

    override fun onMediaPause() = playerSurface.pause()

    override fun onMediaTogglePlayPause() {
        if (playerSurface.state.paused) playWithFocus() else playerSurface.pause()
    }

    override fun onMediaSeekTo(positionMs: Long) {
        playerSurface.seek(positionMs)
    }

    override fun onMediaSeekBy(deltaMs: Long) {
        val s = playerSurface.state
        val target = (s.positionMs + deltaMs).coerceIn(0L, s.durationMs.coerceAtLeast(0L))
        playerSurface.seek(target)
    }

    override fun onMediaNext() {
        if (hasNextEpisode()) playNextEpisode() else showTransientHint("已经是最后一集了")
    }

    // ---- MediaSession 前台服务推送 ----

    /** 当前会话副标题：剧集名（与单集标题不同时）。 */
    private fun mediaSubtitle(): String {
        val series = loadArgsMap["seriesTitle"]?.toString().orEmpty()
        return if (series.isNotEmpty() && series != mediaTitle) series else ""
    }

    /** 把当前播放状态推给前台服务（启动/刷新通知与媒体会话）。 */
    private fun updateMediaSession(state: MpvPlayerState) {
        val (artUrl, artAuth) = currentArtwork()
        NativePlaybackMediaService.update(
            context = this,
            title = mediaTitle.ifEmpty { loadArgsMap["seriesTitle"]?.toString().orEmpty() },
            subtitle = mediaSubtitle(),
            artworkUrl = artUrl,
            artworkAuth = artAuth,
            isPlaying = !state.paused,
            positionMs = state.positionMs,
            durationMs = state.durationMs,
            speed = state.speed.toFloat(),
            canNext = hasNextEpisode(),
        )
        mediaSessionStarted = true
    }

    // ---- PIP 参数（含 RemoteAction 播放控制 + 自动进入） ----

    private fun currentPipRatio(): Rational {
        val vw = (loadArgsMap["videoWidth"] as? Number)?.toInt() ?: 0
        val vh = (loadArgsMap["videoHeight"] as? Number)?.toInt() ?: 0
        return if (vw > 0 && vh > 0) {
            val r = vw.toDouble() / vh.toDouble()
            if (r in 0.42..2.39) Rational(vw, vh) else Rational(16, 9)
        } else {
            Rational(16, 9)
        }
    }

    private fun pipCommandIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, NativePlaybackMediaService::class.java).apply {
            this.action = action
            `package` = packageName
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    private fun pipRemoteActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val paused = playerSurface.state.paused
        val rewind = RemoteAction(
            Icon.createWithResource(this, android.R.drawable.ic_media_rew),
            "后退", "后退10秒",
            pipCommandIntent(NativeMediaCommandCoordinator.ACTION_REWIND, 41),
        )
        val playPause = if (paused) {
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_play),
                "播放", "播放",
                pipCommandIntent(NativeMediaCommandCoordinator.ACTION_PLAY, 42),
            )
        } else {
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                "暂停", "暂停",
                pipCommandIntent(NativeMediaCommandCoordinator.ACTION_PAUSE, 43),
            )
        }
        val forward = RemoteAction(
            Icon.createWithResource(this, android.R.drawable.ic_media_ff),
            "快进", "快进10秒",
            pipCommandIntent(NativeMediaCommandCoordinator.ACTION_FORWARD, 44),
        )
        return listOf(rewind, playPause, forward)
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(currentPipRatio())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setActions(pipRemoteActions())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipAutoEnter && !playerSurface.state.paused)
        }
        return builder.build()
    }

    /** 刷新 PIP 参数（播停切换时更新小窗按钮图标 + 自动进入开关）。 */
    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching { setPictureInPictureParams(buildPipParams()) }
    }

    private fun toggleControls() = setControlsVisible(!controlsVisible)

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        // 锁定态下主控制栏（顶栏/底栏）始终隐藏，只有侧边锁按钮跟随显隐。
        val showChrome = visible && !isLocked
        for (chrome in arrayOf(topBar, bottomBar)) {
            animateChromeVisibility(chrome, showChrome)
        }
        if (this::lockButton.isInitialized) {
            animateChromeVisibility(lockButton, visible)
        }
        if (visible) scheduleControlsAutoHide() else cancelControlsAutoHide()
    }

    private fun animateChromeVisibility(view: View, visible: Boolean) {
        view.animate().cancel()
        if (visible && view.visibility != View.VISIBLE) {
            view.visibility = View.VISIBLE
        }
        view.animate()
            .alpha(if (visible) 1f else 0f)
            .setDuration(CHROME_FADE_MS)
            .withEndAction { if (!visible) view.visibility = View.GONE }
            .start()
    }

    private fun scheduleControlsAutoHide() {
        cancelControlsAutoHide()
        bottomBar.postDelayed(hideControlsRunnable, CONTROLS_AUTO_HIDE_MS)
    }

    private fun cancelControlsAutoHide() {
        bottomBar.removeCallbacks(hideControlsRunnable)
    }

    // ---- 返回键 ----

    /**
     * 返回键分层处理，避免误退出播放：
     *  1. 二级面板打开 → 在面板内回退一层 / 关闭面板。
     *  2. 锁定态 → 吞掉返回键，仅亮出锁按钮提示先解锁，绝不退出。
     *  3. 其余 → 退出播放。
     *
     * 返回 true 表示已消费（不退出）。targetSdk≥35 的设备默认走预测式返回
     * （OnBackInvokedCallback），onBackPressed() 不再被调用，故两条路径都接到这里。
     */
    private fun consumeBackEvent(): Boolean {
        if (panelVisible) {
            if (panelStack.size > 1) popPanel() else hidePanel()
            return true
        }
        if (isLocked) {
            setControlsVisible(true)
            showTransientHint("已锁定，点按锁图标解锁")
            return true
        }
        return false
    }

    /** 旧设备（API < 33，或未启用预测式返回）走经典 onBackPressed。 */
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (consumeBackEvent()) return
        super.onBackPressed()
    }

    /** 新设备（API ≥ 33，targetSdk≥35 默认启用）需主动注册返回回调，否则返回键直接退出。 */
    private fun registerBackHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (backInvokedCallback != null) return
        val callback = OnBackInvokedCallback {
            if (!consumeBackEvent()) finish()
        }
        backInvokedCallback = callback
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            callback,
        )
    }

    private fun unregisterBackHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        (backInvokedCallback as? OnBackInvokedCallback)?.let {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
        }
        backInvokedCallback = null
    }

    // ---- 生命周期 ----

    override fun onStart() {
        super.onStart()
        registerBatteryReceiver()
        // 顶栏可见时回前台，刷新一次电量/网络（网络回调可能在后台被合并丢失）。
        updateSystemInfo()
    }

    override fun onStop() {
        // 真正退到后台/不可见才停周期上报（PiP 仍可见，不在此停）；退出前补写一次进度。
        stopPeriodicReport()
        reportProgress()
        unregisterBatteryReceiver()
        super.onStop()
    }

    /** 注册电量监听（粘性广播，注册即回当前电量，顶栏立刻显示真实百分比）。 */
    private fun registerBatteryReceiver() {
        if (batteryReceiverRegistered) return
        runCatching {
            registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.onSuccess { batteryReceiverRegistered = true }
    }

    private fun unregisterBatteryReceiver() {
        if (!batteryReceiverRegistered) return
        runCatching { unregisterReceiver(batteryReceiver) }
        batteryReceiverRegistered = false
    }

    override fun onPause() {
        // back/finish/切后台都会经过 onPause，覆盖退出场景：把当前进度写回 NAS。
        // 不在此停周期循环：PiP 下会走 onPause 但仍在播放，周期上报应继续；真正不可见
        // （onStop）才停。
        reportProgress()
        super.onPause()
    }

    /**
     * 把当前播放进度投递回 Flutter，由详情页 State 调 recordPlayback 写回 NAS。
     * 续播所需的静态字段（item/media/video/audio/subtitle guid、分辨率、码率、playLink）
     * 全在 loadArgsMap（source.toMap）里，连同 ts/duration 一起回传。本地源缺 mediaGuid，
     * Flutter 端会自动跳过。节流：ts 秒级未变则不重复上报。
     */
    private fun reportProgress(periodic: Boolean = false) {
        if (!this::playerSurface.isInitialized) return
        val state = playerSurface.state
        val durationSec = state.durationMs / 1000
        if (durationSec <= 0L) return
        val ts = (state.positionMs / 1000).coerceIn(0L, durationSec)
        if (ts == lastRecordedTs) return
        lastRecordedTs = ts
        val args = HashMap<String, Any?>()
        args["itemGuid"] = loadArgsMap["itemGuid"]
        args["mediaGuid"] = loadArgsMap["mediaGuid"]
        args["videoGuid"] = loadArgsMap["videoGuid"]
        // 回写「当前实际选中」的轨道（用户切过则为新值），供续播恢复到正确的音轨/字幕。
        args["audioGuid"] = selectedAudioGuid.ifEmpty { loadArgsMap["audioTrackGuid"] }
        args["subtitleGuid"] = selectedSubtitleGuid
        args["resolution"] = loadArgsMap["resolution"]
        args["bitrate"] = loadArgsMap["bitrate"]
        args["playLink"] = loadArgsMap["playLink"]
        args["ts"] = ts
        args["duration"] = durationSec
        NativePlayerReverseBridge.dispatch("recordProgress", args)
    }

    override fun onDestroy() {
        cancelControlsAutoHide()
        cancelAutoNext()
        unregisterBatteryReceiver()
        unregisterNetworkMonitor()
        unregisterBackHandler()
        // 退出即收掉前台媒体服务（锁屏/通知栏控制），不让通知与服务在后台滞留。
        if (mediaSessionStarted) NativePlaybackMediaService.stop(this)
        if (this::resumeCard.isInitialized) resumeCard.removeCallbacks(resumeHideRunnable)
        if (this::playerSurface.isInitialized) {
            playerSurface.release()
        }
        // 播放器真正销毁（非 resize；configChanges 已挡住 resize 重建）→ 清原生分屏标志，避免悬挂。
        if (isFinishing) ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
        super.onDestroy()
    }

    // ---- 工具 ----

    /** 标题优先取单集 title，退回剧集名 seriesTitle。 */
    private fun resolveTitle(loadArgs: Map<String, Any?>): String {
        val title = (loadArgs["title"] as? String)?.trim().orEmpty()
        if (title.isNotEmpty()) return title
        return (loadArgs["seriesTitle"] as? String)?.trim().orEmpty()
    }

    /** adb 测试快捷入参：`--es url "<可播放URL或本地路径>"` 即可，免去 JSON 转义。 */
    private fun simpleUrlLoadArgs(): Map<String, Any?>? {
        val url = intent?.getStringExtra("url")?.trim().orEmpty()
        if (url.isEmpty()) return null
        return mapOf("url" to url, "loadNonce" to 1, "startPositionMs" to 0L)
    }

    /** 从 Intent 指向的 JSON 文件读弹幕 payload（Flutter 端落盘的临时文件）。 */
    private fun parseJsonFile(key: String): Map<String, Any?>? {
        val path = intent?.getStringExtra(key)?.trim().orEmpty()
        if (path.isEmpty()) return null
        return runCatching {
            val text = java.io.File(path).readText()
            jsonObjectToMap(JSONObject(text))
        }.getOrNull()
    }

    private fun parseJsonExtra(key: String): Map<String, Any?>? {
        val raw = intent?.getStringExtra(key)?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return runCatching { jsonObjectToMap(JSONObject(raw)) }.getOrNull()
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        for (key in json.keys()) {
            map[key] = jsonToValue(json.get(key))
        }
        return map
    }

    private fun jsonToValue(value: Any?): Any? = when (value) {
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> (0 until value.length()).map { jsonToValue(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    private fun formatTime(ms: Long): String {
        if (ms <= 0) return "00:00"
        val totalSeconds = ms / 1000
        val seconds = totalSeconds % 60
        val minutes = (totalSeconds / 60) % 60
        val hours = totalSeconds / 3600
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    /**
     * 生成一批密集滚动测试弹幕（前 2 分钟、每 500ms 灌 4 条），用于 adb 直接验证
     * 原生壳的弹幕渲染是否 120fps 丝滑——不依赖 Flutter 弹幕拉取。
     * settings 全走默认（仅 enabled=true + 120fps），comments 用易读的 Map 格式。
     */
    private fun buildTestDanmakuPayload(): Map<String, Any?> {
        val phrases = listOf(
            "测试弹幕", "原生渲染丝滑吗", "前方高能", "哈哈哈哈哈", "2333333",
            "这画面绝了", "awsl", "名场面", "泪目了", "高能预警", "一键三连",
        )
        val comments = ArrayList<Map<String, Any?>>()
        var timeMs = 0
        var index = 0
        while (timeMs < 120_000) {
            repeat(4) {
                comments.add(
                    mapOf(
                        "text" to "${phrases[index % phrases.size]} #$index",
                        "timeMs" to timeMs,
                        "type" to "scroll",
                        "color" to Color.WHITE,
                    ),
                )
                index += 1
            }
            timeMs += 500
        }
        return mapOf(
            "enabled" to true,
            "targetFrameRateHz" to 120,
            "comments" to comments,
            "commentsMode" to "replace",
            "finalChunk" to true,
        )
    }
}
