package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeServiceDanmakuRequestsTest {
    private fun context() = NativeServiceDanmakuContext(
        signedIn = true,
        accountIdentity = "account-session-1",
        statsScope = "binding-scope-1",
        playbackContextId = "load-1",
        seekEpoch = 3L,
        mediaArgs = mapOf("itemGuid" to "episode-1", "mediaGuid" to "file-1", "seasonGuid" to "season-1"),
    )

    @Test fun sameRequestCanCrossBothAsyncBoundariesOnlyWhileCurrent() {
        val requests = NativeServiceDanmakuRequests()
        val current = context()
        val ticket = requests.begin(current)
        assertTrue(requests.accepts(ticket, current, activityDestroying = false))
        // A file-read completion can arrive after the reverse-channel result.
        assertTrue(requests.accepts(ticket, current.copy(), activityDestroying = false))
        assertFalse(requests.accepts(ticket, current, activityDestroying = true))
    }

    @Test fun logoutAccountBindingLoadSeekOrEpisodeChangesRejectLatePayload() {
        val requests = NativeServiceDanmakuRequests()
        val current = context()
        val ticket = requests.begin(current)
        val invalid = listOf(
            current.copy(signedIn = false),
            current.copy(accountIdentity = "account-session-2"),
            current.copy(statsScope = "binding-scope-2"),
            current.copy(playbackContextId = "load-2"),
            current.copy(seekEpoch = 4L),
            current.copy(mediaArgs = current.mediaArgs + ("itemGuid" to "episode-2")),
            current.copy(mediaArgs = current.mediaArgs + ("mediaGuid" to "file-2")),
            current.copy(mediaArgs = current.mediaArgs + ("seasonGuid" to "season-2")),
        )
        for (next in invalid) assertFalse(next.toString(), requests.accepts(ticket, next, false))
    }

    @Test fun newerRequestOrManualSourceChoiceCannotBeOverwrittenByOldServiceResult() {
        val requests = NativeServiceDanmakuRequests()
        val current = context()
        val first = requests.begin(current)
        val second = requests.begin(current)
        assertFalse(requests.accepts(first, current, false))
        assertTrue(requests.accepts(second, current, false))
        requests.invalidate()
        assertFalse(requests.accepts(second, current, false))
    }

    @Test fun signedInFlagAloneIsNotEnoughToApplyServiceData() {
        for (current in listOf(
            context().copy(accountIdentity = ""),
            context().copy(statsScope = ""),
            context().copy(playbackContextId = ""),
            context().copy(mediaArgs = emptyMap()),
        )) {
            val requests = NativeServiceDanmakuRequests()
            assertFalse(requests.accepts(requests.begin(current), current, false))
        }
    }

    @Test fun onlyReadyServiceRepliesWithMatchingPayloadIdentityCanApply() {
        val ready = mapOf("status" to "ready", "danmakuFile" to "/private/payload.json", "sourceKey" to "nas:match:2:version")
        val reply = NativeServiceDanmakuPayload.fromReply(ready)!!
        assertEquals("/private/payload.json", reply.path)
        assertTrue(reply.matches(mapOf("sourceKey" to "nas:match:2:version")))
        assertFalse(reply.matches(mapOf("sourceKey" to "nas:match:1:old-version")))
        assertFalse(reply.matches(null))
        for (status in listOf("missing", "unavailable", "pending", "")) {
            assertNull(NativeServiceDanmakuPayload.fromReply(ready + ("status" to status)))
        }
        assertNull(NativeServiceDanmakuPayload.fromReply(ready + ("sourceKey" to "dandan:1")))
        assertEquals("dandan:1", NativeServiceDanmakuPayload.fromReply(
            ready + ("sourceKey" to "dandan:1"), allowOriginal = true)?.sourceKey)
        assertNull(NativeServiceDanmakuPayload.fromReply(ready + ("sourceKey" to "local:file"), allowOriginal = true))
        assertNull(NativeServiceDanmakuPayload.fromReply(ready + ("danmakuFile" to "")))
        assertNull(NativeServiceDanmakuPayload.fromReply(null))
    }
}
