package com.geqian.flyplayer.fly_player

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 悬浮小窗设置键（floating_mini_player_enabled）的内存语义：JVM 下无法触达
 * SharedPreferences（persistSettings 的落盘半边归真机/门禁），这里锁定
 * 「默认关 opt-in + setter 可翻转 + settingsMap 始终回传该键」三条契约——
 * 这正是 NativeSplitGate FLOAT 分支与悬浮窗入口三态的数据来源（悬浮小窗方案 3.6）。
 */
class ParallelWindowCoordinatorSettingsTest {

    @After
    fun resetSetting() {
        // coordinator 是进程级单例，恢复默认避免用例间串扰。
        ParallelWindowCoordinator.setFloatingMiniPlayerEnabled(false)
    }

    @Test
    fun `floating mini player setting defaults to off`() {
        // 默认关：未显式开启时入口不得给 FLOAT（避免授权用户行为静默漂移）。
        assertFalse(ParallelWindowCoordinator.floatingMiniPlayerEnabled())
        assertFalse(ParallelWindowCoordinator.settingsMap()["floatingMiniPlayerEnabled"] == true)
    }

    @Test
    fun `setting flips in memory and round-trips through settings map`() {
        ParallelWindowCoordinator.setFloatingMiniPlayerEnabled(true)
        assertTrue(ParallelWindowCoordinator.floatingMiniPlayerEnabled())
        assertEquals(
            true,
            ParallelWindowCoordinator.settingsMap()["floatingMiniPlayerEnabled"],
        )
        // get/update 通道共用同一份快照：Flutter 设置页写入后回读一致。
        assertTrue(
            ParallelWindowCoordinator.settingsMap().containsKey("floatingMiniPlayerEnabled"),
        )
    }

    @Test
    fun `setting can be turned back off`() {
        ParallelWindowCoordinator.setFloatingMiniPlayerEnabled(true)
        ParallelWindowCoordinator.setFloatingMiniPlayerEnabled(false)
        assertFalse(ParallelWindowCoordinator.floatingMiniPlayerEnabled())
        assertEquals(
            false,
            ParallelWindowCoordinator.settingsMap()["floatingMiniPlayerEnabled"],
        )
    }
}
