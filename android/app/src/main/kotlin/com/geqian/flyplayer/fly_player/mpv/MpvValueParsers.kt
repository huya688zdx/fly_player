package com.geqian.flyplayer.fly_player.mpv

fun Any?.toLongValue(): Long {
    return when (this) {
        is Long -> this
        is Int -> toLong()
        is Double -> toLong()
        is Float -> toLong()
        is Number -> toLong()
        else -> toString().toLongOrNull() ?: 0L
    }
}

fun Any?.toIntValue(): Int? {
    return when (this) {
        null -> null
        is Int -> this
        is Long -> toInt()
        is Double -> toInt()
        is Float -> toInt()
        is Number -> toInt()
        else -> toString().toIntOrNull()
    }
}

fun Any?.toDoubleValue(): Double? {
    return when (this) {
        null -> null
        is Double -> this
        is Float -> toDouble()
        is Int -> toDouble()
        is Long -> toDouble()
        is Number -> toDouble()
        else -> toString().toDoubleOrNull()
    }
}

fun sanitizeMpvIntProperty(property: String, value: Long?): Long? {
    val numeric = value ?: return null
    if (numeric <= 0L) return null
    return when (property) {
        "display-depth" -> numeric.takeIf { it in 1L..64L }
        "video-params/w",
        "video-params/h",
        "video-out-params/w",
        "video-out-params/h" -> numeric.takeIf { it in 1L..16384L }
        else -> numeric
    }
}

fun sanitizeMpvDoubleProperty(property: String, value: Double?): Double? {
    val numeric = value ?: return null
    if (!numeric.isFinite()) return null
    return when (property) {
        "video-params/sig-peak",
        "video-out-params/sig-peak" -> numeric.takeIf { it in 0.001..100000.0 }
        else -> numeric.takeIf { it > 0.0 }
    }
}
