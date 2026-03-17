package com.geqian.flyplayer.fly_player.mpv

import android.os.Process
import android.os.SystemClock
import java.io.File
import java.util.Locale

data class PlaybackPerformanceSnapshot(
    val cpuUsagePercent: Double?,
    val gpuUsagePercent: Double?,
    val estimatedVfFps: Double?,
    val containerFps: Double?,
    val displayFps: Double?,
) {
    fun toMap(): Map<String, Any?> {
        return linkedMapOf(
            "cpuUsagePercent" to cpuUsagePercent,
            "gpuUsagePercent" to gpuUsagePercent,
            "estimatedVfFps" to estimatedVfFps,
            "containerFps" to containerFps,
            "displayFps" to displayFps,
        )
    }
}

class PlaybackPerformanceSampler(
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    private val cpuCoreCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
    private val unsupportedMpvProperties = mutableSetOf<String>()
    private var lastCpuSampleUptimeMs = 0L
    private var lastProcessCpuTimeMs = 0L
    private var gpuUsageReader: (() -> Double?)? = null
    private var triedResolveGpuUsageReader = false

    fun reset() {
        lastCpuSampleUptimeMs = 0L
        lastProcessCpuTimeMs = 0L
        unsupportedMpvProperties.clear()
    }

    fun sample(): PlaybackPerformanceSnapshot {
        return PlaybackPerformanceSnapshot(
            cpuUsagePercent = sampleCpuUsagePercent(),
            gpuUsagePercent = sampleGpuUsagePercent(),
            estimatedVfFps = sampleFirstMpvDouble("estimated-vf-fps", "fps"),
            containerFps = sampleFirstMpvDouble("container-fps"),
            displayFps = null,
        )
    }

    private fun sampleCpuUsagePercent(): Double? {
        val now = SystemClock.elapsedRealtime()
        val processCpuTimeMs = Process.getElapsedCpuTime()
        if (lastCpuSampleUptimeMs == 0L || processCpuTimeMs <= 0L) {
            lastCpuSampleUptimeMs = now
            lastProcessCpuTimeMs = processCpuTimeMs
            return null
        }
        val elapsedWallMs = now - lastCpuSampleUptimeMs
        val elapsedCpuMs = processCpuTimeMs - lastProcessCpuTimeMs
        lastCpuSampleUptimeMs = now
        lastProcessCpuTimeMs = processCpuTimeMs
        if (elapsedWallMs <= 0L || elapsedCpuMs < 0L) return null
        val usage = (elapsedCpuMs.toDouble() / (elapsedWallMs.toDouble() * cpuCoreCount)) * 100.0
        return usage.coerceIn(0.0, 100.0)
    }

    private fun sampleGpuUsagePercent(): Double? {
        if (!triedResolveGpuUsageReader) {
            gpuUsageReader = resolveGpuUsageReader()
            triedResolveGpuUsageReader = true
        }
        return gpuUsageReader?.invoke()?.coerceIn(0.0, 100.0)
    }

    private fun resolveGpuUsageReader(): (() -> Double?)? {
        val directCandidates = listOf(
            "/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage",
            "/sys/class/kgsl/kgsl-3d0/devfreq/gpu_busy_percentage",
            "/sys/devices/platform/kgsl-3d0.0/gpu_busy_percentage",
            "/sys/class/misc/mali0/device/utilization",
            "/sys/devices/platform/mali/utilization",
        )
        for (path in directCandidates) {
            val reader = buildSimplePercentReader(File(path))
            if (reader != null) return reader
        }

        val devfreqRoot = File("/sys/class/devfreq")
        val devfreqEntries = devfreqRoot.listFiles().orEmpty()
        for (entry in devfreqEntries) {
            val normalizedName = entry.name.lowercase(Locale.US)
            if (!normalizedName.contains("mali") &&
                !normalizedName.contains("gpu") &&
                !normalizedName.contains("3d")
            ) {
                continue
            }
            val readers = listOf(
                buildSimplePercentReader(entry.resolve("gpu_busy_percentage")),
                buildSimplePercentReader(entry.resolve("load")),
                buildSimplePercentReader(entry.resolve("utilization")),
                buildSimplePercentReader(entry.resolve("busy_percent")),
                buildSimplePercentReader(entry.resolve("device/utilization")),
                buildSimplePercentReader(entry.resolve("device/gpu_busy_percentage")),
                buildSimplePercentReader(entry.resolve("device/load")),
            )
            for (reader in readers) {
                if (reader != null) return reader
            }
        }
        return null
    }

    private fun buildSimplePercentReader(file: File): (() -> Double?)? {
        if (!file.isFile || !file.canRead()) return null
        return {
            val raw = runCatching { file.readText() }.getOrNull()?.trim().orEmpty()
            parsePercentLikeValue(raw)
        }
    }

    private fun parsePercentLikeValue(raw: String): Double? {
        if (raw.isBlank()) return null
        val allTokens = raw
            .split(Regex("[^0-9.]+"))
            .filter { it.isNotBlank() }
        if (allTokens.size >= 2) {
            val busy = allTokens[0].toDoubleOrNull()
            val total = allTokens[1].toDoubleOrNull()
            if (busy != null && total != null && total > 0.0) {
                return ((busy / total) * 100.0).coerceIn(0.0, 100.0)
            }
        }
        val firstToken = allTokens.firstOrNull() ?: return null
        val numeric = firstToken.toDoubleOrNull() ?: return null
        return when {
            numeric <= 100.0 -> numeric
            numeric <= 1000.0 -> numeric / 10.0
            else -> null
        }
    }

    private fun sampleFirstMpvDouble(vararg properties: String): Double? {
        for (property in properties) {
            sampleMpvDouble(property)?.let { return it }
        }
        return null
    }

    private fun sampleMpvDouble(property: String): Double? {
        if (unsupportedMpvProperties.contains(property)) return null
        val numericValue = sanitizeMpvDoubleProperty(
            property = property,
            value = runCatching { mpv.getPropertyDouble(property) }.getOrNull(),
        )
        if (numericValue != null) return numericValue
        val stringValue = runCatching { mpv.getPropertyString(property) }.getOrNull()?.trim()
        val parsed = sanitizeMpvDoubleProperty(property, stringValue?.toDoubleOrNull())
        if (parsed == null && stringValue.isNullOrEmpty()) {
            unsupportedMpvProperties += property
        }
        return parsed
    }
}
