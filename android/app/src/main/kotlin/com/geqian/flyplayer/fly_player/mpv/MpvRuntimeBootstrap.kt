package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.util.Log
import java.io.File

private const val BOOTSTRAP_TAG = "FlyPlayerMpv"
private const val BOOTSTRAP_VIDEO_OUTPUT_NONE = "null"
private const val BOOTSTRAP_GPU_CONTEXT = "android"
private const val BOOTSTRAP_HWDEC_DEFAULT = "mediacodec,auto-safe"
private const val BOOTSTRAP_SCALE = "spline36"
private const val BOOTSTRAP_CSCALE = "catmull_rom"
private const val BOOTSTRAP_DSCALE = "box"
private val SYSTEM_SUBTITLE_FONT_CANDIDATES = listOf(
    SystemSubtitleFontCandidate("/system/fonts/NotoSansCJK-Regular.ttc", "Noto Sans CJK SC"),
    SystemSubtitleFontCandidate("/system/fonts/NotoSerifCJK-Regular.ttc", "Noto Serif CJK SC"),
    SystemSubtitleFontCandidate("/system/fonts/MiSansVF.ttf", "MiSans"),
    SystemSubtitleFontCandidate("/system/fonts/MiSansTCVF.ttf", "MiSans"),
    SystemSubtitleFontCandidate("/system/fonts/MiSansJapaneseVF.ttf", "MiSans"),
    SystemSubtitleFontCandidate("/system/fonts/MiSansKoreanVF.ttf", "MiSans"),
    SystemSubtitleFontCandidate("/product/fonts/MiSansRoundedSC.ttf", "MiSans"),
    SystemSubtitleFontCandidate("/product/fonts/MiSerifSCVF.ttf", "MiSerif"),
)

private data class SystemSubtitleFontCandidate(
    val path: String,
    val familyName: String,
)

private data class PreparedSubtitleFonts(
    val copiedCount: Int,
    val selectedFamily: String?,
)

class MpvRuntimeBootstrap(
    private val context: Context,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var lastErrorMessage: String? = null
    @Volatile
    private var released = false
    @Volatile
    private var generation = 0L

    fun consumeLastErrorMessage(): String? {
        val message = lastErrorMessage
        lastErrorMessage = null
        return message
    }

    fun initialize(playbackSpeed: Double): Boolean {
        released = false
        generation += 1L
        lastErrorMessage = null
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
                val preparedSubtitleFonts = prepareSubtitleFonts(subtitleFontDir)
                mpv.setOptionString("config", "yes")
                mpv.setOptionString("config-dir", configDir.absolutePath)
                mpv.setOptionString("gpu-shader-cache-dir", cacheDir.absolutePath)
                mpv.setOptionString("icc-cache-dir", cacheDir.absolutePath)
                configureSubtitleFonts(subtitleFontDir, preparedSubtitleFonts)
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
                logSubtitleFontConfig(subtitleFontDir, preparedSubtitleFonts)
                true
            } else {
                lastErrorMessage = formatNativePlaybackError("player initialization")
                false
            }
        }.onFailure { error ->
            lastErrorMessage = formatNativePlaybackError("player initialization", error)
        }.getOrDefault(false)
    }

    fun release() {
        released = true
        runCatching { mpv.shutdown() }
        Log.d(BOOTSTRAP_TAG, "releaseMpv shutdown complete")
    }

    private fun prepareSubtitleFonts(fontDir: File): PreparedSubtitleFonts {
        purgeStaleSubtitleFonts(fontDir)
        var copiedCount = 0
        var selectedFamily: String? = null
        for (candidate in SYSTEM_SUBTITLE_FONT_CANDIDATES) {
            val sourceFile = File(candidate.path)
            if (!sourceFile.isFile || sourceFile.length() <= 0L) {
                continue
            }
            val targetFile = fontDir.resolve(sourceFile.name)
            if (!targetFile.isFile || targetFile.length() != sourceFile.length()) {
                val copied = runCatching {
                    copyFile(sourceFile, targetFile)
                }.onFailure { error ->
                    Log.w(
                        BOOTSTRAP_TAG,
                        "copy system subtitle font failed source=${sourceFile.absolutePath}",
                        error,
                    )
                }.getOrDefault(false)
                if (!copied) {
                    continue
                }
            }
            copiedCount += 1
            if (selectedFamily == null) {
                selectedFamily = candidate.familyName
            }
        }
        return PreparedSubtitleFonts(copiedCount = copiedCount, selectedFamily = selectedFamily)
    }

    private fun configureSubtitleFonts(
        fontDir: File,
        preparedFonts: PreparedSubtitleFonts,
    ) {
        if (preparedFonts.copiedCount > 0) {
            mpv.setOptionString("sub-font-provider", "none")
            mpv.setOptionString("sub-fonts-dir", fontDir.absolutePath)
            preparedFonts.selectedFamily?.let { family ->
                mpv.setOptionString("sub-font", family)
                mpv.setOptionString("osd-font", family)
            }
            return
        }
        mpv.setOptionString("sub-font-provider", "auto")
    }

    private fun logSubtitleFontConfig(
        fontDir: File,
        preparedFonts: PreparedSubtitleFonts,
    ) {
        val fontEntries = fontDir.listFiles()
            ?.map { "${it.name}(${it.length()})" }
            ?.sorted()
            ?.joinToString(", ")
            .orEmpty()
        val provider = if (preparedFonts.copiedCount > 0) "none" else "auto"
        Log.d(
            BOOTSTRAP_TAG,
            "subtitle font config provider=$provider selectedFamily=${preparedFonts.selectedFamily} dir=${fontDir.absolutePath} files=[$fontEntries]",
        )
    }

    private fun purgeStaleSubtitleFonts(fontDir: File) {
        val keepNames = SYSTEM_SUBTITLE_FONT_CANDIDATES
            .map { File(it.path).name }
            .toSet()
        fontDir.listFiles()?.forEach { file ->
            if (file.isFile && file.name !in keepNames) {
                runCatching {
                    file.delete()
                }.onFailure { error ->
                    Log.w(BOOTSTRAP_TAG, "delete stale subtitle font failed path=${file.absolutePath}", error)
                }
            }
        }
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
}
