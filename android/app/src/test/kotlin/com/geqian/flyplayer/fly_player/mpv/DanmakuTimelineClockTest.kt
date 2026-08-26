package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DanmakuTimelineClockTest {
    @Test
    fun `暂停时钟保持锚点`() {
        val clock = DanmakuTimelineClock()
        clock.reset(
            positionMs = 1_000f,
            nowNs = 0L,
            paused = true,
        )

        assertEquals(1_000f, clock.currentTimelineMs(nowNs = 5_000_000_000L, playbackSpeed = 1f), 0.001f)
    }

    @Test
    fun `播放时钟按倍速预测`() {
        val clock = DanmakuTimelineClock()
        clock.reset(
            positionMs = 1_000f,
            nowNs = 0L,
            paused = false,
        )

        assertEquals(2_500f, clock.currentTimelineMs(nowNs = 1_000_000_000L, playbackSpeed = 1.5f), 0.001f)
    }

    @Test
    fun `正向小漂移按上限软同步`() {
        val clock = DanmakuTimelineClock()
        clock.reset(
            positionMs = 1_000f,
            nowNs = 0L,
            paused = false,
        )

        val applied =
            clock.softSync(
                predictedMs = 1_100f,
                targetMs = 1_200f,
                nowNs = 100_000_000L,
            )

        assertEquals(true, applied)
        assertEquals(1_101.5f, clock.currentTimelineMs(nowNs = 100_000_000L, playbackSpeed = 1f), 0.001f)
    }

    @Test
    fun `微卡顿后的负向漂移会小步回拉`() {
        val clock = playingClock(positionMs = 10_000f)

        val result =
            clock.update(
                positionMs = 9_980f,
                sampleTimeNs = 20_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.SOFT_SYNC, result.correction)
        assertTrue(result.stabilizedDriftMs < -12f)
        assertEquals(10_098.5f, clock.currentTimelineMs(100_000_000L, 1f), 0.01f)
    }

    @Test
    fun `一百二十毫秒迟样本仍保留正权重并持续回拉`() {
        val clock = playingClock(positionMs = 10_000f)

        val first =
            clock.update(
                positionMs = 10_000f,
                sampleTimeNs = 80_000_000L,
                nowNs = 200_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        val second =
            clock.update(
                positionMs = 10_200f,
                sampleTimeNs = 280_000_000L,
                nowNs = 400_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertTrue(first.stabilizedDriftMs < 0f)
        assertEquals(DanmakuTimelineCorrection.SOFT_SYNC, first.correction)
        assertTrue(second.stabilizedDriftMs < 0f)
        assertEquals(DanmakuTimelineCorrection.SOFT_SYNC, second.correction)
    }

    @Test
    fun `高延迟的大幅原始负漂移仍会重建`() {
        val clock = playingClock(positionMs = 10_000f)

        val result =
            clock.update(
                positionMs = 9_300f,
                sampleTimeNs = 80_000_000L,
                nowNs = 200_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertTrue(result.rawDriftMs < -500f)
        assertEquals(DanmakuTimelineCorrection.REBUILD, result.correction)
    }

    @Test
    fun `六百毫秒准确迟样本不误判跳变但真实跳变重建到上报位置`() {
        val accurateClock = playingClock(positionMs = 10_000f)
        val accurateLateSample =
            accurateClock.update(
                positionMs = 10_400f,
                sampleTimeNs = 400_000_000L,
                nowNs = 1_000_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertFalse(accurateLateSample.correction == DanmakuTimelineCorrection.REBUILD)

        val discontinuityClock = playingClock(positionMs = 10_000f)
        val trueBackwardJump =
            discontinuityClock.update(
                positionMs = 9_700f,
                sampleTimeNs = 400_000_000L,
                nowNs = 1_000_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REBUILD, trueBackwardJump.correction)
        assertEquals(9_700f, trueBackwardJump.timelineMs, 0.001f)
        assertEquals(9_700f, discontinuityClock.currentTimelineMs(1_000_000_000L, 1f), 0.001f)
    }

    @Test
    fun `六百毫秒准确迟样本不触发软同步`() {
        val clock = playingClock(positionMs = 10_000f)

        val result =
            clock.update(
                positionMs = 10_400f,
                sampleTimeNs = 400_000_000L,
                nowNs = 1_000_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.NONE, result.correction)
        assertEquals(0f, result.rawDriftMs, 0.001f)
        assertEquals(11_000f, result.timelineMs, 0.001f)
    }

    @Test
    fun `主线程积压的按序历史样本不制造伪回退`() {
        val clock = playingClock(positionMs = 10_000f)

        val first =
            clock.update(
                positionMs = 10_250f,
                sampleTimeNs = 250_000_000L,
                nowNs = 1_500_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        val second =
            clock.update(
                positionMs = 10_500f,
                sampleTimeNs = 500_000_000L,
                nowNs = 1_500_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.NONE, first.correction)
        assertEquals(DanmakuTimelineCorrection.NONE, second.correction)
        assertEquals(11_500f, clock.currentTimelineMs(1_500_000_000L, 1f), 0.001f)
    }

    @Test
    fun `恢复短窗不屏蔽正向大跳变`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(
            positionMs = 1_500f,
            sampleTimeNs = 500_000_000L,
            nowNs = 500_000_000L,
            phase = DanmakuTimelinePlaybackPhase.PAUSED,
            playbackSpeed = 1f,
        )
        clock.update(
            positionMs = 1_500f,
            sampleTimeNs = 1_500_000_000L,
            nowNs = 1_500_000_000L,
            phase = DanmakuTimelinePlaybackPhase.PLAYING,
            playbackSpeed = 1f,
        )

        val result =
            clock.update(
                positionMs = 5_000f,
                sampleTimeNs = 1_600_000_000L,
                nowNs = 1_600_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REBUILD, result.correction)
        assertEquals(5_000f, result.timelineMs, 0.001f)
        assertEquals(5_000f, clock.currentTimelineMs(1_600_000_000L, 1f), 0.001f)
    }

    @Test
    fun `常态大幅负漂移会重建到上报位置`() {
        val clock = playingClock(positionMs = 10_000f)

        val result =
            clock.update(
                positionMs = 9_300f,
                sampleTimeNs = 100_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REBUILD, result.correction)
        assertEquals(9_300f, result.timelineMs, 0.001f)
        assertEquals(9_300f, clock.currentTimelineMs(100_000_000L, 1f), 0.001f)
    }

    @Test
    fun `seek 后只在首个新播放样本处重建一次`() {
        val clock = playingClock(positionMs = 10_000f)

        clock.hintSeek(positionMs = 50_000f, nowNs = 1_000_000_000L)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)
        assertEquals(50_000f, clock.currentTimelineMs(2_000_000_000L, 1f), 0.001f)

        val seeking =
            clock.update(
                positionMs = 48_000f,
                sampleTimeNs = 1_050_000_000L,
                nowNs = 1_050_000_000L,
                phase = DanmakuTimelinePlaybackPhase.SEEKING,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, seeking.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        val paused =
            clock.update(
                positionMs = 50_000f,
                sampleTimeNs = 1_100_000_000L,
                nowNs = 1_100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, paused.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        val settled =
            clock.update(
                positionMs = 50_120f,
                sampleTimeNs = 1_200_000_000L,
                nowNs = 1_200_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.REBUILD, settled.correction)
        assertEquals(DanmakuTimelineState.PLAYING, clock.state)
        assertEquals(50_120f, settled.timelineMs, 0.001f)

        val following =
            clock.update(
                positionMs = 50_220f,
                sampleTimeNs = 1_300_000_000L,
                nowNs = 1_300_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertFalse(following.correction == DanmakuTimelineCorrection.REBUILD)
    }

    @Test
    fun `seek hold 内异步重建不得回放弹幕`() {
        val clock = playingClock(positionMs = 10_000f)
        clock.hintSeek(positionMs = 50_000f, nowNs = 1_000_000_000L, seekEpoch = 1L)

        assertFalse(clock.canReplayTimeline)

        val oldSample =
            clock.update(
                positionMs = 10_100f,
                sampleTimeNs = 1_100_000_000L,
                nowNs = 1_100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
                completedSeekEpoch = 0L,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, oldSample.correction)
        assertFalse(clock.canReplayTimeline)

        val authoritativeSample =
            clock.update(
                positionMs = 50_120f,
                sampleTimeNs = 1_200_000_000L,
                nowNs = 1_200_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
                activeSeekEpoch = 1L,
                completedSeekEpoch = 1L,
            )
        assertEquals(DanmakuTimelineCorrection.REBUILD, authoritativeSample.correction)
        assertTrue(clock.canReplayTimeline)
    }

    @Test
    fun `暂停与恢复在新鲜样本下保持零漂移`() {
        val clock = playingClock(positionMs = 1_000f)

        val paused =
            clock.update(
                positionMs = 1_500f,
                sampleTimeNs = 500_000_000L,
                nowNs = 500_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.REANCHOR, paused.correction)
        assertEquals(DanmakuTimelineState.PAUSED, clock.state)
        assertEquals(1_500f, clock.currentTimelineMs(2_000_000_000L, 1f), 0.001f)

        val resumed =
            clock.update(
                positionMs = 1_500f,
                sampleTimeNs = 2_000_000_000L,
                nowNs = 2_000_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.REANCHOR, resumed.correction)
        assertEquals(DanmakuTimelineState.RESUME_SETTLE, clock.state)
        assertEquals(0f, resumed.stabilizedDriftMs, 0.001f)

        val steady =
            clock.update(
                positionMs = 1_600f,
                sampleTimeNs = 2_100_000_000L,
                nowNs = 2_100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, steady.correction)
        assertEquals(0f, steady.stabilizedDriftMs, 0.001f)
    }

    @Test
    fun `暂停相位复用旧位置样本时保持可见时间线连续`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(
            positionMs = 1_100f,
            sampleTimeNs = 100_000_000L,
            nowNs = 100_000_000L,
            phase = DanmakuTimelinePlaybackPhase.PLAYING,
            playbackSpeed = 1f,
        )

        val paused =
            clock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 300_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REANCHOR, paused.correction)
        assertEquals(1_300f, paused.timelineMs, 0.001f)
        assertEquals(1_300f, clock.currentTimelineMs(2_000_000_000L, 1f), 0.001f)
    }

    @Test
    fun `恢复相位复用旧位置样本时从冻结位置继续`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(
            positionMs = 1_100f,
            sampleTimeNs = 100_000_000L,
            nowNs = 300_000_000L,
            phase = DanmakuTimelinePlaybackPhase.PAUSED,
            playbackSpeed = 1f,
        )
        val frozenPositionMs = clock.currentTimelineMs(2_000_000_000L, 1f)

        val resumed =
            clock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 2_000_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REANCHOR, resumed.correction)
        assertEquals(frozenPositionMs, resumed.timelineMs, 0.001f)
        assertEquals(frozenPositionMs + 100f, clock.currentTimelineMs(2_100_000_000L, 1f), 0.001f)
    }

    @Test
    fun `复用暂停样本时间戳的播放事件立即进入恢复态`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(
            positionMs = 1_100f,
            sampleTimeNs = 100_000_000L,
            nowNs = 100_000_000L,
            phase = DanmakuTimelinePlaybackPhase.PAUSED,
            playbackSpeed = 1f,
        )

        val resumed =
            clock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 200_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REANCHOR, resumed.correction)
        assertEquals(DanmakuTimelineState.RESUME_SETTLE, clock.state)
        assertFalse(resumed.metricsEligible)
    }

    @Test
    fun `恢复短窗内允许回退守卫但常态播放不钳制`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(1_500f, 500_000_000L, 500_000_000L, DanmakuTimelinePlaybackPhase.PAUSED, 1f)
        clock.update(1_500f, 2_000_000_000L, 2_000_000_000L, DanmakuTimelinePlaybackPhase.PLAYING, 1f)

        val guarded =
            clock.update(
                positionMs = 1_300f,
                sampleTimeNs = 2_100_000_000L,
                nowNs = 2_100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertEquals(0f, guarded.stabilizedDriftMs, 0.001f)
        assertEquals(DanmakuTimelineCorrection.NONE, guarded.correction)

        val normal =
            clock.update(
                positionMs = 3_000f,
                sampleTimeNs = 3_600_000_000L,
                nowNs = 3_600_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )
        assertEquals(DanmakuTimelineState.PLAYING, clock.state)
        assertEquals(DanmakuTimelineCorrection.SOFT_SYNC, normal.correction)
        assertTrue(normal.stabilizedDriftMs < 0f)
    }

    @Test
    fun `乱序迟到样本不会破坏时间轴`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(1_100f, 100_000_000L, 100_000_000L, DanmakuTimelinePlaybackPhase.PLAYING, 1f)

        val late =
            clock.update(
                positionMs = 500f,
                sampleTimeNs = 50_000_000L,
                nowNs = 150_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertFalse(late.accepted)
        assertFalse(late.isNewPositionSample)
        assertFalse(late.metricsEligible)
        assertEquals(DanmakuTimelineCorrection.NONE, late.correction)
        assertEquals(1_150f, clock.currentTimelineMs(150_000_000L, 1f), 0.001f)
    }

    @Test
    fun `重复时间戳状态更新不重复校时也不进入指标`() {
        val clock = playingClock(positionMs = 1_000f)
        val first =
            clock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        val duplicate =
            clock.update(
                positionMs = 5_000f,
                sampleTimeNs = 100_000_000L,
                nowNs = 150_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
            )

        assertTrue(first.isNewPositionSample)
        assertTrue(first.metricsEligible)
        assertFalse(duplicate.isNewPositionSample)
        assertFalse(duplicate.metricsEligible)
        assertEquals(DanmakuTimelineCorrection.NONE, duplicate.correction)
        assertEquals(1_150f, clock.currentTimelineMs(150_000_000L, 1f), 0.001f)
    }

    @Test
    fun `暂停和 seek 的新样本不稀释播放校时指标`() {
        val pausedClock = playingClock(positionMs = 1_000f)
        val paused =
            pausedClock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )
        assertTrue(paused.isNewPositionSample)
        assertFalse(paused.metricsEligible)

        val seekingClock = playingClock(positionMs = 1_000f)
        val seeking =
            seekingClock.update(
                positionMs = 2_000f,
                sampleTimeNs = 100_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.SEEKING,
                playbackSpeed = 1f,
                activeSeekEpoch = 1L,
            )
        assertTrue(seeking.isNewPositionSample)
        assertFalse(seeking.metricsEligible)
    }

    @Test
    fun `暂停重锚计入纠偏事件但不增加漂移样本`() {
        val clock = playingClock(positionMs = 1_000f)
        val paused =
            clock.update(
                positionMs = 1_100f,
                sampleTimeNs = 100_000_000L,
                nowNs = 100_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )
        val accumulator = DanmakuPlaybackSyncStatsAccumulator()

        accumulator.record(
            metricsEligible = paused.metricsEligible,
            correction = paused.correction,
        )

        assertEquals(1, accumulator.reanchorEventCount)
        assertEquals(0, accumulator.driftSampleCount)
        assertEquals(0, accumulator.rebuildEventCount)
        assertEquals(0, accumulator.softSyncEventCount)
    }

    @Test
    fun `乱序迟到的暂停样本不会冻结时间轴`() {
        val clock = playingClock(positionMs = 1_000f)
        clock.update(1_100f, 100_000_000L, 100_000_000L, DanmakuTimelinePlaybackPhase.PLAYING, 1f)

        val latePause =
            clock.update(
                positionMs = 500f,
                sampleTimeNs = 50_000_000L,
                nowNs = 150_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PAUSED,
                playbackSpeed = 1f,
            )

        assertFalse(latePause.accepted)
        assertEquals(DanmakuTimelineState.PLAYING, clock.state)
        assertEquals(1_150f, clock.currentTimelineMs(150_000_000L, 1f), 0.001f)
    }

    private fun playingClock(positionMs: Float): DanmakuTimelineClock {
        return DanmakuTimelineClock().apply {
            reset(
                positionMs = positionMs,
                nowNs = 0L,
                paused = false,
            )
        }
    }
}
