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
    fun displayModeGivesFloatWhenEnabledOutsidePip() {
        // 悬浮小窗设置开启即给 FLOAT（方案 3.6）：权限/SDK 短板不在入口让位，
        // 否则未授权用户永远拿到系统 PiP、内联引导不可达；短板由点击三态接管。
        // 前置：平行窗口设置关闭——用户明确的小窗与分屏二选一，分屏优先。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = true,
            ) == DisplayModeEntry.FLOAT,
        )
    }

    @Test
    fun floatEntryRequiresUserSettingAndYieldsInPip() {
        // 设置未开启：即便能力就绪也维持 PiP（opt-in 语义）。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = false,
            ) == DisplayModeEntry.PIP,
        )
        // 系统小窗态不让入口切悬浮（避免 PiP 内嵌套悬浮入口），维持 PiP。
        assertTrue(
            entry(
                parallelWindowEnabled = false,
                floatingMiniPlayerEnabled = true,
                inPipMode = true,
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
            ) == DisplayModeEntry.SPLIT,
        )
        // 分屏中保留退出出口，悬浮窗设置不劫持。
        assertTrue(
            entry(
                currentlySplit = true,
                floatingMiniPlayerEnabled = true,
            ) == DisplayModeEntry.FULLSCREEN,
        )
    }

    private fun entry(
        parallelWindowEnabled: Boolean = true,
        currentlySplit: Boolean = false,
        splitSupported: Boolean = true,
        pipSupported: Boolean = true,
        floatingMiniPlayerEnabled: Boolean = false,
        inPipMode: Boolean = false,
    ): DisplayModeEntry = NativeSplitGate.displayModeEntry(
        parallelWindowEnabled = parallelWindowEnabled,
        currentlySplit = currentlySplit,
        splitSupported = splitSupported,
        pipSupported = pipSupported,
        floatingMiniPlayerEnabled = floatingMiniPlayerEnabled,
        inPipMode = inPipMode,
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
