package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DanmakuMaskTimestampPolicyTest {
    @Test
    fun `absent timestamp keeps the live capture fallback`() {
        assertEquals(DanmakuMaskTimestampAction.LEGACY, route(null))
        assertEquals(DanmakuMaskTimestampAction.LEGACY, route(null, hasMask = false))
    }

    @Test
    fun `zero is a timed mask`() {
        assertEquals(DanmakuMaskTimestampAction.BUFFER_MASK, route(0L))
    }

    @Test
    fun `positive timestamps keep the timed path`() {
        assertEquals(DanmakuMaskTimestampAction.BUFFER_MASK, route(200L))
    }

    @Test
    fun `empty zero inserts an empty sample instead of the latest bitmap`() {
        assertEquals(DanmakuMaskTimestampAction.BUFFER_EMPTY, route(0L, empty = true, hasMask = false))
        val samples = listOf(DanmakuMaskTimelineSample(0L, empty = true))
        val selected = DanmakuMaskTimelinePolicy.selectBracket(samples, 0L, 360L)!!
        assertTrue(samples[selected.floorIndex].empty)
    }

    @Test
    fun `explicit empty wins even when an obsolete bitmap accompanies it`() {
        assertEquals(DanmakuMaskTimestampAction.BUFFER_EMPTY, route(0L, empty = true))
        assertEquals(DanmakuMaskTimestampAction.BUFFER_EMPTY, route(200L, empty = true))
    }

    @Test
    fun `seek hold rejects late timed zero positive and empty callbacks`() {
        for (pts in listOf(0L, 200L)) {
            assertEquals(DanmakuMaskTimestampAction.IGNORE, route(pts, hold = true))
            assertEquals(DanmakuMaskTimestampAction.IGNORE, route(pts, empty = true, hold = true))
        }
    }

    @Test
    fun `seek hold does not turn absent timestamps into timed callbacks`() {
        assertEquals(DanmakuMaskTimestampAction.LEGACY, route(null, hold = true))
    }

    @Test
    fun `negative timestamps are invalid and never become live masks`() {
        assertEquals(DanmakuMaskTimestampAction.IGNORE, route(-1L))
        assertEquals(DanmakuMaskTimestampAction.IGNORE, route(Long.MIN_VALUE, empty = true))
    }

    @Test
    fun `known timestamp without a bitmap or explicit empty never falls back`() {
        assertEquals(DanmakuMaskTimestampAction.IGNORE, route(0L, hasMask = false))
        assertEquals(DanmakuMaskTimestampAction.IGNORE, route(200L, hasMask = false))
    }

    @Test
    fun `zero sample still expires and cannot be selected before its time`() {
        val samples = listOf(DanmakuMaskTimelineSample(0L, empty = false))
        assertNull(DanmakuMaskTimelinePolicy.selectBracket(samples, -1L, 360L))
        assertEquals(0, DanmakuMaskTimelinePolicy.selectBracket(samples, 360L, 360L)?.floorIndex)
        assertNull(DanmakuMaskTimelinePolicy.selectBracket(samples, 361L, 360L))
    }

    @Test
    fun `untimed file cache exits timed mode without a runtime bitmap`() {
        val fileCache = DanmakuDynamicOcclusionState.disabled().copy(
            enabled = true,
            available = true,
            occlusionMode = "mask",
            maskPath = "/cache/mask.png",
        )
        val action = route(fileCache.maskPtsMs, hasMask = false)
        assertEquals(DanmakuMaskTimestampAction.LEGACY, action)
        assertFalse(DanmakuMaskTimestampPolicy.nextPtsMode(true, action))
    }

    @Test
    fun `timed replay preserves the whole sample while updating control state`() {
        for (pts in listOf(0L, 200L)) {
            val sample = DanmakuDynamicOcclusionState.disabled().copy(
                enabled = true,
                available = true,
                backend = "paddle",
                occlusionMode = "mask",
                updatedAtMs = 1234L,
                maskWidth = 512,
                maskHeight = 512,
                maskPtsMs = pts,
                maskVelocityX = 0.001,
                maskVelocityY = -0.002,
                effectiveSampleIntervalMs = 280L,
                effectiveInputWidth = 512,
                maskSceneCut = true,
                videoAspect = 16.0 / 9.0,
            )
            val replay = DanmakuDynamicOcclusionState.disabled().copy(
                enabled = false,
                backend = "cpu",
                degradationLevel = "interval",
                effectiveSampleIntervalMs = 800L,
                effectiveInputWidth = 256,
            )
            assertEquals(
                sample.copy(enabled = false, backend = "cpu", degradationLevel = "interval"),
                DanmakuMaskTimestampPolicy.preserveTimedSample(sample, replay),
            )
        }
    }

    @Test
    fun `untimed replay keeps the freshly constructed legacy state`() {
        val previous = DanmakuDynamicOcclusionState.disabled().copy(
            effectiveSampleIntervalMs = 280L,
            effectiveInputWidth = 512,
        )
        val replay = previous.copy(effectiveSampleIntervalMs = 800L, effectiveInputWidth = 256)
        assertEquals(replay, DanmakuMaskTimestampPolicy.preserveTimedSample(previous, replay))
    }

    private fun route(
        pts: Long?,
        empty: Boolean = false,
        hasMask: Boolean = true,
        hold: Boolean = false,
    ) = DanmakuMaskTimestampPolicy.route(pts, empty, hasMask, hold)
}
