package com.geqian.flyplayer.fly_player.mpv

import kotlin.math.abs

internal enum class DanmakuTimelinePlaybackPhase {
    PLAYING,
    PAUSED,
    SEEKING,
}

internal enum class DanmakuTimelineState {
    PLAYING,
    PAUSED,
    SEEK_HOLD,
    RESUME_SETTLE,
}

internal enum class DanmakuTimelineCorrection {
    NONE,
    REBUILD,
    REANCHOR,
    SOFT_SYNC,
}

internal data class DanmakuTimelineUpdate(
    val accepted: Boolean,
    val isNewPositionSample: Boolean,
    val metricsEligible: Boolean,
    val state: DanmakuTimelineState,
    val correction: DanmakuTimelineCorrection,
    val timelineMs: Float,
    val rawDriftMs: Float,
    val stabilizedDriftMs: Float,
    val sampleLatencyMs: Float,
    val projectionMs: Float,
    val latencyFiltered: Boolean,
)

internal class DanmakuPlaybackSyncStatsAccumulator {
    var driftSampleCount: Int = 0
        private set
    var rebuildEventCount: Int = 0
        private set
    var reanchorEventCount: Int = 0
        private set
    var softSyncEventCount: Int = 0
        private set

    fun record(
        metricsEligible: Boolean,
        correction: DanmakuTimelineCorrection,
    ) {
        if (metricsEligible) {
            driftSampleCount += 1
        }
        when (correction) {
            DanmakuTimelineCorrection.REBUILD -> rebuildEventCount += 1
            DanmakuTimelineCorrection.REANCHOR -> reanchorEventCount += 1
            DanmakuTimelineCorrection.SOFT_SYNC -> softSyncEventCount += 1
            DanmakuTimelineCorrection.NONE -> Unit
        }
    }

    fun reset() {
        driftSampleCount = 0
        rebuildEventCount = 0
        reanchorEventCount = 0
        softSyncEventCount = 0
    }
}

internal class DanmakuTimelineClock {
    private var anchorPositionMs = 0f
    private var anchorTimeNs = 0L
    private var lastSoftSyncAppliedNs = 0L
    private var lastAcceptedSampleTimeNs = 0L
    private var seekHoldSampleFloorNs = 0L
    private var requiredSeekEpoch = 0L
    private var resumeFloorMs = 0f
    private var resumeSettleUntilNs = 0L
    private var lastReportedPositionMs = 0f

    var state: DanmakuTimelineState = DanmakuTimelineState.PAUSED
        private set

    val lastKnownPositionMs: Float
        get() = lastReportedPositionMs

    val isAdvancing: Boolean
        get() = state == DanmakuTimelineState.PLAYING || state == DanmakuTimelineState.RESUME_SETTLE

    val canReplayTimeline: Boolean
        get() = state != DanmakuTimelineState.SEEK_HOLD

    fun reset(
        positionMs: Float,
        nowNs: Long,
        paused: Boolean,
    ) {
        reanchor(positionMs, nowNs)
        lastReportedPositionMs = positionMs.coerceAtLeast(0f)
        state = if (paused) DanmakuTimelineState.PAUSED else DanmakuTimelineState.PLAYING
        lastSoftSyncAppliedNs = 0L
        lastAcceptedSampleTimeNs = 0L
        seekHoldSampleFloorNs = 0L
        requiredSeekEpoch = 0L
        resumeFloorMs = 0f
        resumeSettleUntilNs = 0L
    }

    fun reanchor(
        positionMs: Float,
        nowNs: Long,
    ) {
        anchorPositionMs = positionMs.coerceAtLeast(0f)
        anchorTimeNs = nowNs
    }

    fun rebuildAt(
        positionMs: Float,
        nowNs: Long,
    ) {
        reanchor(positionMs, nowNs)
        lastReportedPositionMs = positionMs.coerceAtLeast(0f)
        lastSoftSyncAppliedNs = 0L
    }

    fun hintSeek(
        positionMs: Float,
        nowNs: Long,
        seekEpoch: Long = 0L,
    ) {
        reanchor(positionMs, nowNs)
        lastReportedPositionMs = positionMs.coerceAtLeast(0f)
        state = DanmakuTimelineState.SEEK_HOLD
        seekHoldSampleFloorNs = maxOf(seekHoldSampleFloorNs, lastAcceptedSampleTimeNs)
        requiredSeekEpoch = maxOf(requiredSeekEpoch, seekEpoch)
        resumeSettleUntilNs = 0L
        lastSoftSyncAppliedNs = 0L
    }

    fun currentTimelineMs(
        nowNs: Long,
        playbackSpeed: Float,
    ): Float {
        if (state != DanmakuTimelineState.PLAYING && state != DanmakuTimelineState.RESUME_SETTLE) {
            return anchorPositionMs
        }
        val elapsedMs = (nowNs - anchorTimeNs).coerceAtLeast(0L) / 1_000_000f
        return anchorPositionMs + (elapsedMs * playbackSpeed.coerceAtLeast(0.1f))
    }

    fun update(
        positionMs: Float,
        sampleTimeNs: Long,
        nowNs: Long,
        phase: DanmakuTimelinePlaybackPhase,
        playbackSpeed: Float,
        activeSeekEpoch: Long = 0L,
        completedSeekEpoch: Long = 0L,
    ): DanmakuTimelineUpdate {
        val reportedPositionMs = positionMs.coerceAtLeast(0f)
        val predictedMs = currentTimelineMs(nowNs, playbackSpeed)
        val sampleFloorNs = maxOf(lastAcceptedSampleTimeNs, seekHoldSampleFloorNs)
        val isNewPositionSample = sampleTimeNs > 0L && sampleTimeNs > sampleFloorNs
        val safeSampleTimeNs =
            sampleTimeNs
                .takeIf { it > 0L }
                ?.coerceAtMost(nowNs)
                ?: nowNs

        if (phase == DanmakuTimelinePlaybackPhase.SEEKING) {
            lastReportedPositionMs = reportedPositionMs
            if (state != DanmakuTimelineState.SEEK_HOLD) {
                hintSeek(reportedPositionMs, nowNs, activeSeekEpoch)
            } else {
                requiredSeekEpoch = maxOf(requiredSeekEpoch, activeSeekEpoch)
            }
            rememberHoldSample(sampleTimeNs)
            return unchangedUpdate(predictedMs, isNewPositionSample = isNewPositionSample)
        }

        if (state == DanmakuTimelineState.SEEK_HOLD) {
            if (phase != DanmakuTimelinePlaybackPhase.PLAYING ||
                completedSeekEpoch < requiredSeekEpoch ||
                sampleTimeNs <= 0L ||
                sampleTimeNs <= seekHoldSampleFloorNs
            ) {
                rememberHoldSample(sampleTimeNs)
                return unchangedUpdate(predictedMs, isNewPositionSample = isNewPositionSample)
            }
            reanchor(reportedPositionMs, nowNs)
            lastReportedPositionMs = reportedPositionMs
            state = DanmakuTimelineState.PLAYING
            lastAcceptedSampleTimeNs = sampleTimeNs
            seekHoldSampleFloorNs = 0L
            requiredSeekEpoch = 0L
            return result(
                correction = DanmakuTimelineCorrection.REBUILD,
                timelineMs = reportedPositionMs,
                rawDriftMs = reportedPositionMs - predictedMs,
                stabilizedDriftMs = reportedPositionMs - predictedMs,
                isNewPositionSample = isNewPositionSample,
            )
        }

        if (sampleTimeNs > 0L &&
            lastAcceptedSampleTimeNs > 0L &&
            sampleTimeNs < lastAcceptedSampleTimeNs
        ) {
            return unchangedUpdate(predictedMs, accepted = false)
        }

        if (sampleTimeNs > 0L && sampleTimeNs == lastAcceptedSampleTimeNs &&
            phase == DanmakuTimelinePlaybackPhase.PLAYING &&
            (state == DanmakuTimelineState.PLAYING || state == DanmakuTimelineState.RESUME_SETTLE)
        ) {
            return unchangedUpdate(predictedMs)
        }

        if (phase == DanmakuTimelinePlaybackPhase.PAUSED) {
            if (state == DanmakuTimelineState.PAUSED) {
                rememberAcceptedSample(sampleTimeNs)
                return unchangedUpdate(predictedMs)
            }
            // 播停相位变化会先于下一份 time-pos 到达，不能用复用的旧位置把可见弹幕拉回。
            val pausePositionMs = predictedMs.coerceAtLeast(0f)
            reanchor(pausePositionMs, nowNs)
            lastReportedPositionMs = reportedPositionMs
            state = DanmakuTimelineState.PAUSED
            resumeSettleUntilNs = 0L
            rememberAcceptedSample(sampleTimeNs)
            return result(
                correction = DanmakuTimelineCorrection.REANCHOR,
                timelineMs = pausePositionMs,
                rawDriftMs = reportedPositionMs - predictedMs,
                stabilizedDriftMs = 0f,
                isNewPositionSample = isNewPositionSample,
            )
        }

        if (state == DanmakuTimelineState.PAUSED) {
            // 恢复事件也可能复用暂停前的旧样本，应从已经冻结的可见位置继续推进。
            val resumePositionMs = predictedMs.coerceAtLeast(0f)
            reanchor(resumePositionMs, nowNs)
            lastReportedPositionMs = reportedPositionMs
            state = DanmakuTimelineState.RESUME_SETTLE
            resumeFloorMs = resumePositionMs
            resumeSettleUntilNs = nowNs + RESUME_SETTLE_WINDOW_NS
            rememberAcceptedSample(sampleTimeNs)
            return result(
                correction = DanmakuTimelineCorrection.REANCHOR,
                timelineMs = resumePositionMs,
                rawDriftMs = 0f,
                stabilizedDriftMs = 0f,
                isNewPositionSample = isNewPositionSample,
            )
        }

        if (state == DanmakuTimelineState.RESUME_SETTLE && nowNs >= resumeSettleUntilNs) {
            state = DanmakuTimelineState.PLAYING
            resumeSettleUntilNs = 0L
        }

        val sampleLatencyMs = (nowNs - safeSampleTimeNs).coerceAtLeast(0L) / 1_000_000f
        val safePlaybackSpeed = playbackSpeed.coerceAtLeast(0.1f)
        val predictedAtSampleMs = timelineAtSample(safeSampleTimeNs, safePlaybackSpeed)
        val discontinuityDriftMs = reportedPositionMs - predictedAtSampleMs
        val projectionMs = sampleLatencyMs * safePlaybackSpeed
        val projectedPositionMs = reportedPositionMs + projectionMs
        val rawDriftMs = projectedPositionMs - predictedMs
        val reliability = sampleReliability(sampleLatencyMs)
        val latencyAdjustedPositionMs = predictedMs + (rawDriftMs * reliability)
        var stabilizedPositionMs = latencyAdjustedPositionMs

        if (state == DanmakuTimelineState.RESUME_SETTLE &&
            stabilizedPositionMs + ROLLBACK_TOLERANCE_MS < resumeFloorMs
        ) {
            stabilizedPositionMs = predictedMs
        }

        val stabilizedDriftMs = stabilizedPositionMs - predictedMs
        rememberAcceptedSample(sampleTimeNs)
        lastReportedPositionMs = reportedPositionMs

        if (discontinuityDriftMs > FORWARD_REBUILD_THRESHOLD_MS ||
            (state != DanmakuTimelineState.RESUME_SETTLE &&
                discontinuityDriftMs < BACKWARD_REBUILD_THRESHOLD_MS)
        ) {
            reanchor(reportedPositionMs, nowNs)
            lastSoftSyncAppliedNs = 0L
            return result(
                correction = DanmakuTimelineCorrection.REBUILD,
                timelineMs = reportedPositionMs,
                rawDriftMs = rawDriftMs,
                stabilizedDriftMs = stabilizedDriftMs,
                sampleLatencyMs = sampleLatencyMs,
                projectionMs = projectionMs,
                latencyFiltered = abs(latencyAdjustedPositionMs - projectedPositionMs) >= 0.5f,
                isNewPositionSample = isNewPositionSample,
                metricsEligible = isNewPositionSample,
            )
        }

        if (state == DanmakuTimelineState.RESUME_SETTLE) {
            return result(
                correction = DanmakuTimelineCorrection.NONE,
                timelineMs = predictedMs,
                rawDriftMs = rawDriftMs,
                stabilizedDriftMs = stabilizedDriftMs,
                sampleLatencyMs = sampleLatencyMs,
                projectionMs = projectionMs,
                latencyFiltered = abs(latencyAdjustedPositionMs - projectedPositionMs) >= 0.5f,
                isNewPositionSample = isNewPositionSample,
            )
        }

        val softSyncApplied = softSync(predictedMs, stabilizedPositionMs, nowNs)
        return result(
            correction =
                if (softSyncApplied) {
                    DanmakuTimelineCorrection.SOFT_SYNC
                } else {
                    DanmakuTimelineCorrection.NONE
                },
            timelineMs = currentTimelineMs(nowNs, playbackSpeed),
            rawDriftMs = rawDriftMs,
            stabilizedDriftMs = stabilizedDriftMs,
            sampleLatencyMs = sampleLatencyMs,
            projectionMs = projectionMs,
            latencyFiltered = abs(latencyAdjustedPositionMs - projectedPositionMs) >= 0.5f,
            isNewPositionSample = isNewPositionSample,
            metricsEligible = isNewPositionSample,
        )
    }

    fun softSync(
        predictedMs: Float,
        targetMs: Float,
        nowNs: Long,
    ): Boolean {
        val driftMs = targetMs - predictedMs
        if (abs(driftMs) <= SOFT_SYNC_DEAD_ZONE_MS) {
            return false
        }
        val sinceLastSoftSyncNs =
            if (lastSoftSyncAppliedNs == 0L) {
                Long.MAX_VALUE
            } else {
                (nowNs - lastSoftSyncAppliedNs).coerceAtLeast(0L)
            }
        if (sinceLastSoftSyncNs < SOFT_SYNC_MIN_INTERVAL_NS && abs(driftMs) < SOFT_SYNC_FORCE_DRIFT_MS) {
            return false
        }
        val deltaMs =
            (driftMs * SOFT_SYNC_GAIN)
                .coerceIn(-SOFT_SYNC_MAX_STEP_MS, SOFT_SYNC_MAX_STEP_MS)
        reanchor(predictedMs + deltaMs, nowNs)
        lastSoftSyncAppliedNs = nowNs
        return true
    }

    private fun timelineAtSample(
        sampleTimeNs: Long,
        playbackSpeed: Float,
    ): Float {
        if (state != DanmakuTimelineState.PLAYING && state != DanmakuTimelineState.RESUME_SETTLE) {
            return anchorPositionMs
        }
        val elapsedMs = (sampleTimeNs - anchorTimeNs) / 1_000_000f
        return anchorPositionMs + (elapsedMs * playbackSpeed)
    }

    private fun sampleReliability(sampleLatencyMs: Float): Float {
        if (sampleLatencyMs <= FULL_RELIABILITY_LATENCY_MS) {
            return 1f
        }
        if (sampleLatencyMs >= MIN_RELIABILITY_LATENCY_MS) {
            return MIN_SAMPLE_RELIABILITY
        }
        val span = MIN_RELIABILITY_LATENCY_MS - FULL_RELIABILITY_LATENCY_MS
        val latencyProgress = (sampleLatencyMs - FULL_RELIABILITY_LATENCY_MS) / span
        return 1f - (latencyProgress * (1f - MIN_SAMPLE_RELIABILITY))
    }

    private fun rememberHoldSample(sampleTimeNs: Long) {
        if (sampleTimeNs > seekHoldSampleFloorNs) {
            seekHoldSampleFloorNs = sampleTimeNs
        }
    }

    private fun rememberAcceptedSample(sampleTimeNs: Long) {
        if (sampleTimeNs > lastAcceptedSampleTimeNs) {
            lastAcceptedSampleTimeNs = sampleTimeNs
        }
    }

    private fun unchangedUpdate(
        timelineMs: Float,
        accepted: Boolean = true,
        isNewPositionSample: Boolean = false,
    ): DanmakuTimelineUpdate {
        return result(
            accepted = accepted,
            correction = DanmakuTimelineCorrection.NONE,
            timelineMs = timelineMs,
            rawDriftMs = 0f,
            stabilizedDriftMs = 0f,
            isNewPositionSample = isNewPositionSample,
        )
    }

    private fun result(
        accepted: Boolean = true,
        correction: DanmakuTimelineCorrection,
        timelineMs: Float,
        rawDriftMs: Float,
        stabilizedDriftMs: Float,
        sampleLatencyMs: Float = 0f,
        projectionMs: Float = 0f,
        latencyFiltered: Boolean = false,
        isNewPositionSample: Boolean = false,
        metricsEligible: Boolean = false,
    ): DanmakuTimelineUpdate {
        return DanmakuTimelineUpdate(
            accepted = accepted,
            isNewPositionSample = isNewPositionSample,
            metricsEligible = metricsEligible,
            state = state,
            correction = correction,
            timelineMs = timelineMs,
            rawDriftMs = rawDriftMs,
            stabilizedDriftMs = stabilizedDriftMs,
            sampleLatencyMs = sampleLatencyMs,
            projectionMs = projectionMs,
            latencyFiltered = latencyFiltered,
        )
    }

    private companion object {
        const val SOFT_SYNC_DEAD_ZONE_MS = 12f
        const val SOFT_SYNC_GAIN = 0.12f
        const val SOFT_SYNC_MAX_STEP_MS = 1.5f
        const val SOFT_SYNC_MIN_INTERVAL_NS = 110_000_000L
        const val SOFT_SYNC_FORCE_DRIFT_MS = 28f
        const val BACKWARD_REBUILD_THRESHOLD_MS = -500f
        const val FORWARD_REBUILD_THRESHOLD_MS = 2_500f
        const val ROLLBACK_TOLERANCE_MS = 48f
        const val FULL_RELIABILITY_LATENCY_MS = 12f
        const val MIN_RELIABILITY_LATENCY_MS = 120f
        const val MIN_SAMPLE_RELIABILITY = 0.2f
        const val RESUME_SETTLE_WINDOW_NS = 1_400_000_000L
    }
}
