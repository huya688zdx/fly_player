package com.geqian.flyplayer.fly_player

import java.security.SecureRandom
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** 原生图片请求头的安全解析、Intent 扁平化与旧版 token 兼容策略。 */
object NativeImageRequestHeaders {
    private val fingerprintKey = ByteArray(32).also(SecureRandom()::nextBytes)
    private val blocked =
        setOf(
            "connection",
            "host",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "proxy-connection",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        )
    private val validName = Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")

    fun fromAny(raw: Any?): Map<String, String> {
        val source = raw as? Map<*, *> ?: return emptyMap()
        val parsed = linkedMapOf<String, String>()
        source.forEach { (rawKey, rawValue) ->
            val key = rawKey?.toString()?.trim().orEmpty()
            val value = rawValue?.toString()?.trim().orEmpty()
            val normalizedKey = key.lowercase(Locale.US)
            if (
                key.isEmpty() ||
                value.isEmpty() ||
                !validName.matches(key) ||
                '\r' in value ||
                '\n' in value ||
                normalizedKey in blocked
            ) {
                return@forEach
            }
            parsed.keys.firstOrNull { it.equals(key, ignoreCase = true) }?.let(parsed::remove)
            parsed[key] = value
        }
        return parsed
    }

    fun fromAnyOrLegacy(
        raw: Any?,
        legacyToken: String,
    ): Map<String, String> = fromAny(raw).takeIf { it.isNotEmpty() } ?: legacyAuth(legacyToken)

    fun toFlatList(headers: Map<String, String>): ArrayList<String> =
        ArrayList<String>().apply {
            fromAny(headers).forEach { (key, value) ->
                add(key)
                add(value)
            }
        }

    fun fromFlatList(values: List<String>?): Map<String, String> {
        if (values.isNullOrEmpty()) return emptyMap()
        val pairs = linkedMapOf<String, String>()
        var index = 0
        while (index + 1 < values.size) {
            pairs[values[index]] = values[index + 1]
            index += 2
        }
        return fromAny(pairs)
    }

    fun legacyAuth(token: String): Map<String, String> {
        val normalized = token.trim()
        if (normalized.isEmpty()) return emptyMap()
        return mapOf(
            "Authorization" to normalized,
            "Trim-MC-token" to normalized,
        )
    }

    /** 仅返回规范请求头的摘要，供内存缓存键使用，不暴露原始凭据。 */
    fun fingerprint(headers: Map<String, String>): String {
        val canonical =
            fromAny(headers)
                .entries
                .map { it.key.lowercase(Locale.US) to it.value.trim() }
                .sortedBy { it.first }
                .joinToString("\n") { (key, value) -> "$key:$value" }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(fingerprintKey, "HmacSHA256"))
        return mac
            .doFinal(canonical.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    fun cacheIdentity(
        normalizedImageIdentity: String,
        headers: Map<String, String>,
    ): String {
        if (normalizedImageIdentity.isEmpty()) return ""
        return "$normalizedImageIdentity|${fingerprint(headers)}"
    }

    fun candidateIdentity(
        urls: List<String>,
        headers: Map<String, String>,
    ): String {
        if (urls.isEmpty()) return ""
        return "${urls.joinToString(separator = "|")}|${fingerprint(headers)}"
    }
}
