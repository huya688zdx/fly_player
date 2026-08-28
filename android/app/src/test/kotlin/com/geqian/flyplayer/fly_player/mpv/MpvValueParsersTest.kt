package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MpvValueParsersTest {
    @Test
    fun audioChannelCountRejectsJniGarbageValues() {
        assertEquals(
            2L,
            sanitizeMpvIntProperty("audio-out-params/channel-count", 2L),
        )
        assertNull(
            sanitizeMpvIntProperty("audio-out-params/channel-count", 1_401_423_373L),
        )
    }
}
