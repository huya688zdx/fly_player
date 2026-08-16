package com.geqian.flyplayer.fly_player.mpv

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.IOException

class NativeProxyHeaderPolicyTest {
    @Test
    fun `代理保留访问码并丢弃由代理重建或禁止转发的头`() {
        val forwarded = NativeProxyHeaderPolicy.copyForwardable(
            linkedMapOf(
                "x-access-code" to "encoded-code",
                "x-access-source" to "app",
                "X-Custom" to "custom",
                "Authorization" to "old-token",
                "Trim-MC-token" to "old-token",
                "User-Agent" to "old-agent",
                "Range" to "bytes=1-2",
                "Authx" to "stale-sign",
                "Host" to "evil.example",
                "Connection" to "keep-alive",
                "Proxy-Authenticate" to "challenge",
                "Proxy-Authorization" to "credential",
                "Proxy-Connection" to "keep-alive",
            ),
        )

        assertEquals("encoded-code", forwarded["x-access-code"])
        assertEquals("app", forwarded["x-access-source"])
        assertEquals("custom", forwarded["X-Custom"])
        listOf(
            "Authorization",
            "Trim-MC-token",
            "User-Agent",
            "Range",
            "Authx",
            "Host",
            "Connection",
            "Proxy-Authenticate",
            "Proxy-Authorization",
            "Proxy-Connection",
        ).forEach { blocked ->
            assertFalse(forwarded.keys.any { it.equals(blocked, ignoreCase = true) })
        }
    }

    @Test
    fun `非法名称和包含换行的头会被拒绝`() {
        val forwarded = NativeProxyHeaderPolicy.copyForwardable(
            linkedMapOf(
                "Bad Header" to "bad-name",
                "X-Bad\r\nName" to "bad-name-crlf",
                "X-Bad-Value" to "safe\r\nInjected: value",
                "X-Trailing-Newline" to "unsafe\r\n",
                "X-Good" to "safe",
            ),
        )

        assertEquals(mapOf("X-Good" to "safe"), forwarded)
    }

    @Test
    fun `大小写重复头由最后一项覆盖并保留最后键名`() {
        val forwarded = NativeProxyHeaderPolicy.copyForwardable(
            linkedMapOf(
                "X-Access-Code" to "old-code",
                "x-access-code" to "new-code",
                "X-ACCESS-SOURCE" to "old-source",
                "x-access-source" to "app",
            ),
        )

        assertEquals(
            linkedMapOf(
                "x-access-code" to "new-code",
                "x-access-source" to "app",
            ),
            forwarded,
        )
    }

    @Test
    fun `同源重定向保留访问码和Range并按新路径重建Authx`() {
        MockWebServer().use { server ->
            server.enqueue(
                MockResponse()
                    .setResponseCode(302)
                    .setHeader("Location", "/v/media/redirected/video"),
            )
            server.enqueue(MockResponse().setResponseCode(206).setBody("ok"))
            val client = redirectDisabledClient()
            val builtUrls = mutableListOf<String>()

            NativeProxyHeaderPolicy.executeSameOriginRedirects(
                client = client,
                initialUrl = server.url("/v/media/original").toString(),
            ) { redirectedUrl ->
                builtUrls += redirectedUrl
                Request.Builder()
                    .url(redirectedUrl)
                    .headers(
                        buildSignedHeaders(
                            remoteUrl = redirectedUrl,
                            method = "GET",
                            authToken = "fresh-token",
                            userAgent = "FlyPlayer-Test",
                            forwardHeaders = mapOf(
                                "x-access-code" to "encoded-code",
                                "x-access-source" to "app",
                                "Authx" to "stale-sign",
                            ),
                            incomingRange = "bytes=10-20",
                        ),
                    )
                    .build()
            }.use { response ->
                assertEquals(206, response.code)
            }

            val first = server.takeRequest()
            val second = server.takeRequest()
            assertEquals("encoded-code", first.getHeader("x-access-code"))
            assertEquals("encoded-code", second.getHeader("x-access-code"))
            assertEquals("app", second.getHeader("x-access-source"))
            assertEquals("bytes=10-20", second.getHeader("Range"))
            assertEquals("fresh-token", second.getHeader("Authorization"))
            assertFalse(second.getHeader("Authx").isNullOrBlank())
            assertNotEquals("stale-sign", second.getHeader("Authx"))
            assertEquals(
                listOf(
                    server.url("/v/media/original").toString(),
                    server.url("/v/media/redirected/video").toString(),
                ),
                builtUrls,
            )
        }
    }

    @Test
    fun `跨源重定向被拒绝且目标服务器收不到请求`() {
        MockWebServer().use { source ->
            MockWebServer().use { target ->
                source.enqueue(
                    MockResponse()
                        .setResponseCode(302)
                        .setHeader("Location", target.url("/leak")),
                )
                target.enqueue(MockResponse().setResponseCode(200).setBody("leaked"))
                val client = redirectDisabledClient()

                assertThrows(IOException::class.java) {
                    NativeProxyHeaderPolicy.executeSameOriginRedirects(
                        client = client,
                        initialUrl = source.url("/protected").toString(),
                    ) { redirectedUrl ->
                        Request.Builder()
                            .url(redirectedUrl)
                            .header("x-access-code", "encoded-code")
                            .build()
                    }
                }

                assertEquals(1, source.requestCount)
                assertEquals(0, target.requestCount)
            }
        }
    }

    @Test
    fun `超过最大同源重定向次数后停止请求`() {
        MockWebServer().use { server ->
            repeat(6) { index ->
                server.enqueue(
                    MockResponse()
                        .setResponseCode(302)
                        .setHeader("Location", "/hop-${index + 1}"),
                )
            }

            assertThrows(IOException::class.java) {
                NativeProxyHeaderPolicy.executeSameOriginRedirects(
                    client = redirectDisabledClient(),
                    initialUrl = server.url("/hop-0").toString(),
                ) { redirectedUrl ->
                    Request.Builder().url(redirectedUrl).build()
                }
            }

            assertEquals(6, server.requestCount)
        }
    }

    private fun redirectDisabledClient(): OkHttpClient =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .build()
}
