package com.geqian.flyplayer.fly_player.mpv

import java.util.Locale

object MpvLoadfileOptions {
    fun buildCommand(
        url: String,
        headers: Map<String, String>,
        disableTlsVerify: Boolean,
        startPositionMs: Long = 0L,
    ): Array<String> {
        val optionEntries = mutableListOf<String>()
        val userAgent = headers.entries.firstOrNull {
            it.key.equals("User-Agent", ignoreCase = true)
        }?.value?.trim().orEmpty()
        if (userAgent.isNotEmpty()) {
            optionEntries += "user-agent=${quote(userAgent)}"
        }

        val forwardedHeaders = headers.entries
            .filterNot { it.key.equals("User-Agent", ignoreCase = true) }
            .map { "${it.key}: ${it.value}" }
        if (forwardedHeaders.isNotEmpty()) {
            optionEntries += "http-header-fields=${quote(forwardedHeaders.joinToString(","))}"
        }

        if (url.startsWith("https://", ignoreCase = true)) {
            optionEntries += "tls-verify=${if (disableTlsVerify) "no" else "yes"}"
        }
        if (startPositionMs > 0L) {
            val startSeconds = startPositionMs / 1000.0
            optionEntries += "start=${quote(String.format(Locale.US, "%.3f", startSeconds))}"
        }

        return if (optionEntries.isEmpty()) {
            arrayOf(
                "loadfile",
                url,
                "replace",
            )
        } else {
            arrayOf(
                "loadfile",
                url,
                "replace",
                "-1",
                optionEntries.joinToString(","),
            )
        }
    }

    private fun quote(value: String): String {
        return buildString(value.length + 2) {
            append('"')
            value.forEach { char ->
                when (char) {
                    '\\' -> append("\\\\")
                    '"' -> append("\\\"")
                    else -> append(char)
                }
            }
            append('"')
        }
    }
}
