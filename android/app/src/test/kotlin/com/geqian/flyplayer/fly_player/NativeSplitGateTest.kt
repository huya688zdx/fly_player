package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeSplitGateTest {
    @Test
    fun sdk31IsRejected() {
        assertFalse(allowed(sdkInt = 31))
    }

    @Test
    fun embeddedActivityBypassesEntryWindowChecks() {
        assertTrue(
            allowed(
                alreadyEmbedded = true,
                inMultiWindow = true,
                windowWidthDp = 400f,
                windowHeightDp = 300f,
                windowIsFullDisplay = false,
                splitAvailable = false,
            ),
        )
    }

    @Test
    fun multiWindowModeIsRejected() {
        assertFalse(allowed(inMultiWindow = true))
    }

    @Test
    fun nonFullDisplayWindowIsRejected() {
        assertFalse(allowed(windowIsFullDisplay = false))
    }

    @Test
    fun qualifyingFullscreenLandscapeIsAllowed() {
        assertTrue(allowed(windowWidthDp = 1440f, windowHeightDp = 900f))
    }

    @Test
    fun windowNarrowerThanMinimumWidthIsRejected() {
        assertFalse(allowed(windowWidthDp = 800f, windowHeightDp = 1280f))
    }

    @Test
    fun windowWithShortSideBelowMinimumIsRejected() {
        assertFalse(allowed(windowWidthDp = 1000f, windowHeightDp = 560f))
    }

    @Test
    fun unavailableActivityEmbeddingIsRejected() {
        assertFalse(allowed(splitAvailable = false))
    }

    private fun allowed(
        sdkInt: Int = 32,
        alreadyEmbedded: Boolean = false,
        inMultiWindow: Boolean = false,
        windowWidthDp: Float = 1440f,
        windowHeightDp: Float = 900f,
        windowIsFullDisplay: Boolean = true,
        splitAvailable: Boolean = true,
    ): Boolean = NativeSplitGate.splitEntryAllowed(
        sdkInt = sdkInt,
        alreadyEmbedded = alreadyEmbedded,
        inMultiWindow = inMultiWindow,
        windowWidthDp = windowWidthDp,
        windowHeightDp = windowHeightDp,
        windowIsFullDisplay = windowIsFullDisplay,
        splitAvailable = splitAvailable,
    )
}
