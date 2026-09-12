package com.geqian.flyplayer.fly_player.oped

private fun milliseconds(value: Any?): Long? = when (value) {
    is Int -> value.toLong()
    is Long -> value
    else -> null
}?.takeIf { it in 0L..9007199254740991L }
private fun identifier(value: Any?): String? = (value as? String)?.takeIf { it.isNotEmpty() && it.length <= 500 && it == it.trim() }

data class FlyOpedSegment(val id: String, val kind: String, val startMs: Long, val endMs: Long, val policy: String) {
    fun contains(positionMs: Long) = positionMs >= startMs && positionMs < endMs
}

/** Values supplied by Fly's existing authenticated bridge; no file identity is
 * derived locally. Fail closed on the entire set, including protected content. */
data class FlyOpedPublication(val contextId: String, val fileId: String, val coordinateId: String,
    val revision: String, val source: Map<*, *>, val durationMs: Long, val segments: List<FlyOpedSegment>) {
    fun at(positionMs: Long) = segments.firstOrNull { it.policy != "never" && it.kind in listOf("op", "ed") && it.contains(positionMs) }
    companion object {
        fun parse(raw: Any?, contextId: String, generation: Long, itemId: String, mediaId: String): FlyOpedPublication? {
            val data = raw as? Map<*, *> ?: return null
            if (data["status"] != "published" || data["playback_context_id"] != contextId || milliseconds(data["generation"]) != generation) return null
            val file = data["file_context"] as? Map<*, *> ?: return null
            if (file["identity_state"] != "verified") return null
            val source = file["source_ref"] as? Map<*, *> ?: return null
            if (identifier(source["binding_id"]) == null || source["remote_item_id"] != itemId || (source["remote_media_source_id"] ?: "") != mediaId) return null
            val fileId = identifier(file["file_revision_id"]) ?: return null
            val coordinate = identifier(file["media_coordinate_id"]) ?: return null
            val revision = identifier(data["set_revision"]) ?: return null
            val duration = milliseconds(file["duration_ms"])?.takeIf { it > 0 } ?: return null
            val items = data["segments"] as? List<*> ?: return null
            val protected = data["protected_ranges"] as? List<*> ?: return null
            if (items.size > 64 || protected.size > 64) return null
            val ranges = mutableListOf<Pair<Long, Long>>()
            for (value in protected) {
                val range = value as? Map<*, *> ?: return null
                val start = milliseconds(range["start_ms"]) ?: return null
                val end = milliseconds(range["end_ms"]) ?: return null
                if (start >= end || end > duration) return null
                ranges.add(start to end)
            }
            val segments = mutableListOf<FlyOpedSegment>()
            for (value in items) {
                val item = value as? Map<*, *> ?: return null
                val id = identifier(item["id"]) ?: return null
                val start = milliseconds(item["start_ms"]) ?: return null
                val end = milliseconds(item["end_ms"]) ?: return null
                val kind = item["kind"] as? String ?: return null
                val policy = item["skip_policy"] as? String ?: return null
                if (start >= end || end > duration || kind !in listOf("op", "ed", "recap", "preview", "post_credit") || policy !in listOf("auto", "prompt_only", "never")) return null
                if (segments.any { it.id == id || start < it.endMs && end > it.startMs }) return null
                if (policy != "never" && ranges.any { start < it.second && end > it.first }) return null
                segments.add(FlyOpedSegment(id, kind, start, end, policy))
            }
            return FlyOpedPublication(contextId, fileId, coordinate, revision, source.toMap(), duration, segments.toList())
        }
    }
}

class FlyOpedEntryPolicy {
    private var previous: Long? = null
    private var epoch: Long? = null
    private val entered = mutableSetOf<String>()
    fun observe(set: FlyOpedPublication, positionMs: Long, seekEpoch: Long): FlyOpedSegment? {
        val last = if (epoch != seekEpoch) null else previous
        epoch = seekEpoch
        previous = positionMs
        val segment = set.at(positionMs) ?: return null
        if (!entered.add("${set.revision}:${segment.id}")) return null
        return segment.takeIf { last != null && positionMs >= last && positionMs - last <= 2500 && last < segment.startMs && segment.policy == "auto" }
    }
}

class FlyOpedPending(val set: FlyOpedPublication, val segment: FlyOpedSegment, val actionId: String,
    val generation: Long, val positionMs: Long) {
    var seekEpoch: Long? = null
    private var terminal = false
    private var terminalPositionMs: Long? = null
    fun finish(phase: String): String? {
        if (terminal || phase !in listOf("settled", "failed", "cancelled")) return null
        terminal = true
        return phase
    }
    fun observe(active: Long, completed: Long, position: Long): String? {
        val expected = seekEpoch ?: return null
        if (terminal) return null
        if (active > expected) return finish("cancelled")
        if (active == expected && completed == expected && kotlin.math.abs(position - segment.endMs) <= 500) {
            terminalPositionMs = position
            return finish("settled")
        }
        return null
    }
    fun event(phase: String): Map<String, Any?> = mapOf(
        "action_id" to actionId, "phase" to phase, "source_ref" to set.source,
        "playback_context_id" to set.contextId, "generation" to generation,
        "file_revision_id" to set.fileId, "media_coordinate_id" to set.coordinateId,
        "set_revision" to set.revision, "segment_id" to segment.id,
        "position_ms" to (if (phase == "settled") terminalPositionMs else positionMs), "target_ms" to segment.endMs)
}
