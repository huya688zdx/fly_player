package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.util.HashMap

class PlayerActivity : FlutterHostActivity() {
    private fun currentLayoutMode(): String = PlayerLaunchContract.readLayoutMode(intent)

    private fun currentInitialRightPaneRoute(): String {
        return PlayerLaunchContract.readInitialRightPaneRoute(intent)
    }

    private fun applyLayoutModeState() {
        ParallelWindowCoordinator.setSplitPlayerVisible(
            currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT,
        )
    }

    override fun getInitialRoute(): String = "/player?layoutMode=${currentLayoutMode()}"

    override fun hostSurface(): String = "player"

    override fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    override fun hostRoleOverride(): ParallelHostRole = ParallelHostRole.FULLSCREEN

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlaybackSessionCoordinator.allowSessionUpdates()
        ParallelWindowCoordinator.attachPlayerHost(this)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onCreate layoutMode=${currentLayoutMode()} action=${intent?.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onNewIntent layoutMode=${currentLayoutMode()} action=${intent.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
        if (intent.action == PlayerLaunchContract.ACTION_RESUME_PLAYER) {
            return
        }
        PlayerLaunchContract.buildInitialArgs(intent)?.let { args ->
            playerHostStateChannel?.invokeMethod("replaceSource", args)
        }
    }

    override fun onDestroy() {
        if (isFinishing && !isChangingConfigurations) {
            PlaybackSessionCoordinator.blockSessionUpdates()
            PlaybackSessionCoordinator.detachHost(this)
            PlayerNotificationService.stop(applicationContext)
        }
        ParallelWindowCoordinator.detachPlayerHost(this)
        ParallelWindowCoordinator.setSplitPlayerVisible(false)
        super.onDestroy()
    }

    fun replaceSourceInPlace(
        title: String,
        source: HashMap<String, Any?>,
    ) {
        val normalizedTitle = title.trim()
        if (normalizedTitle.isEmpty() || source.isEmpty()) return
        val nextIntent =
            createIntent(
                context = this,
                title = normalizedTitle,
                source = HashMap(source),
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext = getParallelHostContext(),
                layoutMode = currentLayoutMode(),
                initialRightPaneRoute = currentInitialRightPaneRoute(),
            )
        setIntent(nextIntent)
        PlayerLaunchContract.buildInitialArgs(nextIntent)?.let { args ->
            Log.d(
                TAG,
                "replaceSourceInPlace layoutMode=${currentLayoutMode()} itemGuid=${source["itemGuid"]}",
            )
            playerHostStateChannel?.invokeMethod("replaceSource", args)
        }
    }

    fun replaceRightPaneRouteInPlace(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return false
        Log.d(
            TAG,
            "replaceRightPaneRouteInPlace layoutMode=${currentLayoutMode()} route=$normalizedRoute",
        )
        playerHostStateChannel?.invokeMethod(
            "replaceRightPaneRoute",
            hashMapOf("routeName" to normalizedRoute),
        )
        return true
    }

    override fun consumeInitialPlayerArgs(): HashMap<String, Any?>? {
        return PlayerLaunchContract.buildInitialArgs(intent)
    }

    override fun finishPlayerActivity(result: HashMap<String, Any?>?): Boolean {
        PlaybackSessionCoordinator.blockSessionUpdates()
        PlaybackSessionCoordinator.detachHost(this)
        PlayerNotificationService.stop(applicationContext)
        Log.d(
            TAG,
            "finishPlayerActivity layoutMode=${currentLayoutMode()} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                PlayerLaunchContract.putResultPayload(this, result)
            },
        )
        finish()
        return true
    }

    override fun switchPlayerLayoutMode(
        title: String,
        source: HashMap<String, Any?>?,
        targetMode: String,
        resultPayload: HashMap<String, Any?>?,
    ): Boolean {
        if (targetMode != PlayerLaunchContract.MODE_SPLIT &&
            targetMode != PlayerLaunchContract.MODE_FULLSCREEN
        ) {
            return false
        }
        PlayerLaunchContract.updateLayoutMode(intent, targetMode)
        setIntent(intent)
        applyLayoutModeState()
        Log.d(TAG, "switchPlayerLayoutMode target=$targetMode handledInFlutter=true")
        return true
    }

    companion object {
        private const val TAG = "PlayerActivity"

        fun createIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            fromParallelHost: Boolean = false,
            hostContext: HashMap<String, Any?> = hashMapOf(),
            layoutMode: String = PlayerLaunchContract.MODE_FULLSCREEN,
            initialRightPaneRoute: String = "",
        ): Intent {
            return PlayerLaunchContract.applyLaunchExtras(
                intent = Intent(context, PlayerActivity::class.java),
                title = title,
                source = source,
                fromParallelHost = fromParallelHost,
                hostContext = hostContext,
                layoutMode = layoutMode,
                initialRightPaneRoute = initialRightPaneRoute,
            )
        }

        fun createResumeIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            fromParallelHost: Boolean = false,
            layoutMode: String = PlayerLaunchContract.MODE_FULLSCREEN,
            initialRightPaneRoute: String = "",
        ): Intent {
            return createIntent(
                context = context,
                title = title,
                source = source,
                fromParallelHost = fromParallelHost,
                hostContext = hashMapOf(),
                layoutMode = layoutMode,
                initialRightPaneRoute = initialRightPaneRoute,
            ).apply {
                action = PlayerLaunchContract.ACTION_RESUME_PLAYER
            }
        }
    }
}
