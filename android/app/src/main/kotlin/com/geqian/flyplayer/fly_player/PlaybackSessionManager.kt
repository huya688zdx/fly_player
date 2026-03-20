package com.geqian.flyplayer.fly_player

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.util.LruCache
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PlaybackSessionManager(
    private val context: Context,
    private val onNotificationInvalidated: () -> Unit,
) {
    private val logTag = "PlaybackSessionManager"
    private val mediaSession =
        MediaSessionCompat(context, SESSION_TAG).apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onSkipToPrevious() {
                        PlaybackSessionCoordinator.dispatchCommand("systemSkipToPrevious")
                    }

                    override fun onPlay() {
                        PlaybackSessionCoordinator.dispatchCommand("systemPlay")
                    }

                    override fun onPause() {
                        PlaybackSessionCoordinator.dispatchCommand("systemPause")
                    }

                    override fun onSeekTo(pos: Long) {
                        PlaybackSessionCoordinator.dispatchCommand(
                            "systemSeekTo",
                            hashMapOf("positionMs" to pos.coerceAtLeast(0L)),
                        )
                    }

                    override fun onSkipToNext() {
                        PlaybackSessionCoordinator.dispatchCommand("systemSkipToNext")
                    }
                },
            )
            isActive = true
        }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val artworkExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var lastPayload: PlaybackSessionPayload? = null
    private var artworkBitmap: Bitmap? = null
    private var artworkCandidateKey: String = ""
    private var artworkResolvedUrl: String = ""

    @Volatile
    private var artworkFetchInFlightUrl: String? = null

    @Volatile
    private var released = false

    fun updateSession(payload: PlaybackSessionPayload) {
        lastPayload = payload
        syncArtwork(payload)
        mediaSession.setMetadata(buildMetadata(payload, artworkBitmap))
        mediaSession.setPlaybackState(buildPlaybackState(payload))
        mediaSession.setExtras(buildSessionExtras(payload))
        mediaSession.setQueueTitle(payload.albumTitle.ifBlank { payload.title })
        mediaSession.setSessionActivity(buildContentIntent())
        mediaSession.isActive = true
    }

    fun buildNotification(): android.app.Notification {
        val payload = lastPayload ?: error("Playback payload is not available")
        val actions = mutableListOf<NotificationCompat.Action>()
        val compactViewIndexes = mutableListOf<Int>()
        val playPauseAction =
            if (payload.isPlaying) {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    buildCommandPendingIntent(PlaybackCommandReceiver.ACTION_PAUSE),
                )
            } else {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "Play",
                    buildCommandPendingIntent(PlaybackCommandReceiver.ACTION_PLAY),
                )
            }
        if (payload.canSkipToPrevious) {
            compactViewIndexes += actions.size
            actions +=
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    buildCommandPendingIntent(PlaybackCommandReceiver.ACTION_SKIP_TO_PREVIOUS),
                )
        }
        compactViewIndexes += actions.size
        actions += playPauseAction
        if (payload.canSkipToNext) {
            compactViewIndexes += actions.size
            actions +=
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    buildCommandPendingIntent(PlaybackCommandReceiver.ACTION_SKIP_TO_NEXT),
                )
        }

        val builder =
            NotificationCompat
                .Builder(context, PlayerNotificationService.NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(payload.title)
                .setContentText(
                    payload.subtitle.ifBlank { payload.albumTitle.ifBlank { "Playing" } },
                )
                .setSubText(payload.description.ifBlank { null })
                .setContentIntent(buildContentIntent())
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setOngoing(payload.isPlaying)
                .setShowWhen(false)
                .setLargeIcon(artworkBitmap)
                .setStyle(buildMediaStyle(compactViewIndexes))
        actions.forEach(builder::addAction)
        return builder.build()
    }

    fun release() {
        lastPayload = null
        released = true
        artworkFetchInFlightUrl = null
        artworkBitmap = null
        artworkCandidateKey = ""
        artworkResolvedUrl = ""
        artworkExecutor.shutdownNow()
        mediaSession.isActive = false
        mediaSession.release()
    }

    private fun buildMetadata(
        payload: PlaybackSessionPayload,
        artwork: Bitmap?,
    ): MediaMetadataCompat {
        val metadataArtworkUrl = artworkResolvedUrl.ifBlank { payload.artworkUrl }
        val builder =
            MediaMetadataCompat
                .Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, payload.itemGuid)
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, payload.title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, payload.title)
                .putString(
                    MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE,
                    payload.subtitle,
                )
                .putString(
                    MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION,
                    payload.description,
                )
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, payload.artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, payload.albumTitle)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ARTIST, payload.artist)
                .putString(MediaMetadataCompat.METADATA_KEY_GENRE, payload.mediaType)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, metadataArtworkUrl)
                .putString(MediaMetadataCompat.METADATA_KEY_ART_URI, metadataArtworkUrl)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, metadataArtworkUrl)
        if (payload.durationMs > 0L) {
            builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, payload.durationMs)
        }
        if (payload.seasonNumber > 0) {
            builder.putLong(
                MediaMetadataCompat.METADATA_KEY_DISC_NUMBER,
                payload.seasonNumber.toLong(),
            )
        }
        if (payload.episodeNumber > 0) {
            builder.putLong(
                MediaMetadataCompat.METADATA_KEY_TRACK_NUMBER,
                payload.episodeNumber.toLong(),
            )
        }
        if (payload.trackCount > 0) {
            builder.putLong(
                MediaMetadataCompat.METADATA_KEY_NUM_TRACKS,
                payload.trackCount.toLong(),
            )
        }
        if (artwork != null) {
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, artwork)
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artwork)
        }
        return builder.build()
    }

    private fun buildPlaybackState(payload: PlaybackSessionPayload): PlaybackStateCompat {
        val actions =
            (if (payload.canPlay) PlaybackStateCompat.ACTION_PLAY else 0L) or
                (if (payload.canPause) PlaybackStateCompat.ACTION_PAUSE else 0L) or
                (if (payload.canSkipToPrevious) {
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                } else {
                    0L
                }) or
                (if (payload.canSkipToNext) {
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                } else {
                    0L
                }) or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                (if (payload.canSeek && payload.durationMs > 0L) {
                    PlaybackStateCompat.ACTION_SEEK_TO
                } else {
                    0L
                })
        val state =
            when {
                payload.error != null -> PlaybackStateCompat.STATE_PAUSED
                !payload.ready -> PlaybackStateCompat.STATE_BUFFERING
                payload.isPlaying -> PlaybackStateCompat.STATE_PLAYING
                else -> PlaybackStateCompat.STATE_PAUSED
            }
        val speed = if (payload.isPlaying) payload.speed.toFloat().coerceAtLeast(0.1f) else 0f
        return PlaybackStateCompat
            .Builder()
            .setActions(actions)
            .setState(
                state,
                payload.positionMs.coerceAtLeast(0L),
                speed,
                SystemClock.elapsedRealtime(),
            )
            .build()
    }

    private fun buildMediaStyle(compactViewIndexes: List<Int>): MediaStyle {
        val style = MediaStyle().setMediaSession(mediaSession.sessionToken)
        if (compactViewIndexes.isNotEmpty()) {
            style.setShowActionsInCompactView(*compactViewIndexes.toIntArray())
        }
        return style
    }

    private fun buildContentIntent(): PendingIntent? {
        val payload = lastPayload
        val launchIntent =
            payload
                ?.launchSource
                ?.takeIf { it.isNotEmpty() }
                ?.let { source ->
                    PlayerActivity.createResumeIntent(
                        context = context,
                        title = payload.launchTitle.ifBlank { payload.title },
                        source = HashMap(source),
                        fromParallelHost = payload.launchFromParallelHost,
                        layoutMode = payload.launchLayoutMode,
                        initialRightPaneRoute = payload.launchInitialRightPaneRoute,
                    )
                }?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                ?: context.packageManager
                    .getLaunchIntentForPackage(context.packageName)
                    ?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                ?: return null
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        return PendingIntent.getActivity(context, 0, launchIntent, flags)
    }

    private fun buildCommandPendingIntent(action: String): PendingIntent {
        val intent =
            Intent(context, PlaybackCommandReceiver::class.java).apply {
                this.action = action
                `package` = context.packageName
            }
        val requestCode =
            when (action) {
                PlaybackCommandReceiver.ACTION_PLAY -> 11
                PlaybackCommandReceiver.ACTION_PAUSE -> 12
                PlaybackCommandReceiver.ACTION_SKIP_TO_PREVIOUS -> 13
                PlaybackCommandReceiver.ACTION_SKIP_TO_NEXT -> 14
                else -> action.hashCode()
            }
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun buildSessionExtras(payload: PlaybackSessionPayload): Bundle =
        Bundle().apply {
            putString("mediaType", payload.mediaType)
            putString("albumTitle", payload.albumTitle)
            putString("artist", payload.artist)
            putString("description", payload.description)
            putInt("seasonNumber", payload.seasonNumber)
            putInt("episodeNumber", payload.episodeNumber)
            putInt("trackCount", payload.trackCount)
            putBoolean("canSkipToPrevious", payload.canSkipToPrevious)
            putBoolean("canSkipToNext", payload.canSkipToNext)
        }

    private fun syncArtwork(payload: PlaybackSessionPayload) {
        val candidateUrls =
            payload.artworkUrls
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .ifEmpty {
                    payload.artworkUrl.trim().takeIf { it.isNotEmpty() }?.let(::listOf) ?: emptyList()
                }
        val nextArtworkCandidateKey = candidateUrls.joinToString(separator = "|")
        if (nextArtworkCandidateKey.isEmpty()) {
            Log.d(logTag, "Artwork skipped: no candidate urls")
            artworkCandidateKey = ""
            artworkResolvedUrl = ""
            artworkBitmap = null
            artworkFetchInFlightUrl = null
            return
        }
        if (nextArtworkCandidateKey == artworkCandidateKey && artworkBitmap != null) {
            Log.d(logTag, "Artwork cache hit for active payload")
            return
        }
        artworkCandidateKey = nextArtworkCandidateKey
        artworkResolvedUrl = ""
        artworkBitmap = candidateUrls.firstNotNullOfOrNull { artworkCache.get(it) }
        if (artworkBitmap != null) {
            artworkResolvedUrl =
                candidateUrls.firstOrNull { artworkCache.get(it) === artworkBitmap }.orEmpty()
            Log.d(logTag, "Artwork memory cache hit: $artworkResolvedUrl")
            return
        }
        if (artworkFetchInFlightUrl == nextArtworkCandidateKey) {
            Log.d(logTag, "Artwork fetch already in flight")
            return
        }
        artworkFetchInFlightUrl = nextArtworkCandidateKey
        Log.d(
            logTag,
            "Artwork fetch start candidates=${candidateUrls.size} headers=${payload.artworkHeaders.keys.joinToString()}",
        )
        artworkExecutor.execute {
            val artworkResult = loadArtworkBitmap(candidateUrls, payload.artworkHeaders)
            mainHandler.post {
                if (released || artworkFetchInFlightUrl != nextArtworkCandidateKey) {
                    return@post
                }
                artworkFetchInFlightUrl = null
                if (artworkResult == null) {
                    Log.w(logTag, "Artwork fetch failed for all candidates")
                    return@post
                }
                val (resolvedUrl, bitmap) = artworkResult
                artworkCache.put(resolvedUrl, bitmap)
                val latestCandidateKey =
                    lastPayload
                        ?.let { latestPayload ->
                            latestPayload.artworkUrls
                                .map { it.trim() }
                                .filter { it.isNotEmpty() }
                                .ifEmpty {
                                    latestPayload.artworkUrl
                                        .trim()
                                        .takeIf { it.isNotEmpty() }
                                        ?.let(::listOf) ?: emptyList()
                                }.joinToString(separator = "|")
                        }.orEmpty()
                if (latestCandidateKey != nextArtworkCandidateKey) {
                    return@post
                }
                artworkResolvedUrl = resolvedUrl
                artworkBitmap = bitmap
                Log.d(logTag, "Artwork applied: $resolvedUrl ${bitmap.width}x${bitmap.height}")
                lastPayload?.let { currentPayload ->
                    mediaSession.setMetadata(buildMetadata(currentPayload, bitmap))
                    onNotificationInvalidated()
                }
            }
        }
    }

    private fun loadArtworkBitmap(
        urls: List<String>,
        headers: Map<String, String>,
    ): Pair<String, Bitmap>? {
        for (url in urls) {
            val bitmap =
                runCatching {
                    Log.d(logTag, "Artwork request: $url")
                    val requestBuilder = Request.Builder().url(url)
                    headers.forEach { (key, value) ->
                        requestBuilder.header(key, value)
                    }
                    val request = requestBuilder.build()
                    artworkClient.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            Log.w(logTag, "Artwork http ${response.code} for $url")
                            return@use null
                        }
                        val bytes = response.body?.bytes()
                        if (bytes == null || bytes.isEmpty()) {
                            Log.w(logTag, "Artwork empty body for $url")
                            return@use null
                        }
                        val bitmap = decodeArtworkBitmap(bytes)
                        if (bitmap == null) {
                            Log.w(logTag, "Artwork decode failed for $url bytes=${bytes.size}")
                        } else {
                            Log.d(
                                logTag,
                                "Artwork decoded for $url bytes=${bytes.size} size=${bitmap.width}x${bitmap.height}",
                            )
                        }
                        bitmap
                    }
                }.getOrElse { error ->
                    Log.w(logTag, "Artwork request error for $url: ${error.message}")
                    null
                }
            if (bitmap != null) {
                return url to bitmap
            }
            if (released) {
                return null
            }
        }
        return null
    }

    private fun decodeArtworkBitmap(bytes: ByteArray): Bitmap? {
        val bounds =
            BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }
        val maxDimension = maxOf(bounds.outWidth, bounds.outHeight)
        val sampleSize = Integer.highestOneBit((maxDimension / 512).coerceAtLeast(1))
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    companion object {
        private const val SESSION_TAG = "fly_player_playback_session"
        private val artworkClient = OkHttpClient()
        private val artworkCache =
            object : LruCache<String, Bitmap>(12 * 1024 * 1024) {
                override fun sizeOf(
                    key: String,
                    value: Bitmap,
                ): Int = value.byteCount
            }
    }
}
