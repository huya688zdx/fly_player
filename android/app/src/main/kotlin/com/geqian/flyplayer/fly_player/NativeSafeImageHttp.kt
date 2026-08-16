package com.geqian.flyplayer.fly_player

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.io.IOException

/** 图片字节下载器：敏感头请求只手动跟随同源重定向。 */
object NativeSafeImageHttp {
    const val DEFAULT_MAX_IMAGE_BYTES = 20L * 1024L * 1024L

    private val publicClient = OkHttpClient()
    private val sensitiveClient =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .build()

    fun fetchBytes(
        imageUrl: String,
        headers: Map<String, String>,
        maxBytes: Long = DEFAULT_MAX_IMAGE_BYTES,
    ): ByteArray? = newSession(imageUrl, headers, maxBytes).fetchBytes()

    fun newSession(
        imageUrl: String,
        headers: Map<String, String>,
        maxBytes: Long = DEFAULT_MAX_IMAGE_BYTES,
    ): Session = Session(imageUrl, headers, maxBytes)

    class Session internal constructor(
        private val imageUrl: String,
        headers: Map<String, String>,
        private val maxBytes: Long,
    ) {
        private val safeHeaders = NativeImageRequestHeaders.fromAny(headers)

        @Volatile
        private var activeCall: Call? = null

        @Volatile
        private var cancelled = false

        fun cancel() {
            cancelled = true
            activeCall?.cancel()
        }

        fun fetchBytes(): ByteArray? {
            if (maxBytes <= 0L || cancelled) return null
            if (safeHeaders.isEmpty()) {
                val request = Request.Builder().url(imageUrl).build()
                return execute(publicClient, request).use { response ->
                    if (response.isSuccessful) readBounded(response.body) else null
                }
            }

            var currentUrl = imageUrl
            var followedRedirects = 0
            while (!cancelled) {
                val request =
                    Request.Builder().url(currentUrl).apply {
                        safeHeaders.forEach { (key, value) -> header(key, value) }
                    }.build()
                execute(sensitiveClient, request).use { response ->
                    if (response.isSuccessful) return readBounded(response.body)
                    if (!NativeImageRedirectPolicy.isRedirect(response.code)) return null
                    if (followedRedirects >= NativeImageRedirectPolicy.MAX_REDIRECTS) return null
                    currentUrl =
                        NativeImageRedirectPolicy.resolveSameOrigin(
                            currentUrl = currentUrl,
                            location = response.header("Location"),
                        ) ?: return null
                    followedRedirects += 1
                }
            }
            return null
        }

        private fun execute(
            client: OkHttpClient,
            request: Request,
        ) = client.newCall(request).let { call ->
            activeCall = call
            if (cancelled) {
                call.cancel()
                throw IOException("图片请求已取消")
            }
            call.execute()
        }

        private fun readBounded(body: okhttp3.ResponseBody?): ByteArray? {
            body ?: return null
            val declaredLength = body.contentLength()
            if (declaredLength > maxBytes) return null
            val initialSize =
                if (declaredLength in 1..maxBytes) {
                    declaredLength.coerceAtMost(64L * 1024L).toInt()
                } else {
                    8 * 1024
                }
            val output = ByteArrayOutputStream(initialSize)
            val buffer = ByteArray(8 * 1024)
            body.byteStream().use { input ->
                var total = 0L
                while (!cancelled) {
                    val count = input.read(buffer)
                    if (count < 0) return output.toByteArray()
                    total += count
                    if (total > maxBytes) return null
                    output.write(buffer, 0, count)
                }
            }
            return null
        }
    }
}
