package com.geqian.flyplayer.fly_player

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NativeImageRedirectPolicyTest {
    @Test
    fun `relative and absolute same-origin redirects are accepted`() {
        assertEquals(
            "https://nas.test:5666/final.jpg",
            NativeImageRedirectPolicy.resolveSameOrigin(
                currentUrl = "https://nas.test:5666/path/start.jpg",
                location = "/final.jpg",
            ),
        )
        assertEquals(
            "https://nas.test:5666/final.jpg",
            NativeImageRedirectPolicy.resolveSameOrigin(
                currentUrl = "https://nas.test:5666/path/start.jpg",
                location = "https://NAS.TEST:5666/final.jpg",
            ),
        )
    }

    @Test
    fun `cross scheme host and effective port redirects are rejected`() {
        for (
            location in
                listOf(
                    "http://nas.test:5666/final.jpg",
                    "https://cdn.test:5666/final.jpg",
                    "https://nas.test:443/final.jpg",
                )
        ) {
            assertNull(
                NativeImageRedirectPolicy.resolveSameOrigin(
                    currentUrl = "https://nas.test:5666/start.jpg",
                    location = location,
                ),
            )
        }
        assertEquals(
            "https://nas.test/final.jpg",
            NativeImageRedirectPolicy.resolveSameOrigin(
                currentUrl = "https://nas.test:443/start.jpg",
                location = "https://nas.test/final.jpg",
            ),
        )
    }

    @Test
    fun `sensitive fetch follows relative same-origin redirect with headers`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/final"))
            server.enqueue(MockResponse().setBody("image-bytes"))

            val bytes =
                NativeSafeImageHttp.fetchBytes(
                    server.url("/start").toString(),
                    mapOf("x-access-code" to "encoded-code", "x-access-source" to "app"),
                )

            assertArrayEquals("image-bytes".toByteArray(), bytes)
            assertEquals("encoded-code", server.takeRequest().getHeader("x-access-code"))
            assertEquals("encoded-code", server.takeRequest().getHeader("x-access-code"))
        }
    }

    @Test
    fun `sensitive fetch blocks cross-origin redirect before credentials can escape`() {
        MockWebServer().use { source ->
            MockWebServer().use { target ->
                source.enqueue(
                    MockResponse()
                        .setResponseCode(302)
                        .addHeader("Location", target.url("/stolen").toString()),
                )

                val bytes =
                    NativeSafeImageHttp.fetchBytes(
                        source.url("/start").toString(),
                        mapOf("x-access-code" to "encoded-code", "Authorization" to "token"),
                    )

                assertNull(bytes)
                assertEquals("encoded-code", source.takeRequest().getHeader("x-access-code"))
                assertEquals(0, target.requestCount)
            }
        }
    }

    @Test
    fun `image response larger than configured limit is rejected`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("01234567890"))

            val bytes =
                NativeSafeImageHttp.fetchBytes(
                    server.url("/large").toString(),
                    mapOf("x-access-code" to "encoded-code"),
                    maxBytes = 10,
                )

            assertNull(bytes)
        }
    }

    @Test
    fun `cancelling an image session cancels the active HTTP call`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val session =
                NativeSafeImageHttp.newSession(
                    server.url("/slow").toString(),
                    mapOf("x-access-code" to "encoded-code"),
                )
            val executor = Executors.newSingleThreadExecutor()
            try {
                val result = executor.submit<ByteArray?> {
                    runCatching { session.fetchBytes() }.getOrNull()
                }
                assertNotNull(server.takeRequest(2, TimeUnit.SECONDS))

                session.cancel()

                assertNull(result.get(2, TimeUnit.SECONDS))
            } finally {
                executor.shutdownNow()
            }
        }
    }
}
