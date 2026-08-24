package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackReloadPositionTest {
    @Test
    fun listenModeReloadUsesCurrentProgressInsteadOfLaunchProgress() {
        assertEquals(
            612_000L,
            resolveInternalReloadStartPositionMs(
                reliableSeek = true,
                currentPositionMs = 612_000L,
                sourceStartPositionMs = 15_000L,
            ),
        )
    }

    @Test
    fun reloadFallsBackToLaunchProgressBeforeFirstPositionSample() {
        assertEquals(
            15_000L,
            resolveInternalReloadStartPositionMs(
                reliableSeek = true,
                currentPositionMs = 0L,
                sourceStartPositionMs = 15_000L,
            ),
        )
    }

    @Test
    fun unreliableSourceStillReloadsFromStart() {
        assertEquals(
            0L,
            resolveInternalReloadStartPositionMs(
                reliableSeek = false,
                currentPositionMs = 612_000L,
                sourceStartPositionMs = 15_000L,
            ),
        )
    }
}
