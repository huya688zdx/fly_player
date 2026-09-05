package com.geqian.flyplayer.fly_player

import android.util.Log
import android.view.Choreographer
import android.view.View
import java.util.Locale

class ViewFrameRateProbe(
    private val logTag: String,
    private val label: String,
    private val viewProvider: () -> View?,
) {
    companion object {
        private const val LOG_WINDOW_NS = 3_000_000_000L
        private const val SLOW_FRAME_THRESHOLD_MULTIPLIER = 1.35f
    }

    private val frameCallback =
        object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                frameScheduled = false
                if (!running) {
                    return
                }
                recordFrame(frameTimeNanos)
                scheduleFrame()
            }
        }

    private var running = false
    private var frameScheduled = false
    private var windowStartNs = 0L
    private var lastFrameNs = 0L
    private var frameCount = 0
    private var slowFrameCount = 0
    private var accumulatedDeltaNs = 0L
    private var maxDeltaNs = 0L

    fun start() {
        if (running) {
            return
        }
        running = true
        resetStats()
        scheduleFrame()
        Log.d(logTag, "[FRAME][PROBE] start label=$label")
    }

    fun stop(reason: String) {
        if (!running && !frameScheduled) {
            return
        }
        running = false
        if (frameScheduled) {
            Choreographer.getInstance().removeFrameCallback(frameCallback)
            frameScheduled = false
        }
        resetStats()
        Log.d(logTag, "[FRAME][PROBE] stop label=$label reason=$reason")
    }

    private fun scheduleFrame() {
        if (!running || frameScheduled) {
            return
        }
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun recordFrame(frameTimeNanos: Long) {
        if (windowStartNs == 0L) {
            windowStartNs = frameTimeNanos
            lastFrameNs = frameTimeNanos
            frameCount = 1
            slowFrameCount = 0
            accumulatedDeltaNs = 0L
            maxDeltaNs = 0L
            return
        }
        val frameDeltaNs = (frameTimeNanos - lastFrameNs).coerceAtLeast(0L)
        lastFrameNs = frameTimeNanos
        frameCount += 1
        if (frameDeltaNs > 0L) {
            accumulatedDeltaNs += frameDeltaNs
            if (frameDeltaNs > maxDeltaNs) {
                maxDeltaNs = frameDeltaNs
            }
            val displayRefreshRate = viewProvider()?.display?.refreshRate ?: 60f
            val targetFrameIntervalNs =
                (1_000_000_000.0 / displayRefreshRate.coerceAtLeast(1f).toDouble()).toLong()
            val slowThresholdNs =
                (targetFrameIntervalNs.toDouble() * SLOW_FRAME_THRESHOLD_MULTIPLIER.toDouble()).toLong()
            if (frameDeltaNs >= slowThresholdNs) {
                slowFrameCount += 1
            }
        }
        val windowDurationNs = frameTimeNanos - windowStartNs
        if (windowDurationNs < LOG_WINDOW_NS) {
            return
        }
        val view = viewProvider()
        val actualFps =
            if (windowDurationNs > 0L) {
                frameCount.toDouble() * 1_000_000_000.0 / windowDurationNs.toDouble()
            } else {
                0.0
            }
        val averageDeltaMs =
            if (frameCount > 1 && accumulatedDeltaNs > 0L) {
                accumulatedDeltaNs.toDouble() / (frameCount - 1).toDouble() / 1_000_000.0
            } else {
                0.0
            }
        Log.d(
            logTag,
            String.format(
                Locale.US,
                "[FRAME][PROBE] label=%s actual=%.1ffps displayHz=%.1f avgDeltaMs=%.2f maxDeltaMs=%.2f slowFrames=%d windowMs=%d attached=%s shown=%s",
                label,
                actualFps,
                view?.display?.refreshRate ?: 0f,
                averageDeltaMs,
                maxDeltaNs.toDouble() / 1_000_000.0,
                slowFrameCount,
                windowDurationNs / 1_000_000L,
                view?.isAttachedToWindow ?: false,
                view?.isShown ?: false,
            ),
        )
        windowStartNs = frameTimeNanos
        frameCount = 1
        slowFrameCount = 0
        accumulatedDeltaNs = 0L
        maxDeltaNs = 0L
    }

    private fun resetStats() {
        windowStartNs = 0L
        lastFrameNs = 0L
        frameCount = 0
        slowFrameCount = 0
        accumulatedDeltaNs = 0L
        maxDeltaNs = 0L
    }
}
