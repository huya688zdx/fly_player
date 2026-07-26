package com.geqian.flyplayer.fly_player

import android.os.Looper
import java.lang.ref.WeakReference

/**
 * 把「系统媒体会话/通知/PIP/蓝牙线控」产生的播放命令路由回当前活跃的原生播放壳。
 *
 * 与 [PlaybackSessionCoordinator]（服务于旧 Flutter 壳，命令转发进 Flutter）平行，但这里
 * 直达 [NativePlayerActivity]：命令落到 [Handler] 回调，由 Activity 调 playerSurface 执行，
 * 不经 MethodChannel / Flutter。命令统一切回主线程派发。
 */
object NativeMediaCommandCoordinator {

    /** 由 [NativePlayerActivity] 实现并注册；服务/通知/PIP 的命令最终落到这里。 */
    interface Handler {
        fun onMediaPlay()
        fun onMediaPause()
        fun onMediaTogglePlayPause()
        fun onMediaSeekTo(positionMs: Long)
        fun onMediaSeekBy(deltaMs: Long)
        fun onMediaNext()
    }

    const val ACTION_PLAY = "com.geqian.flyplayer.fly_player.media.PLAY"
    const val ACTION_PAUSE = "com.geqian.flyplayer.fly_player.media.PAUSE"
    const val ACTION_TOGGLE = "com.geqian.flyplayer.fly_player.media.TOGGLE"
    const val ACTION_FORWARD = "com.geqian.flyplayer.fly_player.media.FORWARD"
    const val ACTION_REWIND = "com.geqian.flyplayer.fly_player.media.REWIND"
    const val ACTION_NEXT = "com.geqian.flyplayer.fly_player.media.NEXT"

    /** ±10s 快进/快退步长。 */
    const val SEEK_STEP_MS = 10_000L

    private val mainHandler = android.os.Handler(Looper.getMainLooper())

    @Volatile
    private var handlerRef: WeakReference<Handler>? = null

    fun attach(handler: Handler) {
        handlerRef = WeakReference(handler)
    }

    fun detach(handler: Handler) {
        if (handlerRef?.get() === handler) {
            handlerRef = null
        }
    }

    /** 由 action 字符串派发（通知动作 / PIP RemoteAction / 服务 onStartCommand 共用）。 */
    fun dispatchAction(action: String?) {
        val handler = handlerRef?.get() ?: return
        when (action) {
            ACTION_PLAY -> post { handler.onMediaPlay() }
            ACTION_PAUSE -> post { handler.onMediaPause() }
            ACTION_TOGGLE -> post { handler.onMediaTogglePlayPause() }
            ACTION_FORWARD -> post { handler.onMediaSeekBy(SEEK_STEP_MS) }
            ACTION_REWIND -> post { handler.onMediaSeekBy(-SEEK_STEP_MS) }
            ACTION_NEXT -> post { handler.onMediaNext() }
        }
    }

    fun dispatchSeekTo(positionMs: Long) {
        val handler = handlerRef?.get() ?: return
        post { handler.onMediaSeekTo(positionMs.coerceAtLeast(0L)) }
    }

    fun dispatchPlay() = post { handlerRef?.get()?.onMediaPlay() }

    fun dispatchPause() = post { handlerRef?.get()?.onMediaPause() }

    fun dispatchNext() = post { handlerRef?.get()?.onMediaNext() }

    private inline fun post(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }
}
