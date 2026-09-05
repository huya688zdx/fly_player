package com.geqian.flyplayer.fly_player.mpv

internal fun resolveInternalReloadStartPositionMs(
    reliableSeek: Boolean,
    currentPositionMs: Long,
    sourceStartPositionMs: Long,
): Long {
    if (!reliableSeek) return 0L
    return currentPositionMs.takeIf { it > 0L }
        ?: sourceStartPositionMs.coerceAtLeast(0L)
}
