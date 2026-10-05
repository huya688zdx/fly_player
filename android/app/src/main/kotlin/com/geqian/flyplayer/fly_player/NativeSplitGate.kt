package com.geqian.flyplayer.fly_player

/**
 * 原生播放器分屏入口的纯判定，与 [ActivityEmbeddingInstaller] 的窗口阈值保持同源。
 * 所有运行时状态均由 Activity 采集后传入，便于 JVM 单元测试。
 */
object NativeSplitGate {
    fun splitEntryAllowed(
        sdkInt: Int,
        alreadyEmbedded: Boolean,
        inMultiWindow: Boolean,
        windowWidthDp: Float,
        windowHeightDp: Float,
        windowIsFullDisplay: Boolean,
        splitAvailable: Boolean,
    ): Boolean {
        if (sdkInt < 32) return false
        // 已嵌入时窗格宽度会低于入口阈值，且系统可能报告多窗口；不能反向否决现有分屏。
        if (alreadyEmbedded) return true
        if (inMultiWindow || !windowIsFullDisplay) return false
        if (windowWidthDp < ActivityEmbeddingInstaller.MIN_WIDTH_DP) return false
        if (minOf(windowWidthDp, windowHeightDp) < ActivityEmbeddingInstaller.MIN_SMALLEST_WIDTH_DP) {
            return false
        }
        return splitAvailable
    }

    /**
     * 播放器底栏显示模式入口：分屏与悬浮小窗/画中画让位序，横竖屏为无小窗能力时的兜底。
     * 让位序（悬浮小窗方案 3.6）：分屏（用户明确的二选一）→ 悬浮窗 → PiP → 横竖屏；
     * [floatingMiniPlayerEnabled] 为用户设置键（floating_mini_player_enabled，
     * parallel_window_settings 同模式），[floatingWindowReady] = 悬浮窗能力
     * （overlayPermissionGranted && SDK≥26 && !inPipMode，由调用方合成）。
     */
    fun displayModeEntry(
        parallelWindowEnabled: Boolean,
        currentlySplit: Boolean,
        splitSupported: Boolean,
        pipSupported: Boolean,
        floatingMiniPlayerEnabled: Boolean = false,
        floatingWindowReady: Boolean = false,
    ): DisplayModeEntry {
        // 已嵌入分屏时保留退出出口，不受设置回退影响。
        if (currentlySplit) return DisplayModeEntry.FULLSCREEN
        // 平行窗口设置关闭即视为放弃分屏能力，入口让位给小窗。
        if (parallelWindowEnabled && splitSupported) return DisplayModeEntry.SPLIT
        // 悬浮小窗：设置开启且能力就绪才进入口（未授权由入口三态转内联引导）。
        if (floatingMiniPlayerEnabled && floatingWindowReady) return DisplayModeEntry.FLOAT
        if (pipSupported) return DisplayModeEntry.PIP
        return DisplayModeEntry.ROTATE
    }
}

enum class DisplayModeEntry { SPLIT, FULLSCREEN, PIP, FLOAT, ROTATE }
