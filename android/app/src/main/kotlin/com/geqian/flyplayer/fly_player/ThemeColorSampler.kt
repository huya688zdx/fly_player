package com.geqian.flyplayer.fly_player

import android.net.Uri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.core.graphics.ColorUtils
import androidx.palette.graphics.Palette
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.Executors
import java.util.LinkedHashMap
import kotlin.math.max
import kotlin.math.min

object ThemeColorSampler {
    private const val MAX_CACHE_ENTRIES = 72
    private val client = OkHttpClient()
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val seedCache =
        LinkedHashMap<String, Map<String, Any>?>(MAX_CACHE_ENTRIES, 0.75f, true)
    private val inflight =
        mutableMapOf<String, MutableList<(Map<String, Any>?) -> Unit>>()

    fun sample(
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
                if (seedCache.containsKey(normalizedImageKey)) {
                    cachedResult = seedCache[normalizedImageKey]
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
                        seedCache[normalizedImageKey] = result
                        trimSeedCacheLocked()
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
                buildSeedMap(bitmap)
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun decodeBitmap(bytes: ByteArray): Bitmap? {
        val bounds =
            BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val sampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, 220, 140)
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    private fun trimSeedCacheLocked() {
        while (seedCache.size > MAX_CACHE_ENTRIES) {
            val eldestKey = seedCache.entries.firstOrNull()?.key ?: return
            seedCache.remove(eldestKey)
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
        var halfWidth = width / 2
        var halfHeight = height / 2
        while (halfWidth / inSampleSize >= reqWidth && halfHeight / inSampleSize >= reqHeight) {
            inSampleSize *= 2
        }
        return max(1, inSampleSize)
    }

    private fun buildSeedMap(bitmap: Bitmap): Map<String, Any>? {
        val palette =
            Palette
                .from(bitmap)
                .maximumColorCount(16)
                .clearFilters()
                .generate()

        val backgroundCandidate =
            firstAccepted(
                listOf(
                    palette.darkVibrantSwatch?.rgb,
                    palette.vibrantSwatch?.rgb,
                    palette.dominantSwatch?.rgb,
                    palette.mutedSwatch?.rgb,
                ),
            )
        val accentCandidate =
            firstAccepted(
                listOf(
                    palette.vibrantSwatch?.rgb,
                    palette.darkVibrantSwatch?.rgb,
                    palette.lightVibrantSwatch?.rgb,
                    palette.dominantSwatch?.rgb,
                    palette.mutedSwatch?.rgb,
                ),
            )

        // When all swatches are filtered (dark/gray/bright images), fall back
        // to the dominant color without filtering so every image gets a theme.
        val fallback = palette.dominantSwatch?.rgb
            ?: palette.vibrantSwatch?.rgb
            ?: palette.mutedSwatch?.rgb
        val baseCandidate = backgroundCandidate ?: accentCandidate ?: fallback ?: return null
        val actionCandidate = accentCandidate ?: backgroundCandidate ?: fallback ?: return null
        val preferLightSurface = preferLightSurface(baseCandidate)

        val candidatesAreSame = baseCandidate == actionCandidate
        val accentSource = if (candidatesAreSame) shiftHue(actionCandidate, 30f) else actionCandidate
        val linkSource = if (candidatesAreSame) shiftHue(actionCandidate, -20f) else actionCandidate

        return mapOf(
            "backgroundSeed" to backgroundSeedFor(baseCandidate, preferLightSurface),
            "accentSeed" to accentSeedFor(accentSource),
            "selectionSeed" to selectionSeedFor(accentSource),
            "linkSeed" to linkSeedFor(linkSource),
            "preferLightSurface" to preferLightSurface,
        )
    }

    private fun firstAccepted(colors: List<Int?>): Int? {
        for (color in colors) {
            val normalized = normalizeCandidate(color) ?: continue
            return normalized
        }
        return null
    }

    private fun normalizeCandidate(color: Int?): Int? {
        color ?: return null
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        if (hsl[1] < 0.08f) return null
        if (hsl[2] < 0.06f || hsl[2] > 0.90f) return null

        val hue = hsl[0]
        val isHarshRed = hue <= 10f || hue >= 350f
        if (isHarshRed && hsl[1] > 0.72f) {
            hsl[1] = 0.72f
        }
        return ColorUtils.HSLToColor(hsl)
    }

    private fun preferLightSurface(color: Int): Boolean {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        return hsl[2] >= 0.62f
    }

    private fun backgroundSeedFor(
        color: Int,
        preferLightSurface: Boolean,
    ): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        if (preferLightSurface) {
            hsl[1] = clamp(hsl[1] * 0.42f, 0.08f, 0.22f)
            hsl[2] = clamp(hsl[2] * 0.92f, 0.74f, 0.90f)
        } else {
            hsl[1] = clamp(hsl[1] * 0.84f, 0.18f, 0.54f)
            hsl[2] = clamp((hsl[2] * 0.58f) + 0.02f, 0.18f, 0.36f)
        }
        return ColorUtils.HSLToColor(hsl)
    }

    private fun accentSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.22f, 0.58f)
        hsl[2] = clamp(hsl[2], 0.34f, 0.56f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun selectionSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.24f, 0.62f)
        hsl[2] = clamp(hsl[2] - 0.02f, 0.30f, 0.52f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun linkSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.20f, 0.54f)
        hsl[2] = clamp(hsl[2] + 0.08f, 0.42f, 0.64f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun clamp(
        value: Float,
        minValue: Float,
        maxValue: Float,
    ): Float = max(minValue, min(maxValue, value))

    private fun shiftHue(color: Int, degrees: Float): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[0] = (hsl[0] + degrees) % 360f
        if (hsl[0] < 0f) hsl[0] += 360f
        return ColorUtils.HSLToColor(hsl)
    }
}
