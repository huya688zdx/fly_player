package com.geqian.flyplayer.fly_player.mpv

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.geqian.flyplayer.fly_player.R
import com.geqian.flyplayer.fly_player.ScreenshotDirectoryAccessController
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal class MpvCaptureExportController(
    private val context: Context,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private val screenshotDirectoryController =
        ScreenshotDirectoryAccessController(context)

    private companion object {
        const val CAPTURE_UNAVAILABLE_MESSAGE = "capture unavailable"
        const val CAPTURE_FAILED_MESSAGE = "capture failed"
        const val CAPTURE_SAVED_MESSAGE = "capture saved"
        const val CAPTURE_SAVE_FAILED_MESSAGE = "capture save failed"
        const val CAPTURE_CUSTOM_DIR_REQUIRED_CODE = "custom_directory_required"
        const val CAPTURE_CUSTOM_DIR_UNAVAILABLE_CODE = "custom_directory_unavailable"
        const val MAX_CAPTURE_STEM_LENGTH = 96
        // HDR 截图临时回退用的 SDR 目标色彩（与 VideoOutputController 的 SDR tone-map 一致）。
        const val SCREENSHOT_TARGET_PRIM_SDR = "bt.709"
        const val SCREENSHOT_TARGET_TRC_SDR = "bt.1886"
        const val SCREENSHOT_TONE_MAPPING = "bt.2390"
    }

    fun captureFrame(
        initialized: Boolean,
        sourceFileLoaded: Boolean,
        currentSource: MpvSource?,
        args: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        if (!initialized || !mpv.isAvailable() || !sourceFileLoaded) {
            return mapOf(
                "success" to false,
                "message" to CAPTURE_UNAVAILABLE_MESSAGE,
            )
        }
        val includeSubtitles = args["includeSubtitles"] == true
        val savePathMode = args["savePathMode"]?.toString().orEmpty().trim()
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val displayName =
            buildCaptureDisplayName(
                source = currentSource,
                includeSubtitles = includeSubtitles,
                stamp = stamp,
            )
        val tempFile = File(context.cacheDir, "fly_player_frame_$stamp.jpg")
        val commandSuccess =
            withSdrScreenshotTarget {
                runCatching {
                    mpv.command(
                        arrayOf(
                            "screenshot-to-file",
                            tempFile.absolutePath,
                            if (includeSubtitles) "subtitles" else "video",
                        ),
                    ) >= 0
                }.getOrDefault(false)
            }
        if (!commandSuccess || !tempFile.exists() || tempFile.length() <= 0L) {
            tempFile.delete()
            return mapOf(
                "success" to false,
                "message" to CAPTURE_FAILED_MESSAGE,
            )
        }
        val saveResult = saveCapturedFrame(tempFile, displayName, savePathMode)
        tempFile.delete()
        return if (saveResult.path != null) {
            mapOf(
                "success" to true,
                "message" to CAPTURE_SAVED_MESSAGE,
                "path" to saveResult.path,
            )
        } else {
            mapOf(
                "success" to false,
                "message" to (saveResult.message ?: CAPTURE_SAVE_FAILED_MESSAGE),
                "code" to saveResult.code,
            )
        }
    }

    /**
     * mpv 截图沿用当前输出目标色彩。若正在 HDR 直通（target 为 HDR/PQ），截图写进 8-bit
     * JPEG 会发灰失真。这里仅当当前帧为 HDR 源时，临时把目标切到 SDR + tone-mapping，
     * 截完恢复，保证落地的截图色彩正确（SDR/DCI、HDR_TONEMAP_SDR 模式下为无害的同值重设）。
     */
    private fun <T> withSdrScreenshotTarget(block: () -> T): T {
        if (!isCurrentFrameHdr()) {
            return block()
        }
        val savedPrim = mpv.getPropertyString("target-prim")
        val savedTrc = mpv.getPropertyString("target-trc")
        val savedHint = mpv.getPropertyString("target-colorspace-hint")
        val savedTone = mpv.getPropertyString("tone-mapping")
        val savedGamut = mpv.getPropertyString("gamut-mapping-mode")
        return try {
            mpv.setPropertyString("target-colorspace-hint", "no")
            mpv.setPropertyString("target-prim", SCREENSHOT_TARGET_PRIM_SDR)
            mpv.setPropertyString("target-trc", SCREENSHOT_TARGET_TRC_SDR)
            mpv.setPropertyString("tone-mapping", SCREENSHOT_TONE_MAPPING)
            mpv.setPropertyString("gamut-mapping-mode", "clip")
            block()
        } finally {
            // 恢复成原值（含 auto），避免改动残留影响后续直通显示。
            savedPrim?.let { mpv.setPropertyString("target-prim", it) }
            savedTrc?.let { mpv.setPropertyString("target-trc", it) }
            savedHint?.let { mpv.setPropertyString("target-colorspace-hint", it) }
            savedTone?.let { mpv.setPropertyString("tone-mapping", it) }
            savedGamut?.let { mpv.setPropertyString("gamut-mapping-mode", it) }
        }
    }

    private fun isCurrentFrameHdr(): Boolean {
        val gamma = mpv.getPropertyString("video-params/gamma")
            ?.trim()
            ?.lowercase()
            .orEmpty()
        return gamma == "pq" || gamma == "hlg" || gamma == "st2084"
    }

    private fun saveCapturedFrame(
        tempFile: File,
        displayName: String,
        savePathMode: String,
    ): CaptureSaveResult {
        if (savePathMode == "custom") {
            if (!screenshotDirectoryController.hasConfiguredDirectory()) {
                return CaptureSaveResult(
                    path = null,
                    code = CAPTURE_CUSTOM_DIR_REQUIRED_CODE,
                    message = "Please choose a custom screenshot directory first",
                )
            }
            val savedPath = screenshotDirectoryController.saveCapturedFrame(tempFile, displayName)
            return if (savedPath != null) {
                CaptureSaveResult(path = savedPath)
            } else {
                CaptureSaveResult(
                    path = null,
                    code = CAPTURE_CUSTOM_DIR_UNAVAILABLE_CODE,
                    message = "Custom screenshot directory is unavailable",
                )
            }
        }
        if (savePathMode == "app_pictures") {
            return saveToDirectory(
                targetDir = appCaptureDirectory(savePathMode),
                tempFile = tempFile,
                displayName = displayName,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                val values =
                    ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                        put(
                            MediaStore.Images.Media.RELATIVE_PATH,
                            captureRelativeDirectory(savePathMode),
                        )
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                val resolver = context.contentResolver
                val uri =
                    resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: return@runCatching null
                resolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(tempFile).use { input ->
                        input.copyTo(output)
                    }
                } ?: return@runCatching null
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return CaptureSaveResult(path = uri.toString())
            }.getOrNull()?.let { return it }
        }

        val publicDir = publicCaptureDirectory(savePathMode)
        val appDir = appCaptureDirectory(savePathMode)
        val targetDir = when {
            publicDir.exists() || publicDir.mkdirs() -> publicDir
            appDir.exists() || appDir.mkdirs() -> appDir
            else -> null
        } ?: return CaptureSaveResult(path = null)
        return saveToDirectory(
            targetDir = targetDir,
            tempFile = tempFile,
            displayName = displayName,
        )
    }

    private fun saveToDirectory(
        targetDir: File,
        tempFile: File,
        displayName: String,
    ): CaptureSaveResult {
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            return CaptureSaveResult(path = null)
        }
        return runCatching {
            val target = File(targetDir, displayName)
            FileInputStream(tempFile).use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }
            CaptureSaveResult(path = target.absolutePath)
        }.getOrDefault(CaptureSaveResult(path = null))
    }

    private fun captureRelativeDirectory(savePathMode: String): String =
        when (savePathMode) {
            "dcim" -> "${Environment.DIRECTORY_DCIM}/FlyPlayer"
            else -> "${Environment.DIRECTORY_PICTURES}/FlyPlayer"
        }

    private fun publicCaptureDirectory(savePathMode: String): File {
        val root =
            when (savePathMode) {
                "dcim" -> Environment.DIRECTORY_DCIM
                else -> Environment.DIRECTORY_PICTURES
            }
        return File(Environment.getExternalStoragePublicDirectory(root), "FlyPlayer")
    }

    private fun appCaptureDirectory(savePathMode: String): File {
        val root =
            when (savePathMode) {
                "dcim" -> Environment.DIRECTORY_DCIM
                else -> Environment.DIRECTORY_PICTURES
            }
        val base = context.getExternalFilesDir(root) ?: context.filesDir
        return File(base, "FlyPlayer")
    }

    private fun buildCaptureDisplayName(
        source: MpvSource?,
        includeSubtitles: Boolean,
        stamp: String,
    ): String {
        val segments = mutableListOf<String>()
        val primaryTitle = source?.primaryCaptureTitle().orEmpty()
        if (primaryTitle.isNotEmpty()) {
            segments += primaryTitle
        }

        source?.captureContextLabels()?.let { labels ->
            segments += labels
        }

        val secondaryTitle = source?.secondaryCaptureTitle(primaryTitle).orEmpty()
        if (secondaryTitle.isNotEmpty()) {
            segments += secondaryTitle
        }

        source?.captureResolutionLabel()?.let { segments += it }
        if (includeSubtitles) {
            segments += context.getString(R.string.capture_include_subtitles)
        }

        val stem =
            sanitizeFileName(
                value = segments.joinToString(" - ").ifBlank { "FlyPlayer" },
            )
        val boundedStem =
            stem
                .take(MAX_CAPTURE_STEM_LENGTH)
                .trim()
                .trimEnd('.', '-', '_')
                .ifEmpty { "FlyPlayer" }
        return "$boundedStem - $stamp.jpg"
    }

    private fun sanitizeFileName(value: String): String =
        value
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .replace(Regex("\\s+"), " ")
            .trim()

    private fun MpvSource.primaryCaptureTitle(): String =
        seriesTitle.trim()
            .ifEmpty { ancestorName.trim() }
            .ifEmpty { title.trim() }

    private fun MpvSource.secondaryCaptureTitle(primaryTitle: String): String {
        val candidate = title.trim()
        if (candidate.isEmpty()) return ""
        if (candidate.equals(primaryTitle, ignoreCase = true)) return ""
        val compactPrimary = primaryTitle.replace(" ", "")
        val compactCandidate = candidate.replace(" ", "")
        if (compactPrimary.isNotEmpty() && compactCandidate.startsWith(compactPrimary)) {
            return ""
        }
        return candidate
    }

    private fun MpvSource.captureContextLabels(): List<String> {
        val labels = mutableListOf<String>()
        val normalizedMediaType = mediaType.trim().lowercase(Locale.US)
        val isMovie =
            normalizedMediaType.contains("movie") ||
                normalizedMediaType.contains("film")
        when {
            episodeNumber > 0 && seasonNumber == 0 -> {
                labels += context.getString(R.string.capture_special_episode)
                labels += context.getString(R.string.capture_episode_number, episodeNumber)
            }
            episodeNumber > 0 && seasonNumber > 0 -> {
                labels += context.getString(R.string.capture_season_number, seasonNumber)
                labels += context.getString(R.string.capture_episode_number, episodeNumber)
            }
            seasonNumber > 0 -> {
                labels += context.getString(R.string.capture_season_number, seasonNumber)
            }
            isMovie -> {
                labels += context.getString(R.string.capture_movie)
            }
            normalizedMediaType.isNotEmpty() -> {
                labels += mediaType.trim()
            }
        }
        return labels
    }

    private fun MpvSource.captureResolutionLabel(): String? {
        val rawResolution = resolution.trim()
        if (rawResolution.isNotEmpty()) {
            return rawResolution
        }
        if (videoWidth > 0 && videoHeight > 0) {
            return "${videoWidth}x${videoHeight}"
        }
        return null
    }

    private data class CaptureSaveResult(
        val path: String?,
        val code: String? = null,
        val message: String? = null,
    )
}
