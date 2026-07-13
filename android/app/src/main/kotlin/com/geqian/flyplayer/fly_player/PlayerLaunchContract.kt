package com.geqian.flyplayer.fly_player

import android.net.Uri
import java.security.MessageDigest
import java.util.HashMap
import java.util.Locale

object PlayerLaunchContract {
    const val MODE_FULLSCREEN = "fullscreen"
    const val MODE_SPLIT = "split"
    fun buildExternalLocalVideoLoadArgs(
        uri: Uri,
        title: String,
        sizeBytes: Long = 0L,
    ): HashMap<String, Any?> {
        val normalizedTitle = title.trim().ifEmpty { "Local Video" }
        val normalizedSizeBytes = sizeBytes.coerceAtLeast(0L)
        val stableId = externalLocalVideoId(uri, normalizedTitle, normalizedSizeBytes)
        val loadNonce = (System.currentTimeMillis() and 0x7fffffff).toInt().coerceAtLeast(1)
        return hashMapOf<String, Any?>(
                "loadNonce" to loadNonce,
                "itemGuid" to stableId,
                "seriesGuid" to "",
                "seasonGuid" to "",
                "posterPath" to "",
                "mediaGuid" to "$stableId-media",
                "mediaType" to "local",
                "ancestorName" to "",
                "videoGuid" to "$stableId-video",
                "url" to uri.toString(),
                "headers" to hashMapOf<String, String>(),
                "title" to normalizedTitle,
                "seriesTitle" to "",
                "seasonNumber" to 0,
                "tmdbId" to "",
                "episodeNumber" to 0,
                "startPositionMs" to 0L,
                "videoWidth" to 0,
                "videoHeight" to 0,
                "resolution" to "",
                "bitrate" to 0,
                "durationSeconds" to 0,
                "videoCodecName" to "",
                "videoProfile" to "",
                "colorSpace" to "",
                "colorTransfer" to "",
                "colorPrimaries" to "",
                "bitDepth" to 0,
                "isDownloadedFile" to true,
                "externalLocalSource" to true,
                "danmakuAutoSearchAllowed" to false,
                "externalLocalFileSizeBytes" to normalizedSizeBytes,
                "preferExternalSubtitle" to false,
                "forceNativeProxy" to false,
                "extremePlaybackEnabled" to false,
                "reliableSeek" to true,
                "seekProbeSummary" to "external-local",
                "playbackMode" to "originalQuality",
                "playbackSpeed" to 1.0,
                "listenVideoModeEnabled" to false,
                "audioTracks" to arrayListOf<HashMap<String, Any?>>(),
                "subtitleTracks" to arrayListOf<HashMap<String, Any?>>(),
                "qualities" to arrayListOf<HashMap<String, Any?>>(),
            )
    }

    private fun externalLocalVideoId(
        uri: Uri,
        title: String,
        sizeBytes: Long,
    ): String {
        val raw =
            listOf(
                uri.normalizeScheme().toString(),
                title.trim(),
                sizeBytes.coerceAtLeast(0L).toString(),
            ).joinToString("|")
        val digest = MessageDigest
            .getInstance("SHA-256")
            .digest(raw.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte ->
                (byte.toInt() and 0xff).toString(16).padStart(2, '0')
            }
            .lowercase(Locale.US)
        return "external-local-${digest.take(24)}"
    }

}
