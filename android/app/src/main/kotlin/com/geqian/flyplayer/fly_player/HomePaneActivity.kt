package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

class HomePaneActivity : FlutterHostActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate action=${intent?.action} splitPlayerVisible=${ParallelWindowCoordinator.isSplitPlayerVisible()}")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent action=${intent.action} splitPlayerVisible=${ParallelWindowCoordinator.isSplitPlayerVisible()}")
    }

    override fun getInitialRoute(): String = "/"

    override fun hostSurface(): String = "home"

    override fun hostPaneSide(): ParallelPaneSide =
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.activePlayerSecondaryPaneSide()
        } else {
            ParallelWindowCoordinator.preferredPrimaryPaneSide()
        }

    override fun hostRoleOverride(): ParallelHostRole? =
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelHostRole.SECONDARY
        } else {
            null
        }

    companion object {
        private const val TAG = "HomePaneActivity"
        private const val ACTION_ATTACH_HOME_TO_PLAYER =
            "com.geqian.flyplayer.fly_player.action.ATTACH_HOME_TO_PLAYER"

        fun createAttachToPlayerIntent(context: Context): Intent {
            return Intent(context, HomePaneActivity::class.java).apply {
                action = ACTION_ATTACH_HOME_TO_PLAYER
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        }
    }
}
