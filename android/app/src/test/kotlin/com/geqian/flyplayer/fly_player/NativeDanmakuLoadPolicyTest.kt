package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeDanmakuLoadPolicyTest {
    @Suppress("UNCHECKED_CAST")
    @Test
    fun manualLoadPayloadUsesCurrentEnabledState() {
        val activity = NativePlayerActivity()
        val settingsField = NativePlayerActivity::class.java.getDeclaredField("danmakuSettings")
        settingsField.isAccessible = true
        val settings = settingsField.get(activity) as MutableMap<String, Any?>
        settings["enabled"] = true

        val mergeMethod = NativePlayerActivity::class.java.getDeclaredMethod(
            "payloadWithPersistedDanmakuPrefs",
            Map::class.java,
        )
        mergeMethod.isAccessible = true
        val merged = mergeMethod.invoke(
            activity,
            mapOf<String, Any?>("enabled" to false, "commentsCompact" to emptyList<Any?>()),
        ) as Map<String, Any?>

        assertEquals(true, merged["enabled"])
    }
}
