package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Test

class DanmakuSeekCompletionChainTest {
    @Test
    fun `目标附近样本不能早于显式 seek 完成退出等待`() {
        val coordinator = MpvPlaybackRestoreCoordinator()
        coordinator.onLoadRequested(startPositionMs = 0L, hasPendingExternalSubtitle = false)
        coordinator.onSourceFileLoaded()
        coordinator.onSeekQueued(positionMs = 50_000L)
        coordinator.onSeekingChanged(isSeeking = true)
        val clock =
            DanmakuTimelineClock().apply {
                reset(positionMs = 10_000f, nowNs = 0L, paused = false)
                hintSeek(positionMs = 50_000f, nowNs = 1_000_000_000L)
            }

        coordinator.onTimePosition(positionMs = 49_900L)
        val nearTarget =
            clock.update(
                positionMs = 49_900f,
                sampleTimeNs = 1_100_000_000L,
                nowNs = 1_100_000_000L,
                phase = coordinator.timelinePhase(),
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.NONE, nearTarget.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        coordinator.onSeekingChanged(isSeeking = false)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        coordinator.onTimePosition(positionMs = 50_120L)
        val firstSampleAfterCompletion =
            clock.update(
                positionMs = 50_120f,
                sampleTimeNs = 1_200_000_000L,
                nowNs = 1_200_000_000L,
                phase = coordinator.timelinePhase(),
                playbackSpeed = 1f,
            )

        assertEquals(DanmakuTimelineCorrection.REBUILD, firstSampleAfterCompletion.correction)
        assertEquals(DanmakuTimelineState.PLAYING, clock.state)
    }

    @Test
    fun `异步旧样本与旧 seek false 都不能完成较新的 seek epoch`() {
        val coordinator = MpvPlaybackRestoreCoordinator()
        coordinator.onLoadRequested(startPositionMs = 0L, hasPendingExternalSubtitle = false)
        coordinator.onSourceFileLoaded()
        val clock =
            DanmakuTimelineClock().apply {
                reset(positionMs = 10_000f, nowNs = 0L, paused = false)
            }

        // UI 线程先拿到 epoch 并同步进入 hold，播放线程尚未处理 seek 命令。
        clock.hintSeek(positionMs = 50_000f, nowNs = 1_000_000_000L, seekEpoch = 1L)
        val oldPlayingSample =
            clock.update(
                positionMs = 10_100f,
                sampleTimeNs = 1_050_000_000L,
                nowNs = 1_050_000_000L,
                phase = DanmakuTimelinePlaybackPhase.PLAYING,
                playbackSpeed = 1f,
                activeSeekEpoch = coordinator.activeSeekEpoch,
                completedSeekEpoch = coordinator.completedSeekEpoch,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, oldPlayingSample.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        coordinator.onSeekQueued(positionMs = 50_000L, seekEpoch = 1L)

        // 连续 seek 创建新 epoch；随后到达的 false 属于旧 epoch，必须忽略。
        clock.hintSeek(positionMs = 80_000f, nowNs = 1_100_000_000L, seekEpoch = 2L)
        coordinator.onSeekQueued(positionMs = 80_000L, seekEpoch = 2L)
        coordinator.onSeekingChanged(isSeeking = false)
        assertEquals(0L, coordinator.completedSeekEpoch)

        val oldEpochSample =
            clock.update(
                positionMs = 50_100f,
                sampleTimeNs = 1_150_000_000L,
                nowNs = 1_150_000_000L,
                phase = coordinator.timelinePhase(),
                playbackSpeed = 1f,
                activeSeekEpoch = coordinator.activeSeekEpoch,
                completedSeekEpoch = coordinator.completedSeekEpoch,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, oldEpochSample.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        coordinator.onSeekingChanged(isSeeking = true)
        coordinator.onSeekingChanged(isSeeking = false)
        coordinator.onTimePosition(positionMs = 80_120L)
        val staleTimestampAfterCompletion =
            clock.update(
                positionMs = 80_100f,
                sampleTimeNs = 1_100_000_000L,
                nowNs = 1_180_000_000L,
                phase = coordinator.timelinePhase(),
                playbackSpeed = 1f,
                activeSeekEpoch = coordinator.activeSeekEpoch,
                completedSeekEpoch = coordinator.completedSeekEpoch,
            )
        assertEquals(DanmakuTimelineCorrection.NONE, staleTimestampAfterCompletion.correction)
        assertEquals(DanmakuTimelineState.SEEK_HOLD, clock.state)

        coordinator.onTimePosition(positionMs = 80_120L)
        val firstNewEpochSample =
            clock.update(
                positionMs = 80_120f,
                sampleTimeNs = 1_200_000_000L,
                nowNs = 1_200_000_000L,
                phase = coordinator.timelinePhase(),
                playbackSpeed = 1f,
                activeSeekEpoch = coordinator.activeSeekEpoch,
                completedSeekEpoch = coordinator.completedSeekEpoch,
            )

        assertEquals(DanmakuTimelineCorrection.REBUILD, firstNewEpochSample.correction)
        assertEquals(DanmakuTimelineState.PLAYING, clock.state)
        assertEquals(2L, coordinator.completedSeekEpoch)
    }

    @Test
    fun `属性已为 true 时连续多次 seek 不要求第二个 true 边沿`() {
        val coordinator = MpvPlaybackRestoreCoordinator()
        coordinator.onLoadRequested(startPositionMs = 0L, hasPendingExternalSubtitle = false)
        coordinator.onSourceFileLoaded()

        coordinator.onSeekQueued(positionMs = 50_000L, seekEpoch = 1L)
        coordinator.onSeekingChanged(isSeeking = true)
        coordinator.onSeekQueued(positionMs = 60_000L, seekEpoch = 2L)
        coordinator.onSeekQueued(positionMs = 70_000L, seekEpoch = 3L)

        // mpv 的 seeking 属性一直为 true，不会为后续命令重复发送 true。
        coordinator.onSeekingChanged(isSeeking = false)

        assertEquals(3L, coordinator.completedSeekEpoch)
        coordinator.onTimePosition(positionMs = 70_120L)
        assertEquals(false, coordinator.isSeekingOrRestoringVideo)
    }

    private fun MpvPlaybackRestoreCoordinator.timelinePhase(): DanmakuTimelinePlaybackPhase {
        return if (isSeekingOrRestoringVideo) {
            DanmakuTimelinePlaybackPhase.SEEKING
        } else {
            DanmakuTimelinePlaybackPhase.PLAYING
        }
    }
}
