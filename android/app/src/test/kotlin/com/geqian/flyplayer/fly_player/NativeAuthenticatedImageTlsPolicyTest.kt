package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAuthenticatedImageTlsPolicyTest {
    @Test
    fun `authenticated image accepts private and custom HTTPS endpoints`() {
        val allowedUrls =
            listOf(
                "https://192.168.1.9/poster.jpg",
                "https://100.125.130.96:5667/poster.jpg",
                "https://[fd12::1]/poster.jpg",
                "https://device.fnos.net/poster.jpg",
                "https://nas.example.com/poster.jpg",
            )

        allowedUrls.forEach { url ->
            assertTrue(url, NativeAuthenticatedImageTlsPolicy.allowsPrivateCertificate(url))
        }
    }

    @Test
    fun `authenticated image rejects HTTP and invalid URLs`() {
        assertFalse(
            NativeAuthenticatedImageTlsPolicy.allowsPrivateCertificate(
                "http://nas.example.com/poster.jpg",
            ),
        )
        assertFalse(NativeAuthenticatedImageTlsPolicy.allowsPrivateCertificate("not-a-url"))
        assertFalse(NativeAuthenticatedImageTlsPolicy.allowsPrivateCertificate(""))
    }
}
