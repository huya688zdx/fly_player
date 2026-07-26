package com.geqian.flyplayer.fly_player.mpv

internal data class DanmakuMaskTimelineSample(
    val ptsMs: Long,
    val empty: Boolean,
)

internal data class DanmakuMaskTimelineBracket(
    val floorIndex: Int,
    val nextIndex: Int?,
)

internal object DanmakuMaskTimelinePolicy {
    fun tailExtrapolationMs(
        timelineMs: Long,
        floorPtsMs: Long,
        hasNext: Boolean,
    ): Long {
        if (hasNext) return 0L
        return (timelineMs - floorPtsMs).coerceIn(0L, 150L)
    }

    fun selectBracket(
        samples: List<DanmakuMaskTimelineSample>,
        timelineMs: Long,
        staleMaxMs: Long,
    ): DanmakuMaskTimelineBracket? {
        var floorIndex = -1
        for (index in samples.indices) {
            val sample = samples[index]
            if (sample.ptsMs <= timelineMs &&
                (floorIndex < 0 || sample.ptsMs > samples[floorIndex].ptsMs)
            ) {
                floorIndex = index
            }
        }
        if (floorIndex < 0) return null
        val floor = samples[floorIndex]
        if (timelineMs - floor.ptsMs > staleMaxMs) return null
        var nextIndex = -1
        for (index in samples.indices) {
            val sample = samples[index]
            if (sample.ptsMs > floor.ptsMs &&
                (nextIndex < 0 || sample.ptsMs < samples[nextIndex].ptsMs)
            ) {
                nextIndex = index
            }
        }
        return DanmakuMaskTimelineBracket(
            floorIndex = floorIndex,
            nextIndex = nextIndex.takeIf { it >= 0 },
        )
    }
}

internal class DanmakuMaskGate(
    private val confirmationSteps: Int = 2,
) {
    var active: Boolean = false
        private set
    private var pendingState: Boolean? = null
    private var pendingCount = 0

    fun accept(
        ratio: Float,
        minRatio: Float,
        maxRatio: Float,
        minHysteresis: Float,
        maxHysteresis: Float,
    ): Boolean {
        val minGate = if (active) minRatio - minHysteresis else minRatio
        val maxGate = if (active) maxRatio + maxHysteresis else maxRatio
        val candidate = ratio >= minGate && ratio <= maxGate
        if (candidate == active) {
            pendingState = null
            pendingCount = 0
            return active
        }
        if (pendingState != candidate) {
            pendingState = candidate
            pendingCount = 1
        } else {
            pendingCount += 1
        }
        if (pendingCount >= confirmationSteps.coerceAtLeast(1)) {
            active = candidate
            pendingState = null
            pendingCount = 0
        }
        return active
    }

    fun reset() {
        active = false
        pendingState = null
        pendingCount = 0
    }
}

internal data class DanmakuPlanBBudgetDecision(
    val inputWidth: Int,
    val stepMs: Long,
    val inputWidthChanged: Boolean,
)

internal class DanmakuPlanBBudgetPolicy(
    initialInputWidth: Int = 512,
) {
    var inputWidth: Int = normalizeWidth(initialInputWidth)
        private set

    fun adapt(
        budgetEmaMs: Double,
        highMotion: Boolean,
    ): DanmakuPlanBBudgetDecision {
        val previousWidth = inputWidth
        if (budgetEmaMs > INPUT_REDUCTION_BUDGET_MS) {
            inputWidth = when (inputWidth) {
                512 -> 384
                384 -> 320
                else -> inputWidth
            }
        }
        val motionFloor = if (highMotion) STEP_MS_MIN else STEP_MS_DEFAULT
        val inputWidthChanged = inputWidth != previousWidth
        val budgetFloor =
            if (inputWidth == MIN_INPUT_WIDTH && !inputWidthChanged) {
                (budgetEmaMs / STEP_SUSTAIN_RATIO).toLong()
            } else {
                motionFloor
            }
        return DanmakuPlanBBudgetDecision(
            inputWidth = inputWidth,
            stepMs = maxOf(motionFloor, budgetFloor).coerceIn(STEP_MS_MIN, STEP_MS_MAX),
            inputWidthChanged = inputWidthChanged,
        )
    }

    fun reset() {
        inputWidth = 512
    }

    private fun normalizeWidth(width: Int): Int = when {
        width >= 512 -> 512
        width >= 384 -> 384
        else -> 320
    }

    private companion object {
        const val INPUT_REDUCTION_BUDGET_MS = 224.0
        const val MIN_INPUT_WIDTH = 320
        const val STEP_MS_MIN = 140L
        const val STEP_MS_DEFAULT = 280L
        // 旧上限 960ms 会把包夹带和 stale 窗拉得过宽；640ms 是本轮观感上限。
        const val STEP_MS_MAX = 640L
        const val STEP_SUSTAIN_RATIO = 0.8
    }
}
