package com.geqian.flyplayer.fly_player

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** 携带 NAS 鉴权头的 HTTPS 图片兼容私有、自签名证书和自定义域名。 */
object NativeAuthenticatedImageTlsPolicy {
    fun allowsPrivateCertificate(rawUrl: String): Boolean {
        val url = rawUrl.trim().toHttpUrlOrNull() ?: return false
        return url.isHttps
    }
}
