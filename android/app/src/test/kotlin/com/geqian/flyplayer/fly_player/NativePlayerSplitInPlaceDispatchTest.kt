package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * 分屏副栏进程内换片（dispatchInPlaceLoad）的兜底契约：
 * 本进程没有可用的播放器实例时必须返回 false，让 FlutterHostActivity 的 launch
 * 回退 startActivity 启动路径——否则分屏标志残留（实例已死）时点播放会静默丢片。
 */
class NativePlayerSplitInPlaceDispatchTest {
    private fun setRetained(value: java.lang.ref.WeakReference<NativePlayerActivity>?) {
        NativePlayerActivity::class.java.getDeclaredField("retainedPlayer").apply {
            isAccessible = true
        }.set(null, value)
    }

    @Test fun withoutRetainedPlayerDispatchReportsFalseSoHostFallsBackToStartActivity() {
        setRetained(java.lang.ref.WeakReference(null))
        try {
            assertFalse(NativePlayerActivity.dispatchInPlaceLoad("""{"url":"https://x"}""", null))
        } finally {
            setRetained(java.lang.ref.WeakReference(null))
        }
    }
}
