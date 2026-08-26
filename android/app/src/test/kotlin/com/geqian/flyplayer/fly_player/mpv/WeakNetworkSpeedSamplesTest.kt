package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Test

class WeakNetworkSpeedSamplesTest {
    @Test
    fun prefersSaneStringCacheSpeedOverImplausibleIntValue() {
        val sample =
            resolveMpvCacheSpeedSampleBytesPerSecond(
                rawIntBytesPerSecond = 519_530_930_176L,
                rawStringBytesPerSecond = "495462",
            )

        assertEquals(495_462L, sample)
    }

    @Test
    fun fallsBackToIntCacheSpeedWhenStringValueMissing() {
        val sample =
            resolveMpvCacheSpeedSampleBytesPerSecond(
                rawIntBytesPerSecond = 786_432L,
                rawStringBytesPerSecond = null,
            )

        assertEquals(786_432L, sample)
    }

    @Test
    fun supportsDecimalCacheSpeedStrings() {
        val sample =
            resolveMpvCacheSpeedSampleBytesPerSecond(
                rawIntBytesPerSecond = null,
                rawStringBytesPerSecond = "1572864.0",
            )

        assertEquals(1_572_864L, sample)
    }

    @Test
    fun clearsImplausibleSpeedSamples() {
        assertEquals(0L, sanitizeWeakNetworkSpeedSampleBytesPerSecond(300L * 1024L * 1024L))
    }
}
