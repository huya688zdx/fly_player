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

    // ---- Monet 式取色（评分 + 互异色相分配） ----
    // 不再只取 Palette 的 vibrant/muted 几个固定 swatch、也不再用人工 hue-shift 凑深度。
    // 而是对全部量化 swatch 做 Monet 式评分（彩度 × 人口权重，滤近灰/极端调），accent 取
    // 最高分；selection/link 取与已选色相距离足够远的“真实图像色”，无第二色相时退回同色相
    // 不同明度。4 个 seed 下游喂 ColorScheme.fromSeed（HCT 色调调和）。
    private const val MIN_DISTINCT_HUE = 32f

    private class ScoredSwatch(
        val rgb: Int,
        val hue: Float,
        val saturation: Float,
        val lightness: Float,
        val population: Int,
        val score: Double,
    )

    private fun buildSeedMap(bitmap: Bitmap): Map<String, Any>? {
        val palette =
            Palette
                .from(bitmap)
                .maximumColorCount(24)
                .clearFilters()
                .generate()

        val swatches = palette.swatches
        if (swatches.isEmpty()) return null

        var totalPopulation = 0.0
        var weightedLuminance = 0.0
        val scored = ArrayList<ScoredSwatch>(swatches.size)
        for (swatch in swatches) {
            val rgb = swatch.rgb
            val hsl = FloatArray(3)
            ColorUtils.colorToHSL(rgb, hsl)
            val population = swatch.population
            totalPopulation += population
            weightedLuminance += relativeLuminance(rgb) * population
            scored.add(
                ScoredSwatch(
                    rgb = rgb,
                    hue = hsl[0],
                    saturation = hsl[1],
                    lightness = hsl[2],
                    population = population,
                    score = chromaScore(hsl[1], hsl[2], population),
                ),
            )
        }
        scored.sortByDescending { it.score }

        // 人口加权亮度判定亮/暗表面（比单一 swatch 的 lightness 更稳，允许亮色海报出亮主题）。
        val preferLightSurface =
            totalPopulation > 0 && (weightedLuminance / totalPopulation) >= 0.60

        // 背景基色：人口最多的 swatch（含灰），决定表面主调。
        val dominant = swatches.maxByOrNull { it.population }!!.rgb

        // accent：评分最高的有彩色；若全是近灰则退回 dominant。
        val colorful = scored.filter { it.saturation >= 0.12f }
        val accent = (colorful.firstOrNull() ?: scored.first()).rgb

        // selection / link：优先取与已选“色相距离够远”的真实图像色；没有则退回同色相不同明度。
        val accentHue = hueOf(accent)
        val selectionSwatch =
            colorful.firstOrNull { hueDistance(it.hue, accentHue) >= MIN_DISTINCT_HUE }
        val selectionHue = selectionSwatch?.hue ?: accentHue
        val linkSwatch =
            colorful.firstOrNull {
                hueDistance(it.hue, accentHue) >= MIN_DISTINCT_HUE &&
                    hueDistance(it.hue, selectionHue) >= MIN_DISTINCT_HUE
            }

        val selectionSource = selectionSwatch?.rgb ?: tonalSibling(accent, -0.06f)
        val linkSource = linkSwatch?.rgb ?: tonalSibling(accent, 0.10f)

        return mapOf(
            "backgroundSeed" to backgroundSeedFor(dominant, preferLightSurface),
            "accentSeed" to accentSeedFor(accent),
            "selectionSeed" to selectionSeedFor(selectionSource),
            "linkSeed" to linkSeedFor(linkSource),
            "preferLightSurface" to preferLightSurface,
        )
    }

    /// Monet 式评分：彩度（中明度处峰值）× 人口对数权重；近灰强罚、极端明暗弱罚。
    private fun chromaScore(saturation: Float, lightness: Float, population: Int): Double {
        val toneFalloff = 1.0 - (kotlin.math.abs(lightness - 0.5) * 0.7)
        val chroma = saturation * toneFalloff
        val popWeight = kotlin.math.ln(1.0 + population)
        val grayPenalty = if (saturation < 0.10f) 0.12 else 1.0
        val extremePenalty = if (lightness < 0.06f || lightness > 0.94f) 0.4 else 1.0
        return chroma * popWeight * grayPenalty * extremePenalty
    }

    private fun relativeLuminance(color: Int): Double {
        val r = ((color shr 16) and 0xFF) / 255.0
        val g = ((color shr 8) and 0xFF) / 255.0
        val b = (color and 0xFF) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private fun hueOf(color: Int): Float {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        return hsl[0]
    }

    private fun hueDistance(a: Float, b: Float): Float {
        val diff = kotlin.math.abs(a - b) % 360f
        return if (diff > 180f) 360f - diff else diff
    }

    /// 同色相、明度偏移的兄弟色（无第二色相时给 selection/link 用，比人工 hue-shift 更和谐）。
    private fun tonalSibling(color: Int, deltaLightness: Float): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[2] = clamp(hsl[2] + deltaLightness, 0.12f, 0.88f)
        return ColorUtils.HSLToColor(hsl)
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
            // 柔和：暗表面彩度上限收一档，避免背景过浓。
            hsl[1] = clamp(hsl[1] * 0.80f, 0.16f, 0.48f)
            hsl[2] = clamp((hsl[2] * 0.58f) + 0.02f, 0.18f, 0.36f)
        }
        return ColorUtils.HSLToColor(hsl)
    }

    // 柔和舒适：强调/选中/链接的彩度上限整体收一档，长时间观看不刺眼。
    private fun accentSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.20f, 0.50f)
        hsl[2] = clamp(hsl[2], 0.34f, 0.56f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun selectionSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.22f, 0.52f)
        hsl[2] = clamp(hsl[2] - 0.02f, 0.30f, 0.52f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun linkSeedFor(color: Int): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(color, hsl)
        hsl[1] = clamp(hsl[1], 0.18f, 0.48f)
        hsl[2] = clamp(hsl[2] + 0.08f, 0.42f, 0.64f)
        return ColorUtils.HSLToColor(hsl)
    }

    private fun clamp(
        value: Float,
        minValue: Float,
        maxValue: Float,
    ): Float = max(minValue, min(maxValue, value))
}
