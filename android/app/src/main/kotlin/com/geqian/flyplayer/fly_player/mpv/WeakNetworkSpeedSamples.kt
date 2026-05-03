package com.geqian.flyplayer.fly_player.mpv

private const val MAX_REASONABLE_WEAK_NETWORK_SPEED_BYTES_PER_SECOND = 256L * 1024L * 1024L

internal fun sanitizeWeakNetworkSpeedSampleBytesPerSecond(sampleBytesPerSecond: Long?): Long {
    val normalized = sampleBytesPerSecond ?: return 0L
    if (normalized <= 0L) return 0L
    if (normalized > MAX_REASONABLE_WEAK_NETWORK_SPEED_BYTES_PER_SECOND) {
        return 0L
    }
    return normalized
}

internal fun resolveMpvCacheSpeedSampleBytesPerSecond(
    rawIntBytesPerSecond: Long?,
    rawStringBytesPerSecond: String?,
): Long {
    val parsedStringSample =
        rawStringBytesPerSecond
            ?.trim()
            ?.takeUnless { it.isEmpty() || it == "-" }
            ?.let(::parseWeakNetworkSpeedSampleText)
    val sanitizedStringSample =
        sanitizeWeakNetworkSpeedSampleBytesPerSecond(parsedStringSample)
    if (sanitizedStringSample > 0L) {
        return sanitizedStringSample
    }
    return sanitizeWeakNetworkSpeedSampleBytesPerSecond(rawIntBytesPerSecond)
}

private fun parseWeakNetworkSpeedSampleText(value: String): Long? {
    value.toLongOrNull()?.let { return it }
    val decimal = value.toDoubleOrNull() ?: return null
    if (!decimal.isFinite() || decimal <= 0.0) return null
    return decimal.toLong()
}
