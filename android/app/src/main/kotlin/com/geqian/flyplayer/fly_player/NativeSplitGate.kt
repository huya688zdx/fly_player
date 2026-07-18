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
}
