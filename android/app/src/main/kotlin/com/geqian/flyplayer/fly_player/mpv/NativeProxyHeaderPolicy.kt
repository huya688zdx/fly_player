package com.geqian.flyplayer.fly_player.mpv

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.Locale

object NativeProxyHeaderPolicy {
    private const val MAX_REDIRECTS = 5

    private val rebuiltOrBlocked = setOf(
        "authorization",
        "trim-mc-token",
        "user-agent",
        "range",
        "authx",
        "host",
        "connection",
        "keep-alive",
        "transfer-encoding",
        "te",
        "trailer",
        "upgrade",
        "proxy-authenticate",
        "proxy-authorization",
        "proxy-connection",
    )

    private val redirectStatusCodes = setOf(300, 301, 302, 303, 307, 308)
    private val validName = Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")

    fun copyForwardable(headers: Map<String, String>): Map<String, String> {
        val forwarded = linkedMapOf<String, String>()
        headers.forEach { (rawKey, rawValue) ->
            if ('\r' in rawKey || '\n' in rawKey || '\r' in rawValue || '\n' in rawValue) {
                return@forEach
            }
            val key = rawKey.trim()
            val value = rawValue.trim()
            if (key.isEmpty() || value.isEmpty() || !validName.matches(key)) return@forEach
            if (key.lowercase(Locale.US) in rebuiltOrBlocked) return@forEach
            forwarded.keys.firstOrNull { it.equals(key, ignoreCase = true) }?.let(forwarded::remove)
            forwarded[key] = value
        }
        return forwarded
    }

    @Throws(IOException::class)
    fun executeSameOriginRedirects(
        client: OkHttpClient,
        initialUrl: String,
        buildRequest: (String) -> Request?,
    ): Response {
        if (client.followRedirects || client.followSslRedirects) {
            throw IOException("redirects must be disabled on the upstream client")
        }
        val origin = initialUrl.toHttpUrlOrNull()
            ?: throw IOException("invalid upstream url")
        var currentUrl = origin
        var redirectCount = 0
        while (true) {
            val request = buildRequest(currentUrl.toString())
                ?: throw IOException("invalid upstream redirect url")
            if (!isSameOrigin(origin, request.url)) {
                throw IOException("upstream request escaped its original origin")
            }
            val response = client.newCall(request).execute()
            if (response.code !in redirectStatusCodes) return response

            val location = response.header("Location")
            val nextUrl = location?.let(currentUrl::resolve)
            if (nextUrl == null) {
                response.close()
                throw IOException("invalid upstream redirect location")
            }
            if (!isSameOrigin(origin, nextUrl)) {
                response.close()
                throw IOException("cross-origin upstream redirect rejected")
            }
            if (redirectCount >= MAX_REDIRECTS) {
                response.close()
                throw IOException("too many upstream redirects")
            }
            response.close()
            redirectCount += 1
            currentUrl = nextUrl
        }
    }

    private fun isSameOrigin(first: HttpUrl, second: HttpUrl): Boolean =
        first.scheme.equals(second.scheme, ignoreCase = true) &&
            first.host.equals(second.host, ignoreCase = true) &&
            first.port == second.port
}
