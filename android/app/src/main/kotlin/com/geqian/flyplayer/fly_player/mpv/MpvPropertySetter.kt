package com.geqian.flyplayer.fly_player.mpv

internal inline fun applyMpvPropertyBestEffort(
    ready: Boolean = true,
    block: () -> Unit,
): Boolean {
    if (!ready) return false
    return runCatching { block() }.isSuccess
}
