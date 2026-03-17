package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.util.HashMap

class PlayerActivity : FlutterHostActivity() {
    private fun currentLayoutMode(): String = PlayerLaunchContract.readLayoutMode(intent)

    private fun applyLayoutModeState() {
        ParallelWindowCoordinator.setSplitPlayerVisible(
            currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT,
        )
    }

    override fun getInitialRoute(): String = "/player?layoutMode=${currentLayoutMode()}"

    override fun hostSurface(): String = "player"

    override fun hostPaneSide(): ParallelPaneSide =
        if (currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT) {
            ParallelWindowCoordinator.activePlayerPrimaryPaneSide()
        } else {
            ParallelPaneSide.FULLSCREEN
        }

    override fun hostRoleOverride(): ParallelHostRole =
        if (currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT) {
            ParallelHostRole.PRIMARY
        } else {
            ParallelHostRole.FULLSCREEN
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.attachPlayerHost(this)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onCreate layoutMode=${currentLayoutMode()} action=${intent?.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)}",
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onNewIntent layoutMode=${currentLayoutMode()} action=${intent.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)}",
        )
        PlayerLaunchContract.buildInitialArgs(intent)?.let { args ->
            playerHostStateChannel?.invokeMethod("replaceSource", args)
        }
    }

    override fun onDestroy() {
        ParallelWindowCoordinator.detachPlayerHost(this)
        if (isFinishing && currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT) {
            ParallelWindowCoordinator.setSplitPlayerVisible(false)
        }
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
                fromParallelHost = true,
                hostContext = getParallelHostContext(),
                layoutMode = currentLayoutMode(),
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

    override fun consumeInitialPlayerArgs(): HashMap<String, Any?>? {
        return PlayerLaunchContract.buildInitialArgs(intent)
    }

    override fun finishPlayerActivity(result: HashMap<String, Any?>?): Boolean {
        Log.d(
            TAG,
            "finishPlayerActivity layoutMode=${currentLayoutMode()} rememberedDetailRoute=${ParallelWindowCoordinator.rememberedDetailRoute()} rememberedDetailItem=${ParallelWindowCoordinator.rememberedDetailItemGuid()}",
        )
        if (currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT) {
            ParallelWindowCoordinator.setSplitPlayerVisible(false)
            val restoreRoute =
                ParallelWindowCoordinator.rememberedDetailRoute().ifBlank {
                    val itemGuid = ParallelWindowCoordinator.rememberedDetailItemGuid().trim()
                    if (itemGuid.isBlank()) {
                        ""
                    } else {
                        DetailActivity.createIntent(this, itemGuid)
                            .getStringExtra("initial_route")
                            .orEmpty()
                    }
                }
            if (restoreRoute.isNotBlank()) {
                startActivity(
                    DetailActivity.createResumeIntent(
                        context = this,
                        routeName = restoreRoute,
                    ),
                )
            }
        }
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
        val normalizedTitle = title.trim()
        val normalizedSource = source ?: hashMapOf()
        if (normalizedTitle.isEmpty() || normalizedSource.isEmpty()) return false

        return when (targetMode) {
            PlayerLaunchContract.MODE_SPLIT -> enterSplitMode()
            PlayerLaunchContract.MODE_FULLSCREEN -> enterFullscreenMode()
            else -> false
        }
    }

    private fun enterSplitMode(): Boolean {
        if (currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT) return true
        if (!PlayerLaunchContract.isFromParallelHost(intent)) return false

        Log.d(
            TAG,
            "enterSplitMode start action=${intent?.action} rememberedDetailRoute=${ParallelWindowCoordinator.rememberedDetailRoute()} currentDetailRoute=${ParallelWindowCoordinator.currentDetailRoute()}",
        )
        ParallelWindowCoordinator.snapshotDetailForRestore()
        PlayerLaunchContract.updateLayoutMode(intent, PlayerLaunchContract.MODE_SPLIT)
        setIntent(intent)
        applyLayoutModeState()
        ParallelWindowCoordinator.currentDetailHost()?.let { detailHost ->
            Log.d(TAG, "enterSplitMode finishingDetailHost=${detailHost.javaClass.simpleName}")
            detailHost.finish()
        }
        val attachHomeIntent = HomePaneActivity.createAttachToPlayerIntent(this)
        Log.d(
            TAG,
            "enterSplitMode launching=${attachHomeIntent.component?.className} action=${attachHomeIntent.action}",
        )
        startActivity(attachHomeIntent)
        return true
    }

    private fun enterFullscreenMode(): Boolean {
        if (currentLayoutMode() == PlayerLaunchContract.MODE_FULLSCREEN) return true

        val initialArgs = consumeInitialPlayerArgs() ?: return false
        val title = initialArgs["title"]?.toString()?.trim().orEmpty()
        val source = initialArgs["source"] as? HashMap<String, Any?> ?: return false
        if (title.isEmpty() || source.isEmpty()) return false
        val fullscreenIntent =
            createIntent(
                context = this,
                title = title,
                source = source,
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext = getParallelHostContext(),
                layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
        Log.d(
            TAG,
            "enterFullscreenMode start rememberedDetailRoute=${ParallelWindowCoordinator.rememberedDetailRoute()} currentDetailRoute=${ParallelWindowCoordinator.currentDetailRoute()} action=${fullscreenIntent.action}",
        )
        PlayerLayoutHandoffCoordinator.beginFrom(this)
        ParallelWindowCoordinator.snapshotDetailForRestore()
        PlayerLaunchContract.updateLayoutMode(intent, PlayerLaunchContract.MODE_FULLSCREEN)
        setIntent(intent)
        applyLayoutModeState()
        ParallelWindowCoordinator.setSplitPlayerVisible(false)
        ParallelWindowCoordinator.currentDetailHost()?.let { detailHost ->
            Log.d(TAG, "enterFullscreenMode finishingDetailHost=${detailHost.javaClass.simpleName}")
            detailHost.finish()
        }
        window.decorView.post {
            Log.d(
                TAG,
                "enterFullscreenMode relaunching=${fullscreenIntent.component?.className} action=${fullscreenIntent.action}",
            )
            startActivity(fullscreenIntent)
        }
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
        ): Intent {
            return PlayerLaunchContract.applyLaunchExtras(
                intent = Intent(context, PlayerActivity::class.java),
                title = title,
                source = source,
                fromParallelHost = fromParallelHost,
                hostContext = hostContext,
                layoutMode = layoutMode,
            )
        }
    }
}
