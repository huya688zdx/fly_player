package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.Serializable
import java.security.MessageDigest
import java.util.HashMap
import java.util.Locale

object PlayerLaunchContract {
    const val MODE_FULLSCREEN = "fullscreen"
    const val MODE_SPLIT = "split"
    const val ACTION_SPLIT_PLAYER =
        "com.geqian.flyplayer.fly_player.action.SPLIT_PLAYER"
    const val ACTION_FULLSCREEN_PLAYER =
        "com.geqian.flyplayer.fly_player.action.FULLSCREEN_PLAYER"
    const val ACTION_RESUME_PLAYER =
        "com.geqian.flyplayer.fly_player.action.RESUME_PLAYER"
    const val ACTION_ATTACH_DETAIL_TO_PLAYER =
        "com.geqian.flyplayer.fly_player.action.ATTACH_DETAIL_TO_PLAYER"

    private const val EXTRA_PLAYER_TITLE = "player_title"
    private const val EXTRA_PLAYER_SOURCE = "player_source"
    private const val EXTRA_PLAYER_INITIAL_PLAY_INFO = "player_initial_play_info"
    private const val EXTRA_PLAYER_START_SOURCE = "player_start_source"
    private const val EXTRA_PLAYER_RESULT = "player_result"
    private const val EXTRA_PLAYER_FROM_PARALLEL_HOST = "player_from_parallel_host"
    private const val EXTRA_PLAYER_HOST_CONTEXT = "player_host_context"
    private const val EXTRA_PLAYER_LAYOUT_MODE = "player_layout_mode"
    private const val EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE = "player_initial_right_pane_route"

    fun applyLaunchExtras(
        intent: Intent,
        title: String,
        source: HashMap<String, Any?>,
        initialPlayInfo: HashMap<String, Any?>? = null,
        startSource: String = "manual",
        fromParallelHost: Boolean,
        hostContext: HashMap<String, Any?>,
        layoutMode: String,
        initialRightPaneRoute: String = "",
        ): Intent {
        return intent.apply {
            action =
                if (layoutMode == MODE_SPLIT) {
                    ACTION_SPLIT_PLAYER
                } else {
                    ACTION_FULLSCREEN_PLAYER
                }
            putExtra(EXTRA_PLAYER_TITLE, title.trim())
            putExtra(EXTRA_PLAYER_SOURCE, HashMap(source))
            putExtra(EXTRA_PLAYER_INITIAL_PLAY_INFO, initialPlayInfo?.let { HashMap(it) })
            putExtra(EXTRA_PLAYER_START_SOURCE, startSource.trim())
            putExtra(EXTRA_PLAYER_FROM_PARALLEL_HOST, fromParallelHost)
            putExtra(EXTRA_PLAYER_HOST_CONTEXT, HashMap(hostContext))
            putExtra(EXTRA_PLAYER_LAYOUT_MODE, layoutMode)
            putExtra(EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE, initialRightPaneRoute.trim())
        }
    }

    fun readLayoutMode(intent: Intent?): String {
        val value = intent?.getStringExtra(EXTRA_PLAYER_LAYOUT_MODE).orEmpty()
        return if (value == MODE_SPLIT) MODE_SPLIT else MODE_FULLSCREEN
    }

    fun readInitialRightPaneRoute(intent: Intent?): String {
        return intent?.getStringExtra(EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE).orEmpty().trim()
    }

    fun updateLayoutMode(
        intent: Intent,
        layoutMode: String,
    ) {
        intent.action =
            if (layoutMode == MODE_SPLIT) {
                ACTION_SPLIT_PLAYER
            } else {
                ACTION_FULLSCREEN_PLAYER
            }
        intent.putExtra(EXTRA_PLAYER_LAYOUT_MODE, layoutMode)
    }

    fun buildInitialArgs(intent: Intent?): HashMap<String, Any?>? {
        val source = readSerializableHashMap(intent, EXTRA_PLAYER_SOURCE) ?: return null
        val hostContext = readSerializableHashMap(intent, EXTRA_PLAYER_HOST_CONTEXT) ?: hashMapOf()
        return hashMapOf(
            "title" to intent?.getStringExtra(EXTRA_PLAYER_TITLE).orEmpty(),
            "source" to source,
            "initialPlayInfo" to readSerializableHashMap(intent, EXTRA_PLAYER_INITIAL_PLAY_INFO),
            "startSource" to intent?.getStringExtra(EXTRA_PLAYER_START_SOURCE).orEmpty(),
            "fromParallelHost" to
                (intent?.getBooleanExtra(EXTRA_PLAYER_FROM_PARALLEL_HOST, false) ?: false),
            "parallelHostContext" to hostContext,
            "layoutMode" to intent?.getStringExtra(EXTRA_PLAYER_LAYOUT_MODE).orEmpty(),
            "initialRightPaneRoute" to
                intent?.getStringExtra(EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE).orEmpty(),
        )
    }

    fun buildExternalLocalVideoIntent(
        context: Context,
        uri: Uri,
        title: String,
        sizeBytes: Long = 0L,
    ): Intent {
        val loadArgs = buildExternalLocalVideoLoadArgs(uri, title, sizeBytes)
        val normalizedTitle = loadArgs["title"] as String
        return PlayerActivity.createIntent(
            context = context,
            title = normalizedTitle,
            source = loadArgs,
            startSource = "manual",
            fromParallelHost = false,
            hostContext = hashMapOf(),
            layoutMode = MODE_FULLSCREEN,
            initialRightPaneRoute = "",
        )
    }

    fun buildExternalLocalVideoLoadArgs(
        uri: Uri,
        title: String,
        sizeBytes: Long = 0L,
    ): HashMap<String, Any?> {
        val normalizedTitle = title.trim().ifEmpty { "Local Video" }
        val normalizedSizeBytes = sizeBytes.coerceAtLeast(0L)
        val stableId = externalLocalVideoId(uri, normalizedTitle, normalizedSizeBytes)
        val loadNonce = (System.currentTimeMillis() and 0x7fffffff).toInt().coerceAtLeast(1)
        return hashMapOf<String, Any?>(
                "loadNonce" to loadNonce,
                "itemGuid" to stableId,
                "seriesGuid" to "",
                "seasonGuid" to "",
                "posterPath" to "",
                "mediaGuid" to "$stableId-media",
                "mediaType" to "local",
                "ancestorName" to "",
                "videoGuid" to "$stableId-video",
                "url" to uri.toString(),
                "headers" to hashMapOf<String, String>(),
                "title" to normalizedTitle,
                "seriesTitle" to "",
                "seasonNumber" to 0,
                "tmdbId" to "",
                "episodeNumber" to 0,
                "startPositionMs" to 0L,
                "videoWidth" to 0,
                "videoHeight" to 0,
                "resolution" to "",
                "bitrate" to 0,
                "durationSeconds" to 0,
                "videoCodecName" to "",
                "videoProfile" to "",
                "colorSpace" to "",
                "colorTransfer" to "",
                "colorPrimaries" to "",
                "bitDepth" to 0,
                "isDownloadedFile" to true,
                "externalLocalSource" to true,
                "danmakuAutoSearchAllowed" to false,
                "externalLocalFileSizeBytes" to normalizedSizeBytes,
                "preferExternalSubtitle" to false,
                "forceNativeProxy" to false,
                "extremePlaybackEnabled" to false,
                "reliableSeek" to true,
                "seekProbeSummary" to "external-local",
                "playbackMode" to "originalQuality",
                "playbackSpeed" to 1.0,
                "listenVideoModeEnabled" to false,
                "audioTracks" to arrayListOf<HashMap<String, Any?>>(),
                "subtitleTracks" to arrayListOf<HashMap<String, Any?>>(),
                "qualities" to arrayListOf<HashMap<String, Any?>>(),
            )
    }

    fun isFromParallelHost(intent: Intent?): Boolean {
        return intent?.getBooleanExtra(EXTRA_PLAYER_FROM_PARALLEL_HOST, false) ?: false
    }

    fun readResultPayload(intent: Intent?): HashMap<String, Any?>? {
        return readSerializableHashMap(intent, EXTRA_PLAYER_RESULT)
    }

    fun putResultPayload(intent: Intent, result: HashMap<String, Any?>?) {
        intent.putExtra(EXTRA_PLAYER_RESULT, result)
    }

    private fun externalLocalVideoId(
        uri: Uri,
        title: String,
        sizeBytes: Long,
    ): String {
        val raw =
            listOf(
                uri.normalizeScheme().toString(),
                title.trim(),
                sizeBytes.coerceAtLeast(0L).toString(),
            ).joinToString("|")
        val digest = MessageDigest
            .getInstance("SHA-256")
            .digest(raw.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte ->
                (byte.toInt() and 0xff).toString(16).padStart(2, '0')
            }
            .lowercase(Locale.US)
        return "external-local-${digest.take(24)}"
    }

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    fun readSerializableHashMap(
        intent: Intent?,
        key: String,
    ): HashMap<String, Any?>? {
        if (intent == null) return null
        val value =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getSerializableExtra(key, HashMap::class.java)
            } else {
                intent.getSerializableExtra(key)
            }
        return when (value) {
            is HashMap<*, *> -> value as HashMap<String, Any?>
            is Serializable -> value as? HashMap<String, Any?>
            else -> null
        }
    }
}
