package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.net.Uri
import android.os.Environment
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Locale

private const val PLAYBACK_CACHE_MAX_BYTES = 10L * 1024L * 1024L * 1024L
private const val PLAYBACK_CACHE_TARGET_BYTES = 8L * 1024L * 1024L * 1024L

data class PersistentPlaybackCacheDescriptor(
    val resourceKey: String,
    val contentVariantKey: String,
    val itemGuid: String,
    val mediaGuid: String,
    val videoGuid: String,
    val title: String,
    val seriesTitle: String,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val resolution: String,
    val bitrate: Int,
    val sourceUrlFingerprint: String,
    val headerFingerprint: String,
) {
    companion object {
        fun fromSource(source: MpvSource): PersistentPlaybackCacheDescriptor {
            val normalizedUrl = normalizePlaybackUrl(source.url)
            val normalizedHeaders = normalizeKeyHeaders(source.headers)
            val contentVariantKey = sha256(
                listOf(
                    source.itemGuid.trim(),
                    source.mediaGuid.trim(),
                    source.videoGuid.trim(),
                    source.resolution.trim(),
                    source.bitrate.toString(),
                ).joinToString("|"),
            )
            val stableResourceIdentity =
                listOf(
                    source.mediaGuid.trim(),
                    source.videoGuid.trim(),
                    source.resolution.trim(),
                    source.bitrate.toString(),
                ).joinToString("|")
            val resourceKey = sha256(
                listOf(
                    stableResourceIdentity,
                    contentVariantKey,
                ).joinToString("|"),
            )
            return PersistentPlaybackCacheDescriptor(
                resourceKey = resourceKey,
                contentVariantKey = contentVariantKey,
                itemGuid = source.itemGuid.trim(),
                mediaGuid = source.mediaGuid.trim(),
                videoGuid = source.videoGuid.trim(),
                title = source.title.trim(),
                seriesTitle = source.seriesTitle.trim().ifEmpty { source.ancestorName.trim() },
                seasonNumber = source.seasonNumber,
                episodeNumber = source.episodeNumber,
                resolution = source.resolution.trim(),
                bitrate = source.bitrate,
                sourceUrlFingerprint = sha256(normalizedUrl),
                headerFingerprint = sha256(normalizedHeaders),
            )
        }

        private fun normalizePlaybackUrl(url: String): String {
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return url.trim()
            val scheme = uri.scheme?.lowercase(Locale.US).orEmpty()
            val host = uri.host?.lowercase(Locale.US).orEmpty()
            val path = uri.encodedPath.orEmpty()
            val stableParams = uri.queryParameterNames
                .map { it.trim() }
                .filter { it.isNotEmpty() && !isSensitiveQueryParameter(it) }
                .sorted()
                .joinToString("&") { key ->
                    val value = uri.getQueryParameter(key)?.trim().orEmpty()
                    if (value.isEmpty()) key else "$key=$value"
                }
            return buildString {
                append(scheme)
                append("://")
                append(host)
                append(path)
                if (stableParams.isNotEmpty()) {
                    append('?')
                    append(stableParams)
                }
            }
        }

        private fun normalizeKeyHeaders(headers: Map<String, String>): String {
            return headers.entries
                .map { it.key.trim().lowercase(Locale.US) to it.value.trim() }
                .filter { it.first.isNotEmpty() }
                .sortedBy { it.first }
                .joinToString("&") { (key, value) ->
                    when {
                        key == "authorization" || key == "trim-mc-token" -> "$key=present"
                        key == "cookie" -> "$key=present"
                        key == "user-agent" || key == "referer" || key == "origin" -> "$key=$value"
                        else -> key
                    }
                }
        }

        private fun isSensitiveQueryParameter(key: String): Boolean {
            val lower = key.lowercase(Locale.US)
            return lower.contains("token") ||
                lower.contains("signature") ||
                lower.contains("credential") ||
                lower.contains("expires") ||
                lower == "authx" ||
                lower == "awsaccesskeyid"
        }
    }
}

data class PersistentPlaybackCacheMetadata(
    val resourceKey: String,
    val contentVariantKey: String,
    val itemGuid: String,
    val mediaGuid: String,
    val videoGuid: String,
    val title: String,
    val seriesTitle: String,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val resolution: String,
    val bitrate: Int,
    val mimeType: String,
    val totalBytes: Long,
    val downloadedBytes: Long,
    val cachedRanges: List<LongRange>,
    val isComplete: Boolean,
    val lastAccessAtMs: Long,
    val sourceUrlFingerprint: String,
    val headerFingerprint: String,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("resourceKey", resourceKey)
            .put("contentVariantKey", contentVariantKey)
            .put("itemGuid", itemGuid)
            .put("mediaGuid", mediaGuid)
            .put("videoGuid", videoGuid)
            .put("title", title)
            .put("seriesTitle", seriesTitle)
            .put("seasonNumber", seasonNumber)
            .put("episodeNumber", episodeNumber)
            .put("resolution", resolution)
            .put("bitrate", bitrate)
            .put("mimeType", mimeType)
            .put("totalBytes", totalBytes)
            .put("downloadedBytes", downloadedBytes)
            .put("isComplete", isComplete)
            .put("lastAccessAtMs", lastAccessAtMs)
            .put("sourceUrlFingerprint", sourceUrlFingerprint)
            .put("headerFingerprint", headerFingerprint)
            .put(
                "cachedRanges",
                JSONArray().apply {
                    cachedRanges.forEach { range ->
                        put(
                            JSONObject()
                                .put("start", range.first)
                                .put("end", range.last),
                        )
                    }
                },
            )
    }

    companion object {
        fun fromJson(json: JSONObject): PersistentPlaybackCacheMetadata {
            val rangesJson = json.optJSONArray("cachedRanges") ?: JSONArray()
            val ranges = buildList {
                for (index in 0 until rangesJson.length()) {
                    val item = rangesJson.optJSONObject(index) ?: continue
                    val start = item.optLong("start", -1L)
                    val end = item.optLong("end", -1L)
                    if (start >= 0L && end >= start) {
                        add(start..end)
                    }
                }
            }
            return PersistentPlaybackCacheMetadata(
                resourceKey = json.optString("resourceKey"),
                contentVariantKey = json.optString("contentVariantKey"),
                itemGuid = json.optString("itemGuid"),
                mediaGuid = json.optString("mediaGuid"),
                videoGuid = json.optString("videoGuid"),
                title = json.optString("title"),
                seriesTitle = json.optString("seriesTitle"),
                seasonNumber = json.optInt("seasonNumber"),
                episodeNumber = json.optInt("episodeNumber"),
                resolution = json.optString("resolution"),
                bitrate = json.optInt("bitrate"),
                mimeType = json.optString("mimeType", "application/octet-stream"),
                totalBytes = json.optLong("totalBytes", -1L),
                downloadedBytes = json.optLong("downloadedBytes", 0L),
                cachedRanges = ranges,
                isComplete = json.optBoolean("isComplete", false),
                lastAccessAtMs = json.optLong("lastAccessAtMs", System.currentTimeMillis()),
                sourceUrlFingerprint = json.optString("sourceUrlFingerprint"),
                headerFingerprint = json.optString("headerFingerprint"),
            )
        }
    }
}

data class PersistentPlaybackCacheStats(
    val totalBytes: Long,
    val fileCount: Int,
    val completeCount: Int,
)

data class PersistentPlaybackCacheListItem(
    val resourceKey: String,
    val itemGuid: String,
    val mediaGuid: String,
    val videoGuid: String,
    val title: String,
    val seriesTitle: String,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val resolution: String,
    val subtitle: String,
    val bytes: Long,
    val totalBytes: Long,
    val isComplete: Boolean,
    val mimeType: String,
    val lastAccessAtMs: Long,
)

data class PersistentPlaybackCacheLocalPlayback(
    val resourceKey: String,
    val filePath: String,
    val mimeType: String,
)

class PersistentPlaybackCacheEntry internal constructor(
    val rootDir: File,
    metadata: PersistentPlaybackCacheMetadata,
) {
    private val lock = Any()

    val dataFile: File = rootDir.resolve("media.cache")
    val metadataFile: File = rootDir.resolve("meta.json")

    @Volatile
    var metadata: PersistentPlaybackCacheMetadata = metadata
        private set

    init {
        rootDir.mkdirs()
        if (!dataFile.exists()) {
            runCatching { dataFile.createNewFile() }
        }
        persist()
    }

    fun touch() {
        synchronized(lock) {
            metadata = metadata.copy(lastAccessAtMs = System.currentTimeMillis())
            persistLocked()
        }
    }

    fun updateRemoteState(totalBytes: Long, mimeType: String) {
        synchronized(lock) {
            metadata = metadata.copy(
                totalBytes = totalBytes,
                mimeType = mimeType.ifBlank { metadata.mimeType },
                lastAccessAtMs = System.currentTimeMillis(),
            )
            persistLocked()
        }
    }

    fun updateRanges(ranges: List<LongRange>, downloadedBytes: Long, totalBytes: Long, mimeType: String, complete: Boolean) {
        synchronized(lock) {
            metadata = metadata.copy(
                cachedRanges = ranges.toList(),
                downloadedBytes = downloadedBytes.coerceAtLeast(0L),
                totalBytes = if (totalBytes > 0L) totalBytes else metadata.totalBytes,
                mimeType = mimeType.ifBlank { metadata.mimeType },
                isComplete = complete,
                lastAccessAtMs = System.currentTimeMillis(),
            )
            persistLocked()
        }
    }

    fun reloadFromDisk(): PersistentPlaybackCacheMetadata {
        synchronized(lock) {
            metadata = loadMetadata(metadataFile) ?: metadata
            return metadata
        }
    }

    private fun persist() {
        synchronized(lock) {
            persistLocked()
        }
    }

    private fun persistLocked() {
        runCatching {
            metadataFile.writeText(metadata.toJson().toString(), Charsets.UTF_8)
        }
    }
}

class PersistentPlaybackCacheStore(
    context: Context,
) {
    private val rootDir: File = context.getDir("playback_cache", Context.MODE_PRIVATE).apply {
        mkdirs()
    }

    fun resolveEntry(descriptor: PersistentPlaybackCacheDescriptor): PersistentPlaybackCacheEntry {
        val reused = findReusableEntry(descriptor)
        val entryDir = reused?.rootDir ?: rootDir.resolve(descriptor.resourceKey).apply { mkdirs() }
        val metadataFile = entryDir.resolve("meta.json")
        val loaded = loadMetadata(metadataFile)
        val metadata = loaded?.copy(
            itemGuid = descriptor.itemGuid.ifEmpty { loaded.itemGuid },
            mediaGuid = descriptor.mediaGuid.ifEmpty { loaded.mediaGuid },
            videoGuid = descriptor.videoGuid.ifEmpty { loaded.videoGuid },
            title = descriptor.title.ifEmpty { loaded.title },
            seriesTitle = descriptor.seriesTitle.ifEmpty { loaded.seriesTitle },
            seasonNumber = if (descriptor.seasonNumber != 0) descriptor.seasonNumber else loaded.seasonNumber,
            episodeNumber = if (descriptor.episodeNumber != 0) descriptor.episodeNumber else loaded.episodeNumber,
            resolution = descriptor.resolution.ifEmpty { loaded.resolution },
            bitrate = if (descriptor.bitrate > 0) descriptor.bitrate else loaded.bitrate,
            contentVariantKey = descriptor.contentVariantKey.ifEmpty { loaded.contentVariantKey },
            sourceUrlFingerprint = descriptor.sourceUrlFingerprint.ifEmpty { loaded.sourceUrlFingerprint },
            headerFingerprint = descriptor.headerFingerprint.ifEmpty { loaded.headerFingerprint },
            lastAccessAtMs = System.currentTimeMillis(),
        ) ?: PersistentPlaybackCacheMetadata(
            resourceKey = descriptor.resourceKey,
            contentVariantKey = descriptor.contentVariantKey,
            itemGuid = descriptor.itemGuid,
            mediaGuid = descriptor.mediaGuid,
            videoGuid = descriptor.videoGuid,
            title = descriptor.title,
            seriesTitle = descriptor.seriesTitle,
            seasonNumber = descriptor.seasonNumber,
            episodeNumber = descriptor.episodeNumber,
            resolution = descriptor.resolution,
            bitrate = descriptor.bitrate,
            mimeType = "application/octet-stream",
            totalBytes = -1L,
            downloadedBytes = 0L,
            cachedRanges = emptyList(),
            isComplete = false,
            lastAccessAtMs = System.currentTimeMillis(),
            sourceUrlFingerprint = descriptor.sourceUrlFingerprint,
            headerFingerprint = descriptor.headerFingerprint,
        )
        return PersistentPlaybackCacheEntry(entryDir, metadata)
    }

    fun hasReusableEntry(descriptor: PersistentPlaybackCacheDescriptor): Boolean {
        return findReusableEntry(descriptor) != null
    }

    fun findCompleteLocalPlayback(
        descriptor: PersistentPlaybackCacheDescriptor,
    ): PersistentPlaybackCacheLocalPlayback? {
        val entry = findReusableEntry(descriptor) ?: return null
        val metadata = entry.reloadFromDisk()
        val file = entry.dataFile
        val fileLength = runCatching { file.length() }.getOrDefault(0L)
        val totalBytes = metadata.totalBytes.coerceAtLeast(metadata.downloadedBytes)
        val isUsable =
            metadata.isComplete &&
                file.isFile &&
                fileLength > 0L &&
                metadata.downloadedBytes > 0L &&
                (totalBytes <= 0L || fileLength >= totalBytes || metadata.downloadedBytes >= totalBytes)
        if (!isUsable) return null
        entry.touch()
        return PersistentPlaybackCacheLocalPlayback(
            resourceKey = metadata.resourceKey,
            filePath = file.absolutePath,
            mimeType = metadata.mimeType,
        )
    }

    fun loadStats(): PersistentPlaybackCacheStats {
        val entries = scanEntries()
        return PersistentPlaybackCacheStats(
            totalBytes = entries.sumOf { entry ->
                entry.reloadFromDisk().downloadedBytes.coerceAtLeast(0L)
            },
            fileCount = entries.count { it.reloadFromDisk().downloadedBytes > 0L },
            completeCount = entries.count {
                val metadata = it.reloadFromDisk()
                metadata.isComplete && metadata.downloadedBytes > 0L
            },
        )
    }

    fun listEntries(): List<PersistentPlaybackCacheListItem> {
        return scanEntries()
            .map { entry ->
                val metadata = entry.reloadFromDisk()
                PersistentPlaybackCacheListItem(
                    resourceKey = metadata.resourceKey,
                    itemGuid = metadata.itemGuid,
                    mediaGuid = metadata.mediaGuid,
                    videoGuid = metadata.videoGuid,
                    title = metadata.title.ifBlank { metadata.seriesTitle.ifBlank { metadata.mediaGuid } },
                    seriesTitle = metadata.seriesTitle,
                    seasonNumber = metadata.seasonNumber,
                    episodeNumber = metadata.episodeNumber,
                    resolution = metadata.resolution,
                    subtitle = buildEntrySubtitle(metadata),
                    bytes = metadata.downloadedBytes.coerceAtLeast(0L),
                    totalBytes = metadata.totalBytes.coerceAtLeast(metadata.downloadedBytes),
                    isComplete = metadata.isComplete && metadata.downloadedBytes > 0L,
                    mimeType = metadata.mimeType,
                    lastAccessAtMs = metadata.lastAccessAtMs,
                )
            }
            .filter { it.bytes > 0L }
            .sortedByDescending { it.lastAccessAtMs }
    }

    fun clearAll(protectedResourceKeys: Set<String> = emptySet()): Boolean {
        var changed = false
        rootDir.listFiles()?.forEach { child ->
            if (!child.isDirectory) return@forEach
            if (protectedResourceKeys.contains(child.name)) return@forEach
            changed = true
            runCatching { child.deleteRecursively() }
        }
        return changed
    }

    fun clearEntries(
        resourceKeys: Set<String>,
        protectedResourceKeys: Set<String> = emptySet(),
    ): Int {
        if (resourceKeys.isEmpty()) return 0
        var cleared = 0
        resourceKeys.forEach { resourceKey ->
            val normalized = resourceKey.trim()
            if (normalized.isEmpty() || protectedResourceKeys.contains(normalized)) return@forEach
            val child = rootDir.resolve(normalized)
            if (!child.isDirectory) return@forEach
            val deleted = runCatching { child.deleteRecursively() }.getOrDefault(false)
            if (deleted) {
                cleared += 1
            }
        }
        return cleared
    }

    fun evictIfNeeded(protectedResourceKeys: Set<String> = emptySet()) {
        val entries = scanEntries()
        var totalBytes = entries.sumOf { it.reloadFromDisk().downloadedBytes.coerceAtLeast(0L) }
        if (totalBytes <= PLAYBACK_CACHE_MAX_BYTES) return
        val candidates = entries
            .filter { it.metadata.isComplete && !protectedResourceKeys.contains(it.metadata.resourceKey) }
            .sortedBy { it.metadata.lastAccessAtMs }
        for (entry in candidates) {
            if (totalBytes <= PLAYBACK_CACHE_TARGET_BYTES) break
            val reclaimed = entry.reloadFromDisk().downloadedBytes.coerceAtLeast(0L)
            runCatching { entry.rootDir.deleteRecursively() }
            totalBytes = (totalBytes - reclaimed).coerceAtLeast(0L)
        }
    }

    fun queryDownloadable(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
    ): Map<String, Any?> {
        val entry = findEntry(itemGuid, mediaGuid, videoGuid, resourceKey)
            ?: return mapOf("found" to false, "code" to "not_found")
        val metadata = entry.reloadFromDisk()
        val sizeBytes = metadata.downloadedBytes.coerceAtLeast(0L)
        if (!metadata.isComplete || sizeBytes <= 0L) {
            return mapOf(
                "found" to true,
                "downloadable" to false,
                "code" to "not_complete",
                "resourceKey" to metadata.resourceKey,
                "bytes" to sizeBytes,
                "totalBytes" to metadata.totalBytes.coerceAtLeast(sizeBytes),
            )
        }
        return mapOf(
            "found" to true,
            "downloadable" to true,
            "code" to "ok",
            "resourceKey" to metadata.resourceKey,
            "bytes" to sizeBytes,
            "totalBytes" to metadata.totalBytes.coerceAtLeast(sizeBytes),
            "mimeType" to metadata.mimeType,
            "suggestedFileName" to buildSuggestedFileName(metadata),
            "title" to metadata.title,
        )
    }

    fun promote(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
        targetMode: String,
        hasFileAccess: Boolean,
        context: Context,
    ): Map<String, Any?> {
        val entry = findEntry(itemGuid, mediaGuid, videoGuid, resourceKey)
            ?: return mapOf("success" to false, "code" to "not_found")
        val metadata = entry.reloadFromDisk()
        val sourceFile = entry.dataFile
        if (!metadata.isComplete || !sourceFile.isFile || sourceFile.length() <= 0L) {
            return mapOf("success" to false, "code" to "not_complete")
        }
        val targetRoot = when (targetMode) {
            "appExternalMovies" -> {
                context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)?.resolve("FlyPlayer")
            }
            "publicDownloads" -> {
                if (!hasFileAccess) {
                    return mapOf("success" to false, "code" to "permission_required")
                }
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "FlyPlayer")
            }
            else -> null
        } ?: return mapOf("success" to false, "code" to "invalid_target")
        targetRoot.mkdirs()
        val targetFile = uniqueTargetFile(targetRoot, buildSuggestedFileName(metadata))
        return runCatching {
            sourceFile.copyTo(targetFile, overwrite = false)
            mapOf(
                "success" to true,
                "code" to "ok",
                "path" to targetFile.absolutePath,
                "fileName" to targetFile.name,
            )
        }.getOrElse {
            mapOf("success" to false, "code" to "copy_failed")
        }
    }

    fun currentLimitBytes(): Long = PLAYBACK_CACHE_MAX_BYTES

    private fun findEntry(
        itemGuid: String,
        mediaGuid: String,
        videoGuid: String,
        resourceKey: String,
    ): PersistentPlaybackCacheEntry? {
        if (resourceKey.isNotBlank()) {
            val entryDir = rootDir.resolve(resourceKey)
            if (entryDir.isDirectory) {
                val metadata = loadMetadata(entryDir.resolve("meta.json")) ?: return null
                return PersistentPlaybackCacheEntry(entryDir, metadata)
            }
        }
        return scanEntries().firstOrNull { entry ->
            val metadata = entry.metadata
            metadata.itemGuid == itemGuid.trim() &&
                metadata.mediaGuid == mediaGuid.trim() &&
                metadata.videoGuid == videoGuid.trim()
        }
    }

    private fun findReusableEntry(
        descriptor: PersistentPlaybackCacheDescriptor,
    ): PersistentPlaybackCacheEntry? {
        val direct = rootDir.resolve(descriptor.resourceKey)
        if (direct.isDirectory) {
            val metadata = loadMetadata(direct.resolve("meta.json")) ?: return null
            return PersistentPlaybackCacheEntry(direct, metadata)
        }
        return scanEntries().firstOrNull { entry ->
            val metadata = entry.metadata
            when {
                metadata.contentVariantKey == descriptor.contentVariantKey -> true
                metadata.mediaGuid.isNotBlank() &&
                    metadata.videoGuid.isNotBlank() &&
                    metadata.mediaGuid == descriptor.mediaGuid &&
                    metadata.videoGuid == descriptor.videoGuid &&
                    metadata.resolution == descriptor.resolution &&
                    metadata.bitrate == descriptor.bitrate -> true
                else -> false
            }
        }
    }

    private fun scanEntries(): List<PersistentPlaybackCacheEntry> {
        val entries = mutableListOf<PersistentPlaybackCacheEntry>()
        rootDir.listFiles()?.forEach { child ->
            if (!child.isDirectory) return@forEach
            val metadata = loadMetadata(child.resolve("meta.json")) ?: return@forEach
            entries += PersistentPlaybackCacheEntry(child, metadata)
        }
        return entries
    }

    private fun buildSuggestedFileName(metadata: PersistentPlaybackCacheMetadata): String {
        val extension = guessExtension(metadata.mimeType)
        val baseName = when {
            metadata.episodeNumber > 0 -> {
                val series = metadata.seriesTitle.ifBlank { metadata.title }.trim()
                when {
                    metadata.seasonNumber == 0 -> "$series·特别篇·第${metadata.episodeNumber}集"
                    metadata.seasonNumber > 0 -> "$series·第${metadata.seasonNumber}季·第${metadata.episodeNumber}集"
                    else -> "$series·第${metadata.episodeNumber}集"
                }
            }
            metadata.seasonNumber > 0 -> {
                val series = metadata.seriesTitle.ifBlank { metadata.title }.trim()
                "$series·第${metadata.seasonNumber}季"
            }
            metadata.seasonNumber == 0 && metadata.seriesTitle.isNotBlank() -> {
                val series = metadata.seriesTitle.trim()
                "$series·特别篇"
            }
            else -> metadata.title.ifBlank { metadata.mediaGuid.ifBlank { "video" } }.trim()
        }
        return sanitizeFileName("$baseName.$extension")
    }

    private fun buildEntrySubtitle(metadata: PersistentPlaybackCacheMetadata): String {
        val segments = mutableListOf<String>()
        val series = metadata.seriesTitle.trim()
        if (series.isNotEmpty() && !metadata.title.contains(series)) {
            segments += series
        }
        when {
            metadata.episodeNumber > 0 && metadata.seasonNumber == 0 -> {
                segments += "特别篇"
                segments += "第${metadata.episodeNumber}集"
            }
            metadata.episodeNumber > 0 && metadata.seasonNumber > 0 -> {
                segments += "第${metadata.seasonNumber}季"
                segments += "第${metadata.episodeNumber}集"
            }
            metadata.seasonNumber > 0 -> {
                segments += "第${metadata.seasonNumber}季"
            }
        }
        if (metadata.resolution.isNotBlank()) {
            segments += metadata.resolution
        }
        return segments.joinToString(" · ")
    }

    private fun uniqueTargetFile(root: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val base = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var candidate = root.resolve(fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = root.resolve("$base ($index)$extension")
            index++
        }
        return candidate
    }

    private fun guessExtension(mimeType: String): String {
        val normalized = mimeType.lowercase(Locale.US)
        return when {
            normalized.contains("mp4") -> "mp4"
            normalized.contains("matroska") || normalized.contains("mkv") -> "mkv"
            normalized.contains("mpegurl") || normalized.contains("m3u8") -> "m3u8"
            normalized.contains("mp2t") || normalized.contains("mpegts") -> "ts"
            normalized.contains("webm") -> "webm"
            normalized.contains("avi") -> "avi"
            else -> "mp4"
        }
    }

    private fun sanitizeFileName(value: String): String {
        return value.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "video.mp4" }
    }
}

private fun loadMetadata(file: File): PersistentPlaybackCacheMetadata? {
    if (!file.isFile) return null
    return runCatching {
        PersistentPlaybackCacheMetadata.fromJson(JSONObject(file.readText(Charsets.UTF_8)))
    }.getOrNull()
}

private fun sha256(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    return digest.digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { byte ->
        "%02x".format(byte)
    }
}
