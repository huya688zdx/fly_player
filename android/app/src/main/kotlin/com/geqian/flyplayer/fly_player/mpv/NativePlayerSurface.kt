package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.view.Surface
import android.view.View
import android.widget.FrameLayout

/**
 * 纯原生播放视图：把 [MpvPlayerView] 的播放组装（mpv 内核 + SurfaceView 视频 +
 * 原生弹幕）从 Flutter PlatformView 里抽出来，做成一个可被普通 Activity 直接持有的
 * [FrameLayout]，**不依赖 Flutter messenger / MethodChannel / PlatformView**。
 *
 * 渐进原生化阶段 1 的基石：视频(SurfaceView) + 弹幕(原生 Canvas) + 控制层(Activity 叠加)
 * 三者同在原生 View 层级，由系统 SurfaceFlinger 正常合成，没有 Flutter overlay 的
 * Hybrid Composition —— 弹幕可 120fps 丝滑、控制/二级界面也不卡。
 *
 * 这层只负责"渲染 + 把控制透传给 [MpvPlaybackController]"，不做 source 解析、
 * 不做弹幕拉取（那些仍由 Flutter 编排层产出后通过 Activity 喂进来）。
 */
class NativePlayerSurface(
    context: Context,
    creationParams: Map<String, Any?>,
    private val onStateChanged: (MpvPlayerState) -> Unit = {},
    private val onOcclusionChanged: (DanmakuDynamicOcclusionState) -> Unit = {},
) : FrameLayout(context), VideoOutputTarget.Listener {

    private companion object {
        const val DEFAULT_DANMAKU_TARGET_FPS = 120
        const val MIN_DANMAKU_TARGET_FPS = 24
        const val MAX_DANMAKU_TARGET_FPS = 120
    }

    private val mpv: MpvFacade = DefaultMpvFacade

    // 原生播放壳固定走 SurfaceView：视频经 SurfaceFlinger 独立硬件层合成，不与任何
    // Flutter/原生 UI 抢 GPU。这正是"分开"的关键，也是本方案存在的理由。
    private val videoOutputTarget: VideoOutputTarget = SurfaceViewVideoOutputTarget(context)

    private val danmakuOverlay = NativeDanmakuOverlayView(context)

    @Volatile
    private var released = false

    private var latestState = MpvPlayerState(
        nativeLibLoaded = mpv.isAvailable(),
        statusText = if (mpv.isAvailable()) {
            "mpv-android runtime detected"
        } else {
            "mpv-android native runtime missing"
        },
        error = mpv.loadErrorMessage(),
    )
    private var latestOcclusionState = DanmakuDynamicOcclusionState.disabled()
    private var requestedDanmakuFrameRateHz = DEFAULT_DANMAKU_TARGET_FPS

    private val controller = MpvPlaybackController(
        context = context,
        videoOutputTarget = videoOutputTarget,
        creationParams = creationParams,
        stateListener = MpvPlaybackStateListener { state, _ ->
            latestState = state
            danmakuOverlay.updatePlaybackState(state)
            onStateChanged(state)
        },
        danmakuOcclusionStateListener = { next, runtimeMaskBitmap ->
            latestOcclusionState = next
            danmakuOverlay.setOcclusionState(next, runtimeMaskBitmap)
            onOcclusionChanged(next)
        },
    )

    init {
        setBackgroundColor(Color.BLACK)
        videoOutputTarget.setListener(this)
        addView(
            videoOutputTarget.view,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            danmakuOverlay,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        applyDanmakuFrameRateVote(requestedDanmakuFrameRateHz, reason = "init")
    }

    // ---- VideoOutputTarget.Listener：surface 生命周期透传给 controller ----

    override fun onSurfaceAvailable(surface: Surface, generation: Long, width: Int, height: Int) {
        if (released) return
        applyDanmakuFrameRateVote(requestedDanmakuFrameRateHz, reason = "surfaceAvailable")
        controller.onVideoOutputSurfaceAvailable(
            surface = surface,
            generation = generation,
            width = width,
            height = height,
        )
    }

    override fun onSurfaceSizeChanged(surface: Surface, generation: Long, width: Int, height: Int) {
        if (released) return
        controller.onVideoOutputSurfaceSizeChanged(
            surface = surface,
            generation = generation,
            width = width,
            height = height,
        )
    }

    override fun onSurfaceDestroyed(generation: Long) {
        if (released) return
        controller.onVideoOutputSurfaceDestroyed(generation)
    }

    // ---- 播放控制（透传给 controller，无 Flutter channel） ----

    fun load(args: Map<String, Any?>) {
        if (released) return
        controller.load(args)
    }

    fun play() {
        if (released) return
        controller.play()
    }

    fun pause() {
        if (released) return
        controller.pause()
    }

    fun seek(positionMs: Long) {
        if (released) return
        controller.seek(positionMs)
        danmakuOverlay.hintSeek(positionMs)
    }

    fun setSpeed(speed: Double?) {
        if (released) return
        controller.setSpeed(speed)
    }

    /** 临时设输出音量（0~100，音频焦点 duck 用），透传 controller。 */
    fun setPlaybackVolume(volume: Double) {
        if (released) return
        controller.setPlaybackVolume(volume)
    }

    /** 读当前输出音量（duck 前缓存原值）。 */
    fun getPlaybackVolume(): Double {
        if (released) return 100.0
        return controller.getPlaybackVolume()
    }

    /** 解码/输出诊断快照（hwdec/色彩管线/直通/丢帧/帧率），供轨道信息页排查。 */
    fun getPlaybackDiagnostics(): Map<String, Any?> {
        if (released) return emptyMap()
        return controller.getPlaybackDiagnostics()
    }

    fun setAudioTrack(trackIndex: Int?, trackGuid: String?) {
        if (released) return
        controller.setAudioTrack(trackIndex = trackIndex, trackGuid = trackGuid)
    }

    fun setSubtitleTrack(trackIndex: Int?, trackGuid: String?) {
        if (released) return
        controller.setSubtitleTrack(trackIndex = trackIndex, trackGuid = trackGuid)
    }

    /** 外挂字幕：通过 sub-add 加载本地文件并选中（内置字幕走 setSubtitleTrack）。 */
    fun setExternalSubtitleFile(path: String) {
        if (released) return
        controller.setExternalSubtitleFile(path)
    }

    // ---- 字幕/音频微调（透传 controller，供设置抽屉子页调用） ----

    fun setSubtitleDelay(delaySeconds: Double?) {
        if (released) return
        controller.setSubtitleDelay(delaySeconds)
    }

    fun setAudioDelay(delaySeconds: Double?) {
        if (released) return
        controller.setAudioDelay(delaySeconds)
    }

    fun setSubtitlePosition(position: Int?) {
        if (released) return
        controller.setSubtitlePosition(position)
    }

    fun setSubtitleScale(scale: Double?) {
        if (released) return
        controller.setSubtitleScale(scale)
    }

    fun resetSubtitleStyle() {
        if (released) return
        controller.resetSubtitleStyle()
    }

    // ---- 画面/解码/高级 mpv（透传 controller） ----

    fun setVideoAdjustments(args: Map<String, Any?>) {
        if (released) return
        controller.setVideoAdjustments(args)
    }

    fun setDecoderMode(mode: String?) {
        if (released) return
        controller.setDecoderMode(mode)
    }

    fun setDisplayAspectRatioMode(mode: String?) {
        if (released) return
        controller.setDisplayAspectRatioMode(mode)
    }

    fun setMpvAdvancedSettings(args: Map<String, Any?>) {
        if (released) return
        controller.setMpvAdvancedSettings(args)
    }

    /** 听视频（仅音频）模式开关。返回 controller 给出的 {success,enabled,message}。 */
    fun setListenVideoMode(enabled: Boolean): Map<String, Any?> {
        if (released) return emptyMap()
        return controller.setListenVideoMode(enabled)
    }

    /** 熄屏继续播放音频开关（全局设置），透传 controller。 */
    fun setKeepAudioWhenScreenOff(enabled: Boolean) {
        if (released) return
        controller.setKeepAudioWhenScreenOff(enabled)
    }

    fun getChapters(): List<Map<String, Any?>> {
        if (released) return emptyList()
        return controller.getChapters()
    }

    fun captureFrame(args: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        if (released) return emptyMap()
        return controller.captureFrame(args)
    }

    /**
     * 截当前视频帧用作"定格图"（分屏/全屏切换时盖住 SurfaceView 重排的黑闪）。
     * 异步（PixelCopy），回调可能在非 UI 线程，调用方自行切回 UI 线程。不支持/无效时回 null。
     */
    fun captureFreezeFrame(onResult: (Bitmap?) -> Unit) {
        if (released) {
            onResult(null)
            return
        }
        val w = videoOutputTarget.view.width
        val h = videoOutputTarget.view.height
        if (w <= 0 || h <= 0) {
            onResult(null)
            return
        }
        val requestId =
            videoOutputTarget.requestBitmapCapture(w, h, 1.0f) { frame -> onResult(frame?.bitmap) }
        if (requestId == null) onResult(null)
    }

    val state: MpvPlayerState
        get() = latestState

    val occlusionState: DanmakuDynamicOcclusionState
        get() = latestOcclusionState

    // ---- 弹幕（数据由 Flutter 编排层产出后喂进来，格式同 NativeDanmakuOverlayView） ----

    fun setDanmakuPayload(payload: Map<String, Any?>) {
        if (released) return
        applyDanmakuFrameRateVote(
            parseDanmakuTargetFrameRateHz(payload),
            reason = "payload",
        )
        danmakuOverlay.setPayload(payload)
    }

    fun setDanmakuOcclusion(payload: Map<String, Any?>) {
        if (released) return
        danmakuOverlay.setOcclusionState(payload)
    }

    fun clearDanmaku() {
        if (released) return
        applyDanmakuFrameRateVote(DEFAULT_DANMAKU_TARGET_FPS, reason = "clear")
        danmakuOverlay.clear()
    }

    fun setDanmakuVisible(visible: Boolean) {
        if (released) return
        danmakuOverlay.visibility = if (visible) View.VISIBLE else View.GONE
    }

    /**
     * 仅更新弹幕显示设置（不带 comments，[NativeDanmakuOverlayView.applyPayload] 会保留已有
     * 弹幕列表只重排时间线）。调用方须传**完整** settings（含 enabled / sourceKey），否则
     * 缺省值会把弹幕关掉或触发时间线复位。
     */
    fun setDanmakuSettings(settings: Map<String, Any?>) {
        if (released) return
        applyDanmakuFrameRateVote(parseDanmakuTargetFrameRateHz(settings), reason = "settings")
        danmakuOverlay.setPayload(settings)
    }

    /** AI 动态遮罩配置（采样间隔/输入宽/帧率/开关），透传给 controller。 */
    fun setDanmakuOcclusionConfig(args: Map<String, Any?>) {
        if (released) return
        controller.setDanmakuOcclusionConfig(args)
    }

    fun screenshot() {
        if (released) return
        // 发送 mpv 指令截图。具体保存路径由 mpv 配置或默认。
        // app 通常通过 MpvCaptureExportController 处理截图后续（保存到相册等）。
        // 这里简单触发原生 mpv 截图命令。
        mpv.command(arrayOf("screenshot"))
    }

    // ---- 释放 ----

    fun release() {
        if (released) return
        released = true
        videoOutputTarget.setListener(null)
        // Surface 必须比 mpv 的 detach/stop 活得久：先 controller.dispose（同步），
        // 再释放弹幕与视频输出，否则会撞下次播放的崩溃（见 MpvPlayerView.dispose 注释）。
        controller.disposeBlocking()
        danmakuOverlay.release()
        videoOutputTarget.release()
    }

    // ---- 帧率投票（让视频/弹幕跑满目标帧率） ----

    private fun parseDanmakuTargetFrameRateHz(payload: Map<String, Any?>): Int {
        val raw = (payload["targetFrameRateHz"] as? Number)?.toInt()
            ?: DEFAULT_DANMAKU_TARGET_FPS
        return raw.coerceIn(MIN_DANMAKU_TARGET_FPS, MAX_DANMAKU_TARGET_FPS)
    }

    private fun applyDanmakuFrameRateVote(targetFrameRateHz: Int, reason: String) {
        val clamped = targetFrameRateHz.coerceIn(MIN_DANMAKU_TARGET_FPS, MAX_DANMAKU_TARGET_FPS)
        requestedDanmakuFrameRateHz = clamped
        if (Build.VERSION.SDK_INT >= 35) {
            setRequestedFrameRate(clamped.toFloat())
            videoOutputTarget.view.setRequestedFrameRate(clamped.toFloat())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            videoOutputTarget.currentSurface()
                ?.takeIf { it.isValid }
                ?.setFrameRate(
                    clamped.toFloat(),
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                )
        }
    }
}
