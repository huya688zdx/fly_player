package com.geqian.flyplayer.fly_player

import android.content.Intent
import android.os.Build
import java.io.Serializable
import java.util.HashMap

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
    private const val EXTRA_PLAYER_RESULT = "player_result"
    private const val EXTRA_PLAYER_FROM_PARALLEL_HOST = "player_from_parallel_host"
    private const val EXTRA_PLAYER_HOST_CONTEXT = "player_host_context"
    private const val EXTRA_PLAYER_LAYOUT_MODE = "player_layout_mode"
    private const val EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE = "player_initial_right_pane_route"

    fun applyLaunchExtras(
        intent: Intent,
        title: String,
        source: HashMap<String, Any?>,
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
            "fromParallelHost" to
                (intent?.getBooleanExtra(EXTRA_PLAYER_FROM_PARALLEL_HOST, false) ?: false),
            "parallelHostContext" to hostContext,
            "layoutMode" to intent?.getStringExtra(EXTRA_PLAYER_LAYOUT_MODE).orEmpty(),
            "initialRightPaneRoute" to
                intent?.getStringExtra(EXTRA_PLAYER_INITIAL_RIGHT_PANE_ROUTE).orEmpty(),
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
