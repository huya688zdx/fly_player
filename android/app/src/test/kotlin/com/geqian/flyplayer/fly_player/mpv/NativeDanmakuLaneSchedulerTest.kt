package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeDanmakuLaneSchedulerTest {
    @Test
    fun returnsReleasedLaneOnly() {
        val lanes = floatArrayOf(1600f, 900f, 1200f)

        assertEquals(1, NativeDanmakuLaneScheduler.findReleasedLane(lanes, 1000f))
    }

    @Test
    fun blocksWhenAllLanesAreStillOccupied() {
        val lanes = floatArrayOf(1600f, 1800f, 2200f)

        assertNull(NativeDanmakuLaneScheduler.findReleasedLane(lanes, 1000f))
    }

    @Test
    fun emptyLaneSetHasNoCandidate() {
        assertNull(NativeDanmakuLaneScheduler.findReleasedLane(FloatArray(0), 1000f))
    }
}
