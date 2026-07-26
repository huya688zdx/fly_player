package com.geqian.flyplayer.fly_player

import android.net.Uri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.Executors
import java.util.LinkedHashMap
import kotlin.math.max

/**
 * 主题取色的原生采样端：只负责下载、解码、缩到莫奈采样尺寸（≤112×112）并回传 ARGB 像素。
 * 量化与评分统一在 Flutter 侧走 material_color_utilities 的真莫奈管线
 * （Celebi 量化 + CAM16 Score），保证与非 Android 回退路径结果一致。
 */
object ThemeColorSampler {
    // 每条目 ≤112×112×4B ≈ 50KB，12 条 ≈ 600KB；seed 级缓存由 Flutter 侧持久化承担。
    private const val MAX_CACHE_ENTRIES = 12
    private const val TARGET_MAX_DIMENSION = 112
    private val client = OkHttpClient()
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val pixelCache =
        LinkedHashMap<String, Map<String, Any>?>(MAX_CACHE_ENTRIES, 0.75f, true)
    private val inflight =
        mutableMapOf<String, MutableList<(Map<String, Any>?) -> Unit>>()

    fun samplePixels(
        imageUrl: String,
        token: String,
        callback: (Map<String, Any>?) -> Unit,
    ) {
        val normalizedImageKey = normalizeImageIdentity(imageUrl)
        var cachedResult: Map<String, Any>? = null
        var hasCachedResult = false
        var joinedInflight = false
        if (normalizedImageKey.isNotEmpty()) {
            synchronized(lock) {
                if (pixelCache.containsKey(normalizedImageKey)) {
                    cachedResult = pixelCache[normalizedImageKey]
                    hasCachedResult = true
                } else {
                    inflight[normalizedImageKey]?.let { callbacks ->
                        callbacks.add(callback)
                        joinedInflight = true
                    } ?: run {
                        inflight[normalizedImageKey] = mutableListOf(callback)
                    }
                }
            }
        }
        if (hasCachedResult) {
            mainHandler.post { callback(cachedResult) }
            return
        }
        if (joinedInflight) {
            return
        }
        executor.execute {
            val result =
                runCatching {
                    sampleInternal(
                        imageUrl = imageUrl,
                        token = token,
                    )
                }.getOrNull()
            val callbacks =
                if (normalizedImageKey.isEmpty()) {
                    listOf(callback)
                } else {
                    synchronized(lock) {
                        pixelCache[normalizedImageKey] = result
                        trimPixelCacheLocked()
                        inflight.remove(normalizedImageKey)?.toList() ?: listOf(callback)
                    }
                }
            mainHandler.post {
                callbacks.forEach { queuedCallback ->
                    queuedCallback(result)
                }
            }
        }
    }

    private fun sampleInternal(
        imageUrl: String,
        token: String,
    ): Map<String, Any>? {
        if (imageUrl.isBlank()) return null

        val requestBuilder = Request.Builder().url(imageUrl)
        if (token.isNotBlank()) {
            requestBuilder.header("Authorization", token)
            requestBuilder.header("Trim-MC-token", token)
        }
        client.newCall(requestBuilder.build()).execute().use { response ->
            if (!response.isSuccessful) return null
            val bytes = response.body?.bytes() ?: return null
            val bitmap = decodeBitmap(bytes) ?: return null
            return try {
                buildPixelMap(bitmap)
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun buildPixelMap(source: Bitmap): Map<String, Any>? {
        val scaled = scaleToSampleSize(source)
        try {
            val width = scaled.width
            val height = scaled.height
            if (width <= 0 || height <= 0) return null
            val pixels = IntArray(width * height)
            scaled.getPixels(pixels, 0, width, 0, 0, width, height)
            return mapOf(
                "pixels" to pixels,
                "width" to width,
                "height" to height,
            )
        } finally {
            if (scaled !== source) {
                scaled.recycle()
            }
        }
    }

    private fun scaleToSampleSize(bitmap: Bitmap): Bitmap {
        val maxDimension = max(bitmap.width, bitmap.height)
        if (maxDimension <= TARGET_MAX_DIMENSION) return bitmap
        val ratio = TARGET_MAX_DIMENSION.toFloat() / maxDimension
        val targetWidth = max(1, (bitmap.width * ratio).toInt())
        val targetHeight = max(1, (bitmap.height * ratio).toInt())
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun decodeBitmap(bytes: ByteArray): Bitmap? {
        val bounds =
            BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val sampleSize =
            calculateInSampleSize(
                bounds.outWidth,
                bounds.outHeight,
                TARGET_MAX_DIMENSION,
                TARGET_MAX_DIMENSION,
            )
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    private fun trimPixelCacheLocked() {
        while (pixelCache.size > MAX_CACHE_ENTRIES) {
            val eldestKey = pixelCache.entries.firstOrNull()?.key ?: return
            pixelCache.remove(eldestKey)
        }
    }

    private fun normalizeImageIdentity(imageUrl: String): String {
        val trimmed = imageUrl.trim()
        if (trimmed.isEmpty()) {
            return ""
        }
        return runCatching {
            val uri = Uri.parse(trimmed)
            if (uri.scheme.isNullOrEmpty() || uri.host.isNullOrEmpty()) {
                return@runCatching trimmed
            }
            val builder = uri.buildUpon().clearQuery().fragment(null)
            uri.queryParameterNames
                .sorted()
                .filter { it != "w" }
                .forEach { name ->
                    val value = uri.getQueryParameter(name)?.trim().orEmpty()
                    if (value.isNotEmpty()) {
                        builder.appendQueryParameter(name, value)
                    }
                }
            builder.build().toString()
        }.getOrElse { trimmed }
    }

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        reqWidth: Int,
        reqHeight: Int,
    ): Int {
        var inSampleSize = 1
        val halfWidth = width / 2
        val halfHeight = height / 2
        while (halfWidth / inSampleSize >= reqWidth && halfHeight / inSampleSize >= reqHeight) {
            inSampleSize *= 2
        }
        return max(1, inSampleSize)
    }
}
