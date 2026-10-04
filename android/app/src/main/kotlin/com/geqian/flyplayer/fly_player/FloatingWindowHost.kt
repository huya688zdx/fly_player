package com.geqian.flyplayer.fly_player

import android.graphics.Bitmap
import android.view.View

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

    /**
     * 把渲染组根视图收进悬浮窗层级（交接的宿主半边，主线程调用）。
     * [freezeFrame] 为 detach 前抓取的定格图（PixelCopy 需有效 surface，必须先抓后摘），
     * 用于盖住新窗口 surface 重挂前的视觉空洞；可为 null。返回 false 表示接入失败
     * ——调用方会撤销交接（abortSurfaceHandoff）并回退系统 PiP（3.3 失败回退）。
     */
    fun attachPlayerSurface(surface: View, freezeFrame: Bitmap?): Boolean

    /** 移除悬浮窗窗口（展开回全屏或关闭小窗）；渲染组在此之前已被取回或释放。 */
    fun removeWindow()
}
