package com.geqian.flyplayer.fly_player.oped

import org.junit.Assert.*
import org.junit.Test

class FlyOpedPlaybackTest {
    private fun timelinePublication() = FlyOpedPublication("current-load", "file", "coordinate",
        "revision", mapOf("binding_id" to "binding"), 1421005L, listOf(
            FlyOpedSegment("op", "op", 79876L, 164876L, "prompt_only"),
            FlyOpedSegment("recap", "recap", 200000L, 220000L, "prompt_only"),
            FlyOpedSegment("ed", "ed", 1330000L, 1420000L, "auto")))

    @Test fun timelinePreservesExactOpEdCoordinatesAndTail() {
        val set = timelinePublication()
        val ranges = flyOpedTimelineSegments(set, FlyOpedAccess(true, "account", true),
            true, "current-load", 1421005L)
        assertEquals(listOf("op", "ed"), ranges.map { it.kind })
        assertEquals(79876L, ranges.first().startMs)
        assertEquals(164876L, ranges.first().endMs)
        assertEquals(1420000L, ranges.last().endMs)
        assertTrue(ranges.last().endMs < set.durationMs)
        assertSame(set.segments.first(), ranges.first())
    }

    @Test fun timelineClearsForDisabledAccountSourceOrContext() {
        val set = timelinePublication()
        val access = FlyOpedAccess(true, "account", true)
        assertTrue(flyOpedTimelineSegments(set, access.copy(enabled = false), true, "current-load", 1421005L).isEmpty())
        assertTrue(flyOpedTimelineSegments(set, access.copy(signedIn = false), true, "current-load", 1421005L).isEmpty())
        assertTrue(flyOpedTimelineSegments(set, access, false, "current-load", 1421005L).isEmpty())
        assertTrue(flyOpedTimelineSegments(set, access, true, "other-load", 1421005L).isEmpty())
        assertTrue(flyOpedTimelineSegments(null, access, true, "current-load", 1421005L).isEmpty())
        assertTrue(flyOpedTimelineSegments(set, access, true, "current-load", 0L).isEmpty())
    }

    @Test fun timelineOmitsNeverAndDoesNotClampInvalidEndToVideoEnd() {
        val set = timelinePublication()
        val access = FlyOpedAccess(true, "account", true)
        val hiddenOp = set.copy(segments = set.segments.map { if (it.kind == "op") it.copy(policy = "never") else it })
        assertEquals(listOf("ed"), flyOpedTimelineSegments(hiddenOp, access, true, "current-load", 1421005L).map { it.kind })
        assertEquals(listOf("op"), flyOpedTimelineSegments(set, access, true, "current-load", 1400000L).map { it.kind })
    }

    @Test fun timelineCapsPreserveSubpixelTailAndNarrowRanges() {
        val edStart = 300f * (1330000f / 1421005f)
        val edEnd = 300f * (1420000f / 1421005f)
        val caps = flyOpedTimelineCaps(edStart, edEnd, 1f)
        assertTrue(300f - edEnd < 1f)
        assertEquals(edEnd, caps.last().second)
        assertTrue(caps.all { it.first >= edStart && it.second <= edEnd })
        val narrow = flyOpedTimelineCaps(20f, 20.25f, 2f)
        assertTrue(narrow.all { it.first >= 20f && it.second <= 20.25f })
        assertTrue(flyOpedTimelineCaps(20f, 20f, 1f).isEmpty())
    }

    @Test fun serviceVisibilityRequiresExplicitAccountWhileSettingSurvivesLogout() {
        val signedOut = FlyOpedAccess.fromLoadArgs(emptyMap<String, Any?>())
        assertFalse(signedOut.signedIn)
        assertTrue(signedOut.enabled)
        assertFalse(signedOut.canConsume(originalSource = true))
        val disabledAccount = FlyOpedAccess.fromAccountState(mapOf(
            "signedIn" to true, "scopeIdentity" to "account-device", "flyVerifiedEnabled" to false), true)
        assertTrue(disabledAccount.signedIn)
        assertFalse(disabledAccount.canConsume(originalSource = true))
        val loggedOut = FlyOpedAccess.fromAccountState(mapOf("signedIn" to false), disabledAccount.enabled)
        assertFalse(loggedOut.signedIn)
        assertFalse(loggedOut.enabled)
        assertFalse(loggedOut.canConsume(originalSource = true))
    }

    @Test fun signedInServiceSettingConsumesOriginalWithoutLegacyChapterToggle() {
        val access = FlyOpedAccess.fromLoadArgs(mapOf(
            "flyAccountSignedIn" to true, "flyAccountScopeIdentity" to "account-device",
            "flyOpedSettings" to mapOf("flyVerifiedEnabled" to true),
            "introOutro" to mapOf("enabled" to false)), false)
        assertTrue(access.canConsume(originalSource = true))
        assertFalse(access.canConsume(originalSource = false))
        assertFalse(access.copy(enabled = false).canConsume(originalSource = true))
        assertNotEquals(access, access.copy(scopeIdentity = "other-account-device"))
    }

    @Test fun malformedAccountRefreshHidesServiceWithoutErasingUserPreference() {
        val access = FlyOpedAccess.fromAccountState(null, true)
        assertFalse(access.signedIn)
        assertTrue(access.enabled)
        assertFalse(access.canConsume(originalSource = true))
        assertFalse(FlyOpedAccess.fromLoadArgs(mapOf("flyAccountSignedIn" to "true")).signedIn)
    }

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
