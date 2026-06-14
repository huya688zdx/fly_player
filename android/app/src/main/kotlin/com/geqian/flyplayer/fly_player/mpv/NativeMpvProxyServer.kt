package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response as OkHttpResponse
import java.io.File
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.FileInputStream
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
private const val AUTHX_PUBLIC_KEY = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
private const val AUTHX_PUBLIC_SECRET = "16CCEB3D-AB42-077D-36A1-F355324E4237"
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
    val cacheResourceKey: String?,
)

private data class NativeProxySession(
    val remoteUrl: String,
    val authToken: String,
    val userAgent: String,
    val forwardHeaders: Map<String, String>,
    val disableTlsVerify: Boolean,
    val chunkedRangeProxy: Boolean,
    val extremePlaybackEnabled: Boolean,
    val cacheResourceKey: String?,
    val cacheSession: ExtremePlaybackCacheSession?,
    val transferRateTracker: NativeProxyTransferRateTracker,
)

private data class NativeLocalContentSession(
    val context: Context,
    val uri: Uri,
    val displayName: String,
    val mimeType: String,
    val totalBytes: Long,
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
    private val cacheEntry: PersistentPlaybackCacheEntry,
    private val sessionId: String,
    private val remoteUrl: String,
) {
    private val monitor = Object()
    private val cacheFile = cacheEntry.dataFile
    private val startedAtMs = SystemClock.elapsedRealtime()
    private val cachedRanges = cacheEntry.metadata.cachedRanges.toMutableList()
    private val inFlightRanges = mutableListOf<LongRange>()
    @Volatile
    private var started = false
    @Volatile
    private var closed = false
    @Volatile
    private var completed = cacheEntry.metadata.isComplete
    @Volatile
    private var prefetchStarted = false
    @Volatile
    private var failed: Throwable? = null
    @Volatile
    private var totalBytes = cacheEntry.metadata.totalBytes
    @Volatile
    private var downloadedBytes = cacheEntry.metadata.downloadedBytes
    @Volatile
    private var mimeType = cacheEntry.metadata.mimeType.ifBlank { "application/octet-stream" }
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
        cacheEntry.rootDir.mkdirs()
        if (!cacheFile.exists()) {
            runCatching { cacheFile.createNewFile() }
        }
        cacheEntry.touch()
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
        cacheEntry.touch()
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

    fun resourceKey(): String = cacheEntry.metadata.resourceKey

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
        cacheEntry.touch()
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
                cacheEntry.updateRemoteState(totalBytes = totalBytes, mimeType = mimeType)
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
                            upstreamProxySession?.transferRateTracker?.onBytesTransferred(read)
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
            cacheEntry.updateRanges(
                ranges = cachedRanges,
                downloadedBytes = downloadedBytes,
                totalBytes = totalBytes,
                mimeType = mimeType,
                complete = completed || (totalBytes > 0L && downloadedBytes >= totalBytes),
            )
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
    private val transferRateTracker: NativeProxyTransferRateTracker,
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
        transferRateTracker.onBytesTransferred(count, now)
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

private class LocalContentInputStream(
    input: InputStream,
    private var remainingBytes: Long?,
    private val closeResource: () -> Unit,
) : FilterInputStream(input) {
    override fun read(): Int {
        val remaining = remainingBytes
        if (remaining != null && remaining <= 0L) return -1
        val result = super.read()
        if (result >= 0 && remaining != null) {
            remainingBytes = remaining - 1L
        }
        return result
    }

    override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
        val remaining = remainingBytes
        if (remaining != null && remaining <= 0L) return -1
        val cappedCount =
            if (remaining == null) {
                count
            } else {
                minOf(count.toLong(), remaining).toInt()
            }
        val result = super.read(buffer, offset, cappedCount)
        if (result > 0 && remaining != null) {
            remainingBytes = remaining - result
        }
        return result
    }

    override fun skip(byteCount: Long): Long {
        val remaining = remainingBytes
        val cappedCount =
            if (remaining == null) {
                byteCount
            } else {
                minOf(byteCount, remaining)
            }
        val skipped = super.skip(cappedCount)
        if (skipped > 0L && remaining != null) {
            remainingBytes = remaining - skipped
        }
        return skipped
    }

    override fun close() {
        runCatching { super.close() }
        runCatching { closeResource() }
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
    private val localContentSessions: ConcurrentHashMap<String, NativeLocalContentSession>,
) : NanoHTTPD("127.0.0.1", 0) {
    private val remoteMetaCache = ConcurrentHashMap<String, NativeProxyRemoteMeta>()

    override fun serve(session: IHTTPSession): NanoHTTPD.Response {
        val pathSegments = session.uri.trim().split('/').filter { it.isNotBlank() }
        if (pathSegments.size < 2) {
            return newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, MIME_PLAINTEXT, "not found")
        }
        if (pathSegments.first() == "local") {
            val localSession = localContentSessions[pathSegments[1]]
                ?: return newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, MIME_PLAINTEXT, "expired")
            return serveLocalContent(localSession, session)
        }
        if (pathSegments.first() != "stream") {
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
                proxySession = proxySession,
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

    private fun serveLocalContent(
        localSession: NativeLocalContentSession,
        session: IHTTPSession,
    ): NanoHTTPD.Response {
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
        val totalBytes = localSession.totalBytes
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
            totalBytes > 0L -> totalBytes - 1L
            else -> requestedRange?.end
        }
        val responseLength = when {
            endInclusive != null -> (endInclusive - start + 1L).coerceAtLeast(0L)
            totalBytes > 0L -> (totalBytes - start).coerceAtLeast(0L)
            else -> null
        }
        val status = if (requestedRange != null) {
            NativeProxyHttpStatus(206, "Partial Content")
        } else {
            NativeProxyHttpStatus(200, "OK")
        }
        val mimeType = localSession.mimeType.ifBlank { "application/octet-stream" }
        val response =
            if (method == "HEAD") {
                newFixedLengthResponse(status, mimeType, ByteArrayInputStream(ByteArray(0)), 0)
            } else {
                val stream = openLocalContentInputStream(localSession, start, responseLength)
                if (responseLength != null) {
                    newFixedLengthResponse(status, mimeType, stream, responseLength)
                } else {
                    newChunkedResponse(status, mimeType, stream)
                }
            }
        response.addHeader("Accept-Ranges", "bytes")
        if (requestedRange != null && endInclusive != null) {
            val totalPart = if (totalBytes > 0L) totalBytes.toString() else "*"
            response.addHeader("Content-Range", "bytes $start-$endInclusive/$totalPart")
        }
        if (responseLength != null) {
            response.addHeader("Content-Length", responseLength.toString())
        }
        return response
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
                proxySession = proxySession,
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
        proxySession: NativeProxySession,
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
                transferRateTracker = proxySession.transferRateTracker,
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
        proxySession: NativeProxySession,
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
                transferRateTracker = proxySession.transferRateTracker,
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

private fun openLocalContentInputStream(
    session: NativeLocalContentSession,
    start: Long,
    length: Long?,
): InputStream {
    val assetDescriptor = session.context.contentResolver.openAssetFileDescriptor(session.uri, "r")
    if (assetDescriptor != null) {
        val input = FileInputStream(assetDescriptor.fileDescriptor)
        return openLocalContentInputStream(
            input = input,
            start = assetDescriptor.startOffset + start.coerceAtLeast(0L),
            length = length,
            closeResource = { assetDescriptor.close() },
        )
    }
    val descriptor = session.context.contentResolver.openFileDescriptor(session.uri, "r")
        ?: throw IOException("content descriptor unavailable")
    val input = FileInputStream(descriptor.fileDescriptor)
    return openLocalContentInputStream(
        input = input,
        start = start.coerceAtLeast(0L),
        length = length,
        closeResource = { descriptor.close() },
    )
}

private fun openLocalContentInputStream(
    input: FileInputStream,
    start: Long,
    length: Long?,
    closeResource: () -> Unit,
): InputStream {
    val positioned = runCatching {
        input.channel.position(start)
        true
    }.getOrDefault(false)
    if (!positioned) {
        skipFully(input, start)
    }
    return LocalContentInputStream(
        input = BufferedInputStream(input, 256 * 1024),
        remainingBytes = length?.coerceAtLeast(0L),
        closeResource = closeResource,
    )
}

private fun skipFully(input: InputStream, byteCount: Long) {
    var remaining = byteCount.coerceAtLeast(0L)
    val buffer = ByteArray(64 * 1024)
    while (remaining > 0L) {
        val skipped = input.skip(remaining)
        if (skipped > 0L) {
            remaining -= skipped
            continue
        }
        val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
        if (read < 0) break
        remaining -= read.toLong()
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
    private val localContentSessions = ConcurrentHashMap<String, NativeLocalContentSession>()
    private val random = SecureRandom()
    private var server: NativeProxyHttpServer? = null
    @Volatile
    private var playbackCacheStore: PersistentPlaybackCacheStore? = null

    @Synchronized
    fun register(
        remoteUrl: String,
        headers: Map<String, String>,
        disableTlsVerify: Boolean,
        extremePlaybackEnabled: Boolean,
        cacheStore: PersistentPlaybackCacheStore,
        cacheDescriptor: PersistentPlaybackCacheDescriptor,
    ): NativeProxyRegistration {
        ensureStarted()
        playbackCacheStore = cacheStore
        val authToken = headers.entries.firstOrNull {
            it.key.equals("authorization", ignoreCase = true) ||
                it.key.equals("trim-mc-token", ignoreCase = true)
        }?.value.orEmpty()
        val userAgent = headers.entries.firstOrNull {
            it.key.equals("user-agent", ignoreCase = true)
        }?.value.orEmpty()
        val sessionId = nextSessionId()
        val cacheSession = if (extremePlaybackEnabled) {
            val entry = cacheStore.resolveEntry(cacheDescriptor)
            ExtremePlaybackCacheSession(
                cacheEntry = entry,
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
            cacheResourceKey = cacheSession?.resourceKey(),
            cacheSession = cacheSession,
            transferRateTracker = NativeProxyTransferRateTracker(),
        )
        cacheStore.evictIfNeeded(protectedResourceKeys = activeCacheResourceKeys())
        proxyVerboseLog {
            "register host=${remoteUrl.toHttpUrlOrNull()?.host.orEmpty()} chunked=${shouldUseChunkedRangeProxy(remoteUrl)} extreme=$extremePlaybackEnabled headers=${headers.keys.joinToString(",")}"
        }
        val entry = remoteUrl.toHttpUrlOrNull()?.pathSegments?.lastOrNull()?.ifBlank { "stream" } ?: "stream"
        val port = server?.listeningPort ?: error("native proxy not started")
        return NativeProxyRegistration(
            sessionId = sessionId,
            localUrl = "http://127.0.0.1:$port/stream/$sessionId/$entry",
            cacheResourceKey = cacheSession?.resourceKey(),
        )
    }

    @Synchronized
    fun registerLocalContent(
        context: Context,
        uri: Uri,
        displayName: String,
        mimeType: String? = null,
    ): NativeProxyRegistration {
        ensureStarted()
        val sessionId = nextSessionId()
        val appContext = context.applicationContext
        val resolvedMimeType =
            mimeType?.trim()?.takeIf { it.isNotEmpty() }
                ?: runCatching { appContext.contentResolver.getType(uri).orEmpty() }.getOrDefault("")
        val totalBytes = resolveLocalContentSize(appContext, uri)
        localContentSessions[sessionId] = NativeLocalContentSession(
            context = appContext,
            uri = uri,
            displayName = displayName.trim(),
            mimeType = resolvedMimeType.ifBlank { "application/octet-stream" },
            totalBytes = totalBytes,
        )
        val entry = sanitizeLocalContentEntry(displayName)
        val port = server?.listeningPort ?: error("native proxy not started")
        return NativeProxyRegistration(
            sessionId = sessionId,
            localUrl = "http://127.0.0.1:$port/local/$sessionId/$entry",
            cacheResourceKey = null,
        )
    }

    fun unregister(sessionId: String?) {
        if (sessionId.isNullOrBlank()) return
        sessions.remove(sessionId)?.cacheSession?.close()
        localContentSessions.remove(sessionId)
        playbackCacheStore?.evictIfNeeded(protectedResourceKeys = activeCacheResourceKeys())
    }

    fun getCacheProgress(sessionId: String?): NativeProxyCacheProgress? {
        if (sessionId.isNullOrBlank()) return null
        return sessions[sessionId]?.cacheSession?.progress()
    }

    fun getNetworkInputRateBytesPerSecond(sessionId: String?): Long? {
        if (sessionId.isNullOrBlank()) return null
        return sessions[sessionId]?.transferRateTracker?.currentBytesPerSecond()
    }

    @Synchronized
    private fun ensureStarted() {
        if (server != null) return
        server = NativeProxyHttpServer(sessions, localContentSessions).also {
            it.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            proxyVerboseLog { "started port=${it.listeningPort}" }
        }
    }

    fun clearAllCaches() {
        playbackCacheStore?.clearAll(protectedResourceKeys = activeCacheResourceKeys())
    }

    fun hasActiveSessions(): Boolean = sessions.isNotEmpty() || localContentSessions.isNotEmpty()

    fun getPersistentCacheStats(): PersistentPlaybackCacheStats =
        playbackCacheStore?.loadStats() ?: PersistentPlaybackCacheStats(0L, 0, 0)

    fun queryCachedDownloadable(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
    ): Map<String, Any?> {
        return playbackCacheStore?.queryDownloadable(
            itemGuid = itemGuid,
            mediaGuid = mediaGuid,
            videoGuid = videoGuid,
            resourceKey = resourceKey,
        ) ?: mapOf("found" to false, "code" to "not_found")
    }

    fun promoteCachedMedia(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
        targetMode: String,
        hasFileAccess: Boolean,
        context: android.content.Context,
    ): Map<String, Any?> {
        return playbackCacheStore?.promote(
            itemGuid = itemGuid,
            mediaGuid = mediaGuid,
            videoGuid = videoGuid,
            resourceKey = resourceKey,
            targetMode = targetMode,
            hasFileAccess = hasFileAccess,
            context = context,
        ) ?: mapOf("success" to false, "code" to "not_found")
    }

    private fun nextSessionId(): String {
        val bytes = ByteArray(12)
        random.nextBytes(bytes)
        return bytes.joinToString("") { byte ->
            (byte.toInt() and 0xff).toString(16).padStart(2, '0')
        }
    }

    private fun activeCacheResourceKeys(): Set<String> {
        return sessions.values.mapNotNull { it.cacheResourceKey }.toSet()
    }

    private fun resolveLocalContentSize(context: Context, uri: Uri): Long {
        if (uri.scheme.equals("file", ignoreCase = true)) {
            return File(uri.path.orEmpty()).length().coerceAtLeast(0L)
        }
        val queried = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use 0L
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (index >= 0) cursor.getLong(index).coerceAtLeast(0L) else 0L
            } ?: 0L
        }.getOrDefault(0L)
        if (queried > 0L) return queried
        return runCatching {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                descriptor.length.takeIf { it > 0L } ?: 0L
            } ?: 0L
        }.getOrDefault(0L)
    }

    private fun sanitizeLocalContentEntry(displayName: String): String {
        val normalized = displayName.trim().ifBlank { "video" }
        return normalized.replace(Regex("[^A-Za-z0-9._-]+"), "_").ifBlank { "video" }
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
        builder["Authx"] = buildAuthxHeader(method, url, path)
    }
    return builder.build()
}

private fun shouldAttachAuthx(path: String): Boolean {
    if (path.startsWith("/v/media/")) return true
    if (!path.startsWith(AUTHX_API_PREFIX)) return false
    return path != AUTHX_LOGIN_PATH
}

// 新版飞牛后端严格校验 Authx：md5("KEY_path_nonce_timestamp_payloadMd5_SECRET")。
// GET 的 payload 是按 key 排序、值取解码原文的 query 串；代理转发无请求体，其余方法取空串。
private fun buildAuthxHeader(method: String, url: HttpUrl?, path: String): String {
    val nonce = (100000 + SecureRandom().nextInt(900000)).toString()
    val timestamp = System.currentTimeMillis().toString()
    val payload = if (method.uppercase(Locale.US) == "GET" && url != null) {
        url.queryParameterNames.sorted().mapNotNull { name ->
            url.queryParameterValues(name).lastOrNull()?.let { "$name=$it" }
        }.joinToString("&")
    } else {
        ""
    }
    val signBase = listOf(
        AUTHX_PUBLIC_KEY,
        path,
        nonce,
        timestamp,
        md5(payload),
        AUTHX_PUBLIC_SECRET,
    ).joinToString("_")
    val sign = md5(signBase)
    return "nonce=$nonce&timestamp=$timestamp&sign=$sign"
}

private fun md5(value: String): String {
    val digest = MessageDigest.getInstance("MD5").digest(value.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}
