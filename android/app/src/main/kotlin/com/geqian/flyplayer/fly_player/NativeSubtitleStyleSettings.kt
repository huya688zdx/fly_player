package com.geqian.flyplayer.fly_player

data class NativeSubtitleStyleSettings(
    val delaySeconds: Double = DEFAULT_DELAY_SECONDS,
    val position: Int = DEFAULT_POSITION,
    val scale: Double = DEFAULT_SCALE,
) {
    fun toMap(): LinkedHashMap<String, Any?> =
        linkedMapOf("delay" to delaySeconds, "position" to position, "scale" to scale)

    companion object {
        const val DEFAULT_DELAY_SECONDS = 0.0
        const val DEFAULT_POSITION = 92
        const val DEFAULT_SCALE = 1.0

        fun defaultMap(): LinkedHashMap<String, Any?> =
            NativeSubtitleStyleSettings().toMap()

        fun fromMap(raw: Map<String, Any?>): NativeSubtitleStyleSettings {
            return NativeSubtitleStyleSettings(
                delaySeconds = (raw["delay"] as? Number)
                    ?.toDouble()
                    ?.coerceIn(-10.0, 10.0)
                    ?: DEFAULT_DELAY_SECONDS,
                position = (raw["position"] as? Number)
                    ?.toInt()
                    ?.coerceIn(0, 100)
                    ?: DEFAULT_POSITION,
                scale = (raw["scale"] as? Number)
                    ?.toDouble()
                    ?.coerceIn(0.5, 2.5)
                    ?: DEFAULT_SCALE,
            )
        }
    }
}
