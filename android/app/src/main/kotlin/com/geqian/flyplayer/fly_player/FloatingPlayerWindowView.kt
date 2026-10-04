package com.geqian.flyplayer.fly_player

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import kotlin.math.hypot

/**
 * 悬浮小窗窗口内容（悬浮小窗方案 3.2：拖动 / 可拖出屏边 / 左右吸附 / 边缘拖拽自由缩放；
 * 交互对齐参考稿 design/floating-mini-player-mockup.html 的安卓交互清单）。
 *
 * 子层级（自下而上）：[playerSurface 由宿主 attach 进来] → 定格图覆盖层 → 8 个边缘
 * 缩放手柄（贴边内侧热区，透明）。渲染组子项均不消费触摸，拖动/单击由本容器
 * OnTouchListener 处理；缩放手柄各自持触摸（参考稿：把手不触发拖动）。
 *
 * 单击（位移 ≤ [FloatingPlayerWindowPolicy.TAP_SLOP_SLOP_PX]）当前直接请求展开回全屏；
 * 3.5 控制层落地后改为呼出控制层（含关闭/锁定/选集），届时替换本行为。
 */
@SuppressLint("ClickableViewAccessibility")
internal class FloatingPlayerWindowView(
    context: Context,
    private val callbacks: Callbacks,
) : FrameLayout(context) {

    /** 窗口与播放壳的协作面（由 FloatingPlayerService 桥接）。 */
    interface Callbacks {
        /** 单击小窗（未拖动）→ 请求展开回全屏。 */
        fun onExpandRequested()

        /** 拖拽缩放松手、新尺寸已生效 → 重设 android-surface-size。 */
        fun onWindowSizeSettled(widthPx: Int, heightPx: Int)
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    // 定格图覆盖层：交接（进/出）与缩放重排瞬间盖住渲染空洞（方案 3.3 流程 2/3）。
    private val freezeView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        setBackgroundColor(Color.BLACK)
        visibility = View.GONE
    }

    // 8 个贴边缩放手柄（n/s/e/w + 四角），透明热区（参考稿 .rz 布局）。
    private val resizeHandles = mutableMapOf<String, View>()
    private val handleHideRunnable = Runnable { setResizeHandlesVisible(false) }

    private val density = resources.displayMetrics.density
    private val screenWidthPx = resources.displayMetrics.widthPixels
    private val screenHeightPx = resources.displayMetrics.heightPixels

    private var dragState: DragState? = null
    private var resizeState: ResizeState? = null
    private var snapAnimator: ValueAnimator? = null

    // 窗口几何（WindowManager 层）；命名避开 View.layoutParams（Java getter/setter 对）。
    val windowParams: WindowManager.LayoutParams = WindowManager.LayoutParams(
        FloatingPlayerWindowPolicy.DEFAULT_WIDTH_DP.dp,
        FloatingPlayerWindowPolicy.heightFromWidthPx(FloatingPlayerWindowPolicy.DEFAULT_WIDTH_DP.dp),
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        // 首次落位：右侧吸附 + 上部 96dp（参考稿 enterFloat 首次贴右）。
        x = FloatingPlayerWindowPolicy.snapX(
            SnapSide.RIGHT,
            width,
            screenWidthPx,
            FloatingPlayerWindowPolicy.SNAP_MARGIN_DP.dp,
        )
        y = 96.dp
    }

    /** 当前窗口宽（px），随缩放更新；宿主持久化用。 */
    var currentWidthPx: Int = windowParams.width
        private set

    init {
        // 层级（自下而上）：渲染组槽位（installPlayerSurface 加到 index 0）→ 定格图 → 缩放手柄。
        addView(
            freezeView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        buildResizeHandles()
        setResizeHandlesVisible(false)
        setOnTouchListener { _, event -> handleWindowTouch(event) }
    }

    /** 服务启动建窗时按记忆尺寸（floating_mini_player_size）恢复宽度并重落吸附位。 */
    fun restoreSize(widthPx: Int) {
        val clamped = FloatingPlayerWindowPolicy.clampWidthPx(
            widthPx,
            FloatingPlayerWindowPolicy.MIN_WIDTH_DP.dp,
            FloatingPlayerWindowPolicy.maxWidthPx(screenWidthPx),
        )
        windowParams.width = clamped
        windowParams.height = FloatingPlayerWindowPolicy.heightFromWidthPx(clamped)
        currentWidthPx = clamped
        windowParams.x = FloatingPlayerWindowPolicy.snapX(
            SnapSide.RIGHT,
            clamped,
            screenWidthPx,
            FloatingPlayerWindowPolicy.SNAP_MARGIN_DP.dp,
        )
    }

    private fun applyWindowParams() {
        runCatching { windowManager.updateViewLayout(this, windowParams) }
    }

    // ---- 渲染组宿主（FloatingPlayerService.attachPlayerSurface 调用） ----

    fun installPlayerSurface(surface: View, freezeFrame: Bitmap?) {
        addView(
            surface,
            0,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        if (freezeFrame != null) {
            freezeView.setImageBitmap(freezeFrame)
            freezeView.visibility = View.VISIBLE
            // 定格图只覆盖交接空洞：TextureView 复用成立时首帧即有画面，超时兜底收回。
            postDelayed({ hideFreezeFrame() }, FREEZE_COVER_MS)
        }
    }

    fun takePlayerSurface(surface: View): Boolean {
        if (surface.parent !== this) return false
        removeView(surface)
        return true
    }

    private fun hideFreezeFrame() {
        freezeView.visibility = View.GONE
        freezeView.setImageBitmap(null)
    }

    // ---- 拖动 / 单击（参考稿 pointerdown/move/up） ----

    private data class DragState(
        val pointerX: Float,
        val pointerY: Float,
        val startX: Int,
        val startY: Int,
        var moved: Boolean = false,
    )

    private fun handleWindowTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                snapAnimator?.cancel()
                dragState = DragState(event.rawX, event.rawY, windowParams.x, windowParams.y)
                // 拖动开始时亮出缩放手柄提示可缩放，超时自动收回。
                setResizeHandlesVisible(true)
                removeCallbacks(handleHideRunnable)
                postDelayed(handleHideRunnable, HANDLE_HINT_TIMEOUT_MS)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val state = dragState ?: return true
                if (!state.moved &&
                    hypot(
                        (event.rawX - state.pointerX).toDouble(),
                        (event.rawY - state.pointerY).toDouble(),
                    ) > FloatingPlayerWindowPolicy.TAP_SLOP_SLOP_PX
                ) {
                    state.moved = true
                }
                if (!state.moved) return true
                val dx = (event.rawX - state.pointerX).toInt()
                val dy = (event.rawY - state.pointerY).toInt()
                // 模拟 FLAG_LAYOUT_NO_LIMITS：允许拖出屏边，但保留 56dp 可见（参考稿 clamp）。
                windowParams.x = FloatingPlayerWindowPolicy.clampDragX(
                    state.startX + dx,
                    windowParams.width,
                    screenWidthPx,
                    FloatingPlayerWindowPolicy.MIN_DRAG_VISIBLE_DP.dp,
                )
                windowParams.y = FloatingPlayerWindowPolicy.clampY(
                    state.startY + dy,
                    windowParams.height,
                    screenHeightPx,
                    FloatingPlayerWindowPolicy.DRAG_VERTICAL_MARGIN_DP.dp,
                )
                applyWindowParams()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val state = dragState
                dragState = null
                if (state == null) return true
                if (!state.moved) {
                    // 原地松手 = 单击：当前直接展开回全屏（3.5 控制层落地后改为呼出控制层）。
                    callbacks.onExpandRequested()
                    return true
                }
                snapToEdge()
                return true
            }
            else -> return true
        }
    }

    /** 松手吸附左/右边缘（按窗口中心在左/右半屏判定），带短过渡动画（参考稿 placeFloat）。 */
    private fun snapToEdge() {
        val side = FloatingPlayerWindowPolicy.resolveSnapSide(
            windowParams.x + windowParams.width / 2,
            screenWidthPx,
        )
        val targetX = FloatingPlayerWindowPolicy.snapX(
            side,
            windowParams.width,
            screenWidthPx,
            FloatingPlayerWindowPolicy.SNAP_MARGIN_DP.dp,
        )
        val fromX = windowParams.x
        if (fromX == targetX) return
        snapAnimator?.cancel()
        snapAnimator = ValueAnimator.ofInt(fromX, targetX).apply {
            duration = SNAP_ANIMATOR_MS
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                windowParams.x = animator.animatedValue as Int
                applyWindowParams()
            }
            start()
        }
    }

    // ---- 边缘缩放（参考稿 rz 手柄：e/w/s/n + 四角，等比 16:9，无档位） ----

    private data class ResizeState(
        val mode: String,
        val pointerX: Float,
        val pointerY: Float,
        val startX: Int,
        val startY: Int,
        val startWidth: Int,
    )

    private fun buildResizeHandles() {
        val modes = listOf("n", "s", "e", "w", "ne", "nw", "se", "sw")
        for (mode in modes) {
            val handle = View(context).apply {
                isClickable = false
                setOnTouchListener { _, event ->
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            snapAnimator?.cancel()
                            resizeState = ResizeState(
                                mode = mode,
                                pointerX = event.rawX,
                                pointerY = event.rawY,
                                startX = windowParams.x,
                                startY = windowParams.y,
                                startWidth = windowParams.width,
                            )
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            applyResize(event)
                            true
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            if (resizeState != null) {
                                resizeState = null
                                settleAfterResize()
                            }
                            true
                        }
                        else -> false
                    }
                }
            }
            resizeHandles[mode] = handle
            addView(handle, handleLayoutParams(mode))
        }
    }

    private fun handleLayoutParams(mode: String): LayoutParams {
        val thickness = HANDLE_THICKNESS_DP.dp
        val inset = HANDLE_INSET_DP.dp
        val result = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        when (mode) {
            "n" -> {
                result.width = LayoutParams.MATCH_PARENT
                result.height = thickness
                result.setMargins(inset, 0, inset, 0)
            }
            "s" -> {
                result.width = LayoutParams.MATCH_PARENT
                result.height = thickness
                result.gravity = Gravity.BOTTOM
                result.setMargins(inset, 0, inset, 0)
            }
            "e" -> {
                result.width = thickness
                result.height = LayoutParams.MATCH_PARENT
                result.gravity = Gravity.END
                result.setMargins(0, inset, 0, inset)
            }
            "w" -> {
                result.width = thickness
                result.height = LayoutParams.MATCH_PARENT
                result.gravity = Gravity.START
                result.setMargins(0, inset, 0, inset)
            }
            "ne" -> {
                result.width = thickness
                result.height = thickness
                result.gravity = Gravity.TOP or Gravity.END
            }
            "nw" -> {
                result.width = thickness
                result.height = thickness
                result.gravity = Gravity.TOP or Gravity.START
            }
            "se" -> {
                result.width = thickness
                result.height = thickness
                result.gravity = Gravity.BOTTOM or Gravity.END
            }
            "sw" -> {
                result.width = thickness
                result.height = thickness
                result.gravity = Gravity.BOTTOM or Gravity.START
            }
        }
        return result
    }

    private fun applyResize(event: MotionEvent) {
        val state = resizeState ?: return
        val dx = (event.rawX - state.pointerX).toInt()
        val dy = (event.rawY - state.pointerY).toInt()
        val minWidth = FloatingPlayerWindowPolicy.MIN_WIDTH_DP.dp
        val maxWidth = FloatingPlayerWindowPolicy.maxWidthPx(screenWidthPx)
        val delta = FloatingPlayerWindowPolicy.resizeDeltaWidthPx(state.mode, dx, dy)
        val newWidth = FloatingPlayerWindowPolicy.clampWidthPx(state.startWidth + delta, minWidth, maxWidth)
        val newHeight = FloatingPlayerWindowPolicy.heightFromWidthPx(newWidth)
        // 被拖的对边保持不动：西/北向缩放反向补偿位置（参考稿 pointermove）。
        if (FloatingPlayerWindowPolicy.resizeAnchorsWest(state.mode)) {
            windowParams.x = state.startX + (state.startWidth - newWidth)
        }
        if (FloatingPlayerWindowPolicy.resizeAnchorsNorth(state.mode)) {
            val startHeight = FloatingPlayerWindowPolicy.heightFromWidthPx(state.startWidth)
            windowParams.y = state.startY + (startHeight - newHeight)
        }
        windowParams.y = FloatingPlayerWindowPolicy.clampY(
            windowParams.y,
            newHeight,
            screenHeightPx,
            FloatingPlayerWindowPolicy.DRAG_VERTICAL_MARGIN_DP.dp,
        )
        windowParams.width = newWidth
        windowParams.height = newHeight
        currentWidthPx = newWidth
        applyWindowParams()
    }

    /** 缩放松手：吸附 + 通知播放壳重设 android-surface-size（方案 3.3）。 */
    private fun settleAfterResize() {
        snapToEdge()
        callbacks.onWindowSizeSettled(windowParams.width, windowParams.height)
    }

    private fun setResizeHandlesVisible(visible: Boolean) {
        for (handle in resizeHandles.values) {
            handle.visibility = if (visible) View.VISIBLE else View.GONE
        }
    }

    private val Int.dp: Int
        get() = (this * density).toInt()

    private companion object {
        const val FREEZE_COVER_MS = 160L
        const val SNAP_ANIMATOR_MS = 150L
        const val HANDLE_HINT_TIMEOUT_MS = 1800L
        const val HANDLE_THICKNESS_DP = 9
        const val HANDLE_INSET_DP = 12
    }
}
