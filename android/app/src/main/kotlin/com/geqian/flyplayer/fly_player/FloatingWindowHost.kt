package com.geqian.flyplayer.fly_player

import android.graphics.Bitmap
import android.view.View

/** 悬浮窗迷你条/控制层的播放壳状态快照（Activity → 窗口单向推送，方案 3.5）。 */
data class FloatingPlayerUiState(
    val episodeTitle: String = "",
    val nextEpisodeTitle: String = "",
    val paused: Boolean = false,
    val danmakuEnabled: Boolean = true,
    val hasNextEpisode: Boolean = false,
)

/** 悬浮窗选集面板条目（数据复用当前播放序列/目录，由 Activity 组装，方案 3.5）。 */
data class FloatingEpisodeUiItem(
    val guid: String,
    val label: String,
    val selected: Boolean,
)

/**
 * 悬浮小窗宿主接缝（悬浮小窗方案 3.3/3.4）：承载从 Activity 视图树 reparent 出来的
 * 渲染组（NativePlayerSurface 整体，视频 + 弹幕随迁）。
 *
 * FloatingPlayerService（方案 3.2 的 `TYPE_APPLICATION_OVERLAY` 前台服务，API 26+）
 * 落地后提供生产实现；宿主缺位时 NativePlayerActivity 的收小窗判定恒不就绪，
 * back 键维持既有 PiP/保留/退出路径（3.4 表「否则维持 PiP 路径」）。
 */
interface FloatingWindowHost {
    /** 宿主窗口就绪（服务存活 + 悬浮窗权限齐备），可接收渲染组。 */
    val isActive: Boolean

    /** 窗口交互回传（拖动/缩放由窗口自处理，需要播放壳配合的走这里）。 */
    interface Callback {
        /** 迷你条「展开」：请求展开回全屏（重挂回 Activity 视图树，不停播）。 */
        fun onExpandRequested()

        /** 迷你条「关闭」：关闭悬浮窗，回退系统 PiP 兜底路径（方案 3.2 / 阶段 2 验收 3）。 */
        fun onCloseRequested()

        /** 拖拽缩放松手、新尺寸已生效：播放壳应重设 android-surface-size（方案 3.3）。 */
        fun onWindowSizeSettled()

        /** 控制层「选集」：打开选集面板（数据由播放壳组装后经 [showEpisodePanel] 回推）。 */
        fun onEpisodePanelRequested()

        /** 选集面板点选条目：与上一集/下一集同一条原地换片链路（requestEpisode）。 */
        fun onEpisodeSelected(guid: String)

        /** 控制层弹幕开关：播放壳切换后经 [updatePlayerUi] 回推新状态。 */
        fun onDanmakuToggleRequested()
    }

    fun setCallback(callback: Callback?)

    /** 推送迷你条/控制层所需状态（集名跑马灯、播停图标、弹幕开关态、是否有下一集）。 */
    fun updatePlayerUi(state: FloatingPlayerUiState)

    /** 打开选集面板并装载条目（当前集定位与高亮由窗口自处理）。 */
    fun showEpisodePanel(episodes: List<FloatingEpisodeUiItem>)

    /**
     * 把渲染组根视图收进悬浮窗层级（交接的宿主半边，主线程调用）。
     * [freezeFrame] 为 detach 前抓取的定格图（PixelCopy 需有效 surface，必须先抓后摘），
     * 用于盖住新窗口 surface 重挂前的视觉空洞；可为 null。返回 false 表示接入失败
     * ——调用方会撤销交接（abortSurfaceHandoff）并回退系统 PiP（3.3 失败回退）。
     */
    fun attachPlayerSurface(surface: View, freezeFrame: Bitmap?): Boolean

    /**
     * 把渲染组根视图从悬浮窗层级摘出（展开回全屏第一步；窗口此时仍存活），
     * 供调用方装回原视图树后 [removeWindow]。
     */
    fun detachPlayerSurface(surface: View): Boolean

    /** 移除悬浮窗窗口（展开回全屏或关闭小窗）；渲染组在此之前已被取回或释放。 */
    fun removeWindow()
}
