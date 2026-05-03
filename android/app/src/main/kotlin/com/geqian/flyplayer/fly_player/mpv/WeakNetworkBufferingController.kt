package com.geqian.flyplayer.fly_player.mpv

import java.util.ArrayDeque
import kotlin.math.max
import kotlin.math.roundToLong

private const val LOCAL_REBUFFER_TARGET_MS = 1_000L
private const val NORMAL_REMOTE_REBUFFER_TARGET_MS = 2_000L
private const val WEAK_NETWORK_FALLBACK_REBUFFER_TARGET_MS = 8_000L
private const val WEAK_NETWORK_ENTER_WINDOW_MS = 45_000L
private const val WEAK_NETWORK_EXIT_IDLE_MS = 60_000L
private const val CACHE_SPEED_SAMPLE_MIN_INTERVAL_MS = 900L
private const val CACHE_SPEED_SAMPLE_STALE_MS = 4_000L

data class WeakNetworkBufferingSnapshot(
    val weakNetworkMode: Boolean,
    val networkSpeedBytesPerSecond: Long,
    val rebufferTargetMs: Long,
    val estimatedResumeWaitMs: Long?,
)

class WeakNetworkBufferingController {
    private val qualifiedRebufferEventsUptimeMs = ArrayDeque<Long>()
    private var qualifiedBufferingActive = false
    private var weakNetworkMode = false
    private var lastQualifiedRebufferUptimeMs = 0L
    private var lastSpeedSampleUptimeMs = 0L
    private var smoothedSpeedBytesPerSecond = 0.0

    fun reset() {
        qualifiedRebufferEventsUptimeMs.clear()
        qualifiedBufferingActive = false
        weakNetworkMode = false
        lastQualifiedRebufferUptimeMs = 0L
        lastSpeedSampleUptimeMs = 0L
        smoothedSpeedBytesPerSecond = 0.0
    }

    fun onBufferingStateChanged(
        buffering: Boolean,
        qualifiesAsRebuffer: Boolean,
        nowUptimeMs: Long,
    ) {
        if (buffering && qualifiesAsRebuffer) {
            if (!qualifiedBufferingActive) {
                recordQualifiedRebuffer(nowUptimeMs)
            }
            qualifiedBufferingActive = true
        } else {
            qualifiedBufferingActive = false
        }
        refreshWeakNetworkMode(nowUptimeMs)
    }

    fun onCacheSpeedSample(
        sampleBytesPerSecond: Long,
        nowUptimeMs: Long,
    ) {
        if (
            lastSpeedSampleUptimeMs > 0L &&
            nowUptimeMs - lastSpeedSampleUptimeMs < CACHE_SPEED_SAMPLE_MIN_INTERVAL_MS
        ) {
            return
        }
        lastSpeedSampleUptimeMs = nowUptimeMs
        val normalizedSample = sampleBytesPerSecond.coerceAtLeast(0L).toDouble()
        smoothedSpeedBytesPerSecond =
            if (smoothedSpeedBytesPerSecond <= 0.0) {
                normalizedSample
            } else {
                smoothedSpeedBytesPerSecond * 0.75 + normalizedSample * 0.25
            }
    }

    fun snapshot(
        isRemoteSource: Boolean,
        sourceBitrateBitsPerSec: Long,
        demuxerCacheDurationMs: Long,
        nowUptimeMs: Long,
    ): WeakNetworkBufferingSnapshot {
        refreshWeakNetworkMode(nowUptimeMs)
        val resolvedSpeedBytesPerSecond = currentSmoothedSpeedBytesPerSecond(nowUptimeMs)
        val rebufferTargetMs =
            resolveRebufferTargetMs(
                isRemoteSource = isRemoteSource,
                sourceBitrateBitsPerSec = sourceBitrateBitsPerSec,
                resolvedSpeedBytesPerSecond = resolvedSpeedBytesPerSecond,
            )
        val estimatedResumeWaitMs =
            estimateResumeWaitMs(
                isRemoteSource = isRemoteSource,
                sourceBitrateBitsPerSec = sourceBitrateBitsPerSec,
                resolvedSpeedBytesPerSecond = resolvedSpeedBytesPerSecond,
                rebufferTargetMs = rebufferTargetMs,
                demuxerCacheDurationMs = demuxerCacheDurationMs.coerceAtLeast(0L),
            )
        return WeakNetworkBufferingSnapshot(
            weakNetworkMode = isRemoteSource && weakNetworkMode,
            networkSpeedBytesPerSecond = if (isRemoteSource) resolvedSpeedBytesPerSecond else 0L,
            rebufferTargetMs = rebufferTargetMs,
            estimatedResumeWaitMs = estimatedResumeWaitMs,
        )
    }

    private fun recordQualifiedRebuffer(nowUptimeMs: Long) {
        lastQualifiedRebufferUptimeMs = nowUptimeMs
        qualifiedRebufferEventsUptimeMs.addLast(nowUptimeMs)
        trimExpiredRebufferEvents(nowUptimeMs)
        if (qualifiedRebufferEventsUptimeMs.size >= 2) {
            weakNetworkMode = true
        }
    }

    private fun refreshWeakNetworkMode(nowUptimeMs: Long) {
        trimExpiredRebufferEvents(nowUptimeMs)
        if (
            weakNetworkMode &&
            lastQualifiedRebufferUptimeMs > 0L &&
            nowUptimeMs - lastQualifiedRebufferUptimeMs >= WEAK_NETWORK_EXIT_IDLE_MS
        ) {
            weakNetworkMode = false
        }
    }

    private fun trimExpiredRebufferEvents(nowUptimeMs: Long) {
        while (qualifiedRebufferEventsUptimeMs.isNotEmpty()) {
            val ageMs = nowUptimeMs - qualifiedRebufferEventsUptimeMs.first()
            if (ageMs < WEAK_NETWORK_ENTER_WINDOW_MS) {
                break
            }
            qualifiedRebufferEventsUptimeMs.removeFirst()
        }
    }

    private fun currentSmoothedSpeedBytesPerSecond(nowUptimeMs: Long): Long {
        if (
            lastSpeedSampleUptimeMs <= 0L ||
            nowUptimeMs - lastSpeedSampleUptimeMs > CACHE_SPEED_SAMPLE_STALE_MS
        ) {
            return 0L
        }
        return smoothedSpeedBytesPerSecond.roundToLong().coerceAtLeast(0L)
    }

    private fun resolveRebufferTargetMs(
        isRemoteSource: Boolean,
        sourceBitrateBitsPerSec: Long,
        resolvedSpeedBytesPerSecond: Long,
    ): Long {
        if (!isRemoteSource) return LOCAL_REBUFFER_TARGET_MS
        if (!weakNetworkMode) return NORMAL_REMOTE_REBUFFER_TARGET_MS
        if (sourceBitrateBitsPerSec <= 0L || resolvedSpeedBytesPerSecond <= 0L) {
            return WEAK_NETWORK_FALLBACK_REBUFFER_TARGET_MS
        }
        val ratio =
            (resolvedSpeedBytesPerSecond.toDouble() * 8.0) /
                sourceBitrateBitsPerSec.toDouble()
        val targetSeconds =
            (6.0 + max(0.0, 1.15 - ratio) * 20.0)
                .coerceIn(6.0, 18.0)
        return (targetSeconds * 1000.0).roundToLong()
    }

    private fun estimateResumeWaitMs(
        isRemoteSource: Boolean,
        sourceBitrateBitsPerSec: Long,
        resolvedSpeedBytesPerSecond: Long,
        rebufferTargetMs: Long,
        demuxerCacheDurationMs: Long,
    ): Long? {
        if (!isRemoteSource) return null
        if (sourceBitrateBitsPerSec <= 0L || resolvedSpeedBytesPerSecond <= 0L) {
            return null
        }
        val ratio =
            (resolvedSpeedBytesPerSecond.toDouble() * 8.0) /
                sourceBitrateBitsPerSec.toDouble()
        if (ratio <= 0.0) return null
        val remainingBufferMs = (rebufferTargetMs - demuxerCacheDurationMs).coerceAtLeast(0L)
        if (remainingBufferMs <= 0L) return 0L
        return (remainingBufferMs.toDouble() / ratio).roundToLong().coerceAtLeast(0L)
    }
}
