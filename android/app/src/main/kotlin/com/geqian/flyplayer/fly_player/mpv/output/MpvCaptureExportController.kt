package com.geqian.flyplayer.fly_player.mpv

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
    private companion object {
        const val CAPTURE_UNAVAILABLE_MESSAGE = "capture unavailable"
        const val CAPTURE_FAILED_MESSAGE = "capture failed"
        const val CAPTURE_SAVED_MESSAGE = "capture saved"
        const val CAPTURE_SAVE_FAILED_MESSAGE = "capture save failed"
    }

    fun captureFrame(
        initialized: Boolean,
        sourceFileLoaded: Boolean,
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
        val displayName = "FlyPlayer_$stamp.jpg"
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
        val savedPath = saveCapturedFrame(tempFile, displayName, savePathMode)
        tempFile.delete()
        return if (savedPath != null) {
            mapOf(
                "success" to true,
                "message" to CAPTURE_SAVED_MESSAGE,
                "path" to savedPath,
            )
        } else {
            mapOf(
                "success" to false,
                "message" to CAPTURE_SAVE_FAILED_MESSAGE,
            )
        }
    }

    private fun saveCapturedFrame(
        tempFile: File,
        displayName: String,
        savePathMode: String,
    ): String? {
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
                return uri.toString()
            }.getOrNull()?.let { return it }
        }

        val publicDir = publicCaptureDirectory(savePathMode)
        val appDir = appCaptureDirectory(savePathMode)
        val targetDir = when {
            publicDir.exists() || publicDir.mkdirs() -> publicDir
            appDir.exists() || appDir.mkdirs() -> appDir
            else -> null
        } ?: return null
        return runCatching {
            val target = File(targetDir, displayName)
            FileInputStream(tempFile).use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }
            target.absolutePath
        }.getOrNull()
    }

    private fun captureRelativeDirectory(savePathMode: String): String =
        when (savePathMode) {
            "dcim" -> "${Environment.DIRECTORY_DCIM}/FlyPlayer"
            "app_pictures" -> "${Environment.DIRECTORY_PICTURES}/FlyPlayer/App"
            else -> "${Environment.DIRECTORY_PICTURES}/FlyPlayer"
        }

    private fun publicCaptureDirectory(savePathMode: String): File {
        val root =
            when (savePathMode) {
                "dcim" -> Environment.DIRECTORY_DCIM
                else -> Environment.DIRECTORY_PICTURES
            }
        val child = if (savePathMode == "app_pictures") "FlyPlayer/App" else "FlyPlayer"
        return File(Environment.getExternalStoragePublicDirectory(root), child)
    }

    private fun appCaptureDirectory(savePathMode: String): File {
        val root =
            when (savePathMode) {
                "dcim" -> Environment.DIRECTORY_DCIM
                else -> Environment.DIRECTORY_PICTURES
            }
        val base = context.getExternalFilesDir(root) ?: context.filesDir
        val child = if (savePathMode == "app_pictures") "FlyPlayer/App" else "FlyPlayer"
        return File(base, child)
    }
}
