package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeProxyTransferRateTrackerTest {
    @Test
    fun reportsRollingInputRateAfterSampleWindow() {
        val tracker = NativeProxyTransferRateTracker()

        tracker.onBytesTransferred(byteCount = 256 * 1024, nowElapsedMs = 0L)
        tracker.onBytesTransferred(byteCount = 256 * 1024, nowElapsedMs = 1_000L)

        assertEquals(512 * 1024L, tracker.currentBytesPerSecond(nowElapsedMs = 1_000L))
    }

    @Test
    fun fallsBackToPartialWindowRateBeforeFirstFullSample() {
        val tracker = NativeProxyTransferRateTracker()

        tracker.onBytesTransferred(byteCount = 128 * 1024, nowElapsedMs = 0L)
        tracker.onBytesTransferred(byteCount = 128 * 1024, nowElapsedMs = 500L)

        assertEquals(256 * 1024L, tracker.currentBytesPerSecond(nowElapsedMs = 1_000L))
    }

    @Test
    fun clearsStaleRate() {
        val tracker = NativeProxyTransferRateTracker()

        tracker.onBytesTransferred(byteCount = 512 * 1024, nowElapsedMs = 0L)
        tracker.onBytesTransferred(byteCount = 512 * 1024, nowElapsedMs = 1_000L)

        assertEquals(0L, tracker.currentBytesPerSecond(nowElapsedMs = 6_000L))
    }
}
