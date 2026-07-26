package com.geqian.flyplayer.fly_player.mpv

import java.net.URI

data class DanmakuPlanBDecodeSource(
    val sourceUrl: String,
    val url: String,
    val headers: Map<String, String>,
    val isNetworkProxy: Boolean,
)

internal object DanmakuPlanBSourcePolicy {
    fun resolve(
        url: String,
        headers: Map<String, String>,
        networkEnabled: Boolean,
        failedUrl: String?,
    ): DanmakuPlanBDecodeSource? {
        val raw = url.trim()
        if (raw.isEmpty() || raw == failedUrl) return null
        if (raw.startsWith("/")) {
            return DanmakuPlanBDecodeSource(raw, raw, emptyMap(), isNetworkProxy = false)
        }
        if (raw.startsWith("file://")) {
            val path = runCatching { URI(raw).path }.getOrNull().orEmpty()
            return DanmakuPlanBDecodeSource(
                sourceUrl = raw,
                url = path.ifEmpty { raw.removePrefix("file://") },
                headers = emptyMap(),
                isNetworkProxy = false,
            )
        }
        if (!networkEnabled) return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() != "http") return null
        val host = uri.host?.lowercase() ?: return null
        if (host != "127.0.0.1" && host != "localhost") return null
        return DanmakuPlanBDecodeSource(raw, raw, headers.toMap(), isNetworkProxy = true)
    }
}
