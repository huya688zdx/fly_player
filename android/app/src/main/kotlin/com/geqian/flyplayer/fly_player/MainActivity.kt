package com.geqian.flyplayer.fly_player

import com.geqian.flyplayer.fly_player.mpv.NativeMpvProxyServer

class MainActivity : FlutterHostActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.attachMainHost(this)
        ParallelWindowCoordinator.attachBrowseHost(this)
        window.decorView.postDelayed({
            ParallelFlutterEngineRegistry.warmIfEligible(applicationContext)
        }, 1500L)
    }

    override fun onResume() {
        super.onResume()
        ParallelWindowCoordinator.attachBrowseHost(this)
    }

    override fun hostSurface(): String = "home"

    override fun hostPaneSide(): ParallelPaneSide =
        if (ParallelWindowCoordinator.isNativeSplitPlayerVisible()) {
            ParallelWindowCoordinator.activePlayerSecondaryPaneSide()
        } else {
            ParallelWindowCoordinator.preferredPrimaryPaneSide()
        }

    override fun hostRoleOverride(): ParallelHostRole? =
        if (ParallelWindowCoordinator.isNativeSplitPlayerVisible()) {
            ParallelHostRole.SECONDARY
        } else {
            null
        }

    override fun onDestroy() {
        if (isFinishing) {
            ParallelWindowCoordinator.detachMainHost(this)
            ParallelWindowCoordinator.detachBrowseHost(this)
        }
        NativeMpvProxyServer.clearAllCaches()
        super.onDestroy()
    }
}
