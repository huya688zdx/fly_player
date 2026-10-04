package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 渲染组交接闸门（悬浮小窗方案 3.3 必要改造 A/B 的状态核）：
 *  - 交接窗口内 mpv 侧 destroy 走 detach-only 旁路（不 pause 不 vid=no）——判定位即 gate.active；
 *  - TextureView 侧 onSurfaceTextureDestroyed 返回 false 自持 SurfaceTexture（改造 B），
 *    裁决由 [textureHandoffShouldKeepTexture] 给出，降级开关关闭时只做改造 A。
 * 时钟注入桩，测试不触 android.os.SystemClock。
 */
class SurfaceHandoffGateTest {

    @Test
    fun `begin arms the gate once and freezes the start timestamp`() {
        var now = 100L
        val gate = SurfaceHandoffGate(nowMs = { now })
        assertTrue(gate.begin())
        assertTrue(gate.active)
        assertEquals(100L, gate.handoffStartUptimeMs)
        now = 200L
        // 幂等：重复 begin 不翻转、不刷新起始时间戳（P3 耗时样本不受重入影响）。
        assertFalse(gate.begin())
        assertTrue(gate.active)
        assertEquals(100L, gate.handoffStartUptimeMs)
    }

    @Test
    fun `end closes the gate and records the P3 handoff elapsed`() {
        var now = 1_000L
        val gate = SurfaceHandoffGate(nowMs = { now })
        assertTrue(gate.begin())
        now = 1_247L
        assertTrue(gate.end())
        assertFalse(gate.active)
        // P3 观测样本（方案 5.1：detach handoff → 新窗口 surface 重挂，预算 <200ms）。
        assertEquals(247L, gate.lastHandoffElapsedMs)
        assertEquals(0L, gate.handoffStartUptimeMs)
    }

    @Test
    fun `end without begin is a no-op and writes no sample`() {
        val gate = SurfaceHandoffGate(nowMs = { 5L })
        assertFalse(gate.end())
        assertFalse(gate.active)
        assertEquals(-1L, gate.lastHandoffElapsedMs)
    }

    @Test
    fun `gate re-arms for the reverse handoff and keeps the latest sample`() {
        // 进悬浮窗/展开回全屏各一次交接：闸门可重复武装，耗时取最近一次。
        var now = 0L
        val gate = SurfaceHandoffGate(nowMs = { now })
        gate.begin()
        now = 150L
        gate.end()
        gate.begin()
        now = 400L
        gate.end()
        assertEquals(250L, gate.lastHandoffElapsedMs)
    }

    @Test
    fun `destroy bypass policy keeps texture only under the gate`() {
        // 改造 B：闸门内 + 保活开启 → onSurfaceTextureDestroyed 返回 false 自持纹理。
        assertTrue(
            textureHandoffShouldKeepTexture(handoffActive = true, keepTextureEnabled = true),
        )
        // 降级路径（真机复用验证不过，保活关闭）：只做改造 A，纹理照常销毁，定格图兜底。
        assertFalse(
            textureHandoffShouldKeepTexture(handoffActive = true, keepTextureEnabled = false),
        )
        // 非交接窗口：常规 destroy 语义完全不变。
        assertFalse(
            textureHandoffShouldKeepTexture(handoffActive = false, keepTextureEnabled = true),
        )
        assertFalse(
            textureHandoffShouldKeepTexture(handoffActive = false, keepTextureEnabled = false),
        )
    }
}
