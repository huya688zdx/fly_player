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

    /** 播放器底栏显示模式入口：分屏与画中画（小窗）二选一，横竖屏为无小窗能力时的兜底。 */
    fun displayModeEntry(
        parallelWindowEnabled: Boolean,
        currentlySplit: Boolean,
        splitSupported: Boolean,
        pipSupported: Boolean,
    ): DisplayModeEntry {
        // 已嵌入分屏时保留退出出口，不受设置回退影响。
        if (currentlySplit) return DisplayModeEntry.FULLSCREEN
        // 平行窗口设置关闭即视为放弃分屏能力，入口让位给小窗。
        if (parallelWindowEnabled && splitSupported) return DisplayModeEntry.SPLIT
        if (pipSupported) return DisplayModeEntry.PIP
        return DisplayModeEntry.ROTATE
    }
}

enum class DisplayModeEntry { SPLIT, FULLSCREEN, PIP, ROTATE }
