package com.geqian.flyplayer.fly_player

import org.json.JSONArray
import org.json.JSONObject

/** Native mirror mutations share the preferences transaction with additions. */
internal class NativeDanmakuSourceStore(
    private val settings: NativePlayerSettingsStore,
    private val identity: (JSONObject) -> String,
) {
    private fun without(raw: String?, mediaKey: String, sourceKey: String): JSONArray {
        val existing = if (raw == null) JSONArray() else JSONArray(raw)
        val kept = JSONArray()
        for (i in 0 until existing.length()) {
            val value = existing.get(i)
            val row = value as? JSONObject
            if (row == null || row.optString("mediaKey") != mediaKey || identity(row) != sourceKey) kept.put(value)
        }
        return kept
    }

    fun upsert(record: JSONObject): Boolean {
        val mediaKey = record.optString("mediaKey")
        if (mediaKey.isEmpty()) return false
        return settings.updateString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES) { raw ->
            without(raw, mediaKey, identity(record)).put(record).toString()
        }
    }

    fun removalCompletion(mediaKey: String, sourceKey: String): (Any?) -> Boolean {
        // Capture only identity. A reverse-channel round trip may overlap other
        // removals or imports; its success must transform the latest list.
        return { result ->
            result == true && settings.updateString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES) { raw ->
                without(raw, mediaKey, sourceKey).toString()
            }
        }
    }
}
