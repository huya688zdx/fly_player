package com.geqian.flyplayer.fly_player.oped

import org.junit.Assert.*
import org.junit.Test

class FlyOpedPlaybackTest {
    private fun publication(): Map<String, Any?> = mapOf(
        "status" to "published", "playback_context_id" to "context", "generation" to 0L,
        "set_revision" to "set1", "file_context" to mapOf(
            "identity_state" to "verified", "file_revision_id" to "file1", "media_coordinate_id" to "coord1", "duration_ms" to 120000L,
            "source_ref" to mapOf("binding_id" to "binding", "remote_item_id" to "episode", "remote_media_source_id" to null)),
        "segments" to listOf(mapOf("id" to "ed", "kind" to "ed", "start_ms" to 90000L, "end_ms" to 110000L, "skip_policy" to "auto")),
        "protected_ranges" to listOf(mapOf("start_ms" to 110000L, "end_ms" to 120000L)))

    @Test fun parsedEndingRetainsPostCredits() {
        val set = FlyOpedPublication.parse(publication(), "context", 0L, "episode", "")!!
        assertEquals(110000L, set.at(100000L)!!.endMs)
        assertNull(set.at(110000L))
        assertNull(FlyOpedPublication.parse(publication(), "different", 0L, "episode", ""))
        assertNull(FlyOpedPublication.parse(publication(), "context", 1L, "episode", ""))
        assertNull(FlyOpedPublication.parse(publication(), "context", 0L, "other", ""))
    }
    @Test fun actualSeekEpochMustCompleteAndTerminalIsUnique() {
        val set = FlyOpedPublication.parse(publication(), "context", 0L, "episode", "")!!
        val action = FlyOpedPending(set, set.at(95000)!!, "action", 0L, 95000L)
        action.seekEpoch = 5L
        assertNull(action.observe(5L, 4L, 110000L))
        assertNull(action.observe(5L, 5L, 95000L))
        assertNull(action.observe(5L, 5L, 110501L))
        assertEquals("settled", action.observe(5L, 5L, 110010L))
        assertNull(action.observe(5L, 5L, 110000L))
        assertEquals(110000L, action.event("intent")["target_ms"])
        assertEquals(110010L, action.event("settled")["position_ms"])
    }
    @Test fun interveningSeekCancelsAndResumeDoesNotAutoSkip() {
        val set = FlyOpedPublication.parse(publication(), "context", 0L, "episode", "")!!
        val action = FlyOpedPending(set, set.at(95000)!!, "action", 0L, 95000L)
        action.seekEpoch = 5L
        assertEquals("cancelled", action.observe(6L, 6L, 110000L))
        val policy = FlyOpedEntryPolicy()
        assertNull(policy.observe(set, 95000L, 0L))
        assertNull(policy.observe(set, 89000L, 1L))
        assertNull(policy.observe(set, 90000L, 1L))
        val normal = FlyOpedEntryPolicy()
        assertNull(normal.observe(set, 89000L, 0L))
        assertEquals("ed", normal.observe(set, 90000L, 0L)!!.id)
        val afterSeek = FlyOpedEntryPolicy()
        assertNull(afterSeek.observe(set, 1000L, 0L))
        assertNull(afterSeek.observe(set, 89000L, 1L))
        assertEquals("ed", afterSeek.observe(set, 90000L, 1L)?.id)
    }
}
