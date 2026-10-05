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
        // 设置关闭即让位给小窗，即使设备仍支持分屏。
        assertTrue(
            entry(parallelWindowEnabled = false, splitSupported = true) == DisplayModeEntry.PIP,
        )
        assertTrue(
            entry(parallelWindowEnabled = true, splitSupported = false) == DisplayModeEntry.PIP,
        )
    }

    @Test
    fun displayModeKeepsExitEntryWhileEmbedded() {
        assertTrue(
            entry(currentlySplit = true, parallelWindowEnabled = false) == DisplayModeEntry.FULLSCREEN,
        )
    }

    @Test
    fun displayModeFallsBackToRotateWithoutPip() {
        assertTrue(
            entry(splitSupported = false, pipSupported = false) == DisplayModeEntry.ROTATE,
        )
        assertTrue(
            entry(currentlySplit = true, pipSupported = false) == DisplayModeEntry.FULLSCREEN,
        )
    }

    @Test
    fun displayModeGivesFloatWhenEnabledAndReady() {
        // 悬浮小窗设置开启且能力就绪（权限+SDK26+ 且不在 PiP）→ 入口给 FLOAT（方案 3.6）。
        // 前置：平行窗口设置关闭——用户明确的小窗与分屏二选一，分屏优先。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = true,
                floatingWindowReady = true,
            ) == DisplayModeEntry.FLOAT,
        )
    }

    @Test
    fun floatEntryRequiresUserSettingAndReadiness() {
        // 设置未开启：即便能力就绪也维持 PiP（opt-in 语义）。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = false,
                floatingWindowReady = true,
            ) == DisplayModeEntry.PIP,
        )
        // 设置开启但能力未就绪（未授权/低版本/在 PiP 中）：让位 PiP。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = true,
                floatingWindowReady = false,
            ) == DisplayModeEntry.PIP,
        )
    }

    @Test
    fun floatYieldsToSplitAndFullscreenExit() {
        // 用户明确的二选一：平行窗口开启且支持分屏时入口让位分屏（方案 3.6）。
        assertTrue(
            entry(
                parallelWindowEnabled = true,
                splitSupported = true,
                floatingMiniPlayerEnabled = true,
                floatingWindowReady = true,
            ) == DisplayModeEntry.SPLIT,
        )
        // 分屏中保留退出出口，悬浮窗设置不劫持。
        assertTrue(
            entry(
                currentlySplit = true,
                floatingMiniPlayerEnabled = true,
                floatingWindowReady = true,
            ) == DisplayModeEntry.FULLSCREEN,
        )
    }

    private fun entry(
        parallelWindowEnabled: Boolean = true,
        currentlySplit: Boolean = false,
        splitSupported: Boolean = true,
        pipSupported: Boolean = true,
        floatingMiniPlayerEnabled: Boolean = false,
        floatingWindowReady: Boolean = false,
    ): DisplayModeEntry = NativeSplitGate.displayModeEntry(
        parallelWindowEnabled = parallelWindowEnabled,
        currentlySplit = currentlySplit,
        splitSupported = splitSupported,
        pipSupported = pipSupported,
        floatingMiniPlayerEnabled = floatingMiniPlayerEnabled,
        floatingWindowReady = floatingWindowReady,
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
