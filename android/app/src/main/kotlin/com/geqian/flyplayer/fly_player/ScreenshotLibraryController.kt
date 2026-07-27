package com.geqian.flyplayer.fly_player

import android.content.Context
import android.os.Environment
import java.io.File

internal class ScreenshotLibraryController(
    private val context: Context,
    private val customDirectoryController: ScreenshotDirectoryAccessController =
        ScreenshotDirectoryAccessController(context),
) {
    fun listLibrary(hasFileAccess: Boolean): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
        fileSources(includePublic = hasFileAccess).forEach { source ->
            source.root
                .takeIf { it.exists() }
                ?.walkTopDown()
                ?.filter { it.isFile && isImageFile(it.name) }
                ?.forEach { file ->
                    val format = ScreenshotImageFormatInspector.inspectFile(file)
                    items +=
                        mapOf(
                            "id" to "file:${file.absolutePath}",
                            "name" to file.name,
                            "sourceKind" to source.kind,
                            "locationLabel" to source.locationLabel,
                            "formatKind" to format.formatKind,
                            "isHdr" to format.isHdr,
                            "sizeBytes" to file.length().coerceAtLeast(0L),
                            "modifiedAtMs" to file.lastModified().coerceAtLeast(0L),
                            "isScoped" to false,
                            "pathOrIdentifier" to file.absolutePath,
                        )
                }
        }
        items += customDirectoryController.listImageEntries()
        items.sortWith(
            compareByDescending<Map<String, Any?>> {
                (it["modifiedAtMs"] as? Number)?.toLong() ?: 0L
            }.thenBy {
                (it["name"] as? String).orEmpty().lowercase()
            },
        )
        return items
    }

    fun readFileBytes(
        sourceKind: String,
        pathOrIdentifier: String,
    ): ByteArray? {
        val trimmedPath = pathOrIdentifier.trim()
        if (trimmedPath.isEmpty()) {
            return null
        }
        return if (sourceKind.trim() == "custom") {
            customDirectoryController.readFileBytes(trimmedPath)
        } else {
            runCatching { File(trimmedPath).readBytes() }.getOrNull()
        }
    }

    fun deleteEntries(rawItems: List<Map<String, String>>): Int {
        var deletedCount = 0
        rawItems.forEach { item ->
            val sourceKind = item["sourceKind"].orEmpty().trim()
            val pathOrIdentifier = item["pathOrIdentifier"].orEmpty().trim()
            if (pathOrIdentifier.isEmpty()) {
                return@forEach
            }
            val deleted =
                if (sourceKind == "custom") {
                    customDirectoryController.deleteFile(pathOrIdentifier)
                } else {
                    val file = File(pathOrIdentifier)
                    runCatching { file.exists() && file.delete() }.getOrDefault(false)
                }
            if (deleted) {
                deletedCount += 1
            }
        }
        return deletedCount
    }

    private fun fileSources(includePublic: Boolean): List<FileSource> {
        val sources = mutableListOf<FileSource>()
        if (includePublic) {
            sources +=
                FileSource(
                    kind = "pictures",
                    locationLabel = "Pictures/FlyPlayer",
                    root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "FlyPlayer"),
                )
            sources +=
                FileSource(
                    kind = "dcim",
                    locationLabel = "DCIM/FlyPlayer",
                    root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "FlyPlayer"),
                )
        }
        context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)?.resolve("FlyPlayer")?.let {
            sources +=
                FileSource(
                    kind = "app",
                    locationLabel = context.localizedString(R.string.screenshot_app_pictures_directory),
                    root = it,
                )
        }
        context.getExternalFilesDir(Environment.DIRECTORY_DCIM)?.resolve("FlyPlayer")?.let {
            sources +=
                FileSource(
                    kind = "app",
                    locationLabel = context.localizedString(R.string.screenshot_app_dcim_directory),
                    root = it,
                )
        }
        return sources
    }

    private fun isImageFile(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension in supportedImageExtensions
    }

    private data class FileSource(
        val kind: String,
        val locationLabel: String,
        val root: File,
    )

    private companion object {
        val supportedImageExtensions =
            setOf("jpg", "jpeg", "png", "webp", "bmp")
    }
}
