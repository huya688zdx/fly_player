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

    @Test
    fun displayModeGivesSplitOnlyWhenParallelWindowEnabledAndSupported() {
        assertTrue(
            entry(parallelWindowEnabled = true, splitSupported = true) == DisplayModeEntry.SPLIT,
        )
        // 设置关闭或设备不支持即退回横竖屏切换；小窗（画中画）入口固定在顶栏，不占用底栏。
        assertTrue(
            entry(parallelWindowEnabled = false, splitSupported = true) == DisplayModeEntry.ROTATE,
        )
        assertTrue(
            entry(parallelWindowEnabled = true, splitSupported = false) == DisplayModeEntry.ROTATE,
        )
    }

    @Test
    fun displayModeKeepsExitEntryWhileEmbedded() {
        assertTrue(
            entry(currentlySplit = true, parallelWindowEnabled = false) == DisplayModeEntry.FULLSCREEN,
        )
    }

    @Test
    fun displayModeFallsBackToRotateWhenSplitUnavailable() {
        assertTrue(entry(splitSupported = false) == DisplayModeEntry.ROTATE)
        assertTrue(entry(currentlySplit = true) == DisplayModeEntry.FULLSCREEN)
    }

    private fun entry(
        parallelWindowEnabled: Boolean = true,
        currentlySplit: Boolean = false,
        splitSupported: Boolean = true,
    ): DisplayModeEntry = NativeSplitGate.displayModeEntry(
        parallelWindowEnabled = parallelWindowEnabled,
        currentlySplit = currentlySplit,
        splitSupported = splitSupported,
    )

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
