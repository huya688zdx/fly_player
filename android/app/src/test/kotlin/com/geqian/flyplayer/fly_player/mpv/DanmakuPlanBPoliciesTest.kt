package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DanmakuPlanBPoliciesTest {
    @Test
    fun `空步成为 floor 时明确清除旧遮罩`() {
        val samples =
            listOf(
                DanmakuMaskTimelineSample(ptsMs = 1_000L, empty = false),
                DanmakuMaskTimelineSample(ptsMs = 1_280L, empty = true),
                DanmakuMaskTimelineSample(ptsMs = 1_560L, empty = false),
            )

        val atEmpty = DanmakuMaskTimelinePolicy.selectBracket(samples, 1_300L, staleMaxMs = 500L)
        assertEquals(1, atEmpty?.floorIndex)
        assertEquals(2, atEmpty?.nextIndex)
        val beforeEmpty = DanmakuMaskTimelinePolicy.selectBracket(samples, 1_200L, staleMaxMs = 500L)
        assertEquals(0, beforeEmpty?.floorIndex)
        assertEquals(1, beforeEmpty?.nextIndex)
    }

    @Test
    fun `未来空步阻断联合而不是被当成可绘制 next`() {
        val samples =
            listOf(
                DanmakuMaskTimelineSample(ptsMs = 1_000L, empty = false),
                DanmakuMaskTimelineSample(ptsMs = 1_280L, empty = true),
            )

        val bracket = DanmakuMaskTimelinePolicy.selectBracket(samples, 1_200L, staleMaxMs = 500L)

        assertEquals(0, bracket?.floorIndex)
        assertEquals(1, bracket?.nextIndex)
    }

    @Test
    fun `有 next 时不外推而缓冲尽头最多外推一百五十毫秒`() {
        assertEquals(
            0L,
            DanmakuMaskTimelinePolicy.tailExtrapolationMs(
                timelineMs = 1_400L,
                floorPtsMs = 1_000L,
                hasNext = true,
            ),
        )
        assertEquals(
            150L,
            DanmakuMaskTimelinePolicy.tailExtrapolationMs(
                timelineMs = 1_400L,
                floorPtsMs = 1_000L,
                hasNext = false,
            ),
        )
    }

    @Test
    fun `门控复位后首步立即采纳其后翻转需连续两步`() {
        val gate = DanmakuMaskGate()

        // 新建/复位后的首步直接采纳（否则每次 sceneCut 后首个有主体的 mask 都被吃掉）。
        assertEquals(true, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        // 稳态翻转（关闭）需连续两步确认。
        assertEquals(true, gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertEquals(false, gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
        // 稳态翻转（重新开启）同样需连续两步。
        assertEquals(false, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertEquals(true, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        // reset 后再次回到"首步立即采纳"。
        gate.reset()
        assertEquals(true, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
    }

    @Test
    fun `门控边界恢复会取消待确认翻转`() {
        val gate = DanmakuMaskGate()
        gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f)
        gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f)

        assertTrue(gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertTrue(gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertTrue(gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
    }

    @Test
    fun `预算紧张只拉步长且输入宽钉死512`() {
        val policy = DanmakuPlanBBudgetPolicy(initialInputWidth = 512)

        val relaxed = policy.adapt(budgetEmaMs = 100.0, highMotion = false)
        val tight = policy.adapt(budgetEmaMs = 300.0, highMotion = false)
        val extreme = policy.adapt(budgetEmaMs = 600.0, highMotion = false)

        assertEquals(512, relaxed.inputWidth)
        assertEquals(280L, relaxed.stepMs)
        assertEquals(false, relaxed.inputWidthChanged)
        assertEquals(512, tight.inputWidth)
        assertEquals(375L, tight.stepMs)
        assertEquals(512, extreme.inputWidth)
        assertEquals(640L, extreme.stepMs)
    }

    @Test
    fun `倍速播放按速度放大可持续步长与上限`() {
        val policy = DanmakuPlanBBudgetPolicy(initialInputWidth = 512)

        // 2x：450ms 推理 → 可持续步长 450*2/0.8=1125ms（视频时间），上限放大到 1280ms。
        val doubled = policy.adapt(budgetEmaMs = 450.0, highMotion = false, playbackSpeed = 2.0)
        assertEquals(1125L, doubled.stepMs)
        // 1x 行为不变：上限仍是 640ms。
        val normal = policy.adapt(budgetEmaMs = 900.0, highMotion = false, playbackSpeed = 1.0)
        assertEquals(640L, normal.stepMs)
    }
}
