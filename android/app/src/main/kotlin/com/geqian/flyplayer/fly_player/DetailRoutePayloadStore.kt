package com.geqian.flyplayer.fly_player

import java.util.LinkedHashMap
import java.util.UUID

object DetailRoutePayloadStore {
    private const val MAX_ENTRIES = 48

    private val payloads =
        object : LinkedHashMap<String, HashMap<String, Any?>>(MAX_ENTRIES, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, HashMap<String, Any?>>?,
            ): Boolean = size > MAX_ENTRIES
        }

    fun putItem(initialItemDetail: HashMap<String, Any?>): String =
        putPayload(
            hashMapOf(
                "initialItemDetail" to HashMap(initialItemDetail),
            ),
        )

    fun putSeason(seasonItem: HashMap<String, Any?>): String =
        putPayload(
            hashMapOf(
                "seasonItem" to HashMap(seasonItem),
            ),
        )

    @Synchronized
    fun read(token: String): HashMap<String, Any?>? {
        val normalized = token.trim()
        if (normalized.isEmpty()) {
            return null
        }
        val payload = payloads.remove(normalized) ?: return null
        payloads[normalized] = payload
        return HashMap(payload)
    }

    @Synchronized
    private fun putPayload(payload: HashMap<String, Any?>): String {
        val token = UUID.randomUUID().toString()
        payloads[token] = payload
        return token
    }
}
