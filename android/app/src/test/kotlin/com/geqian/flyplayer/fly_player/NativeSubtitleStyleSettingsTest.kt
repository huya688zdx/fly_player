package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleStyleSettingsTest {
    @Test
    fun defaultsMatchMpvSubtitlePositionDefault() {
        val settings = NativeSubtitleStyleSettings.fromMap(emptyMap())

        assertEquals(0.0, settings.delaySeconds, 0.0)
        assertEquals(92, settings.position)
        assertEquals(1.0, settings.scale, 0.0)
        assertEquals(
            linkedMapOf<String, Any?>("delay" to 0.0, "position" to 92, "scale" to 1.0),
            settings.toMap(),
        )
    }

    @Test
    fun normalizesPersistedSubtitleStyleValues() {
        val settings = NativeSubtitleStyleSettings.fromMap(
            mapOf(
                "delay" to 12.34,
                "position" to 123,
                "scale" to 0.1,
            ),
        )

        assertEquals(10.0, settings.delaySeconds, 0.0)
        assertEquals(100, settings.position)
        assertEquals(0.5, settings.scale, 0.0)
    }
}
