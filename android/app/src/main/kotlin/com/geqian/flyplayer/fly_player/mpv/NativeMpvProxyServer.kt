package com.geqian.flyplayer.fly_player.mpv

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import okhttp3.Headers
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response as OkHttpResponse
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

private const val PROXY_TAG = "FlyPlayerNativeProxy"
private const val AUTHX_API_PREFIX = "/v/api/v1"
private const val AUTHX_LOGIN_PATH = "$AUTHX_API_PREFIX/login"

data class NativeProxyRegistration(
    val sessionId: String,
    val localUrl: String,
)

private data class NativeProxySession(
    val remoteUrl: String,
    val authToken: String,
    val userAgent: String,
    val disableTlsVerify: Boolean,
)

private class ProxyStreamInputStream(
    upstream: InputStream,
    private val upstreamResponse: OkHttpResponse,
) : FilterInputStream(upstream) {
    override fun close() {
        runCatching { super.close() }
        upstreamResponse.close()
    }
}

private class NativeProxyHttpStatus(
    private val statusCode: Int,
    private val reason: String,
) : NanoHTTPD.Response.IStatus {
    override fun getDescription(): String = "$statusCode $reason"

    override fun getRequestStatus(): Int = statusCode
}

private class NativeProxyHttpServer(
    private val sessions: ConcurrentHashMap<String, NativeProxySession>,
) : NanoHTTPD("127.0.0.1", 0) {
    override fun serve(session: IHTTPSession): NanoHTTPD.Response {
        val pathSegments = session.uri.trim().split('/').filter { it.isNotBlank() }
        if (pathSegments.size < 2 || pathSegments.first() != "stream") {
            return newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, MIME_PLAINTEXT, "not found")
        }
        val proxySession = sessions[pathSegments[1]]
            ?: return newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, MIME_PLAINTEXT, "expired")
        val method = session.method.name.uppercase(Locale.US)
        if (method != "GET" && method != "HEAD") {
            val response = newFixedLengthResponse(
                NanoHTTPD.Response.Status.METHOD_NOT_ALLOWED,
                MIME_PLAINTEXT,
                "method not allowed",
            )
            response.addHeader("Allow", "GET, HEAD")
            return response
        }

        val resolvedRemoteUrl = resolveRemoteUrl(
            proxySession = proxySession,
            requestUri = session.uri,
            requestQuery = session.queryParameterString,
        ) ?: return newFixedLengthResponse(
            NanoHTTPD.Response.Status.BAD_REQUEST,
            MIME_PLAINTEXT,
            "invalid upstream url",
        )
        val upstreamRequest = buildUpstreamRequest(
            proxySession = proxySession,
            resolvedRemoteUrl = resolvedRemoteUrl,
            session = session,
            method = method,
        )
            ?: return newFixedLengthResponse(
                NanoHTTPD.Response.Status.BAD_REQUEST,
                MIME_PLAINTEXT,
                "invalid upstream url",
            )
        val client = if (proxySession.disableTlsVerify) {
            UnsafeOkHttpClient.instance
        } else {
            SafeOkHttpClient.instance
        }
        return runCatching {
            client.newCall(upstreamRequest).execute()
        }.mapCatching { upstreamResponse ->
            Log.d(
                PROXY_TAG,
                "upstream method=$method range=${session.headers["range"] ?: "-"} status=${upstreamResponse.code} remote=$resolvedRemoteUrl",
            )
            buildNanoResponse(method, upstreamResponse)
        }.getOrElse { error ->
            Log.e(PROXY_TAG, "proxy request failed remote=$resolvedRemoteUrl", error)
            newFixedLengthResponse(
                NativeProxyHttpStatus(502, "Bad Gateway"),
                MIME_PLAINTEXT,
                "proxy error: ${error.message ?: error.javaClass.simpleName}",
            )
        }
    }

    private fun resolveRemoteUrl(
        proxySession: NativeProxySession,
        requestUri: String,
        requestQuery: String?,
    ): String? {
        val remoteUrl = proxySession.remoteUrl.toHttpUrlOrNull() ?: return null
        val requestPathSegments = requestUri.trim().split('/').filter { it.isNotBlank() }
        val query = requestQuery?.takeIf { it.isNotBlank() }

        if (requestPathSegments.size <= 2) {
            return remoteUrl.newBuilder().apply {
                if (query != null) {
                    encodedQuery(query)
                }
            }.build().toString()
        }

        val relativePath = requestPathSegments.drop(2).joinToString("/")
        val relativeReference = buildString {
            append(relativePath)
            if (query != null) {
                append('?')
                append(query)
            }
        }
        return remoteUrl.resolve(relativeReference)?.toString()
    }

    private fun buildUpstreamRequest(
        proxySession: NativeProxySession,
        resolvedRemoteUrl: String,
        session: IHTTPSession,
        method: String,
    ): Request? {
        val remoteUrl = resolvedRemoteUrl.toHttpUrlOrNull() ?: return null
        val requestBuilder = Request.Builder().url(remoteUrl)
        if (method == "HEAD") {
            requestBuilder.head()
        } else {
            requestBuilder.get()
        }

        val upstreamHeaders = buildSignedHeaders(
            remoteUrl = resolvedRemoteUrl,
            method = method,
            authToken = proxySession.authToken,
            userAgent = proxySession.userAgent.ifBlank {
                session.headers["user-agent"].orEmpty()
            },
            incomingRange = session.headers["range"],
        )
        requestBuilder.headers(upstreamHeaders)
        return requestBuilder.build()
    }

    private fun buildNanoResponse(method: String, upstreamResponse: OkHttpResponse): NanoHTTPD.Response {
        val body = upstreamResponse.body
        val mimeType = body?.contentType()?.toString() ?: "application/octet-stream"
        val status = NativeProxyHttpStatus(
            upstreamResponse.code,
            upstreamResponse.message.ifBlank { "Upstream" },
        )
        val response = if (method == "HEAD" || body == null) {
            upstreamResponse.close()
            newFixedLengthResponse(status, mimeType, ByteArrayInputStream(ByteArray(0)), 0)
        } else {
            val length = body.contentLength()
            val stream = ProxyStreamInputStream(body.byteStream(), upstreamResponse)
            if (length >= 0L) {
                newFixedLengthResponse(status, mimeType, stream, length)
            } else {
                newChunkedResponse(status, mimeType, stream)
            }
        }
        upstreamResponse.headers.names().forEach { name ->
            val lower = name.lowercase(Locale.US)
            if (lower == "transfer-encoding" || lower == "connection" || lower == "keep-alive") {
                return@forEach
            }
            upstreamResponse.headers.values(name).forEach { value ->
                response.addHeader(name, value)
            }
        }
        if (upstreamResponse.header("Accept-Ranges").isNullOrBlank()) {
            response.addHeader("Accept-Ranges", "bytes")
        }
        return response
    }
}

private object SafeOkHttpClient {
    val instance: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .retryOnConnectionFailure(true)
            .build()
    }
}

private object UnsafeOkHttpClient {
    val instance: OkHttpClient by lazy {
        val trustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
        }
        OkHttpClient.Builder()
            .sslSocketFactory(sslContext.socketFactory, trustManager)
            .hostnameVerifier(HostnameVerifier { _, _ -> true })
            .retryOnConnectionFailure(true)
            .build()
    }
}

object NativeMpvProxyServer {
    private val sessions = ConcurrentHashMap<String, NativeProxySession>()
    private val random = SecureRandom()
    private var server: NativeProxyHttpServer? = null

    @Synchronized
    fun register(
        remoteUrl: String,
        headers: Map<String, String>,
        disableTlsVerify: Boolean,
    ): NativeProxyRegistration {
        ensureStarted()
        val authToken = headers.entries.firstOrNull {
            it.key.equals("authorization", ignoreCase = true) ||
                it.key.equals("trim-mc-token", ignoreCase = true)
        }?.value.orEmpty()
        val userAgent = headers.entries.firstOrNull {
            it.key.equals("user-agent", ignoreCase = true)
        }?.value.orEmpty()
        val sessionId = nextSessionId()
        sessions[sessionId] = NativeProxySession(
            remoteUrl = remoteUrl,
            authToken = authToken,
            userAgent = userAgent,
            disableTlsVerify = disableTlsVerify,
        )
        val entry = remoteUrl.toHttpUrlOrNull()?.pathSegments?.lastOrNull()?.ifBlank { "stream" } ?: "stream"
        val port = server?.listeningPort ?: error("native proxy not started")
        return NativeProxyRegistration(
            sessionId = sessionId,
            localUrl = "http://127.0.0.1:$port/stream/$sessionId/$entry",
        )
    }

    fun unregister(sessionId: String?) {
        if (sessionId.isNullOrBlank()) return
        sessions.remove(sessionId)
    }

    @Synchronized
    private fun ensureStarted() {
        if (server != null) return
        server = NativeProxyHttpServer(sessions).also {
            it.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            Log.d(PROXY_TAG, "started port=${it.listeningPort}")
        }
    }

    private fun nextSessionId(): String {
        val bytes = ByteArray(12)
        random.nextBytes(bytes)
        return bytes.joinToString("") { byte ->
            (byte.toInt() and 0xff).toString(16).padStart(2, '0')
        }
    }
}

private fun buildSignedHeaders(
    remoteUrl: String,
    method: String,
    authToken: String,
    userAgent: String,
    incomingRange: String?,
): Headers {
    val url = remoteUrl.toHttpUrlOrNull()
    val path = url?.encodedPath.orEmpty()
    val range = incomingRange?.trim().takeUnless { it.isNullOrEmpty() }
        ?: if (path.startsWith("$AUTHX_API_PREFIX/media/range/")) "bytes=0-" else null
    val builder = Headers.Builder()
    if (authToken.isNotBlank()) {
        builder["Authorization"] = authToken
        builder["Trim-MC-token"] = authToken
    }
    if (userAgent.isNotBlank()) {
        builder["User-Agent"] = userAgent
    }
    if (!range.isNullOrBlank()) {
        builder["Range"] = range
    }
    if (shouldAttachAuthx(path) && authToken.isNotBlank()) {
        builder["Authx"] = buildAuthxHeader(method, path, authToken)
    }
    return builder.build()
}

private fun shouldAttachAuthx(path: String): Boolean {
    if (path.startsWith("/v/media/")) return true
    if (!path.startsWith(AUTHX_API_PREFIX)) return false
    return path != AUTHX_LOGIN_PATH
}

private fun buildAuthxHeader(method: String, path: String, authToken: String): String {
    val nonce = (100000 + SecureRandom().nextInt(900000)).toString()
    val timestamp = System.currentTimeMillis().toString()
    val payload = "{}"
    val normalizedMethod = method.uppercase(Locale.US)
    val signBase = "$normalizedMethod|$path|$payload|$nonce|$timestamp|$authToken"
    val sign = md5(signBase)
    return "nonce=$nonce&timestamp=$timestamp&sign=$sign"
}

private fun md5(value: String): String {
    val digest = MessageDigest.getInstance("MD5").digest(value.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}
