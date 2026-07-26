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
    fun `门控需要连续两步才开启和关闭`() {
        val gate = DanmakuMaskGate()

        assertEquals(false, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertEquals(true, gate.accept(0.20f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertEquals(true, gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
        assertEquals(false, gate.accept(0.001f, 0.012f, 0.80f, 0.006f, 0.06f))
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
    fun `预算紧张先逐级降输入宽度再拉步长`() {
        val policy = DanmakuPlanBBudgetPolicy(initialInputWidth = 512)

        val first = policy.adapt(budgetEmaMs = 300.0, highMotion = false)
        val second = policy.adapt(budgetEmaMs = 300.0, highMotion = false)
        val third = policy.adapt(budgetEmaMs = 600.0, highMotion = false)

        assertEquals(384, first.inputWidth)
        assertEquals(280L, first.stepMs)
        assertEquals(320, second.inputWidth)
        assertEquals(280L, second.stepMs)
        assertEquals(320, third.inputWidth)
        assertEquals(640L, third.stepMs)
    }
}
