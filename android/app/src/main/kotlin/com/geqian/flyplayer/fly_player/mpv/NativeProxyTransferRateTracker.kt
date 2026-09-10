package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock

private const val TRANSFER_RATE_SAMPLE_WINDOW_MS = 900L
private const val TRANSFER_RATE_STALE_MS = 4_000L
private const val TRANSFER_RATE_PARTIAL_WINDOW_MIN_MS = 200L

internal class NativeProxyTransferRateTracker {
    private val monitor = Any()
    private var windowStartedAtMs = -1L
    private var bytesInWindow = 0L
    private var lastRateBytesPerSecond = 0L
    private var lastRateSampleAtMs = -1L

    fun reset() {
        synchronized(monitor) {
            windowStartedAtMs = -1L
            bytesInWindow = 0L
            lastRateBytesPerSecond = 0L
            lastRateSampleAtMs = -1L
        }
    }

    fun onBytesTransferred(
        byteCount: Int,
        nowElapsedMs: Long = SystemClock.elapsedRealtime(),
    ) {
        if (byteCount <= 0) {
            return
        }
        synchronized(monitor) {
            if (windowStartedAtMs < 0L) {
                windowStartedAtMs = nowElapsedMs
            }
            bytesInWindow += byteCount.toLong()
            val elapsedMs = (nowElapsedMs - windowStartedAtMs).coerceAtLeast(1L)
            if (elapsedMs < TRANSFER_RATE_SAMPLE_WINDOW_MS) {
                return
            }
            lastRateBytesPerSecond = (bytesInWindow * 1000L / elapsedMs).coerceAtLeast(0L)
            lastRateSampleAtMs = nowElapsedMs
            windowStartedAtMs = nowElapsedMs
            bytesInWindow = 0L
        }
    }

    fun currentBytesPerSecond(
        nowElapsedMs: Long = SystemClock.elapsedRealtime(),
    ): Long {
        synchronized(monitor) {
            val lastSampleAgeMs =
                if (lastRateSampleAtMs >= 0L) {
                    nowElapsedMs - lastRateSampleAtMs
                } else {
                    Long.MAX_VALUE
                }
            val lastRate =
                if (lastSampleAgeMs <= TRANSFER_RATE_STALE_MS) {
                    lastRateBytesPerSecond
                } else {
                    0L
                }
            val partialElapsedMs =
                if (windowStartedAtMs >= 0L) {
                    nowElapsedMs - windowStartedAtMs
                } else {
                    0L
                }
            val partialRate =
                if (bytesInWindow > 0L && partialElapsedMs >= TRANSFER_RATE_PARTIAL_WINDOW_MIN_MS) {
                    (bytesInWindow * 1000L / partialElapsedMs.coerceAtLeast(1L)).coerceAtLeast(0L)
                } else {
                    0L
                }
            return maxOf(lastRate, partialRate)
        }
    }
}
