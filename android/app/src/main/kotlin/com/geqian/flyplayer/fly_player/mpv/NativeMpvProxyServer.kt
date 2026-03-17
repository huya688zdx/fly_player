package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import okhttp3.Headers
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response as OkHttpResponse
import java.io.File
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.concurrent.thread

private const val PROXY_TAG = "FlyPlayerNativeProxy"
private const val AUTHX_API_PREFIX = "/v/api/v1"
private const val AUTHX_LOGIN_PATH = "$AUTHX_API_PREFIX/login"
private const val CHUNKED_PROXY_CHUNK_SIZE = 10L * 1024L * 1024L
private const val EXTREME_PLAYBACK_DEMAND_CHUNK_SIZE = 2L * 1024L * 1024L
private const val EXTREME_PLAYBACK_PREFETCH_IDLE_MS = 1500L
private const val ENABLE_PROXY_VERBOSE_LOGS = false

private fun proxyVerboseLog(message: () -> String) {
    if (ENABLE_PROXY_VERBOSE_LOGS) {
        Log.d(PROXY_TAG, message())
    }
}

data class NativeProxyRegistration(
    val sessionId: String,
    val localUrl: String,
)

private data class NativeProxySession(
    val remoteUrl: String,
    val authToken: String,
    val userAgent: String,
    val forwardHeaders: Map<String, String>,
    val disableTlsVerify: Boolean,
    val chunkedRangeProxy: Boolean,
    val extremePlaybackEnabled: Boolean,
    val cacheSession: ExtremePlaybackCacheSession?,
)

private data class NativeProxyRemoteMeta(
    val totalSize: Long,
    val mimeType: String,
)

data class NativeProxyCacheProgress(
    val downloadedBytes: Long,
    val totalBytes: Long,
)

private class ExtremePlaybackCacheSession(
    private val cacheDir: File,
    private val sessionId: String,
    private val remoteUrl: String,
) {
    private val monitor = Object()
    private val cacheFile = cacheDir.resolve("$sessionId.cache")
    private val startedAtMs = SystemClock.elapsedRealtime()
    private val cachedRanges = mutableListOf<LongRange>()
    private val inFlightRanges = mutableListOf<LongRange>()
    @Volatile
    private var started = false
    @Volatile
    private var closed = false
    @Volatile
    private var completed = false
    @Volatile
    private var prefetchStarted = false
    @Volatile
    private var failed: Throwable? = null
    @Volatile
    private var totalBytes = -1L
    @Volatile
    private var downloadedBytes = 0L
    @Volatile
    private var mimeType = "application/octet-stream"
    @Volatile
    private var lastDemandFetchAtMs = 0L
    @Volatile
    private var upstreamClient: OkHttpClient? = null
    @Volatile
    private var upstreamProxySession: NativeProxySession? = null
    @Volatile
    private var upstreamResolvedRemoteUrl: String = remoteUrl
    @Volatile
    private var upstreamRequestBuilder: ((String, String?, String) -> Request?)? = null

    init {
        cacheDir.mkdirs()
        if (!cacheFile.exists()) {
            runCatching { cacheFile.createNewFile() }
        }
    }

    fun ensureStarted(
        client: OkHttpClient,
        proxySession: NativeProxySession,
        resolvedRemoteUrl: String,
        buildRequest: (String, String?, String) -> Request?,
    ) {
        synchronized(monitor) {
            upstreamClient = client
            upstreamProxySession = proxySession
            upstreamResolvedRemoteUrl = resolvedRemoteUrl
            upstreamRequestBuilder = buildRequest
            if (started || closed) return
            started = true
        }
        ensureMetadataFetched()
    }

    private fun startPrefetchIfNeeded() {
        if (prefetchStarted || closed) return
        synchronized(monitor) {
            if (prefetchStarted || closed) return
            prefetchStarted = true
        }
        thread(
            name = "FlyPlayerExtremeCache-$sessionId",
            isDaemon = true,
        ) {
            while (!closed) {
                if (!ensureMetadataFetched()) break
                val total = totalBytes
                if (total <= 0L) break
                val nextStart = nextMissingOffset(0L)
                if (nextStart == null || nextStart >= total) {
                    completed = true
                    synchronized(monitor) { monitor.notifyAll() }
                    proxyVerboseLog {
                        "extreme cache completed remote=$remoteUrl bytes=$downloadedBytes avgKbps=${averageKbps()}"
                    }
                    break
                }
                val demandIdleForMs = SystemClock.elapsedRealtime() - lastDemandFetchAtMs
                if (demandIdleForMs < EXTREME_PLAYBACK_PREFETCH_IDLE_MS) {
                    Thread.sleep((EXTREME_PLAYBACK_PREFETCH_IDLE_MS - demandIdleForMs).coerceAtLeast(50L))
                    continue
                }
                val fetchEnd = minOf(nextStart + CHUNKED_PROXY_CHUNK_SIZE - 1L, total - 1L)
                if (!fetchRange(nextStart, fetchEnd)) {
                    if (failed != null) break
                }
            }
        }
    }

    fun awaitMetadata(timeoutMs: Long = 3000L): Boolean {
        ensureMetadataFetched()
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        synchronized(monitor) {
            while (!closed && failed == null && totalBytes <= 0L && !completed) {
                val remaining = deadline - SystemClock.elapsedRealtime()
                if (remaining <= 0L) break
                monitor.wait(remaining.coerceAtMost(200L))
            }
        }
        return totalBytes > 0L
    }

    fun progress(): NativeProxyCacheProgress? {
        if (downloadedBytes <= 0L && totalBytes <= 0L) return null
        return NativeProxyCacheProgress(
            downloadedBytes = downloadedBytes,
            totalBytes = totalBytes,
        )
    }

    fun mimeType(): String = mimeType

    fun totalBytes(): Long = totalBytes

    fun openInputStream(start: Long, endInclusive: Long?): InputStream {
        return ExtremePlaybackCacheInputStream(
            cacheSession = this,
            start = start,
            endInclusive = endInclusive,
        )
    }

    fun ensureRangeAvailable(start: Long, endInclusive: Long?): Boolean {
        if (closed) return false
        if (!ensureMetadataFetched()) return false
        lastDemandFetchAtMs = SystemClock.elapsedRealtime()
        val total = totalBytes
        if (total > 0L && start >= total) return false
        val normalizedEnd =
            when {
                endInclusive != null && total > 0L -> minOf(endInclusive, total - 1L)
                endInclusive != null -> endInclusive
                total > 0L -> minOf(start + EXTREME_PLAYBACK_DEMAND_CHUNK_SIZE - 1L, total - 1L)
                else -> start + EXTREME_PLAYBACK_DEMAND_CHUNK_SIZE - 1L
            }
        var attempts = 0
        while (!closed && failed == null) {
            if (availableBytesFrom(start, normalizedEnd) > 0L) {
                startPrefetchIfNeeded()
                return true
            }
            val missingStart = firstMissingOffset(start, normalizedEnd) ?: run {
                startPrefetchIfNeeded()
                return true
            }
            val fetchEnd =
                if (total > 0L) {
                    minOf(
                        missingStart + EXTREME_PLAYBACK_DEMAND_CHUNK_SIZE - 1L,
                        total - 1L,
                        normalizedEnd,
                    )
                } else {
                    minOf(
                        missingStart + EXTREME_PLAYBACK_DEMAND_CHUNK_SIZE - 1L,
                        normalizedEnd,
                    )
                }
            if (!fetchRange(missingStart, fetchEnd)) {
                return availableBytesFrom(start, normalizedEnd) > 0L
            }
            attempts += 1
            if (attempts >= 8 && availableBytesFrom(start, normalizedEnd) <= 0L) {
                return false
            }
        }
        startPrefetchIfNeeded()
        return availableBytesFrom(start, normalizedEnd) > 0L
    }

    fun availableBytesFrom(position: Long, endInclusive: Long? = null): Long {
        synchronized(monitor) {
            val containingRange = cachedRanges.firstOrNull { position in it } ?: return 0L
            val cappedEnd =
                if (endInclusive == null) {
                    containingRange.last
                } else {
                    minOf(containingRange.last, endInclusive)
                }
            return (cappedEnd - position + 1L).coerceAtLeast(0L)
        }
    }

    fun isCompleted(): Boolean = completed

    fun failure(): Throwable? = failed

    fun cacheFile(): File = cacheFile

    fun close() {
        closed = true
        synchronized(monitor) {
            monitor.notifyAll()
        }
        runCatching { cacheFile.delete() }
    }

    private fun fail(error: Throwable) {
        failed = error
        proxyVerboseLog { "extreme cache failed remote=$remoteUrl error=${error.message}" }
        synchronized(monitor) {
            monitor.notifyAll()
        }
    }

    private fun ensureMetadataFetched(): Boolean {
        if (totalBytes > 0L) return true
        if (failed != null || closed) return false
        return fetchRange(0L, 2047L)
    }

    private fun fetchRange(start: Long, endInclusive: Long): Boolean {
        if (closed) return false
        val safeEnd = endInclusive.coerceAtLeast(start)
        synchronized(monitor) {
            while (!closed && failed == null && isRangeInFlight(start, safeEnd)) {
                monitor.wait(150L)
            }
            if (closed) return false
            if (isRangeCovered(start, safeEnd)) return true
            inFlightRanges += start..safeEnd
        }
        var wroteAny = false
        try {
            val client = upstreamClient ?: return false
            val buildRequest = upstreamRequestBuilder ?: return false
            val resolvedRemoteUrl = upstreamResolvedRemoteUrl
            val request =
                buildRequest(
                    resolvedRemoteUrl,
                    "bytes=$start-$safeEnd",
                    "GET",
                ) ?: return false
            val response =
                runCatching { client.newCall(request).execute() }
                    .onFailure(::fail)
                    .getOrNull() ?: return false
            response.use { upstream ->
                if (!upstream.isSuccessful) {
                    fail(IOException("upstream status=${upstream.code}"))
                    return false
                }
                val body = upstream.body
                if (body == null) {
                    fail(IOException("empty upstream body"))
                    return false
                }
                mimeType = body.contentType()?.toString() ?: mimeType
                totalBytes =
                    parseTotalSizeFromContentRange(upstream.header("Content-Range").orEmpty()) ?:
                    body.contentLength().takeIf { it > 0L }?.let { contentLength ->
                        when {
                            upstream.code == 206 -> safeEnd + 1L
                            else -> contentLength
                        }
                    } ?:
                    totalBytes
                val writeStart =
                    parseRangeStartFromContentRange(upstream.header("Content-Range").orEmpty()) ?: start
                val buffer = ByteArray(256 * 1024)
                var writePosition = writeStart
                RandomAccessFile(cacheFile, "rw").use { output ->
                    BufferedInputStream(body.byteStream(), 256 * 1024).use { input ->
                        while (!closed) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            if (read == 0) continue
                            output.seek(writePosition)
                            output.write(buffer, 0, read)
                            writePosition += read.toLong()
                            wroteAny = true
                        }
                    }
                }
                if (wroteAny && writePosition > writeStart) {
                    mergeCachedRange(writeStart, writePosition - 1L)
                    if (totalBytes > 0L && nextMissingOffset(0L) == null) {
                        completed = true
                    }
                }
                return wroteAny
            }
        } finally {
            synchronized(monitor) {
                inFlightRanges.removeAll { it.first == start && it.last == safeEnd }
                monitor.notifyAll()
            }
        }
    }

    private fun isRangeCovered(start: Long, endInclusive: Long): Boolean {
        synchronized(monitor) {
            return cachedRanges.any { start >= it.first && endInclusive <= it.last }
        }
    }

    private fun firstMissingOffset(start: Long, endInclusive: Long): Long? {
        synchronized(monitor) {
            var cursor = start
            val sortedRanges = cachedRanges.sortedBy { it.first }
            for (range in sortedRanges) {
                if (range.last < cursor) continue
                if (range.first > cursor) return cursor
                cursor = maxOf(cursor, range.last + 1L)
                if (cursor > endInclusive) return null
            }
            return if (cursor <= endInclusive) cursor else null
        }
    }

    private fun isRangeInFlight(start: Long, endInclusive: Long): Boolean {
        return inFlightRanges.any { inflight ->
            inflight.first <= endInclusive && inflight.last >= start
        }
    }

    private fun nextMissingOffset(start: Long): Long? {
        val total = totalBytes
        if (total <= 0L) return start
        return firstMissingOffset(start, total - 1L)
    }

    private fun mergeCachedRange(start: Long, endInclusive: Long) {
        synchronized(monitor) {
            var mergedStart = start
            var mergedEnd = endInclusive
            val iterator = cachedRanges.iterator()
            while (iterator.hasNext()) {
                val existing = iterator.next()
                if (existing.last + 1L < mergedStart || existing.first - 1L > mergedEnd) {
                    continue
                }
                mergedStart = minOf(mergedStart, existing.first)
                mergedEnd = maxOf(mergedEnd, existing.last)
                iterator.remove()
            }
            cachedRanges += mergedStart..mergedEnd
            cachedRanges.sortBy { it.first }
            downloadedBytes = cachedRanges.sumOf { it.last - it.first + 1L }
        }
    }

    private fun parseRangeStartFromContentRange(contentRange: String): Long? {
        if (!contentRange.startsWith("bytes ", ignoreCase = true)) return null
        val value = contentRange.removePrefix("bytes ").trim()
        val slashIndex = value.indexOf('/')
        if (slashIndex <= 0) return null
        val dashIndex = value.indexOf('-')
        if (dashIndex <= 0 || dashIndex >= slashIndex) return null
        return value.substring(0, dashIndex).trim().toLongOrNull()
    }

    private fun averageKbps(): Long {
        val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(1L)
        return (downloadedBytes * 1000L / elapsedMs) / 1024L
    }
}

private class ExtremePlaybackCacheInputStream(
    private val cacheSession: ExtremePlaybackCacheSession,
    start: Long,
    private val endInclusive: Long?,
) : InputStream() {
    private val reader = RandomAccessFile(cacheSession.cacheFile(), "r")
    private var position = start.coerceAtLeast(0L)

    override fun read(): Int {
        val single = ByteArray(1)
        val count = read(single, 0, 1)
        return if (count <= 0) -1 else single[0].toInt() and 0xff
    }

    override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
        if (count <= 0) return 0
        if (endInclusive != null && position > endInclusive) return -1
        while (true) {
            val available = cacheSession.availableBytesFrom(position, endInclusive)
            if (available > 0L) {
                val remaining = if (endInclusive == null) {
                    Long.MAX_VALUE
                } else {
                    (endInclusive - position + 1L).coerceAtLeast(0L)
                }
                val toRead = minOf(count.toLong(), available, remaining).toInt()
                if (toRead <= 0) return -1
                reader.seek(position)
                val read = reader.read(buffer, offset, toRead)
                if (read <= 0) continue
                position += read.toLong()
                return read
            }
            cacheSession.failure()?.let { throw IOException(it.message ?: "cache prefetch failed", it) }
            if (cacheSession.isCompleted()) {
                return -1
            }
            if (!cacheSession.ensureRangeAvailable(position, endInclusive)) {
                cacheSession.failure()?.let { throw IOException(it.message ?: "cache prefetch failed", it) }
                if (cacheSession.isCompleted()) return -1
                return -1
            }
        }
    }

    override fun close() {
        runCatching { reader.close() }
    }
}

private class ProxyStreamInputStream(
    upstream: InputStream,
    private val upstreamResponse: OkHttpResponse,
    private val remoteUrl: String,
) : FilterInputStream(upstream) {
    private var bytesRead = 0L
    private var startedAtMs = SystemClock.elapsedRealtime()
    private var lastLogAtMs = startedAtMs

    override fun read(): Int {
        val result = super.read()
        if (result >= 0) {
            onBytesRead(1)
        }
        return result
    }

    override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
        val result = super.read(buffer, offset, count)
        if (result > 0) {
            onBytesRead(result)
        }
        return result
    }

    private fun onBytesRead(count: Int) {
        bytesRead += count.toLong()
        val now = SystemClock.elapsedRealtime()
        if (now - lastLogAtMs < 2000L) return
        lastLogAtMs = now
        val elapsedMs = (now - startedAtMs).coerceAtLeast(1L)
        val kbps = (bytesRead * 1000L / elapsedMs) / 1024L
        proxyVerboseLog { "streaming remote=$remoteUrl bytes=$bytesRead avgKbps=$kbps" }
    }

    override fun close() {
        val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(1L)
        val kbps = (bytesRead * 1000L / elapsedMs) / 1024L
        proxyVerboseLog { "stream closed remote=$remoteUrl bytes=$bytesRead avgKbps=$kbps" }
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
    private val remoteMetaCache = ConcurrentHashMap<String, NativeProxyRemoteMeta>()

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
        if (proxySession.extremePlaybackEnabled && resolvedRemoteUrl == proxySession.remoteUrl) {
            proxyVerboseLog {
                "using extreme cache proxy method=$method range=${session.headers["range"] ?: "-"} remote=$resolvedRemoteUrl"
            }
            return serveExtremeCacheProxy(
                proxySession = proxySession,
                client = client,
                resolvedRemoteUrl = resolvedRemoteUrl,
                session = session,
                method = method,
            )
        }
        if (proxySession.chunkedRangeProxy && method == "GET") {
            proxyVerboseLog {
                "using chunked proxy method=$method host=${resolvedRemoteUrl.toHttpUrlOrNull()?.host.orEmpty()} range=${session.headers["range"] ?: "-"} remote=$resolvedRemoteUrl"
            }
            return serveChunkedRangeProxy(
                proxySession = proxySession,
                client = client,
                resolvedRemoteUrl = resolvedRemoteUrl,
                session = session,
            )
        }
        return runCatching {
            client.newCall(upstreamRequest).execute()
        }.mapCatching { upstreamResponse ->
            proxyVerboseLog {
                "upstream method=$method range=${session.headers["range"] ?: "-"} status=${upstreamResponse.code} remote=$resolvedRemoteUrl"
            }
            buildNanoResponse(
                method = method,
                upstreamResponse = upstreamResponse,
                resolvedRemoteUrl = resolvedRemoteUrl,
            )
        }.getOrElse { error ->
            proxyVerboseLog { "proxy request failed remote=$resolvedRemoteUrl error=${error.message}" }
            newFixedLengthResponse(
                NativeProxyHttpStatus(502, "Bad Gateway"),
                MIME_PLAINTEXT,
                "proxy error: ${error.message ?: error.javaClass.simpleName}",
            )
        }
    }

    private fun serveChunkedRangeProxy(
        proxySession: NativeProxySession,
        client: OkHttpClient,
        resolvedRemoteUrl: String,
        session: IHTTPSession,
    ): NanoHTTPD.Response {
        val meta = fetchRemoteMeta(proxySession, client, resolvedRemoteUrl)
            ?: return newFixedLengthResponse(
                NativeProxyHttpStatus(502, "Bad Gateway"),
                MIME_PLAINTEXT,
                "proxy error: failed to resolve remote metadata",
            )
        val requestedRange = parseRangeHeader(
            session.headers["range"] ?: proxySession.forwardHeaders["Range"] ?: "",
        ) ?: ByteRange(0L, null)
        val start = requestedRange.start.coerceAtLeast(0L)
        if (start >= meta.totalSize) {
            val response = newFixedLengthResponse(
                NativeProxyHttpStatus(416, "Requested Range Not Satisfiable"),
                MIME_PLAINTEXT,
                "range not satisfiable",
            )
            response.addHeader("Content-Range", "bytes */${meta.totalSize}")
            return response
        }
        val end = (start + CHUNKED_PROXY_CHUNK_SIZE - 1L).coerceAtMost(meta.totalSize - 1L)
        val upstreamRequest = buildUpstreamRequest(
            proxySession = proxySession,
            resolvedRemoteUrl = resolvedRemoteUrl,
            method = "GET",
            rangeOverride = "bytes=$start-$end",
        ) ?: return newFixedLengthResponse(
            NativeProxyHttpStatus(400, "Bad Request"),
            MIME_PLAINTEXT,
            "invalid upstream url",
        )
        return runCatching {
            client.newCall(upstreamRequest).execute()
        }.mapCatching { upstreamResponse ->
            proxyVerboseLog {
                "chunked upstream range=bytes=$start-$end status=${upstreamResponse.code} remote=$resolvedRemoteUrl"
            }
            buildChunkedRangeResponse(
                upstreamResponse = upstreamResponse,
                resolvedRemoteUrl = resolvedRemoteUrl,
                meta = meta,
                start = start,
                end = end,
            )
        }.getOrElse { error ->
            proxyVerboseLog {
                "chunked proxy request failed remote=$resolvedRemoteUrl error=${error.message}"
            }
            newFixedLengthResponse(
                NativeProxyHttpStatus(502, "Bad Gateway"),
                MIME_PLAINTEXT,
                "proxy error: ${error.message ?: error.javaClass.simpleName}",
            )
        }
    }

    private fun serveExtremeCacheProxy(
        proxySession: NativeProxySession,
        client: OkHttpClient,
        resolvedRemoteUrl: String,
        session: IHTTPSession,
        method: String,
    ): NanoHTTPD.Response {
        val cacheSession = proxySession.cacheSession
            ?: return newFixedLengthResponse(
                NativeProxyHttpStatus(500, "Internal Server Error"),
                MIME_PLAINTEXT,
                "extreme cache session missing",
            )
        cacheSession.ensureStarted(
            client = client,
            proxySession = proxySession,
            resolvedRemoteUrl = resolvedRemoteUrl,
        ) { remote, range, requestMethod ->
            buildUpstreamRequest(
                proxySession = proxySession,
                resolvedRemoteUrl = remote,
                method = requestMethod,
                rangeOverride = range,
            )
        }
        cacheSession.awaitMetadata()
        val totalBytes = cacheSession.totalBytes()
        val mimeType = cacheSession.mimeType()
        val requestedRange = parseRangeHeader(session.headers["range"].orEmpty())
        val start = requestedRange?.start?.coerceAtLeast(0L) ?: 0L
        if (totalBytes > 0L && start >= totalBytes) {
            val response = newFixedLengthResponse(
                NativeProxyHttpStatus(416, "Requested Range Not Satisfiable"),
                MIME_PLAINTEXT,
                "range not satisfiable",
            )
            response.addHeader("Content-Range", "bytes */$totalBytes")
            return response
        }
        val endInclusive = when {
            totalBytes > 0L && requestedRange?.end != null ->
                requestedRange.end.coerceAtMost(totalBytes - 1L)
            totalBytes > 0L && requestedRange != null -> totalBytes - 1L
            totalBytes > 0L -> totalBytes - 1L
            else -> requestedRange?.end
        }
        if (method == "HEAD") {
            val response = newFixedLengthResponse(
                if (requestedRange != null) NativeProxyHttpStatus(206, "Partial Content")
                else NativeProxyHttpStatus(200, "OK"),
                mimeType,
                ByteArrayInputStream(ByteArray(0)),
                0,
            )
            response.addHeader("Accept-Ranges", "bytes")
            if (totalBytes > 0L) {
                val responseLength = if (requestedRange != null && endInclusive != null) {
                    endInclusive - start + 1L
                } else {
                    totalBytes
                }
                response.addHeader("Content-Length", responseLength.toString())
                if (requestedRange != null && endInclusive != null) {
                    response.addHeader("Content-Range", "bytes $start-$endInclusive/$totalBytes")
                }
            }
            return response
        }
        val stream = cacheSession.openInputStream(start, endInclusive)
        val status = if (requestedRange != null) {
            NativeProxyHttpStatus(206, "Partial Content")
        } else {
            NativeProxyHttpStatus(200, "OK")
        }
        val response = if (totalBytes > 0L) {
            val responseLength = if (endInclusive != null) {
                (endInclusive - start + 1L).coerceAtLeast(0L)
            } else {
                (totalBytes - start).coerceAtLeast(0L)
            }
            newFixedLengthResponse(status, mimeType, stream, responseLength)
        } else {
            newChunkedResponse(status, mimeType, stream)
        }
        response.addHeader("Accept-Ranges", "bytes")
        if (totalBytes > 0L && requestedRange != null && endInclusive != null) {
            response.addHeader("Content-Range", "bytes $start-$endInclusive/$totalBytes")
        }
        if (totalBytes > 0L) {
            val responseLength = if (endInclusive != null) {
                (endInclusive - start + 1L).coerceAtLeast(0L)
            } else {
                (totalBytes - start).coerceAtLeast(0L)
            }
            response.addHeader("Content-Length", responseLength.toString())
        }
        return response
    }

    private fun fetchRemoteMeta(
        proxySession: NativeProxySession,
        client: OkHttpClient,
        resolvedRemoteUrl: String,
    ): NativeProxyRemoteMeta? {
        remoteMetaCache[resolvedRemoteUrl]?.let { return it }
        val request = buildUpstreamRequest(
            proxySession = proxySession,
            resolvedRemoteUrl = resolvedRemoteUrl,
            method = "GET",
            rangeOverride = "bytes=0-0",
        ) ?: return null
        val response = runCatching { client.newCall(request).execute() }.getOrNull() ?: return null
        response.use { upstreamResponse ->
            val body = upstreamResponse.body
            val mimeType = body?.contentType()?.toString() ?: "application/octet-stream"
            val contentRange = upstreamResponse.header("Content-Range").orEmpty()
            val totalSize = parseTotalSizeFromContentRange(contentRange)
                ?: body?.contentLength()?.takeIf { it > 0L }
                ?: return null
            return NativeProxyRemoteMeta(totalSize = totalSize, mimeType = mimeType).also {
                remoteMetaCache[resolvedRemoteUrl] = it
                proxyVerboseLog {
                    "resolved remote meta size=${it.totalSize} mime=${it.mimeType} remote=$resolvedRemoteUrl"
                }
            }
        }
    }

    private fun buildChunkedRangeResponse(
        upstreamResponse: OkHttpResponse,
        resolvedRemoteUrl: String,
        meta: NativeProxyRemoteMeta,
        start: Long,
        end: Long,
    ): NanoHTTPD.Response {
        val body = upstreamResponse.body
        if (body == null) {
            upstreamResponse.close()
            return newFixedLengthResponse(
                NativeProxyHttpStatus(502, "Bad Gateway"),
                MIME_PLAINTEXT,
                "proxy error: empty upstream body",
            )
        }
        val expectedLength = end - start + 1L
        val response = newFixedLengthResponse(
            NativeProxyHttpStatus(206, "Partial Content"),
            meta.mimeType,
            ProxyStreamInputStream(
                upstream = BufferedInputStream(body.byteStream(), 256 * 1024),
                upstreamResponse = upstreamResponse,
                remoteUrl = resolvedRemoteUrl,
            ),
            expectedLength,
        )
        response.addHeader("Accept-Ranges", "bytes")
        response.addHeader("Content-Range", "bytes $start-$end/${meta.totalSize}")
        response.addHeader("Content-Length", expectedLength.toString())
        upstreamResponse.headers.names().forEach { name ->
            val lower = name.lowercase(Locale.US)
            if (
                lower == "transfer-encoding" ||
                    lower == "connection" ||
                    lower == "keep-alive" ||
                    lower == "content-length" ||
                    lower == "content-range"
            ) {
                return@forEach
            }
            upstreamResponse.headers.values(name).forEach { value ->
                response.addHeader(name, value)
            }
        }
        return response
    }

    private fun resolveRemoteUrl(
        proxySession: NativeProxySession,
        requestUri: String,
        requestQuery: String?,
    ): String? {
        val remoteUrl = proxySession.remoteUrl.toHttpUrlOrNull() ?: return null
        val requestPathSegments = requestUri.trim().split('/').filter { it.isNotBlank() }
        val query = requestQuery?.takeIf { it.isNotBlank() }

        if (requestPathSegments.size <= 3) {
            return remoteUrl.newBuilder().apply {
                if (query != null) {
                    encodedQuery(query)
                }
            }.build().toString()
        }

        val relativePath = requestPathSegments.drop(3).joinToString("/")
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
        method: String,
        session: IHTTPSession? = null,
        rangeOverride: String? = null,
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
                session?.headers?.get("user-agent").orEmpty()
            },
            forwardHeaders = proxySession.forwardHeaders,
            incomingRange = rangeOverride ?: session?.headers?.get("range"),
        )
        requestBuilder.headers(upstreamHeaders)
        return requestBuilder.build()
    }

    private fun buildNanoResponse(
        method: String,
        upstreamResponse: OkHttpResponse,
        resolvedRemoteUrl: String,
    ): NanoHTTPD.Response {
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
            val stream = ProxyStreamInputStream(
                upstream = BufferedInputStream(body.byteStream(), 256 * 1024),
                upstreamResponse = upstreamResponse,
                remoteUrl = resolvedRemoteUrl,
            )
            val length = body.contentLength()
            if (length >= 0L) {
                newFixedLengthResponse(status, mimeType, stream, length)
            } else {
                newChunkedResponse(status, mimeType, stream)
            }
        }
        upstreamResponse.headers.names().forEach { name ->
            val lower = name.lowercase(Locale.US)
            if (
                lower == "transfer-encoding" ||
                    lower == "connection" ||
                    lower == "keep-alive" ||
                    lower == "content-length"
            ) {
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
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
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
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }
}

object NativeMpvProxyServer {
    private val sessions = ConcurrentHashMap<String, NativeProxySession>()
    private val cacheDirectories = ConcurrentHashMap.newKeySet<String>()
    private val random = SecureRandom()
    private var server: NativeProxyHttpServer? = null

    @Synchronized
    fun register(
        remoteUrl: String,
        headers: Map<String, String>,
        disableTlsVerify: Boolean,
        extremePlaybackEnabled: Boolean,
        cacheDir: File,
    ): NativeProxyRegistration {
        ensureStarted()
        cacheDirectories += cacheDir.absolutePath
        val authToken = headers.entries.firstOrNull {
            it.key.equals("authorization", ignoreCase = true) ||
                it.key.equals("trim-mc-token", ignoreCase = true)
        }?.value.orEmpty()
        val userAgent = headers.entries.firstOrNull {
            it.key.equals("user-agent", ignoreCase = true)
        }?.value.orEmpty()
        val sessionId = nextSessionId()
        val cacheSession = if (extremePlaybackEnabled) {
            ExtremePlaybackCacheSession(
                cacheDir = cacheDir,
                sessionId = sessionId,
                remoteUrl = remoteUrl,
            )
        } else {
            null
        }
        sessions[sessionId] = NativeProxySession(
            remoteUrl = remoteUrl,
            authToken = authToken,
            userAgent = userAgent,
            forwardHeaders = headers,
            disableTlsVerify = disableTlsVerify,
            chunkedRangeProxy = shouldUseChunkedRangeProxy(remoteUrl),
            extremePlaybackEnabled = extremePlaybackEnabled,
            cacheSession = cacheSession,
        )
        proxyVerboseLog {
            "register host=${remoteUrl.toHttpUrlOrNull()?.host.orEmpty()} chunked=${shouldUseChunkedRangeProxy(remoteUrl)} extreme=$extremePlaybackEnabled headers=${headers.keys.joinToString(",")}"
        }
        val entry = remoteUrl.toHttpUrlOrNull()?.pathSegments?.lastOrNull()?.ifBlank { "stream" } ?: "stream"
        val port = server?.listeningPort ?: error("native proxy not started")
        return NativeProxyRegistration(
            sessionId = sessionId,
            localUrl = "http://127.0.0.1:$port/stream/$sessionId/$entry",
        )
    }

    fun unregister(sessionId: String?) {
        if (sessionId.isNullOrBlank()) return
        sessions.remove(sessionId)?.cacheSession?.close()
        if (sessions.isEmpty()) {
            clearCacheDirectories()
        }
    }

    fun getCacheProgress(sessionId: String?): NativeProxyCacheProgress? {
        if (sessionId.isNullOrBlank()) return null
        return sessions[sessionId]?.cacheSession?.progress()
    }

    @Synchronized
    private fun ensureStarted() {
        if (server != null) return
        clearCacheDirectories()
        server = NativeProxyHttpServer(sessions).also {
            it.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            proxyVerboseLog { "started port=${it.listeningPort}" }
        }
    }

    fun clearAllCaches() {
        sessions.keys.toList().forEach(::unregister)
        clearCacheDirectories()
    }

    private fun nextSessionId(): String {
        val bytes = ByteArray(12)
        random.nextBytes(bytes)
        return bytes.joinToString("") { byte ->
            (byte.toInt() and 0xff).toString(16).padStart(2, '0')
        }
    }

    private fun clearCacheDirectories() {
        cacheDirectories.forEach { path ->
            runCatching {
                File(path).deleteRecursively()
                File(path).mkdirs()
            }
        }
    }
}

private data class ByteRange(
    val start: Long,
    val end: Long?,
)

private fun parseRangeHeader(value: String): ByteRange? {
    val normalized = value.trim()
    if (normalized.isEmpty()) return null
    if (!normalized.startsWith("bytes=")) return null
    val rangeValue = normalized.removePrefix("bytes=")
    val dashIndex = rangeValue.indexOf('-')
    if (dashIndex <= 0) return null
    val start = rangeValue.substring(0, dashIndex).trim().toLongOrNull() ?: return null
    val end = rangeValue.substring(dashIndex + 1).trim().takeIf { it.isNotEmpty() }?.toLongOrNull()
    return ByteRange(start = start, end = end)
}

private fun parseTotalSizeFromContentRange(contentRange: String): Long? {
    val slashIndex = contentRange.lastIndexOf('/')
    if (slashIndex < 0 || slashIndex >= contentRange.length - 1) return null
    return contentRange.substring(slashIndex + 1).trim().toLongOrNull()
}

private fun shouldUseChunkedRangeProxy(remoteUrl: String): Boolean {
    val host = remoteUrl.toHttpUrlOrNull()?.host?.lowercase(Locale.US).orEmpty()
    return host.contains("drive.quark.cn") || host.contains("quark.cn") || host.contains("uc.cn")
}

private fun buildSignedHeaders(
    remoteUrl: String,
    method: String,
    authToken: String,
    userAgent: String,
    forwardHeaders: Map<String, String>,
    incomingRange: String?,
): Headers {
    val url = remoteUrl.toHttpUrlOrNull()
    val path = url?.encodedPath.orEmpty()
    val initialRange = forwardHeaders.entries.firstOrNull {
        it.key.equals("range", ignoreCase = true)
    }?.value
    val range = incomingRange?.trim().takeUnless { it.isNullOrEmpty() } ?: initialRange
    val builder = Headers.Builder()
    forwardHeaders.entries.forEach { (key, value) ->
        if (value.isBlank()) return@forEach
        val lower = key.lowercase(Locale.US)
        if (
            lower == "authorization" ||
            lower == "trim-mc-token" ||
            lower == "user-agent" ||
            lower == "range" ||
            lower == "authx" ||
            lower == "host" ||
            lower == "connection" ||
            lower == "keep-alive" ||
            lower == "transfer-encoding" ||
            lower == "te" ||
            lower == "trailer" ||
            lower == "upgrade" ||
            lower == "proxy-authorization" ||
            lower == "proxy-connection"
        ) {
            return@forEach
        }
        builder.addUnsafeNonAscii(key, value)
    }
    if (authToken.isNotBlank()) {
        builder["Authorization"] = authToken
        builder["Trim-MC-token"] = authToken
    }
    if (userAgent.isNotBlank()) {
        builder["User-Agent"] = userAgent
    }
    builder["Accept-Encoding"] = "identity"
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
