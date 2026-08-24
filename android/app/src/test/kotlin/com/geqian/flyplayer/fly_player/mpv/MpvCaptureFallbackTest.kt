package com.geqian.flyplayer.fly_player.mpv

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MpvCaptureFallbackTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun missingMpvImageFallsBackToAndroidSurfaceCapture() {
        val target = File(temporaryFolder.root, "frame.jpg")
        var fallbackCalls = 0

        val captured = captureFrameToFile(
            targetFile = target,
            captureWithMpv = { true },
            captureWithAndroid = {
                fallbackCalls += 1
                target.writeBytes(byteArrayOf(1, 2, 3))
                true
            },
        )

        assertTrue(captured)
        assertEquals(1, fallbackCalls)
        assertTrue(target.length() > 0L)
    }

    @Test
    fun readyMpvImageDoesNotRunAndroidFallback() {
        val target = File(temporaryFolder.root, "frame.jpg")
        var fallbackCalls = 0

        val captured = captureFrameToFile(
            targetFile = target,
            captureWithMpv = {
                target.writeBytes(byteArrayOf(1, 2, 3))
                true
            },
            captureWithAndroid = {
                fallbackCalls += 1
                false
            },
        )

        assertTrue(captured)
        assertEquals(0, fallbackCalls)
    }
}
