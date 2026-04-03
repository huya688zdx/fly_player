package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.os.Bundle

class PlaceholderActivity : FlutterHostActivity() {
    override fun getInitialRoute(): String = "/parallel/placeholder"

    override fun hostSurface(): String = "placeholder"

    override fun hostPaneSide(): ParallelPaneSide =
        ParallelWindowCoordinator.preferredSecondaryPaneSide()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.attachPlaceholderHost(this)
        ParallelWindowCoordinator.attachRightPaneHost(this)
    }

    override fun onDestroy() {
        if (isFinishing) {
            ParallelWindowCoordinator.detachPlaceholderHost(this)
            ParallelWindowCoordinator.detachRightPaneHost(this)
            ParallelWindowCoordinator.clearRightPane()
        }
        super.onDestroy()
    }

    companion object {
        fun createIntent(context: Context): Intent {
            return Intent(context, PlaceholderActivity::class.java)
        }
    }
}
