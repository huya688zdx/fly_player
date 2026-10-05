package com.geqian.flyplayer.fly_player

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.hypot

/**
 * 悬浮小窗窗口内容（悬浮小窗方案 3.2：拖动 / 可拖出屏边 / 左右吸附 / 边缘拖拽自由缩放；
 * 交互对齐参考稿 design/floating-mini-player-mockup.html 的安卓交互清单）。
 *
 * 子层级（自下而上）：[playerSurface 由宿主 attach 进来] → 定格图覆盖层 → 8 个边缘
 * 缩放手柄（贴边内侧热区，透明）。渲染组子项均不消费触摸，拖动/单击由本容器
 * OnTouchListener 处理；缩放手柄各自持触摸（参考稿：把手不触发拖动）。
 *
 * 单击（位移 ≤ [FloatingPlayerWindowPolicy.TAP_SLOP_SLOP_PX]）呼出/收起控制层
 * （锁定/选集/弹幕，2.8s 自动收起；展开/关闭在常显迷你条上）。
 */
@SuppressLint("ClickableViewAccessibility")
internal class FloatingPlayerWindowView(
    context: Context,
    private val callbacks: Callbacks,
) : FrameLayout(context) {

    /** 窗口与播放壳的协作面（由 FloatingPlayerService 桥接）。 */
    interface Callbacks {
        /** 迷你条「展开」→ 请求展开回全屏。 */
        fun onExpandRequested()

        /** 迷你条「关闭」→ 关闭悬浮窗，播放壳走 PiP 兜底路径（方案 3.2）。 */
        fun onCloseRequested()

        /** 迷你条「播停」→ 服务直接派发命令总线（NativeMediaCommandCoordinator）。 */
        fun onPlayPauseRequested()

        /** 迷你条「-15s」→ 服务直接派发命令总线。 */
        fun onSeekBackRequested()

        /** 迷你条「+15s」→ 服务直接派发命令总线。 */
        fun onSeekForwardRequested()

        /** 接下来播放条「下一集」→ 服务走 dispatchInPlaceLoad 同链就地换片（方案 3.5）。 */
        fun onNextEpisodeRequested()

        /** 控制层「选集」→ 播放壳组装目录数据后经 updateEpisodePanel 回推。 */
        fun onEpisodePanelRequested()

        /** 选集面板点选条目 → 播放壳走 requestEpisode 原地换片。 */
        fun onEpisodeSelected(guid: String)

        /** 控制层弹幕开关 → 播放壳切换后经 updatePlayerUi 回推新状态。 */
        fun onDanmakuToggleRequested()

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

    // ---- 3.5 UI 状态（迷你条/控制层/选集面板） ----

    private var uiState = FloatingPlayerUiState()
    private var locked = false
    private var controlLayerVisible = false
    private var episodePanelVisible = false
    private var episodes: List<FloatingEpisodeUiItem> = emptyList()
    private val materializedEpisodeRows = HashMap<Int, TextView>()
    // 到点收起：暂停时不收（可重进 arm 分支保持显示）。
    private val controlHideRunnable = Runnable {
        if (controlLayerVisible &&
            FloatingPlayerWindowPolicy.shouldAutoHideControlLayer(uiState.paused)
        ) {
            hideControlLayer()
        }
    }

    private val scrimColor = 0xB3060A10.toInt()
    private val accentColor = 0xFF3A82F7.toInt()

    // 迷你条（常显）：播停 / ±15s / 集名跑马灯 / 展开关闭。
    private val miniBar = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundColor(scrimColor)
        setPadding(4.dp, 0, 4.dp, 0)
    }
    private val playPauseIcon = ImageButton(context).apply { isClickable = false }
    private val episodeMarquee = TextView(context).apply {
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        marqueeRepeatLimit = -1
        isSelected = true
        isHorizontalFadingEdgeEnabled = true
        setTextColor(Color.WHITE)
        textSize = 12f
    }

    // 接下来播放条（常显，有下一集才显示）：接下来 | 下一集名 | 下一集图标（右侧，方案 3.5）。
    private val nextBar = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundColor(0x99060A10.toInt())
        setPadding(8.dp, 0, 4.dp, 0)
        visibility = View.GONE
    }
    private val nextTitleMarquee = TextView(context).apply {
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        marqueeRepeatLimit = -1
        isSelected = true
        setTextColor(0xCCFFFFFF.toInt())
        textSize = 11f
    }

    // 控制层（单击呼出，2.8s 自动收起；锁定态只留解锁）：接下来播放条 + 锁定/选集/弹幕。
    private val controlLayer = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(scrimColor)
        visibility = View.GONE
    }
    private val controlUnlockButton = pillButton(
        localized(R.string.player_floating_unlock),
    ) { setLocked(false) }

    // 选集面板（控制层「选集」呼出，高度 ≤ 窗口 64%，窗口化惰性构建，打开定位当前集）。
    private val episodePanelRoot = FrameLayout(context).apply { visibility = View.GONE }
    private val episodeListScroll = ScrollView(context).apply { isVerticalScrollBarEnabled = false }
    private val episodeListHost = FrameLayout(context)
    private lateinit var lockPill: TextView
    private lateinit var danmakuPill: TextView
    private lateinit var episodePanelHeadLabel: TextView
    private val chromeButtons = mutableListOf<View>()

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
        // 层级（自下而上）：渲染组槽位（installPlayerSurface 加到 index 0）→ 定格图 → 缩放手柄
        // → 底部 chrome（迷你条/接下来播放条/控制层）→ 选集面板（最上层遮罩）。
        addView(
            freezeView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        buildResizeHandles()
        setResizeHandlesVisible(false)
        buildChrome()
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
                    // 原地松手 = 单击：呼出/收起控制层（参考稿交互清单；展开走迷你条按钮）。
                    toggleControlLayer()
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

    // ---- 3.5 悬浮窗 UI：常显迷你条 / 接下来播放条 / 控制层 / 选集面板 ----

    private var episodeRowHeightPx = 0

    /** 组装底部 chrome：控制层（默认收起）→ 接下来播放条 → 常显迷你条，自上而下叠放。 */
    private fun buildChrome() {
        episodeRowHeightPx = FloatingPlayerWindowPolicy.episodeRowHeightPx(density)
        val chromeColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM
        }

        // 常显迷你条：[播停][-15s][+15s][集名跑马灯][展开][关闭]。
        miniBar.addView(
            playPauseIcon.apply {
                setImageResource(android.R.drawable.ic_media_pause)
                contentDescription = localized(R.string.player_floating_play_pause)
                setBackgroundColor(Color.TRANSPARENT)
                isClickable = true
                setOnClickListener { callbacks.onPlayPauseRequested() }
            },
            linearRowParams(30.dp),
        )
        val back15Button = iconButton(
            android.R.drawable.ic_media_rew,
            localized(R.string.player_media_action_rewind_15s),
        ) { callbacks.onSeekBackRequested() }
        miniBar.addView(back15Button, linearRowParams(26.dp))
        val fwd15Button = iconButton(
            android.R.drawable.ic_media_ff,
            localized(R.string.player_media_action_forward_15s),
        ) { callbacks.onSeekForwardRequested() }
        miniBar.addView(fwd15Button, linearRowParams(26.dp))
        miniBar.addView(
            episodeMarquee,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(6.dp, 0, 6.dp, 0)
            },
        )
        val expandButton = pillButton(localized(R.string.player_floating_expand)) {
            callbacks.onExpandRequested()
        }
        miniBar.addView(expandButton, linearRowParams())
        val closeButton = pillButton(localized(R.string.player_floating_close)) {
            callbacks.onCloseRequested()
        }
        miniBar.addView(
            closeButton,
            linearRowParams().apply { setMargins(4.dp, 0, 0, 0) },
        )

        // 接下来播放条：[接下来][下一集名][下一集图标（右侧，方案 3.5）]，有下一集才显示。
        nextBar.addView(
            pillLabel(localized(R.string.player_floating_next_label)),
            linearRowParams(),
        )
        nextBar.addView(
            nextTitleMarquee,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(6.dp, 0, 6.dp, 0)
            },
        )
        val nextButton = iconButton(
            android.R.drawable.ic_media_next,
            localized(R.string.player_media_action_next),
        ) { callbacks.onNextEpisodeRequested() }
        nextBar.addView(nextButton, linearRowParams(28.dp))

        // 控制层：[锁定][选集][弹幕]；锁定态只剩解锁按钮（参考稿 fw-controls 精简形态）。
        val lockPill = pillButton(localized(R.string.player_floating_lock)) { setLocked(true) }
        this.lockPill = lockPill
        val episodesButton = pillButton(localized(R.string.player_floating_episodes)) {
            callbacks.onEpisodePanelRequested()
        }
        val danmakuPill = pillButton(localized(R.string.player_floating_danmaku)) {
            callbacks.onDanmakuToggleRequested()
        }
        this.danmakuPill = danmakuPill
        val actionRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(6.dp, 4.dp, 6.dp, 8.dp)
            addView(
                lockPill,
                LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(4.dp, 0, 4.dp, 0)
                },
            )
            addView(
                episodesButton,
                LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(4.dp, 0, 4.dp, 0)
                },
            )
            addView(
                danmakuPill,
                LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(4.dp, 0, 4.dp, 0)
                },
            )
        }
        controlLayer.addView(actionRow)
        controlLayer.addView(
            controlUnlockButton,
            LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
                setMargins(0, 8.dp, 0, 8.dp)
            },
        )

        chromeButtons.addAll(
            listOf(playPauseIcon, back15Button, fwd15Button, expandButton, closeButton, nextButton, lockPill, episodesButton, danmakuPill),
        )

        chromeColumn.addView(controlLayer)
        chromeColumn.addView(nextBar)
        chromeColumn.addView(miniBar)
        addView(
            chromeColumn,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM),
        )

        // 选集面板：遮罩（点外部收起）+ 底部面板（计数表头 + 固定行高惰性列表）。
        val panelShield = View(context).apply {
            isClickable = true
            setBackgroundColor(0x66000000)
            setOnClickListener { hideEpisodePanel() }
        }
        episodePanelRoot.addView(
            panelShield,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        val panelHead = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(scrimColor)
            setPadding(10.dp, 4.dp, 6.dp, 4.dp)
        }
        val episodeCountLabel = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
        }
        panelHead.addView(
            episodeCountLabel,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f),
        )
        panelHead.addView(
            pillButton(localized(R.string.player_floating_episodes_collapse)) { hideEpisodePanel() },
            linearRowParams(),
        )
        episodeListScroll.addView(
            episodeListHost,
            FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT),
        )
        episodeListScroll.setOnScrollChangeListener { _, _, scrollY, _, _ ->
            materializeEpisodeRows(scrollY)
        }
        val panelSheet = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(scrimColor)
        }
        panelSheet.addView(panelHead)
        panelSheet.addView(episodeListScroll)
        episodePanelRoot.addView(
            panelSheet,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM),
        )
        addView(
            episodePanelRoot,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        episodePanelHeadLabel = episodeCountLabel
    }

    private fun localized(resId: Int): String = context.getString(resId)

    private fun linearRowParams(sizePx: Int = LayoutParams.WRAP_CONTENT): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(sizePx, sizePx.takeIf { it != LayoutParams.WRAP_CONTENT } ?: LayoutParams.WRAP_CONTENT).apply {
            setMargins(2.dp, 0, 2.dp, 0)
        }

    private fun pillButton(text: String, onClick: () -> Unit): TextView =
        TextView(context).apply {
            this.text = text
            isSingleLine = true
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 11f
            setBackgroundColor(0x33FFFFFF)
            setPadding(8.dp, 5.dp, 8.dp, 5.dp)
            isClickable = true
            setOnClickListener { onClick() }
        }

    /** 静态 pill 标签（无点击语义，如接下来播放条的「接下来」）。 */
    private fun pillLabel(text: String): TextView =
        TextView(context).apply {
            this.text = text
            isSingleLine = true
            gravity = Gravity.CENTER
            setTextColor(0xCCFFFFFF.toInt())
            textSize = 11f
            setBackgroundColor(0x26FFFFFF)
            setPadding(8.dp, 5.dp, 8.dp, 5.dp)
        }

    private fun iconButton(iconRes: Int, contentDesc: String, onClick: () -> Unit): ImageButton =
        ImageButton(context).apply {
            setImageResource(iconRes)
            this.contentDescription = contentDesc
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
            setOnClickListener { onClick() }
        }

    /** 播放壳推送的迷你条/控制层状态（集名跑马灯、播停图标、弹幕态、下一集）。 */
    fun updatePlayerUi(state: FloatingPlayerUiState) {
        uiState = state
        playPauseIcon.setImageResource(
            if (state.paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
        )
        episodeMarquee.text = state.episodeTitle
        nextTitleMarquee.text = state.nextEpisodeTitle
        nextBar.visibility = if (state.hasNextEpisode) View.VISIBLE else View.GONE
        danmakuPill.setTextColor(if (state.danmakuEnabled) Color.WHITE else 0x66FFFFFF.toInt())
        if (controlLayerVisible) armControlLayerHide()
    }

    // ---- 控制层显隐 + 锁定（参考稿 toggleControls / 锁定语义） ----

    private fun toggleControlLayer() {
        if (episodePanelVisible) {
            hideEpisodePanel()
            return
        }
        if (controlLayerVisible) hideControlLayer() else showControlLayer()
    }

    private fun showControlLayer() {
        controlLayerVisible = true
        controlLayer.visibility = View.VISIBLE
        updateLockUi()
        armControlLayerHide()
    }

    private fun hideControlLayer() {
        controlLayerVisible = false
        controlLayer.visibility = View.GONE
        removeCallbacks(controlHideRunnable)
    }

    /** 播放中 2.8s 自动收起，暂停保持（参考稿 armHide 语义）。 */
    private fun armControlLayerHide() {
        if (!controlLayerVisible) return
        removeCallbacks(controlHideRunnable)
        if (!FloatingPlayerWindowPolicy.shouldAutoHideControlLayer(uiState.paused)) return
        postDelayed(controlHideRunnable, FloatingPlayerWindowPolicy.CONTROL_LAYER_AUTO_HIDE_MS)
    }

    /** 锁定（窗口本地态）：控制层只剩解锁按钮，迷你条按钮停用；单击不再唤出其他控制。 */
    private fun setLocked(value: Boolean) {
        locked = value
        updateLockUi()
    }

    private fun updateLockUi() {
        for (button in chromeButtons) {
            button.isEnabled = !locked
            button.alpha = if (locked) 0.45f else 1f
        }
        lockPill.text =
            if (locked) localized(R.string.player_floating_unlock) else localized(R.string.player_floating_lock)
        // 锁定态：控制层只显示解锁按钮（动作行收起）；下一集按钮随 chromeButtons 停用。
        controlLayer.getChildAt(0).visibility = if (locked) View.GONE else View.VISIBLE
        controlUnlockButton.visibility = if (locked) View.VISIBLE else View.GONE
    }

    // ---- 选集面板（窗口化惰性列表：固定行高，滚动物化可见窗口 ± 过扫描） ----

    /** 播放壳回推的选集数据：装载面板、按当前集定位滚动并高亮（方案 3.5）。 */
    fun showEpisodePanel(items: List<FloatingEpisodeUiItem>) {
        episodes = items
        episodePanelVisible = true
        hideControlLayer()
        episodePanelRoot.visibility = View.VISIBLE
        episodePanelHeadLabel.text =
            localized(R.string.player_floating_episodes) + " · " + items.size
        val panelHeight = FloatingPlayerWindowPolicy.episodePanelHeightPx(windowParams.height)
        val headHeight = (34 * density).toInt()
        episodeListScroll.layoutParams = LinearLayout.LayoutParams(
            LayoutParams.MATCH_PARENT,
            panelHeight.coerceAtLeast(episodeRowHeightPx) - headHeight,
        )
        clearEpisodeRows()
        val selectedIndex = items.indexOfFirst { it.selected }
        episodeListScroll.post {
            if (selectedIndex >= 0) {
                episodeListScroll.scrollTo(0, selectedIndex * episodeRowHeightPx)
            }
            materializeEpisodeRows(episodeListScroll.scrollY)
        }
    }

    private fun hideEpisodePanel() {
        episodePanelVisible = false
        episodePanelRoot.visibility = View.GONE
        clearEpisodeRows()
    }

    private fun clearEpisodeRows() {
        for (row in materializedEpisodeRows.values) {
            episodeListHost.removeView(row)
        }
        materializedEpisodeRows.clear()
    }

    private fun materializeEpisodeRows(scrollY: Int) {
        if (!episodePanelVisible) return
        val (first, count) = FloatingPlayerWindowPolicy.episodeWindow(
            scrollY = scrollY,
            viewportHeightPx = episodeListScroll.height,
            totalRows = episodes.size,
            rowHeightPx = episodeRowHeightPx,
        )
        val wanted = first until (first + count)
        for (index in materializedEpisodeRows.keys.toList()) {
            if (index !in wanted) {
                episodeListHost.removeView(materializedEpisodeRows.remove(index))
            }
        }
        for (index in wanted) {
            if (materializedEpisodeRows.containsKey(index)) continue
            val item = episodes[index]
            val row = TextView(context).apply {
                text = item.label
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL
                setPadding(10.dp, 0, 10.dp, 0)
                if (item.selected) {
                    setBackgroundColor(accentColor)
                    setTextColor(Color.WHITE)
                } else {
                    setTextColor(0xE6FFFFFF.toInt())
                }
                isClickable = true
                setOnClickListener {
                    callbacks.onEpisodeSelected(item.guid)
                    hideEpisodePanel()
                }
            }
            episodeListHost.addView(
                row,
                FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, episodeRowHeightPx).apply {
                    topMargin = index * episodeRowHeightPx
                },
            )
            materializedEpisodeRows[index] = row
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
