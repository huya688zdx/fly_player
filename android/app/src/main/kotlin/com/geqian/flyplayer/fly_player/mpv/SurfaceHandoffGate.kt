package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock

/**
 * Surface 交接闸门——悬浮小窗方案 3.3 必要改造 A/B 的状态核。
 *
 * 渲染组 reparent（进悬浮窗/展开回全屏）期间，View 层必然经历一次 surface destroy；
 * 闸门武装（[begin]）到新窗口 surface 重挂完成（[end]）之间：
 *  - mpv 播放线程的 destroy 处理走 detach-only 旁路：不 seek 回写、不 pause、不
 *    `vid=no`、不 `sessionGate.onSurfaceLost`（改造 A，缺它交接必断播）；
 *  - TextureView 的 `onSurfaceTextureDestroyed` 返回 false 且不释放纹理，由
 *    NativePlayerSurface 自持 SurfaceTexture 零黑帧迁移（改造 B，真机验证项）。
 *
 * 线程模型：[begin] 由编排方在主线程调用；[end] 必须经
 * [MpvPlaybackController.onVideoOutputSurfaceAvailable] 在 mpv 播放线程上调用——
 * 排队在播放线程的 destroy 旁路先于 available 处理，此后关闸才不会漏掉迟到的
 * destroy。`active` 用 @Volatile 保证跨线程可见。
 */
class SurfaceHandoffGate(
    private val nowMs: () -> Long = { SystemClock.uptimeMillis() },
) {
    /** 是否处于交接窗口内（destroy 旁路与纹理保活的共同判定位）。 */
    @Volatile
    var active: Boolean = false
        private set

    /** 本次交接起始时间戳（P3 观测：detach handoff 生效时刻）；0 = 未在交接。 */
    @Volatile
    var handoffStartUptimeMs: Long = 0L
        private set

    /** 最近一次交接 detach → 重挂的耗时（P3 观测样本，方案 5.1 预算 <200ms）；-1 = 无样本。 */
    @Volatile
    var lastHandoffElapsedMs: Long = -1L
        private set

    /** 武装交接闸门。幂等：重复 begin 不翻转、不刷新起始时间戳。返回 true = 状态翻转。 */
    fun begin(): Boolean {
        if (active) return false
        active = true
        handoffStartUptimeMs = nowMs()
        return true
    }

    /** 收口交接闸门并记录 P3 耗时样本。幂等。返回 true = 状态翻转。 */
    fun end(): Boolean {
        if (!active) return false
        val startedAt = handoffStartUptimeMs
        if (startedAt > 0L) {
            (nowMs() - startedAt).takeIf { it >= 0L }?.let { lastHandoffElapsedMs = it }
        }
        active = false
        handoffStartUptimeMs = 0L
        return true
    }
}
