package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock
import android.util.Log

private const val MAX_CHAPTER_COUNT = 10000
private const val CHAPTER_LOG_THROTTLE_MS = 30000L

internal class MpvChapterSnapshotBuilder(
    private val tag: String,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private var lastSuspiciousChapterLogMs = 0L

    fun buildChapterList(): List<Map<String, Any?>> {
        if (!mpv.isAvailable()) return emptyList()
        val reportedCount = resolveChapterCount()
        if (reportedCount <= 0) return emptyList()
        val chapters = mutableListOf<Map<String, Any?>>()
        for (index in 0 until reportedCount) {
            val timeSeconds = safeGetChapterTime(index)
            if (timeSeconds == null) {
                if (chapters.isNotEmpty()) {
                    break
                }
                continue
            }
            val title = safeGetChapterTitle(index)
            chapters += mapOf(
                "index" to index,
                "title" to title,
                "timeMs" to (timeSeconds * 1000.0).toLong(),
            )
        }
        return chapters
    }

    private fun resolveChapterCount(): Int {
        val primary = safeGetChapterCount("chapter-list/count")
        if (primary in 1..MAX_CHAPTER_COUNT) {
            return primary
        }
        val secondary = safeGetChapterCount("chapters")
        if (secondary in 1..MAX_CHAPTER_COUNT) {
            return secondary
        }
        val suspiciousCount = maxOf(primary, secondary)
        if (suspiciousCount <= 0) return 0
        if (suspiciousCount > MAX_CHAPTER_COUNT) {
            if (shouldLogSuspiciousChapterCount()) {
                Log.w(tag, "chapter-debug ignoring suspicious chapter count=$suspiciousCount")
            }
            return probeChapterCountFallback()
        }
        return suspiciousCount
    }

    private fun probeChapterCountFallback(): Int {
        var discovered = 0
        for (index in 0 until 256) {
            val timeSeconds = safeGetChapterTime(index)
            if (timeSeconds == null) {
                if (index == 0) {
                    break
                }
                if (discovered > 0) break
                continue
            }
            discovered = index + 1
        }
        if (discovered > 0 && shouldLogSuspiciousChapterCount()) {
            Log.w(tag, "chapter-debug fallback chapter probe count=$discovered")
        }
        return discovered
    }

    private fun shouldLogSuspiciousChapterCount(): Boolean {
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastSuspiciousChapterLogMs < CHAPTER_LOG_THROTTLE_MS) return false
        lastSuspiciousChapterLogMs = nowMs
        return true
    }

    private fun safeGetChapterCount(property: String): Int {
        val value = runCatching { mpv.getPropertyInt(property) }.getOrDefault(0L)
        if (value <= 0L) return 0
        return value.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    private fun safeGetChapterTime(index: Int): Double? {
        val timeProperty = "chapter-list/$index/time"
        val stringValue =
            runCatching { mpv.getPropertyString(timeProperty) }
                .getOrNull()
                ?.trim()
                ?.takeIf { it.isNotEmpty() && it != "-" }
                ?: return null
        return parseMpvTimeString(stringValue)
    }

    private fun safeGetChapterTitle(index: Int): String {
        return safeGetPropertyString("chapter-list/$index/title")
            ?: safeGetPropertyString("chapter-list/$index/name")
            ?: ""
    }

    private fun safeGetPropertyString(property: String): String? {
        return runCatching { mpv.getPropertyString(property) }
            .getOrNull()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun parseMpvTimeString(value: String?): Double? {
        val text = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        text.toDoubleOrNull()?.let { return it }
        val parts = text.split(":")
        if (parts.isEmpty()) return null
        return when (parts.size) {
            3 -> {
                val hours = parts[0].toDoubleOrNull() ?: return null
                val minutes = parts[1].toDoubleOrNull() ?: return null
                val seconds = parts[2].toDoubleOrNull() ?: return null
                (hours * 3600.0) + (minutes * 60.0) + seconds
            }
            2 -> {
                val minutes = parts[0].toDoubleOrNull() ?: return null
                val seconds = parts[1].toDoubleOrNull() ?: return null
                (minutes * 60.0) + seconds
            }
            else -> null
        }
    }
}
