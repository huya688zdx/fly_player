package com.geqian.flyplayer.fly_player

import java.lang.ref.WeakReference

object PlaybackSessionCoordinator {
    @Volatile
    private var activeHostRef: WeakReference<FlutterHostActivity>? = null

    @Volatile
    private var sessionUpdatesBlocked: Boolean = false

    fun attachHost(activity: FlutterHostActivity) {
        activeHostRef = WeakReference(activity)
    }

    fun detachHost(activity: FlutterHostActivity) {
        val current = activeHostRef?.get()
        if (current === activity) {
            activeHostRef = null
        }
    }

    fun dispatchCommand(
        method: String,
        arguments: HashMap<String, Any?> = hashMapOf(),
    ) {
        activeHostRef?.get()?.dispatchSystemPlaybackCommand(method, arguments)
    }

    fun blockSessionUpdates() {
        sessionUpdatesBlocked = true
    }

    fun allowSessionUpdates() {
        sessionUpdatesBlocked = false
    }

    fun areSessionUpdatesBlocked(): Boolean = sessionUpdatesBlocked
}
