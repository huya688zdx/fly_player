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
        // VO 未就绪/属性不可读时 mpv-android JNI 会回垃圾大值（常是相邻内存指针，如 5e11）。
        // 丢帧计数物理上不可能这么大（60fps 跑满一天才 ~5e6），超上限即判为无效。
        "frame-drop-count",
        "decoder-frame-drop-count" -> numeric.takeIf { it in 1L..100_000_000L }
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
