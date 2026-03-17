package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.content.Context
import android.content.Intent
import java.util.HashMap

class FullscreenPlayerActivity : FlutterHostActivity() {
    override fun getInitialRoute(): String = "/player?layoutMode=fullscreen"

    override fun hostSurface(): String = "player"

    override fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    override fun hostRoleOverride(): ParallelHostRole = ParallelHostRole.FULLSCREEN

    override fun consumeInitialPlayerArgs(): HashMap<String, Any?>? {
        return PlayerLaunchContract.buildInitialArgs(intent)
    }

    override fun finishPlayerActivity(result: HashMap<String, Any?>?): Boolean {
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
        if (targetMode != PlayerLaunchContract.MODE_SPLIT) return false
        if (!PlayerLaunchContract.isFromParallelHost(intent)) return false
        val detailHost = ParallelWindowCoordinator.currentDetailHost() ?: return false
        PlayerLayoutHandoffCoordinator.beginFrom(this)
        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                PlayerLaunchContract.putResultPayload(this, resultPayload)
            },
        )
        detailHost.launchSplitPlayer(
            title = normalizedTitle,
            source = HashMap(normalizedSource),
        )
        finish()
        return true
    }

    companion object {
        fun createIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            fromParallelHost: Boolean = false,
            hostContext: HashMap<String, Any?> = hashMapOf(),
        ): Intent {
            return PlayerLaunchContract.applyLaunchExtras(
                intent = Intent(context, FullscreenPlayerActivity::class.java),
                title = title,
                source = source,
                fromParallelHost = fromParallelHost,
                hostContext = hostContext,
                layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
            )
        }
    }
}
