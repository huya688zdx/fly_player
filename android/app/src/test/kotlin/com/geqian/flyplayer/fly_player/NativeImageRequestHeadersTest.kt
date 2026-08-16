package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Test

class NativeImageRequestHeadersTest {
    @Test
    fun `map and intent flat list preserve access-code headers`() {
        val headers =
            NativeImageRequestHeaders.fromAny(
                mapOf(
                    "Authorization" to "token",
                    "x-access-code" to "encoded-code",
                    "x-access-source" to "app",
                ),
            )

        val restored =
            NativeImageRequestHeaders.fromFlatList(
                NativeImageRequestHeaders.toFlatList(headers),
            )

        assertEquals(headers, restored)
    }

    @Test
    fun `blank hop-by-hop and CRLF-injected entries are discarded`() {
        val headers =
            NativeImageRequestHeaders.fromAny(
                mapOf(
                    "" to "x",
                    "Connection" to "keep-alive",
                    "Host" to "nas.test",
                    "Bad\r\nName" to "x",
                    "X-Bad" to "ok\r\nInjected: yes",
                    "X-Test" to "ok",
                ),
            )

        assertFalse(headers.containsKey(""))
        assertFalse(headers.keys.any { it.equals("Connection", ignoreCase = true) })
        assertFalse(headers.keys.any { it.equals("Host", ignoreCase = true) })
        assertFalse(headers.keys.any { it.equals("X-Bad", ignoreCase = true) })
        assertEquals("ok", headers["X-Test"])
    }

    @Test
    fun `header names are deduplicated case-insensitively`() {
        val headers =
            NativeImageRequestHeaders.fromAny(
                linkedMapOf(
                    "Authorization" to "old",
                    "authorization" to "current",
                ),
            )

        assertEquals(1, headers.size)
        assertEquals("current", headers.values.single())
    }

    @Test
    fun `legacy auth creates the two compatible NAS headers`() {
        assertEquals(
            mapOf(
                "Authorization" to "token",
                "Trim-MC-token" to "token",
            ),
            NativeImageRequestHeaders.legacyAuth(" token "),
        )
        assertEquals(emptyMap<String, String>(), NativeImageRequestHeaders.legacyAuth("  "))
    }

    @Test
    fun `complete headers take priority over legacy auth`() {
        assertEquals(
            mapOf("X-Access-Code" to "encoded"),
            NativeImageRequestHeaders.fromAnyOrLegacy(
                mapOf("X-Access-Code" to "encoded"),
                "legacy-token",
            ),
        )
        assertEquals(
            NativeImageRequestHeaders.legacyAuth("legacy-token"),
            NativeImageRequestHeaders.fromAnyOrLegacy(null, "legacy-token"),
        )
    }

    @Test
    fun `cache fingerprint is stable without exposing raw credentials`() {
        val first =
            NativeImageRequestHeaders.fingerprint(
                linkedMapOf("Authorization" to " secret ", "X-Access-Source" to "app"),
            )
        val equivalent =
            NativeImageRequestHeaders.fingerprint(
                linkedMapOf("x-access-source" to "app", "authorization" to "secret"),
            )
        val changed =
            NativeImageRequestHeaders.fingerprint(
                mapOf("Authorization" to "other", "X-Access-Source" to "app"),
            )

        assertEquals(first, equivalent)
        assertNotEquals(first, changed)
        assertFalse(first.contains("secret"))
    }

    @Test
    fun `cache identity scopes the same image by safe header fingerprint`() {
        val first =
            NativeImageRequestHeaders.cacheIdentity(
                "https://nas.test/poster.jpg",
                mapOf("Authorization" to "secret-a"),
            )
        val changed =
            NativeImageRequestHeaders.cacheIdentity(
                "https://nas.test/poster.jpg",
                mapOf("Authorization" to "secret-b"),
            )

        assertNotEquals(first, changed)
        assertFalse(first.contains("secret-a"))
        assertEquals("", NativeImageRequestHeaders.cacheIdentity("", emptyMap()))
    }

    @Test
    fun `candidate identity stays empty when there is no artwork URL`() {
        assertEquals(
            "",
            NativeImageRequestHeaders.candidateIdentity(
                emptyList(),
                mapOf("Authorization" to "secret"),
            ),
        )
    }
}
