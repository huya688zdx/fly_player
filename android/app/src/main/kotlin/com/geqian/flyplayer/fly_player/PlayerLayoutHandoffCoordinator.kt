package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.os.SystemClock

private const val PLAYER_LAYOUT_HANDOFF_GRACE_MS = 5000L

object PlayerLayoutHandoffCoordinator {
    @Volatile
    private var sourceHostClassName: String? = null

    @Volatile
    private var expiresAtUptimeMs: Long = 0L

    fun beginFrom(activity: Activity) {
        sourceHostClassName = activity.javaClass.name
        expiresAtUptimeMs = SystemClock.uptimeMillis() + PLAYER_LAYOUT_HANDOFF_GRACE_MS
    }

    fun shouldPreserveFor(activity: Activity?): Boolean {
        val hostClassName = activity?.javaClass?.name ?: return false
        val sourceClassName = sourceHostClassName ?: return false
        if (SystemClock.uptimeMillis() > expiresAtUptimeMs) {
            clear()
            return false
        }
        return sourceClassName == hostClassName
    }

    private fun clear() {
        sourceHostClassName = null
        expiresAtUptimeMs = 0L
    }
}
