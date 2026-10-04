package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 悬浮小窗窗口策略（悬浮小窗方案 3.2/3.3 + 参考稿交互清单的数值契约）：
 * 等比 16:9、宽 160dp–屏宽 72%、默认 248dp、拖出屏边保留可见、松手按窗口中心吸附
 * 左/右边缘、缩放 delta（角取水平/垂直×16/9 较大值）、入口三态。
 */
class FloatingPlayerWindowPolicyTest {

    @Test
    fun `height follows width with 16 to 9 aspect`() {
        // 16:9 等比：宽 248dp → 高 140（round(248*9/16)）；0 宽回 0。
        assertEquals(140, FloatingPlayerWindowPolicy.heightFromWidthPx(248))
        assertEquals(90, FloatingPlayerWindowPolicy.heightFromWidthPx(160))
        assertEquals(0, FloatingPlayerWindowPolicy.heightFromWidthPx(0))
    }

    @Test
    fun `width clamps between 160dp and 72 percent of screen`() {
        val screenWidth = 1080
        val maxWidth = FloatingPlayerWindowPolicy.maxWidthPx(screenWidth)
        assertEquals(778, maxWidth) // round(1080*0.72)
        assertEquals(300, FloatingPlayerWindowPolicy.clampWidthPx(300, 160, maxWidth))
        assertEquals(160, FloatingPlayerWindowPolicy.clampWidthPx(100, 160, maxWidth))
        assertEquals(maxWidth, FloatingPlayerWindowPolicy.clampWidthPx(5000, 160, maxWidth))
    }

    @Test
    fun `drag allows offscreen but keeps visible margin`() {
        // 可拖出屏边：x 下限 = -(w - 56)，上限 = screenW - 56（参考稿 FLAG_LAYOUT_NO_LIMITS 模拟）。
        val (w, screen, visible) = Triple(300, 1080, 56)
        assertEquals(-(w - visible), FloatingPlayerWindowPolicy.clampDragX(-500, w, screen, visible))
        assertEquals(screen - visible, FloatingPlayerWindowPolicy.clampDragX(2000, w, screen, visible))
        assertEquals(42, FloatingPlayerWindowPolicy.clampDragX(42, w, screen, visible))
    }

    @Test
    fun `snap follows window center to left or right edge`() {
        val screen = 1080
        // 中心在左半屏贴左，否则贴右（参考稿 aDragEnd）。
        assertEquals(SnapSide.LEFT, FloatingPlayerWindowPolicy.resolveSnapSide(200, screen))
        assertEquals(SnapSide.RIGHT, FloatingPlayerWindowPolicy.resolveSnapSide(900, screen))
        // 边界恰在半屏分界归右侧。
        assertEquals(SnapSide.RIGHT, FloatingPlayerWindowPolicy.resolveSnapSide(screen / 2, screen))
        // 吸附位：贴左 = 边距，贴右 = 屏宽 - 窗宽 - 边距。
        assertEquals(8, FloatingPlayerWindowPolicy.snapX(SnapSide.LEFT, 300, screen, 8))
        assertEquals(screen - 300 - 8, FloatingPlayerWindowPolicy.snapX(SnapSide.RIGHT, 300, screen, 8))
    }

    @Test
    fun `resize delta matches handle semantics`() {
        val p = FloatingPlayerWindowPolicy
        // 水平缘直接取 dx。
        assertEquals(40, p.resizeDeltaWidthPx("e", 40, 0))
        assertEquals(-40, p.resizeDeltaWidthPx("w", 40, 0))
        // 垂直缘按 16:9 折算。
        assertEquals(36, p.resizeDeltaWidthPx("s", 0, 20)) // round(20*16/9)
        assertEquals(-36, p.resizeDeltaWidthPx("n", 0, 20))
        // 角取水平 / 垂直折算的较大值；向外拖（dx/dy 背离窗口）恒为正 = 放大。
        assertEquals(40, p.resizeDeltaWidthPx("se", 40, 20))
        assertEquals(36, p.resizeDeltaWidthPx("se", 10, 20))
        assertEquals(40, p.resizeDeltaWidthPx("nw", -40, -20))
        // 西/北向缩放需反向补偿位置（对边保持不动）。
        assertTrue(p.resizeAnchorsWest("w"))
        assertTrue(p.resizeAnchorsWest("nw"))
        assertFalse(p.resizeAnchorsWest("e"))
        assertTrue(p.resizeAnchorsNorth("n"))
        assertFalse(p.resizeAnchorsNorth("se"))
    }

    @Test
    fun `entry action falls back to pip below api 26`() {
        // 低版本不存在 TYPE_APPLICATION_OVERLAY：直接回退系统 PiP（方案 3.2）。
        assertEquals(
            FloatingEntryAction.FALLBACK_PIP,
            FloatingPlayerWindowPolicy.resolveEntryAction(
                sdkAtLeastO = false,
                overlayPermissionGranted = true,
            ),
        )
        assertEquals(
            FloatingEntryAction.FALLBACK_PIP,
            FloatingPlayerWindowPolicy.resolveEntryAction(
                sdkAtLeastO = false,
                overlayPermissionGranted = false,
            ),
        )
    }

    @Test
    fun `entry action guides to settings when permission missing on api 26 plus`() {
        assertEquals(
            FloatingEntryAction.GUIDE_PERMISSION,
            FloatingPlayerWindowPolicy.resolveEntryAction(
                sdkAtLeastO = true,
                overlayPermissionGranted = false,
            ),
        )
    }

    @Test
    fun `entry action enters when capable`() {
        assertEquals(
            FloatingEntryAction.ENTER,
            FloatingPlayerWindowPolicy.resolveEntryAction(
                sdkAtLeastO = true,
                overlayPermissionGranted = true,
            ),
        )
    }
}
