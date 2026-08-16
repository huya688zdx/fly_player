package com.geqian.flyplayer.fly_player

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** 携带图片凭据时允许的重定向边界。 */
object NativeImageRedirectPolicy {
    const val MAX_REDIRECTS = 5

    private val redirectStatuses = setOf(300, 301, 302, 303, 307, 308)

    fun isRedirect(statusCode: Int): Boolean = statusCode in redirectStatuses

    fun resolveSameOrigin(
        currentUrl: String,
        location: String?,
    ): String? {
        val current = currentUrl.toHttpUrlOrNull() ?: return null
        val rawLocation = location?.trim().orEmpty()
        if (rawLocation.isEmpty()) return null
        val target = current.resolve(rawLocation) ?: return null
        if (current.scheme != target.scheme || current.host != target.host || current.port != target.port) {
            return null
        }
        return target.toString()
    }
}
