package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.os.SystemClock

private const val PLAYER_LAYOUT_HANDOFF_GRACE_MS = 5000L

object PlayerLayoutHandoffCoordinator {
    @Volatile
    private var allowedHostClassNames: Set<String>? = null

    @Volatile
    private var expiresAtUptimeMs: Long = 0L

    fun beginFrom(activity: Activity) {
        allowedHostClassNames =
            if (activity is PlayerActivity || activity is FullscreenPlayerActivity) {
                setOf(
                    PlayerActivity::class.java.name,
                    FullscreenPlayerActivity::class.java.name,
                )
            } else {
                setOf(activity.javaClass.name)
            }
        expiresAtUptimeMs = SystemClock.uptimeMillis() + PLAYER_LAYOUT_HANDOFF_GRACE_MS
    }

    fun shouldPreserveFor(activity: Activity?): Boolean {
        val hostClassName = activity?.javaClass?.name ?: return false
        val allowedClassNames = allowedHostClassNames ?: return false
        if (SystemClock.uptimeMillis() > expiresAtUptimeMs) {
            clear()
            return false
        }
        return allowedClassNames.contains(hostClassName)
    }

    private fun clear() {
        allowedHostClassNames = null
        expiresAtUptimeMs = 0L
    }
}
