package com.geqian.flyplayer.fly_player

import android.content.Context
import android.os.Environment
import com.geqian.flyplayer.fly_player.mpv.NativeMpvProxyServer
import com.geqian.flyplayer.fly_player.mpv.PersistentPlaybackCacheStore
import java.io.File

internal class StorageManagementController(
    private val context: Context,
) {
    private val playbackCacheStore = PersistentPlaybackCacheStore(context)
    private val scopedTreeAccessController = ScopedTreeAccessController(context)
    private val screenshotDirectoryAccessController =
        ScreenshotDirectoryAccessController(context)
    private val screenshotLibraryController =
        ScreenshotLibraryController(context, screenshotDirectoryAccessController)

    companion object {
        const val ACTION_CLEAR_PLAYBACK_CACHE = "clearPlaybackCache"
        const val ACTION_CLEAR_DANMAKU_AI_CACHE = "clearDanmakuAiCache"
        const val ACTION_CLEAR_OTHER_CACHE = "clearOtherCache"
        const val ACTION_CLEAR_SCREENSHOTS = "clearScreenshots"
        const val ACTION_CLEAR_PARALLEL_SETTINGS = "clearParallelWindowSettings"
        const val ACTION_CLEAR_SCOPED_TREE_ACCESS = "clearScopedTreeAccess"

        private const val PARALLEL_PREFS_NAME = "parallel_window_settings"
        private const val SCOPED_TREE_PREFS_NAME = "fly_player_scoped_tree"
        private const val DANMAKU_AI_CACHE_DIR_NAME = "danmaku_ai_cache"
    }

    fun loadOverview(hasFileAccess: Boolean): Map<String, Any?> {
        val danmakuAiCacheStats = computeStats(danmakuAiCacheRoot())
        val cacheStats = computeStats(otherCacheRoots())
        val playbackStats = playbackCacheStore.loadStats()
        val danmakuAiCacheBytes = danmakuAiCacheStats.bytes.coerceAtLeast(0L)
        val danmakuAiCacheFiles = danmakuAiCacheStats.fileCount.coerceAtLeast(0)
        val otherCacheBytes =
            (cacheStats.bytes - danmakuAiCacheStats.bytes).coerceAtLeast(0L)
        val otherCacheFiles =
            (cacheStats.fileCount - danmakuAiCacheStats.fileCount).coerceAtLeast(0)

        val screenshotItems = screenshotLibraryController.listLibrary(hasFileAccess)
        val screenshotBytes =
            screenshotItems.fold(0L) { sum, item ->
                sum + ((item["sizeBytes"] as? Number)?.toLong() ?: 0L)
            }
        val screenshotCount = screenshotItems.size
        val parallelPrefs =
            context.getSharedPreferences(PARALLEL_PREFS_NAME, Context.MODE_PRIVATE)
        val scopedTreePrefs =
            context.getSharedPreferences(SCOPED_TREE_PREFS_NAME, Context.MODE_PRIVATE)
        val nativeSettingsBytes =
            estimateSharedPreferencesBytes(parallelPrefs) +
                estimateSharedPreferencesBytes(scopedTreePrefs)

        return mapOf(
            "playbackCache" to
                mapOf(
                    "bytes" to playbackStats.totalBytes,
                    "fileCount" to playbackStats.fileCount,
                    "completeCount" to playbackStats.completeCount,
                    "active" to hasActivePlaybackCache(),
                ),
            "danmakuAiCache" to
                mapOf(
                    "bytes" to danmakuAiCacheBytes,
                    "fileCount" to danmakuAiCacheFiles,
                ),
            "otherCache" to
                mapOf(
                    "bytes" to otherCacheBytes,
                    "fileCount" to otherCacheFiles,
                ),
            "screenshots" to
                mapOf(
                    "bytes" to screenshotBytes,
                    "fileCount" to screenshotCount,
                    "restricted" to !hasFileAccess,
                ),
            "nativeSettingsBytes" to nativeSettingsBytes,
        )
    }

    fun clear(action: String, hasFileAccess: Boolean): Map<String, Any?> {
        return when (action) {
            ACTION_CLEAR_PLAYBACK_CACHE -> {
                if (hasActivePlaybackCache()) {
                    mapOf(
                        "success" to false,
                        "code" to "playback_active",
                    )
                } else {
                    playbackCacheStore.clearAll()
                    mapOf("success" to true)
                }
            }

            ACTION_CLEAR_OTHER_CACHE -> {
                clearOtherCache()
                mapOf("success" to true)
            }

            ACTION_CLEAR_DANMAKU_AI_CACHE -> {
                clearDanmakuAiCache()
                mapOf("success" to true)
            }

            ACTION_CLEAR_SCREENSHOTS -> {
                val items = screenshotLibraryController.listLibrary(hasFileAccess)
                val deleted =
                    screenshotLibraryController.deleteEntries(
                        items.mapNotNull { entry ->
                            val sourceKind = entry["sourceKind"]?.toString()?.trim().orEmpty()
                            val pathOrIdentifier =
                                entry["pathOrIdentifier"]?.toString()?.trim().orEmpty()
                            if (sourceKind.isEmpty() || pathOrIdentifier.isEmpty()) {
                                null
                            } else {
                                mapOf(
                                    "sourceKind" to sourceKind,
                                    "pathOrIdentifier" to pathOrIdentifier,
                                )
                            }
                        },
                    )
                mapOf(
                    "success" to true,
                    "restricted" to !hasFileAccess,
                    "deletedCount" to deleted,
                )
            }

            ACTION_CLEAR_PARALLEL_SETTINGS -> {
                context.getSharedPreferences(PARALLEL_PREFS_NAME, Context.MODE_PRIVATE).edit().clear().apply()
                ParallelWindowCoordinator.restoreFromPreferences(context)
                mapOf("success" to true)
            }

            ACTION_CLEAR_SCOPED_TREE_ACCESS -> {
                scopedTreeAccessController.clearPersistedTree()
                mapOf("success" to true)
            }

            else -> {
                mapOf(
                    "success" to false,
                    "code" to "unknown_action",
                )
            }
        }
    }

    private fun hasActivePlaybackCache(): Boolean = NativeMpvProxyServer.hasActiveSessions()

    fun queryCachedDownloadable(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
    ): Map<String, Any?> {
        return playbackCacheStore.queryDownloadable(
            itemGuid = itemGuid,
            mediaGuid = mediaGuid,
            videoGuid = videoGuid,
            resourceKey = resourceKey,
        )
    }

    fun listPlaybackCacheEntries(): List<Map<String, Any?>> {
        return playbackCacheStore.listEntries().map { entry ->
            mapOf(
                "resourceKey" to entry.resourceKey,
                "itemGuid" to entry.itemGuid,
                "mediaGuid" to entry.mediaGuid,
                "videoGuid" to entry.videoGuid,
                "title" to entry.title,
                "seriesTitle" to entry.seriesTitle,
                "seasonNumber" to entry.seasonNumber,
                "episodeNumber" to entry.episodeNumber,
                "resolution" to entry.resolution,
                "subtitle" to entry.subtitle,
                "bytes" to entry.bytes,
                "totalBytes" to entry.totalBytes,
                "complete" to entry.isComplete,
                "mimeType" to entry.mimeType,
                "lastAccessAtMs" to entry.lastAccessAtMs,
            )
        }
    }

    fun clearPlaybackCacheEntries(resourceKeys: List<String>): Map<String, Any?> {
        if (hasActivePlaybackCache()) {
            return mapOf(
                "success" to false,
                "code" to "playback_active",
            )
        }
        val cleared = playbackCacheStore.clearEntries(resourceKeys.map { it.trim() }.toSet())
        return mapOf(
            "success" to true,
            "clearedCount" to cleared,
        )
    }

    fun promoteCachedMedia(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
        targetMode: String,
        hasFileAccess: Boolean,
    ): Map<String, Any?> {
        return playbackCacheStore.promote(
            itemGuid = itemGuid,
            mediaGuid = mediaGuid,
            videoGuid = videoGuid,
            resourceKey = resourceKey,
            targetMode = targetMode,
            hasFileAccess = hasFileAccess,
            context = context,
        )
    }

    private fun clearOtherCache() {
        otherCacheRoots().forEach(::clearDirectoryContents)
    }

    private fun clearDanmakuAiCache() {
        clearDirectoryContents(danmakuAiCacheRoot())
    }

    private fun otherCacheRoots(): List<File> {
        val roots = linkedMapOf<String, File>()

        fun add(root: File?) {
            if (root == null) return
            val path = root.path.trim()
            if (path.isEmpty()) return
            val normalized = root.canonicalOrSelf()
            roots[normalized.absolutePath] = normalized
        }

        add(context.cacheDir)
        add(context.codeCacheDir)
        add(context.externalCacheDir)
        add(context.filesDir.parentFile?.resolve("cache"))
        add(
            System.getProperty("java.io.tmpdir")
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let(::File),
        )

        return roots.values.toList()
    }

    private fun danmakuAiCacheRoot(): File {
        return context.cacheDir.resolve(DANMAKU_AI_CACHE_DIR_NAME).canonicalOrSelf()
    }

    private fun screenshotRoots(includePublic: Boolean): List<File> {
        val roots = linkedMapOf<String, File>()

        fun add(root: File?) {
            if (root == null) return
            val normalized = root.canonicalOrSelf()
            roots[normalized.absolutePath] = normalized
        }

        if (includePublic) {
            add(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "FlyPlayer"))
            add(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "FlyPlayer"))
        }

        add(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)?.resolve("FlyPlayer"))
        add(context.getExternalFilesDir(Environment.DIRECTORY_DCIM)?.resolve("FlyPlayer"))

        return roots.values.toList()
    }

    private fun clearDirectoryContents(root: File) {
        if (!root.exists()) return
        if (root.isFile) {
            runCatching { root.delete() }
            return
        }
        root.listFiles()?.forEach { child ->
            runCatching {
                if (child.isDirectory) {
                    child.deleteRecursively()
                } else {
                    child.delete()
                }
            }
        }
    }

    private fun computeStats(root: File): FileStats {
        if (!root.exists()) return FileStats()
        return if (root.isFile) {
            FileStats(bytes = root.length().coerceAtLeast(0L), fileCount = 1)
        } else {
            var bytes = 0L
            var fileCount = 0
            root.walkTopDown().forEach { file ->
                if (file.isFile) {
                    bytes += file.length().coerceAtLeast(0L)
                    fileCount += 1
                }
            }
            FileStats(bytes = bytes, fileCount = fileCount)
        }
    }

    private fun computeStats(roots: List<File>): FileStats {
        var bytes = 0L
        var fileCount = 0
        roots.forEach { root ->
            val stats = computeStats(root)
            bytes += stats.bytes
            fileCount += stats.fileCount
        }
        return FileStats(bytes = bytes, fileCount = fileCount)
    }

    private fun estimateSharedPreferencesBytes(prefs: android.content.SharedPreferences): Long {
        var total = 0L
        prefs.all.forEach { (key, value) ->
            total += key.toByteArray(Charsets.UTF_8).size.toLong()
            total += estimateValueBytes(value)
        }
        return total
    }

    private fun estimateValueBytes(value: Any?): Long {
        return when (value) {
            null -> 0L
            is String -> value.toByteArray(Charsets.UTF_8).size.toLong()
            is Int,
            is Long,
            is Float,
            is Boolean,
            is Double,
            -> value.toString().toByteArray(Charsets.UTF_8).size.toLong()
            is Set<*> -> value.sumOf { item -> (item?.toString() ?: "").toByteArray(Charsets.UTF_8).size.toLong() }
            else -> value.toString().toByteArray(Charsets.UTF_8).size.toLong()
        }
    }
}

private data class FileStats(
    val bytes: Long = 0L,
    val fileCount: Int = 0,
)

private fun File.canonicalOrSelf(): File = runCatching { canonicalFile }.getOrDefault(this)
