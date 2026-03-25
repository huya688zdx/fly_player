package com.geqian.flyplayer.fly_player

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

object FullscreenScreenshotPayloadStore {
    private val payloads = ConcurrentHashMap<String, HashMap<String, Any?>>()

    fun put(
        items: List<HashMap<String, Any?>>,
        initialIndex: Int,
    ): String {
        val token = UUID.randomUUID().toString()
        payloads[token] =
            hashMapOf(
                "items" to ArrayList(items),
                "initialIndex" to initialIndex.coerceAtLeast(0),
            )
        return token
    }

    fun consume(token: String): HashMap<String, Any?>? {
        val normalized = token.trim()
        if (normalized.isEmpty()) {
            return null
        }
        return payloads.remove(normalized)
    }
}
