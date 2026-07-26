package com.geqian.flyplayer.fly_player.mpv

import android.app.ActivityManager
import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.os.Process
import android.os.SystemClock
import java.io.File

data class PlaybackPerformanceSnapshot(
    val cpuUsagePercent: Double?,
    val appMemoryUsedBytes: Long?,
    val systemMemoryTotalBytes: Long?,
) {
    fun toMap(): Map<String, Any?> {
        return linkedMapOf(
            "cpuUsagePercent" to cpuUsagePercent,
            "appMemoryUsedBytes" to appMemoryUsedBytes,
            "systemMemoryTotalBytes" to systemMemoryTotalBytes,
        )
    }
}

class PlaybackPerformanceSampler(
    context: Context,
) {
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
    private val cpuCoreCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
    private var lastCpuSampleUptimeMs = 0L
    private var lastProcessCpuTimeMs = 0L

    fun reset() {
        lastCpuSampleUptimeMs = 0L
        lastProcessCpuTimeMs = 0L
    }

    fun sample(): PlaybackPerformanceSnapshot {
        return PlaybackPerformanceSnapshot(
            cpuUsagePercent = sampleCpuUsagePercent(),
            appMemoryUsedBytes = sampleAppMemoryUsedBytes(),
            systemMemoryTotalBytes = sampleSystemMemoryTotalBytes(),
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

    private fun sampleAppMemoryUsedBytes(): Long? {
        val residentBytes = sampleResidentSetBytes()
        if (residentBytes != null && residentBytes > 0L) {
            return residentBytes
        }
        val manager = activityManager
        if (manager != null) {
            val processMemoryBytes =
                runCatching {
                    val processInfo = manager.getProcessMemoryInfo(intArrayOf(Process.myPid()))
                    processInfo.firstOrNull()?.totalPss?.toLong()?.times(1024L)
                }.getOrNull()
            if (processMemoryBytes != null && processMemoryBytes > 0L) {
                return processMemoryBytes
            }
        }
        val runtime = Runtime.getRuntime()
        val heapUsedBytes = runtime.totalMemory() - runtime.freeMemory()
        return heapUsedBytes.takeIf { it > 0L }
    }

    private fun sampleResidentSetBytes(): Long? {
        val pageSize = runCatching { Os.sysconf(OsConstants._SC_PAGESIZE) }.getOrNull()
        val statmBytes =
            if (pageSize != null && pageSize > 0L) {
                runCatching {
                    val content = File("/proc/self/statm").readText().trim()
                    val residentPages = content.split(Regex("\\s+")).getOrNull(1)?.toLongOrNull()
                    residentPages?.times(pageSize)
                }.getOrNull()
            } else {
                null
            }
        if (statmBytes != null && statmBytes > 0L) {
            return statmBytes
        }
        return runCatching {
            File("/proc/self/status")
                .useLines { lines ->
                    lines.firstOrNull { it.startsWith("VmRSS:") }
                }
                ?.split(Regex("\\s+"))
                ?.getOrNull(1)
                ?.toLongOrNull()
                ?.times(1024L)
        }.getOrNull()
    }

    private fun sampleSystemMemoryTotalBytes(): Long? {
        val manager = activityManager ?: return null
        val memoryInfo = ActivityManager.MemoryInfo()
        return runCatching {
            manager.getMemoryInfo(memoryInfo)
            memoryInfo.totalMem.takeIf { it > 0L }
        }.getOrNull()
    }
}
