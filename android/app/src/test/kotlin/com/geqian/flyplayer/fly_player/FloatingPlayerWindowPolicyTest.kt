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

    @Test
    fun `episode panel height caps at 64 percent of window`() {
        // 方案 3.5：面板高度上限 = 窗口高度 64%（长剧集不截断，靠滚动展开）。
        assertEquals(90, FloatingPlayerWindowPolicy.episodePanelHeightPx(140))
        assertEquals(0, FloatingPlayerWindowPolicy.episodePanelHeightPx(0))
    }

    @Test
    fun `episode window materializes viewport plus overscan rows`() {
        val rowHeight = 32
        // 滚动在顶部：首行 0，物化行数 = 视口行数 + 上下过扫描，且不超过总数。
        val (first, count) = FloatingPlayerWindowPolicy.episodeWindow(
            scrollY = 0,
            viewportHeightPx = 160,
            totalRows = 300,
            rowHeightPx = rowHeight,
        )
        assertEquals(0, first)
        // 视口 5 行 + 上下各 4 行过扫描 = 13。
        assertEquals(13, count)
        // 滚动到中部：first 前移过扫描行，不越界。
        val (midFirst, midCount) = FloatingPlayerWindowPolicy.episodeWindow(
            scrollY = 100 * rowHeight,
            viewportHeightPx = 160,
            totalRows = 300,
            rowHeightPx = rowHeight,
        )
        assertEquals(96, midFirst) // 100 - 4
        assertEquals(13, midCount)
        // 尾部：首行钳制在总数内，行数钳制到剩余行。
        val (tailFirst, tailCount) = FloatingPlayerWindowPolicy.episodeWindow(
            scrollY = 299 * rowHeight,
            viewportHeightPx = 160,
            totalRows = 300,
            rowHeightPx = rowHeight,
        )
        assertEquals(295, tailFirst) // 299 - 4
        assertEquals(5, tailCount) // 300 - 295
    }

    @Test
    fun `episode window is empty without rows or rows height`() {
        assertEquals(0 to 0, FloatingPlayerWindowPolicy.episodeWindow(0, 160, 0, 32))
        assertEquals(0 to 0, FloatingPlayerWindowPolicy.episodeWindow(0, 160, 10, 0))
    }

    @Test
    fun `control layer auto hides only while playing`() {
        // 参考稿 armHide 语义：播放中 2.8s 收起，暂停保持。
        assertTrue(FloatingPlayerWindowPolicy.shouldAutoHideControlLayer(paused = false))
        assertFalse(FloatingPlayerWindowPolicy.shouldAutoHideControlLayer(paused = true))
        assertEquals(2800L, FloatingPlayerWindowPolicy.CONTROL_LAYER_AUTO_HIDE_MS)
    }
}
