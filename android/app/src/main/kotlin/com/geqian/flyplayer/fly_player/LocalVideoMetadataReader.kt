package com.geqian.flyplayer.fly_player

import android.media.MediaMetadataRetriever
import java.io.File
import kotlin.math.max

object LocalVideoMetadataReader {
    fun read(path: String): Map<String, Any?> {
        val normalizedPath = path.trim()
        if (normalizedPath.isEmpty()) return emptyMap()
        val file = File(normalizedPath)
        if (!file.exists() || !file.isFile || !file.canRead()) {
            return emptyMap()
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(normalizedPath)
            val durationMs =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?: 0L
            val width =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull()
                    ?: 0
            val height =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull()
                    ?: 0
            val rotation =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull()
                    ?: 0
            val normalizedWidth =
                if ((rotation == 90 || rotation == 270) && width > 0 && height > 0) {
                    height
                } else {
                    width
                }
            val normalizedHeight =
                if ((rotation == 90 || rotation == 270) && width > 0 && height > 0) {
                    width
                } else {
                    height
                }
            mapOf(
                "durationMs" to max(0L, durationMs),
                "width" to max(0, normalizedWidth),
                "height" to max(0, normalizedHeight),
                "rotation" to rotation,
            )
        } catch (_: Throwable) {
            emptyMap()
        } finally {
            runCatching { retriever.release() }
        }
    }
}
