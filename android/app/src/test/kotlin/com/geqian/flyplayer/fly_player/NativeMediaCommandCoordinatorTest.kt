package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 媒体命令总线的 action 路由表：通知/PIP/蓝牙线控共用的 action 字符串必须精确落到对应
 * [NativeMediaCommandCoordinator.Handler] 回调。重点锁两条语义：
 *  - ±10s（ACTION_FORWARD/REWIND）是通知/线控的既有语义，不得漂移；
 *  - ±15s（ACTION_SEEK_BACK_15S/FWD_15S）只服务 PiP 五键（悬浮小窗方案阶段 1）。
 * JVM 桩下 Looper.myLooper()/getMainLooper() 均返回 null，post 走同步分支，可直接断言。
 */
class NativeMediaCommandCoordinatorTest {

    private class RecordingHandler : NativeMediaCommandCoordinator.Handler {
        val calls = mutableListOf<String>()
        var lastSeekDeltaMs: Long = Long.MIN_VALUE

        override fun onMediaPlay() {
            calls += "play"
        }

        override fun onMediaPause() {
            calls += "pause"
        }

        override fun onMediaTogglePlayPause() {
            calls += "togglePlayPause"
        }

        override fun onMediaSeekTo(positionMs: Long) {
            calls += "seekTo"
        }

        override fun onMediaSeekBy(deltaMs: Long) {
            calls += "seekBy"
            lastSeekDeltaMs = deltaMs
        }

        override fun onMediaNext() {
            calls += "next"
        }

        override fun onMediaPrevious() {
            calls += "previous"
        }
    }

    /** attach → dispatch → detach，返回回调记录；隔离单例状态，避免用例间串扰。 */
    private fun dispatch(action: String?): RecordingHandler {
        val handler = RecordingHandler()
        NativeMediaCommandCoordinator.attach(handler)
        try {
            NativeMediaCommandCoordinator.dispatchAction(action)
        } finally {
            NativeMediaCommandCoordinator.detach(handler)
        }
        return handler
    }

    @Test
    fun playPauseToggleRouteToCorrespondingCallbacks() {
        assertEquals(listOf("play"), dispatch(NativeMediaCommandCoordinator.ACTION_PLAY).calls)
        assertEquals(listOf("pause"), dispatch(NativeMediaCommandCoordinator.ACTION_PAUSE).calls)
        assertEquals(
            listOf("togglePlayPause"),
            dispatch(NativeMediaCommandCoordinator.ACTION_TOGGLE).calls,
        )
    }

    @Test
    fun notificationSeekActionsKeepTenSecondStep() {
        val forward = dispatch(NativeMediaCommandCoordinator.ACTION_FORWARD)
        assertEquals(listOf("seekBy"), forward.calls)
        assertEquals(NativeMediaCommandCoordinator.SEEK_STEP_MS, forward.lastSeekDeltaMs)

        val rewind = dispatch(NativeMediaCommandCoordinator.ACTION_REWIND)
        assertEquals(listOf("seekBy"), rewind.calls)
        assertEquals(-NativeMediaCommandCoordinator.SEEK_STEP_MS, rewind.lastSeekDeltaMs)
    }

    @Test
    fun pipFifteenSecondActionsSeekByFifteenSeconds() {
        val back = dispatch(NativeMediaCommandCoordinator.ACTION_SEEK_BACK_15S)
        assertEquals(listOf("seekBy"), back.calls)
        assertEquals(-NativeMediaCommandCoordinator.PIP_SEEK_STEP_MS, back.lastSeekDeltaMs)

        val forward = dispatch(NativeMediaCommandCoordinator.ACTION_SEEK_FWD_15S)
        assertEquals(listOf("seekBy"), forward.calls)
        assertEquals(NativeMediaCommandCoordinator.PIP_SEEK_STEP_MS, forward.lastSeekDeltaMs)
    }

    @Test
    fun episodeSwitchActionsRouteToNextAndPrevious() {
        assertEquals(listOf("next"), dispatch(NativeMediaCommandCoordinator.ACTION_NEXT).calls)
        assertEquals(listOf("previous"), dispatch(NativeMediaCommandCoordinator.ACTION_PREVIOUS).calls)
    }

    @Test
    fun unknownOrNullActionIsIgnored() {
        assertTrue(dispatch("com.geqian.flyplayer.fly_player.media.UNKNOWN").calls.isEmpty())
        assertTrue(dispatch(null).calls.isEmpty())
    }

    @Test
    fun missingHandlerIsIgnored() {
        // 未 attach（或已 detach）时不派发：迟到的通知/PIP 命令不能打到已销毁的壳上。
        val handler = RecordingHandler()
        NativeMediaCommandCoordinator.dispatchAction(NativeMediaCommandCoordinator.ACTION_PLAY)
        assertTrue(handler.calls.isEmpty())
    }
}
