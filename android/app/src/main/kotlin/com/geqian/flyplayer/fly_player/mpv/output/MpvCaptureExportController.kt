package com.geqian.flyplayer.fly_player.mpv

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
            runCatching {
                mpv.command(
                    arrayOf(
                        "screenshot-to-file",
                        tempFile.absolutePath,
                        if (includeSubtitles) "subtitles" else "video",
                    ),
                ) >= 0
            }.getOrDefault(false)
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
            segments += "\u542B\u5B57\u5E55"
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
                labels += "\u7279\u522B\u7BC7"
                labels += "\u7B2C${episodeNumber}\u96C6"
            }
            episodeNumber > 0 && seasonNumber > 0 -> {
                labels += "\u7B2C${seasonNumber}\u5B63"
                labels += "\u7B2C${episodeNumber}\u96C6"
            }
            seasonNumber > 0 -> {
                labels += "\u7B2C${seasonNumber}\u5B63"
            }
            isMovie -> {
                labels += "\u7535\u5F71"
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
