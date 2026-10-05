package com.geqian.flyplayer.fly_player

import kotlin.math.roundToInt

/**
 * 悬浮小窗窗口策略（悬浮小窗方案 3.2/3.3 + 参考稿 design/floating-mini-player-mockup.html
 * 的交互清单）。全部纯函数，JVM 可测；像素换算由调用方（窗口 View）负责。
 *
 * 交互契约（与参考稿一致）：
 *  - 自由缩放无档位，等比 16:9，宽 [160dp, 屏宽 72%]，默认宽 248dp（方案 3.2/3.3）；
 *  - 拖动可拖出屏边但保留 [MIN_DRAG_VISIBLE_DP] 可见，松手按窗口中心吸附左/右边缘
 *    （吸附边距 8dp）；垂直方向始终保留上下边距内可见；
 *  - 缩放 delta：右缘 +dx、左缘 -dx、下缘 +dy*16/9、上缘 -dy*16/9、角取两者较大值
 *    （被拖对边保持不动，西/北向缩放反向补偿位置）。
 */
internal object FloatingPlayerWindowPolicy {
    const val MIN_WIDTH_DP = 160
    const val MAX_WIDTH_SCREEN_RATIO = 0.72
    const val DEFAULT_WIDTH_DP = 248

    /** 拖出屏边时窗口必须保留的可见像素（参考稿 56px 语义，取 dp 由调用方换算）。 */
    const val MIN_DRAG_VISIBLE_DP = 56

    /** 吸附边距（参考稿 8px 语义）与垂直方向上下保留边距。 */
    const val SNAP_MARGIN_DP = 8
    const val DRAG_VERTICAL_MARGIN_DP = 6

    /** 拖动位移超过该距离才算拖动（小于等于则视为单击）。 */
    const val TAP_SLOP_SLOP_PX = 7

    /** 悬浮窗高度 = 宽度 * 9/16（等比 16:9）。 */
    fun heightFromWidthPx(widthPx: Int): Int = (widthPx.coerceAtLeast(0) * 9.0 / 16.0).roundToInt()

    fun maxWidthPx(screenWidthPx: Int): Int =
        (screenWidthPx.coerceAtLeast(0) * MAX_WIDTH_SCREEN_RATIO).roundToInt()

    fun clampWidthPx(widthPx: Int, minPx: Int, maxPx: Int): Int = widthPx.coerceIn(minPx, maxPx)

    /** 拖动 x 边界：可拖出屏边，但窗口保留 [minVisiblePx] 在屏内。 */
    fun clampDragX(x: Int, windowWidth: Int, screenWidth: Int, minVisiblePx: Int): Int =
        x.coerceIn(-(windowWidth - minVisiblePx), screenWidth - minVisiblePx)

    /** 拖动/吸附 y 边界：窗口整体保留在上下边距内（参考稿 placeFloat/clamp 语义）。 */
    fun clampY(y: Int, windowHeight: Int, screenHeight: Int, marginPx: Int): Int =
        y.coerceIn(marginPx, (screenHeight - windowHeight - marginPx).coerceAtLeast(marginPx))

    /** 按窗口中心点解析吸附边：中心在左半屏贴左，否则贴右（参考稿 aDragEnd）。 */
    fun resolveSnapSide(windowCenterX: Int, screenWidth: Int): SnapSide =
        if (windowCenterX < screenWidth / 2) SnapSide.LEFT else SnapSide.RIGHT

    /** 吸附后的 x：贴左 = 边距，贴右 = 屏宽 - 窗宽 - 边距。 */
    fun snapX(side: SnapSide, windowWidth: Int, screenWidth: Int, marginPx: Int): Int =
        when (side) {
            SnapSide.LEFT -> marginPx
            SnapSide.RIGHT -> screenWidth - windowWidth - marginPx
        }

    /**
     * 缩放手柄的宽度增量（像素）。mode ∈ {n, s, e, w, ne, nw, se, sw}；
     * 垂直向按 16:9 折算成宽度，角取水平/垂直推导中的较大值（参考稿 pointermove）。
     */
    fun resizeDeltaWidthPx(mode: String, dx: Int, dy: Int): Int = when (mode) {
        "e" -> dx
        "w" -> -dx
        "s" -> (dy * 16.0 / 9.0).roundToInt()
        "n" -> (-dy * 16.0 / 9.0).roundToInt()
        else -> {
            val horizontal = if (mode.contains("e")) dx else -dx
            val vertical = ((if (mode.contains("s")) dy else -dy) * 16.0 / 9.0).roundToInt()
            maxOf(horizontal, vertical)
        }
    }

    /** 缩放是否包含西（左）向：需要反向补偿 x，让被拖对边保持不动。 */
    fun resizeAnchorsWest(mode: String): Boolean = mode.contains("w")

    /** 缩放是否包含北（上）向：需要反向补偿 y。 */
    fun resizeAnchorsNorth(mode: String): Boolean = mode.contains("n")

    /**
     * 悬浮小窗入口三态决策（方案 3.2：API 26+ 门控，低版本/未授权自动回退系统 PiP；
     * 未授权（API 26+）走一次性内联引导——跳系统悬浮窗设置页）。
     */
    fun resolveEntryAction(
        sdkAtLeastO: Boolean,
        overlayPermissionGranted: Boolean,
    ): FloatingEntryAction = when {
        !sdkAtLeastO -> FloatingEntryAction.FALLBACK_PIP
        !overlayPermissionGranted -> FloatingEntryAction.GUIDE_PERMISSION
        else -> FloatingEntryAction.ENTER
    }

    // ---- 选集面板（悬浮小窗方案 3.5） ----

    /** 选集面板高度上限：窗口高度的 64%（长剧集不截断，靠滚动展开）。 */
    const val EPISODE_PANEL_HEIGHT_RATIO = 0.64

    /** 惰性物化的过扫描行数（视口外的上下缓冲，滚动不露白）。 */
    const val EPISODE_LIST_OVERSCAN_ROWS = 4

    /** 固定行高：窗口化列表按 index×行高定位（定位当前集的必要条件）。 */
    fun episodeRowHeightPx(density: Float): Int = (32 * density).toInt()

    fun episodePanelHeightPx(windowHeightPx: Int): Int =
        (windowHeightPx.coerceAtLeast(0) * EPISODE_PANEL_HEIGHT_RATIO).roundToInt()

    /**
     * 窗口化物化列表（RecyclerView 语义的轻量实现，不引 recyclerview 依赖）：
     * 给定滚动位置/视口/总数/行高，返回需物化的首行与行数（含上下过扫描，钳制在总行数内）。
     */
    fun episodeWindow(
        scrollY: Int,
        viewportHeightPx: Int,
        totalRows: Int,
        rowHeightPx: Int,
    ): Pair<Int, Int> {
        if (totalRows <= 0 || rowHeightPx <= 0) return 0 to 0
        val first = (scrollY / rowHeightPx - EPISODE_LIST_OVERSCAN_ROWS).coerceIn(0, totalRows - 1)
        val visible = (viewportHeightPx + rowHeightPx - 1) / rowHeightPx + EPISODE_LIST_OVERSCAN_ROWS * 2
        val count = visible.coerceIn(0, totalRows - first)
        return first to count
    }

    // ---- 控制层自动收起（参考稿 armHide：播放中 2.8s 收起，暂停保持） ----

    const val CONTROL_LAYER_AUTO_HIDE_MS = 2800L

    fun shouldAutoHideControlLayer(paused: Boolean): Boolean = !paused
}

internal enum class SnapSide {
    LEFT,
    RIGHT,
}

internal enum class FloatingEntryAction {
    /** 悬浮窗能力就绪，直接收小窗。 */
    ENTER,

    /** API 26+ 但未授权悬浮窗：跳系统设置页做一次性内联引导。 */
    GUIDE_PERMISSION,

    /** API < 26 或服务/窗口不可用：回退系统 PiP（阶段 1 五键体验）。 */
    FALLBACK_PIP,
}
