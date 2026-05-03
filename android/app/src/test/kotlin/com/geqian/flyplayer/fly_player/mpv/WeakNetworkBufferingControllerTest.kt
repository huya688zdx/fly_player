package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeakNetworkBufferingControllerTest {
    @Test
    fun entersWeakNetworkModeAfterTwoRebuffersWithinWindow() {
        val controller = WeakNetworkBufferingController()

        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 1_000L,
        )
        controller.onBufferingStateChanged(
            buffering = false,
            qualifiesAsRebuffer = false,
            nowUptimeMs = 3_000L,
        )
        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 30_000L,
        )

        val snapshot =
            controller.snapshot(
                isRemoteSource = true,
                sourceBitrateBitsPerSec = 8_000_000L,
                demuxerCacheDurationMs = 0L,
                nowUptimeMs = 30_500L,
            )

        assertTrue(snapshot.weakNetworkMode)
    }

    @Test
    fun exitsWeakNetworkModeAfterSixtySecondsWithoutRebuffer() {
        val controller = WeakNetworkBufferingController()

        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 1_000L,
        )
        controller.onBufferingStateChanged(
            buffering = false,
            qualifiesAsRebuffer = false,
            nowUptimeMs = 2_000L,
        )
        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 20_000L,
        )

        val snapshot =
            controller.snapshot(
                isRemoteSource = true,
                sourceBitrateBitsPerSec = 8_000_000L,
                demuxerCacheDurationMs = 0L,
                nowUptimeMs = 80_500L,
            )

        assertFalse(snapshot.weakNetworkMode)
        assertEquals(2_000L, snapshot.rebufferTargetMs)
    }

    @Test
    fun computesDynamicWeakNetworkTargetAndResumeEta() {
        val controller = WeakNetworkBufferingController()

        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 1_000L,
        )
        controller.onBufferingStateChanged(
            buffering = false,
            qualifiesAsRebuffer = false,
            nowUptimeMs = 2_000L,
        )
        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 20_000L,
        )
        controller.onCacheSpeedSample(
            sampleBytesPerSecond = 1_000_000L,
            nowUptimeMs = 20_500L,
        )

        val snapshot =
            controller.snapshot(
                isRemoteSource = true,
                sourceBitrateBitsPerSec = 8_000_000L,
                demuxerCacheDurationMs = 3_000L,
                nowUptimeMs = 21_000L,
            )

        assertTrue(snapshot.weakNetworkMode)
        assertEquals(9_000L, snapshot.rebufferTargetMs)
        assertEquals(6_000L, snapshot.estimatedResumeWaitMs)
        assertEquals(1_000_000L, snapshot.networkSpeedBytesPerSecond)
    }

    @Test
    fun fallsBackToFixedWeakTargetWhenBitrateOrSpeedMissing() {
        val controller = WeakNetworkBufferingController()

        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 1_000L,
        )
        controller.onBufferingStateChanged(
            buffering = false,
            qualifiesAsRebuffer = false,
            nowUptimeMs = 2_000L,
        )
        controller.onBufferingStateChanged(
            buffering = true,
            qualifiesAsRebuffer = true,
            nowUptimeMs = 20_000L,
        )

        val snapshot =
            controller.snapshot(
                isRemoteSource = true,
                sourceBitrateBitsPerSec = 0L,
                demuxerCacheDurationMs = 0L,
                nowUptimeMs = 20_500L,
            )

        assertTrue(snapshot.weakNetworkMode)
        assertEquals(8_000L, snapshot.rebufferTargetMs)
        assertEquals(0L, snapshot.networkSpeedBytesPerSecond)
        assertNull(snapshot.estimatedResumeWaitMs)
    }
}
