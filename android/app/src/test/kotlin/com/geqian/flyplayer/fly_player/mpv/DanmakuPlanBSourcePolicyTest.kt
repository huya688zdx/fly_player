package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DanmakuPlanBSourcePolicyTest {
    @Test
    fun `本地文件路径转换为可解码路径`() {
        assertEquals(
            "/storage/emulated/0/video.mp4",
            DanmakuPlanBSourcePolicy.resolve(
                url = "file:///storage/emulated/0/video.mp4",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            )?.url,
        )
        assertEquals(
            "/storage/emulated/0/video.mp4",
            DanmakuPlanBSourcePolicy.resolve(
                url = "/storage/emulated/0/video.mp4",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            )?.url,
        )
    }

    @Test
    fun `环回代理保留完整查询参数和请求头`() {
        val url = "http://127.0.0.1:39271/media/session?id=1&token=a%2Bb"
        val headers = mapOf("Cookie" to "entry-token=secret")

        val source =
            DanmakuPlanBSourcePolicy.resolve(
                url = url,
                headers = headers,
                networkEnabled = true,
                failedUrl = null,
            )

        assertEquals(url, source?.url)
        assertEquals(headers, source?.headers)
        assertTrue(source?.isNetworkProxy == true)
    }

    @Test
    fun `localhost 代理可用但伪装主机和远端地址不可用`() {
        assertTrue(
            DanmakuPlanBSourcePolicy.resolve(
                url = "http://localhost:8443/video",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            ) != null,
        )
        assertNull(
            DanmakuPlanBSourcePolicy.resolve(
                url = "http://localhost.evil.example/video",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            ),
        )
        assertNull(
            DanmakuPlanBSourcePolicy.resolve(
                url = "https://localhost:8443/video",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            ),
        )
        assertNull(
            DanmakuPlanBSourcePolicy.resolve(
                url = "https://nas.example/video",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = null,
            ),
        )
    }

    @Test
    fun `网络开关关闭只禁用代理源`() {
        assertNull(
            DanmakuPlanBSourcePolicy.resolve(
                url = "http://127.0.0.1:39271/video",
                headers = emptyMap(),
                networkEnabled = false,
                failedUrl = null,
            ),
        )
        assertFalse(
            DanmakuPlanBSourcePolicy.resolve(
                url = "/storage/emulated/0/video.mp4",
                headers = emptyMap(),
                networkEnabled = false,
                failedUrl = null,
            ) == null,
        )
    }

    @Test
    fun `当前源失败后熔断但换源可重新尝试`() {
        val failed = "http://127.0.0.1:39271/media/first"

        assertNull(
            DanmakuPlanBSourcePolicy.resolve(
                url = failed,
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = failed,
            ),
        )
        assertTrue(
            DanmakuPlanBSourcePolicy.resolve(
                url = "http://127.0.0.1:39271/media/second",
                headers = emptyMap(),
                networkEnabled = true,
                failedUrl = failed,
            ) != null,
        )
    }
}
