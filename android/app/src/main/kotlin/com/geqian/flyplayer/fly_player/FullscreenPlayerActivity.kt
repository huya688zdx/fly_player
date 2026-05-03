package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.util.HashMap

class FullscreenPlayerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val source = PlayerLaunchContract.readSerializableHashMap(intent, EXTRA_PLAYER_SOURCE)
        if (source == null || source.isEmpty()) {
            finish()
            return
        }
        val launchIntent =
            PlayerActivity.createIntent(
                context = this,
                title = intent?.getStringExtra(EXTRA_PLAYER_TITLE).orEmpty(),
                source = HashMap(source),
                initialPlayInfo =
                    PlayerLaunchContract.readSerializableHashMap(
                        intent,
                        EXTRA_PLAYER_INITIAL_PLAY_INFO,
                    ),
                startSource = intent?.getStringExtra(EXTRA_PLAYER_START_SOURCE).orEmpty(),
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext =
                    PlayerLaunchContract.readSerializableHashMap(
                        intent,
                        EXTRA_PLAYER_HOST_CONTEXT,
                    ) ?: hashMapOf(),
                layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
                initialRightPaneRoute = PlayerLaunchContract.readInitialRightPaneRoute(intent),
            ).apply {
                action = intent?.action ?: action
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                PlayerLaunchContract.readResultPayload(intent)?.let { result ->
                    PlayerLaunchContract.putResultPayload(this, result)
                }
            }
        Log.d(TAG, "redirect fullscreen host to PlayerActivity action=${intent?.action}")
        startActivity(launchIntent)
        finish()
    }

    companion object {
        private const val TAG = "FullscreenPlayerActivity"
        private const val EXTRA_PLAYER_TITLE = "player_title"
        private const val EXTRA_PLAYER_SOURCE = "player_source"
        private const val EXTRA_PLAYER_INITIAL_PLAY_INFO = "player_initial_play_info"
        private const val EXTRA_PLAYER_START_SOURCE = "player_start_source"
        private const val EXTRA_PLAYER_HOST_CONTEXT = "player_host_context"

        fun createIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            initialPlayInfo: HashMap<String, Any?>? = null,
            startSource: String = "manual",
            fromParallelHost: Boolean = false,
            hostContext: HashMap<String, Any?> = hashMapOf(),
        ): Intent {
            return PlayerActivity.createIntent(
                context = context,
                title = title,
                source = source,
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = fromParallelHost,
                hostContext = hostContext,
                layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
        }

        fun createResumeIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            initialPlayInfo: HashMap<String, Any?>? = null,
            startSource: String = "manual",
            fromParallelHost: Boolean = false,
        ): Intent {
            return PlayerActivity.createResumeIntent(
                context = context,
                title = title,
                source = source,
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = fromParallelHost,
                layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
            )
        }
    }
}
