package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

private const val BOOTSTRAP_TAG = "FlyPlayerMpv"
private const val BOOTSTRAP_VIDEO_OUTPUT_NONE = "null"
private const val BOOTSTRAP_GPU_CONTEXT = "android"
private const val BOOTSTRAP_HWDEC_DEFAULT = "mediacodec,auto-safe"
private const val BOOTSTRAP_SCALE = "spline36"
private const val BOOTSTRAP_CSCALE = "catmull_rom"
private const val BOOTSTRAP_DSCALE = "box"
private const val BUNDLED_SUBTITLE_FONT_ASSET = "assets/fonts/NotoSansCJKsc-Regular.otf"
private const val BUNDLED_SUBTITLE_FONT_FILE_NAME = "NotoSansCJKsc-Regular.otf"
private const val BUNDLED_SUBTITLE_FONT_FAMILY = "Noto Sans CJK SC"
private const val FALLBACK_SUBTITLE_FONT_URL =
    "http://192.168.6.120:5666/v/font/GoNotoCurrent.woff2"
private const val FALLBACK_SUBTITLE_FONT_FILE_NAME = "GoNotoCurrent.woff2"
private val SYSTEM_SUBTITLE_FONT_CANDIDATES = listOf(
    "/system/fonts/NotoSansCJK-Regular.ttc",
    "/system/fonts/NotoSerifCJK-Regular.ttc",
    "/system/fonts/MiSansVF.ttf",
    "/system/fonts/MiSansTCVF.ttf",
    "/system/fonts/MiSansJapaneseVF.ttf",
    "/system/fonts/MiSansKoreanVF.ttf",
    "/product/fonts/MiSansRoundedSC.ttf",
    "/product/fonts/MiSerifSCVF.ttf",
)

class MpvRuntimeBootstrap(
    private val context: Context,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var fallbackFontFetchStarted = false

    fun initialize(playbackSpeed: Double): Boolean {
        return runCatching {
            Log.d(BOOTSTRAP_TAG, "initializeMpv start")
            if (mpv.isCreated() || mpv.maybeCreate(context.applicationContext)) {
                val mpvDir = context.getDir("mpv", Context.MODE_PRIVATE)
                val configDir = mpvDir.resolve("config")
                val cacheDir = mpvDir.resolve("cache")
                val subtitleFontDir = context.cacheDir.resolve("mpv_subtitle_fonts")
                configDir.mkdirs()
                cacheDir.mkdirs()
                subtitleFontDir.mkdirs()
                prepareSubtitleFonts(subtitleFontDir)
                mpv.setOptionString("config", "yes")
                mpv.setOptionString("config-dir", configDir.absolutePath)
                mpv.setOptionString("gpu-shader-cache-dir", cacheDir.absolutePath)
                mpv.setOptionString("icc-cache-dir", cacheDir.absolutePath)
                mpv.setOptionString("sub-font-provider", "none")
                mpv.setOptionString("sub-fonts-dir", subtitleFontDir.absolutePath)
                mpv.setOptionString("sub-font", BUNDLED_SUBTITLE_FONT_FAMILY)
                mpv.setOptionString("osd-font", BUNDLED_SUBTITLE_FONT_FAMILY)
                mpv.setOptionString("vo", BOOTSTRAP_VIDEO_OUTPUT_NONE)
                mpv.setOptionString("gpu-context", BOOTSTRAP_GPU_CONTEXT)
                mpv.setOptionString("hwdec", BOOTSTRAP_HWDEC_DEFAULT)
                mpv.setOptionString("scale", BOOTSTRAP_SCALE)
                mpv.setOptionString("cscale", BOOTSTRAP_CSCALE)
                mpv.setOptionString("dscale", BOOTSTRAP_DSCALE)
                mpv.setOptionString("correct-downscaling", "no")
                mpv.setOptionString("sigmoid-upscaling", "no")
                mpv.setOptionString("interpolation", "no")
                mpv.setOptionString("deband", "no")
                mpv.setOptionString("vid", "auto")
                mpv.setOptionString("keep-open", "yes")
                mpv.setOptionString("force-window", "yes")
                mpv.setOptionString("ytdl", "no")
                mpv.setOptionString("sub-ass-override", "scale")
                mpv.setOptionString("sub-ass-use-video-data", "all")
                mpv.setOptionString("demuxer-mkv-subtitle-preroll", "yes")
                mpv.setOptionString("network-timeout", "20")
                mpv.setOptionString("speed", playbackSpeed.toString())
                ensureFallbackSubtitleFont(subtitleFontDir)
                logSubtitleFontConfig(subtitleFontDir)
                true
            } else {
                false
            }
        }.onFailure { error ->
            Log.e(BOOTSTRAP_TAG, "initializeMpv failed", error)
        }.getOrDefault(false)
    }

    fun release() {
        fallbackFontFetchStarted = false
        runCatching {
            mpv.shutdown()
        }.onFailure { error ->
            Log.w(BOOTSTRAP_TAG, "releaseMpv failed", error)
        }
    }

    private fun prepareSubtitleFonts(fontDir: File) {
        val bundledFont = fontDir.resolve(BUNDLED_SUBTITLE_FONT_FILE_NAME)
        val copied = runCatching {
            copyFlutterAssetToFile(BUNDLED_SUBTITLE_FONT_ASSET, bundledFont)
        }.onFailure { error ->
            Log.w(BOOTSTRAP_TAG, "copy bundled subtitle font failed", error)
        }.getOrDefault(false)
        Log.d(
            BOOTSTRAP_TAG,
            "subtitle font bootstrap copied=$copied bundledExists=${bundledFont.exists()} bundledSize=${bundledFont.length()}",
        )
        val systemFontsCopied = copySystemSubtitleFonts(fontDir)
        Log.d(
            BOOTSTRAP_TAG,
            "subtitle system font bootstrap copied=$systemFontsCopied dir=${fontDir.absolutePath}",
        )
    }

    private fun copyFlutterAssetToFile(assetPath: String, targetFile: File): Boolean {
        if (targetFile.isFile && targetFile.length() > 0L) {
            return true
        }
        targetFile.parentFile?.mkdirs()
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        context.assets.open(lookupKey).use { input ->
            val tempFile = File(targetFile.absolutePath + ".tmp")
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
            if (tempFile.length() <= 0L) {
                tempFile.delete()
                return false
            }
            if (targetFile.exists()) {
                targetFile.delete()
            }
            return tempFile.renameTo(targetFile)
        }
    }

    private fun logSubtitleFontConfig(fontDir: File) {
        val fontEntries = fontDir.listFiles()
            ?.map { "${it.name}(${it.length()})" }
            ?.sorted()
            ?.joinToString(", ")
            .orEmpty()
        Log.d(
            BOOTSTRAP_TAG,
            "subtitle font config provider=none subFont=\"$BUNDLED_SUBTITLE_FONT_FAMILY\" osdFont=\"$BUNDLED_SUBTITLE_FONT_FAMILY\" dir=${fontDir.absolutePath} files=[$fontEntries]",
        )
    }

    private fun copySystemSubtitleFonts(fontDir: File): Int {
        var copiedCount = 0
        for (candidatePath in SYSTEM_SUBTITLE_FONT_CANDIDATES) {
            val sourceFile = File(candidatePath)
            if (!sourceFile.isFile || sourceFile.length() <= 0L) {
                continue
            }
            val targetFile = fontDir.resolve(sourceFile.name)
            if (targetFile.isFile && targetFile.length() == sourceFile.length()) {
                continue
            }
            val copied = runCatching {
                copyFile(sourceFile, targetFile)
            }.onFailure { error ->
                Log.w(BOOTSTRAP_TAG, "copy system subtitle font failed source=${sourceFile.absolutePath}", error)
            }.getOrDefault(false)
            if (copied) {
                copiedCount += 1
            }
        }
        return copiedCount
    }

    private fun copyFile(sourceFile: File, targetFile: File): Boolean {
        targetFile.parentFile?.mkdirs()
        val tempFile = File(targetFile.absolutePath + ".tmp")
        sourceFile.inputStream().use { input ->
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (tempFile.length() <= 0L) {
            tempFile.delete()
            return false
        }
        if (targetFile.exists()) {
            targetFile.delete()
        }
        return tempFile.renameTo(targetFile)
    }

    private fun ensureFallbackSubtitleFont(fontDir: File) {
        val fontFile = fontDir.resolve(FALLBACK_SUBTITLE_FONT_FILE_NAME)
        if (fontFile.isFile && fontFile.length() > 0L) {
            Log.d(BOOTSTRAP_TAG, "fallback subtitle font ready path=${fontFile.absolutePath}")
            return
        }
        if (fallbackFontFetchStarted) return
        fallbackFontFetchStarted = true

        Thread {
            val downloaded = runCatching {
                downloadFallbackSubtitleFont(fontFile)
            }.onFailure { error ->
                Log.w(BOOTSTRAP_TAG, "fallback subtitle font download failed", error)
            }.getOrDefault(false)
            if (downloaded) {
                Log.d(BOOTSTRAP_TAG, "fallback subtitle font downloaded path=${fontFile.absolutePath}")
                runCatching {
                    mpv.setPropertyString("sub-fonts-dir", fontDir.absolutePath)
                }.onFailure { error ->
                    Log.w(BOOTSTRAP_TAG, "apply fallback subtitle font dir failed", error)
                }
            }
        }.start()
    }

    @Throws(IOException::class)
    private fun downloadFallbackSubtitleFont(targetFile: File): Boolean {
        val connection = (URL(FALLBACK_SUBTITLE_FONT_URL).openConnection() as? HttpURLConnection)
            ?: return false
        connection.requestMethod = "GET"
        connection.connectTimeout = 10000
        connection.readTimeout = 10000
        connection.instanceFollowRedirects = true
        return try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                false
            } else {
                val tempFile = File(targetFile.absolutePath + ".tmp")
                connection.inputStream.use { input ->
                    tempFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                if (tempFile.length() <= 0L) {
                    tempFile.delete()
                    false
                } else {
                    if (targetFile.exists()) {
                        targetFile.delete()
                    }
                    tempFile.renameTo(targetFile)
                }
            }
        } finally {
            connection.disconnect()
        }
    }
}
