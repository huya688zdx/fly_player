package com.geqian.flyplayer.fly_player

import com.geqian.flyplayer.fly_player.mpv.NativeMpvProxyServer

class MainActivity : FlutterHostActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.attachMainHost(this)
    }

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

    override fun onDestroy() {
        if (isFinishing) {
            ParallelWindowCoordinator.detachMainHost(this)
        }
        NativeMpvProxyServer.clearAllCaches()
        super.onDestroy()
    }
}
