package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.util.LinkedHashSet
import java.util.Locale

data class PlaybackTarget(
    val url: String,
    val headers: Map<String, String>,
    val disableTlsVerify: Boolean,
    val viaNativeProxy: Boolean,
)

class PlaybackSourceResolver(
    context: Context,
) {
    private val playbackCacheStore = PersistentPlaybackCacheStore(context)
    var activeProxySessionId: String? = null
        private set
    var activeProxyUrl: String? = null
        private set
    var activeCacheResourceKey: String? = null
        private set
    private var activeProxyKey: String? = null
    private val retiredProxySessionIds = LinkedHashSet<String>()

    fun prepare(source: MpvSource): PlaybackTarget {
        val cacheDescriptor = PersistentPlaybackCacheDescriptor.fromSource(source)
        val localPlayback = playbackCacheStore.findCompleteLocalPlayback(cacheDescriptor)
        if (localPlayback != null) {
            retireActiveProxy()
            return PlaybackTarget(
                url = localPlayback.filePath,
                headers = emptyMap(),
                disableTlsVerify = false,
                viaNativeProxy = false,
            )
        }
        val hasReusableCache = playbackCacheStore.hasReusableEntry(cacheDescriptor)
        if (!shouldUseNativeProxy(source, hasReusableCache)) {
            return PlaybackTarget(
                url = source.url,
                headers = source.headers,
                disableTlsVerify = shouldDisableTlsVerify(source.url, source.headers),
                viaNativeProxy = false,
            )
        }
        val registration = ensureNativeProxyRegistration(
            source = source,
            cacheDescriptor = cacheDescriptor,
            enablePlaybackCache = source.extremePlaybackEnabled || hasReusableCache,
        )
        return PlaybackTarget(
            url = registration.localUrl,
            headers = emptyMap(),
            disableTlsVerify = false,
            viaNativeProxy = true,
        )
    }

    fun releaseOnSourceChange(previousUrl: String, nextUrl: String) {
        if (previousUrl != nextUrl) {
            retireActiveProxy()
        }
    }

    fun releaseRetiredSessions() {
        if (retiredProxySessionIds.isEmpty()) return
        retiredProxySessionIds.toList().forEach { sessionId ->
            NativeMpvProxyServer.unregister(sessionId)
            retiredProxySessionIds.remove(sessionId)
        }
    }

    fun invalidateActiveProxy(localUrl: String?) {
        if (localUrl.isNullOrBlank() || localUrl != activeProxyUrl) return
        NativeMpvProxyServer.unregister(activeProxySessionId)
        activeProxySessionId = null
        activeProxyUrl = null
        activeProxyKey = null
    }

    fun release() {
        releaseRetiredSessions()
        NativeMpvProxyServer.unregister(activeProxySessionId)
        activeProxySessionId = null
        activeProxyUrl = null
        activeProxyKey = null
    }

    private fun ensureNativeProxyRegistration(
        source: MpvSource,
        cacheDescriptor: PersistentPlaybackCacheDescriptor,
        enablePlaybackCache: Boolean,
    ): NativeProxyRegistration {
        val disableTlsVerify = shouldDisableTlsVerify(source.url, source.headers)
        val key = buildString {
            append(source.url)
            append('|')
            append(disableTlsVerify)
            append('|')
            append(enablePlaybackCache)
            append('|')
            append(
                source.headers.entries
                    .sortedBy { it.key.lowercase(Locale.US) }
                    .joinToString("&") { "${it.key}=${it.value}" },
            )
        }
        if (activeProxySessionId != null && activeProxyUrl != null && activeProxyKey == key) {
            return NativeProxyRegistration(
                sessionId = activeProxySessionId!!,
                localUrl = activeProxyUrl!!,
                cacheResourceKey = activeCacheResourceKey,
            )
        }
        retireActiveProxy()
        return NativeMpvProxyServer.register(
            remoteUrl = source.url,
            headers = source.headers,
            disableTlsVerify = disableTlsVerify,
            extremePlaybackEnabled = enablePlaybackCache,
            cacheStore = playbackCacheStore,
            cacheDescriptor = cacheDescriptor,
        ).also { registration ->
            activeProxySessionId = registration.sessionId
            activeProxyUrl = registration.localUrl
            activeCacheResourceKey = registration.cacheResourceKey
            activeProxyKey = key
            Log.d("FlyPlayerMpv", "native proxy registered session=${registration.sessionId} local=${registration.localUrl}")
        }
    }

    private fun retireActiveProxy() {
        activeProxySessionId?.let(retiredProxySessionIds::add)
        activeProxySessionId = null
        activeProxyUrl = null
        activeCacheResourceKey = null
        activeProxyKey = null
    }

    private fun shouldUseNativeProxy(source: MpvSource, hasReusableCache: Boolean): Boolean {
        if (!source.forceNativeProxy && !source.extremePlaybackEnabled && !hasReusableCache) {
            return false
        }
        val uri = runCatching { java.net.URI(source.url) }.getOrNull() ?: return false
        val scheme = uri.scheme?.lowercase(Locale.US) ?: return false
        if (scheme != "http" && scheme != "https") return false
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        return host != "127.0.0.1" && host != "localhost"
    }

    fun activeBufferedPositionMs(source: MpvSource, positionMs: Long, durationMs: Long): Long? {
        if (!source.extremePlaybackEnabled || durationMs <= 0L) return null
        val progress = NativeMpvProxyServer.getCacheProgress(activeProxySessionId) ?: return null
        val totalBytes = progress.totalBytes
        if (totalBytes <= 0L) return null
        val normalizedDownloaded = progress.downloadedBytes.coerceIn(0L, totalBytes)
        val bufferedMs = (durationMs.toDouble() * normalizedDownloaded.toDouble() / totalBytes.toDouble()).toLong()
        return bufferedMs.coerceAtLeast(positionMs).coerceAtMost(durationMs)
    }

    private fun shouldDisableTlsVerify(url: String, headers: Map<String, String> = emptyMap()): Boolean {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        if (!uri.scheme.equals("https", ignoreCase = true)) return false
        val host = uri.host ?: return false
        if (isSignedCloudPlaybackUrl(uri)) {
            return true
        }
        val hasSessionAuth = headers.keys.any { key ->
            key.equals("Authorization", ignoreCase = true) ||
                key.equals("Trim-MC-token", ignoreCase = true)
        }
        if (hasSessionAuth) {
            return true
        }
        return isPrivateHost(host)
    }

    private fun isSignedCloudPlaybackUrl(uri: Uri): Boolean {
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        if (host.isEmpty()) return false
        val isTrustedSignedCloudHost =
            (host.contains(".obs.") && host.endsWith(".ctyun.cn")) ||
                host.endsWith(".ctyun.cn") ||
                host.endsWith(".ctyunapi.cn") ||
                host.endsWith(".ctyunxs.cn") ||
                host.startsWith("cloudcube.") ||
                host.contains(".cloudcube.") ||
                host.contains("telecomjs") ||
                host.contains("189cloud")
        if (!isTrustedSignedCloudHost) return false
        val hasSignatureMarkers =
            uri.getQueryParameter("X-Amz-Signature") != null ||
            uri.getQueryParameter("x-amz-signature") != null ||
            uri.getQueryParameter("X-Amz-Credential") != null ||
            uri.getQueryParameter("x-amz-credential") != null ||
            uri.getQueryParameter("X-Amz-Algorithm") != null ||
            uri.getQueryParameter("x-amz-algorithm") != null ||
            uri.getQueryParameter("X-Amz-SignedHeaders") != null ||
            uri.getQueryParameter("x-amz-signedheaders") != null ||
            uri.getQueryParameter("AWSAccessKeyId") != null ||
            uri.getQueryParameter("awsaccesskeyid") != null ||
            uri.getQueryParameter("Signature") != null ||
            uri.getQueryParameter("signature") != null ||
            uri.getQueryParameter("Expires") != null ||
            uri.getQueryParameter("expires") != null
        return hasSignatureMarkers
    }

    private fun isPrivateHost(host: String): Boolean {
        if (host == "localhost" || host == "127.0.0.1") return true
        val parts = host.split(".")
        if (parts.size != 4) return false
        val octets = mutableListOf<Int>()
        for (part in parts) {
            val octet = part.toIntOrNull() ?: return false
            octets += octet
        }
        val first = octets[0]
        val second = octets[1]
        return first == 10 ||
            first == 127 ||
            (first == 192 && second == 168) ||
            (first == 172 && second in 16..31)
    }
}
