package com.geqian.flyplayer.fly_player

import android.content.Intent
import android.os.Bundle
import java.io.Serializable
import java.util.ArrayList
import java.util.HashMap

data class PlaybackSessionPayload(
    val itemGuid: String,
    val title: String,
    val subtitle: String,
    val albumTitle: String,
    val artist: String,
    val description: String,
    val mediaType: String,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val trackCount: Int,
    val artworkUrl: String,
    val artworkUrls: List<String>,
    val artworkHeaders: Map<String, String>,
    val isPlaying: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val speed: Double,
    val canSeek: Boolean,
    val canPause: Boolean,
    val canPlay: Boolean,
    val canSkipToPrevious: Boolean,
    val canSkipToNext: Boolean,
    val ready: Boolean,
    val error: String?,
    val launchTitle: String,
    val launchSource: HashMap<String, Any?>?,
    val launchFromParallelHost: Boolean,
    val launchLayoutMode: String,
    val launchInitialRightPaneRoute: String,
) {
    fun toBundle(): Bundle =
        Bundle().apply {
            putString(EXTRA_ITEM_GUID, itemGuid)
            putString(EXTRA_TITLE, title)
            putString(EXTRA_SUBTITLE, subtitle)
            putString(EXTRA_ALBUM_TITLE, albumTitle)
            putString(EXTRA_ARTIST, artist)
            putString(EXTRA_DESCRIPTION, description)
            putString(EXTRA_MEDIA_TYPE, mediaType)
            putInt(EXTRA_SEASON_NUMBER, seasonNumber)
            putInt(EXTRA_EPISODE_NUMBER, episodeNumber)
            putInt(EXTRA_TRACK_COUNT, trackCount)
            putString(EXTRA_ARTWORK_URL, artworkUrl)
            putStringArrayList(EXTRA_ARTWORK_URLS, ArrayList(artworkUrls))
            putBundle(
                EXTRA_ARTWORK_HEADERS,
                Bundle().apply {
                    artworkHeaders.forEach { (key, value) ->
                        putString(key, value)
                    }
                },
            )
            putBoolean(EXTRA_IS_PLAYING, isPlaying)
            putLong(EXTRA_POSITION_MS, positionMs)
            putLong(EXTRA_DURATION_MS, durationMs)
            putDouble(EXTRA_SPEED, speed)
            putBoolean(EXTRA_CAN_SEEK, canSeek)
            putBoolean(EXTRA_CAN_PAUSE, canPause)
            putBoolean(EXTRA_CAN_PLAY, canPlay)
            putBoolean(EXTRA_CAN_SKIP_TO_PREVIOUS, canSkipToPrevious)
            putBoolean(EXTRA_CAN_SKIP_TO_NEXT, canSkipToNext)
            putBoolean(EXTRA_READY, ready)
            putString(EXTRA_ERROR, error)
            putString(EXTRA_LAUNCH_TITLE, launchTitle)
            putSerializable(EXTRA_LAUNCH_SOURCE, launchSource)
            putBoolean(EXTRA_LAUNCH_FROM_PARALLEL_HOST, launchFromParallelHost)
            putString(EXTRA_LAUNCH_LAYOUT_MODE, launchLayoutMode)
            putString(EXTRA_LAUNCH_INITIAL_RIGHT_PANE_ROUTE, launchInitialRightPaneRoute)
        }

    companion object {
        private const val EXTRA_ITEM_GUID = "itemGuid"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SUBTITLE = "subtitle"
        private const val EXTRA_ALBUM_TITLE = "albumTitle"
        private const val EXTRA_ARTIST = "artist"
        private const val EXTRA_DESCRIPTION = "description"
        private const val EXTRA_MEDIA_TYPE = "mediaType"
        private const val EXTRA_SEASON_NUMBER = "seasonNumber"
        private const val EXTRA_EPISODE_NUMBER = "episodeNumber"
        private const val EXTRA_TRACK_COUNT = "trackCount"
        private const val EXTRA_ARTWORK_URL = "artworkUrl"
        private const val EXTRA_ARTWORK_URLS = "artworkUrls"
        private const val EXTRA_ARTWORK_HEADERS = "artworkHeaders"
        private const val EXTRA_IS_PLAYING = "isPlaying"
        private const val EXTRA_POSITION_MS = "positionMs"
        private const val EXTRA_DURATION_MS = "durationMs"
        private const val EXTRA_SPEED = "speed"
        private const val EXTRA_CAN_SEEK = "canSeek"
        private const val EXTRA_CAN_PAUSE = "canPause"
        private const val EXTRA_CAN_PLAY = "canPlay"
        private const val EXTRA_CAN_SKIP_TO_PREVIOUS = "canSkipToPrevious"
        private const val EXTRA_CAN_SKIP_TO_NEXT = "canSkipToNext"
        private const val EXTRA_READY = "ready"
        private const val EXTRA_ERROR = "error"
        private const val EXTRA_LAUNCH_TITLE = "launchTitle"
        private const val EXTRA_LAUNCH_SOURCE = "launchSource"
        private const val EXTRA_LAUNCH_FROM_PARALLEL_HOST = "launchFromParallelHost"
        private const val EXTRA_LAUNCH_LAYOUT_MODE = "launchLayoutMode"
        private const val EXTRA_LAUNCH_INITIAL_RIGHT_PANE_ROUTE = "launchInitialRightPaneRoute"

        fun fromArguments(arguments: Any?): PlaybackSessionPayload? {
            val map = arguments as? Map<*, *> ?: return null
            val title = map[EXTRA_TITLE]?.toString()?.trim().orEmpty()
            if (title.isEmpty()) return null
            return PlaybackSessionPayload(
                itemGuid = map[EXTRA_ITEM_GUID]?.toString()?.trim().orEmpty(),
                title = title,
                subtitle = map[EXTRA_SUBTITLE]?.toString()?.trim().orEmpty(),
                albumTitle = map[EXTRA_ALBUM_TITLE]?.toString()?.trim().orEmpty(),
                artist = map[EXTRA_ARTIST]?.toString()?.trim().orEmpty(),
                description = map[EXTRA_DESCRIPTION]?.toString()?.trim().orEmpty(),
                mediaType = map[EXTRA_MEDIA_TYPE]?.toString()?.trim().orEmpty(),
                seasonNumber = intOf(map[EXTRA_SEASON_NUMBER]),
                episodeNumber = intOf(map[EXTRA_EPISODE_NUMBER]),
                trackCount = intOf(map[EXTRA_TRACK_COUNT]),
                artworkUrl = map[EXTRA_ARTWORK_URL]?.toString()?.trim().orEmpty(),
                artworkUrls = stringListOf(map[EXTRA_ARTWORK_URLS]),
                artworkHeaders = stringMapOf(map[EXTRA_ARTWORK_HEADERS]),
                isPlaying = map[EXTRA_IS_PLAYING] as? Boolean ?: false,
                positionMs = longOf(map[EXTRA_POSITION_MS]),
                durationMs = longOf(map[EXTRA_DURATION_MS]),
                speed = doubleOf(map[EXTRA_SPEED]).coerceIn(0.0, 8.0),
                canSeek = map[EXTRA_CAN_SEEK] as? Boolean ?: false,
                canPause = map[EXTRA_CAN_PAUSE] as? Boolean ?: true,
                canPlay = map[EXTRA_CAN_PLAY] as? Boolean ?: true,
                canSkipToPrevious = map[EXTRA_CAN_SKIP_TO_PREVIOUS] as? Boolean ?: false,
                canSkipToNext = map[EXTRA_CAN_SKIP_TO_NEXT] as? Boolean ?: false,
                ready = map[EXTRA_READY] as? Boolean ?: false,
                error = map[EXTRA_ERROR]?.toString()?.trim()?.ifEmpty { null },
                launchTitle =
                    map[EXTRA_LAUNCH_TITLE]?.toString()?.trim()?.ifEmpty { null } ?: title,
                launchSource = serializableHashMapOf(map[EXTRA_LAUNCH_SOURCE]),
                launchFromParallelHost =
                    map[EXTRA_LAUNCH_FROM_PARALLEL_HOST] as? Boolean ?: false,
                launchLayoutMode =
                    map[EXTRA_LAUNCH_LAYOUT_MODE]
                        ?.toString()
                        ?.trim()
                        ?.ifEmpty { null } ?: PlayerLaunchContract.MODE_FULLSCREEN,
                launchInitialRightPaneRoute =
                    map[EXTRA_LAUNCH_INITIAL_RIGHT_PANE_ROUTE]?.toString()?.trim().orEmpty(),
            )
        }

        fun fromIntent(intent: Intent?): PlaybackSessionPayload? {
            val extras = intent?.extras ?: return null
            val title = extras.getString(EXTRA_TITLE).orEmpty().trim()
            if (title.isEmpty()) return null
            return PlaybackSessionPayload(
                itemGuid = extras.getString(EXTRA_ITEM_GUID).orEmpty().trim(),
                title = title,
                subtitle = extras.getString(EXTRA_SUBTITLE).orEmpty().trim(),
                albumTitle = extras.getString(EXTRA_ALBUM_TITLE).orEmpty().trim(),
                artist = extras.getString(EXTRA_ARTIST).orEmpty().trim(),
                description = extras.getString(EXTRA_DESCRIPTION).orEmpty().trim(),
                mediaType = extras.getString(EXTRA_MEDIA_TYPE).orEmpty().trim(),
                seasonNumber = extras.getInt(EXTRA_SEASON_NUMBER, 0).coerceAtLeast(0),
                episodeNumber = extras.getInt(EXTRA_EPISODE_NUMBER, 0).coerceAtLeast(0),
                trackCount = extras.getInt(EXTRA_TRACK_COUNT, 0).coerceAtLeast(0),
                artworkUrl = extras.getString(EXTRA_ARTWORK_URL).orEmpty().trim(),
                artworkUrls = extras.getStringArrayList(EXTRA_ARTWORK_URLS)?.filter {
                    it.trim().isNotEmpty()
                } ?: emptyList(),
                artworkHeaders = stringMapOf(extras.getBundle(EXTRA_ARTWORK_HEADERS)),
                isPlaying = extras.getBoolean(EXTRA_IS_PLAYING, false),
                positionMs = extras.getLong(EXTRA_POSITION_MS, 0L).coerceAtLeast(0L),
                durationMs = extras.getLong(EXTRA_DURATION_MS, 0L).coerceAtLeast(0L),
                speed = extras.getDouble(EXTRA_SPEED, 1.0).coerceIn(0.0, 8.0),
                canSeek = extras.getBoolean(EXTRA_CAN_SEEK, false),
                canPause = extras.getBoolean(EXTRA_CAN_PAUSE, true),
                canPlay = extras.getBoolean(EXTRA_CAN_PLAY, true),
                canSkipToPrevious = extras.getBoolean(EXTRA_CAN_SKIP_TO_PREVIOUS, false),
                canSkipToNext = extras.getBoolean(EXTRA_CAN_SKIP_TO_NEXT, false),
                ready = extras.getBoolean(EXTRA_READY, false),
                error = extras.getString(EXTRA_ERROR)?.trim()?.ifEmpty { null },
                launchTitle =
                    extras.getString(EXTRA_LAUNCH_TITLE)?.trim()?.ifEmpty { null } ?: title,
                launchSource = readSerializableHashMap(extras, EXTRA_LAUNCH_SOURCE),
                launchFromParallelHost =
                    extras.getBoolean(EXTRA_LAUNCH_FROM_PARALLEL_HOST, false),
                launchLayoutMode =
                    extras.getString(EXTRA_LAUNCH_LAYOUT_MODE)
                        ?.trim()
                        ?.ifEmpty { null } ?: PlayerLaunchContract.MODE_FULLSCREEN,
                launchInitialRightPaneRoute =
                    extras.getString(EXTRA_LAUNCH_INITIAL_RIGHT_PANE_ROUTE).orEmpty().trim(),
            )
        }

        private fun intOf(value: Any?): Int =
            when (value) {
                is Int -> value
                is Long -> value.toInt()
                is Number -> value.toInt()
                else -> value?.toString()?.toIntOrNull() ?: 0
            }.coerceAtLeast(0)

        private fun stringListOf(value: Any?): List<String> =
            when (value) {
                is List<*> ->
                    value
                        .mapNotNull { entry ->
                            entry?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                        }.distinct()
                else -> emptyList()
            }

        private fun stringMapOf(value: Any?): Map<String, String> =
            when (value) {
                is Map<*, *> ->
                    value.entries
                        .mapNotNull { (key, entryValue) ->
                            val normalizedKey = key?.toString()?.trim().orEmpty()
                            val normalizedValue = entryValue?.toString()?.trim().orEmpty()
                            if (normalizedKey.isEmpty() || normalizedValue.isEmpty()) {
                                null
                            } else {
                                normalizedKey to normalizedValue
                            }
                        }.toMap()
                is Bundle ->
                    value.keySet().mapNotNull { key ->
                        val normalizedKey = key.trim()
                        val normalizedValue = value.getString(key).orEmpty().trim()
                        if (normalizedKey.isEmpty() || normalizedValue.isEmpty()) {
                            null
                        } else {
                            normalizedKey to normalizedValue
                        }
                    }.toMap()
                else -> emptyMap()
            }

        private fun serializableHashMapOf(value: Any?): HashMap<String, Any?>? {
            val rawMap = value as? Map<*, *> ?: return null
            if (rawMap.isEmpty()) return null
            val normalized = HashMap<String, Any?>()
            rawMap.forEach { (key, entryValue) ->
                val normalizedKey = key?.toString()?.trim().orEmpty()
                if (normalizedKey.isEmpty()) {
                    return@forEach
                }
                normalized[normalizedKey] = serializableValueOf(entryValue)
            }
            return normalized.takeIf { it.isNotEmpty() }
        }

        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        private fun readSerializableHashMap(
            extras: Bundle,
            key: String,
        ): HashMap<String, Any?>? {
            val value =
                extras.get(key)
                    ?: if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        extras.getSerializable(key, HashMap::class.java)
                    } else {
                        extras.getSerializable(key)
                    }
            return when (value) {
                is HashMap<*, *> -> value as HashMap<String, Any?>
                is Map<*, *> -> serializableHashMapOf(value)
                is Serializable -> value as? HashMap<String, Any?>
                else -> null
            }
        }

        private fun serializableValueOf(value: Any?): Any? =
            when (value) {
                null,
                is String,
                is Boolean,
                is Int,
                is Long,
                is Double,
                is Float,
                is Short,
                is Byte,
                is Char,
                -> value
                is Map<*, *> -> serializableHashMapOf(value)
                is List<*> -> ArrayList(value.map(::serializableValueOf))
                else -> value.toString()
            }

        private fun longOf(value: Any?): Long =
            when (value) {
                is Long -> value
                is Int -> value.toLong()
                is Number -> value.toLong()
                else -> value?.toString()?.toLongOrNull() ?: 0L
            }.coerceAtLeast(0L)

        private fun doubleOf(value: Any?): Double =
            when (value) {
                is Double -> value
                is Float -> value.toDouble()
                is Number -> value.toDouble()
                else -> value?.toString()?.toDoubleOrNull() ?: 1.0
            }
    }
}
