package com.geqian.flyplayer.fly_player.mpv

internal fun formatNativePlaybackError(
    action: String,
    error: Throwable? = null,
    fallbackReason: String? = null,
): String {
    val normalizedAction = action.trim().ifEmpty { "playback" }
    val reason = sequenceOf(error?.message, error?.cause?.message, fallbackReason)
        .mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
        .firstOrNull()
    return if (reason != null) {
        "$normalizedAction failed: $reason"
    } else {
        "$normalizedAction failed"
    }
}
