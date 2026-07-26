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
    private var fresh = true
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
        if (fresh) {
            // 复位（sceneCut/seek）后的首步没有历史可对抗，直接采纳。否则每次镜头
            // 切换后第一张有主体的 mask 都被两步确认吃掉一个步长（弹幕压脸窗口），
            // 追赶重放风暴下每步都 reset → 遮罩永久为空。确认计数只用于稳态翻转。
            fresh = false
            active = candidate
            pendingState = null
            pendingCount = 0
            return active
        }
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
        fresh = true
        pendingState = null
        pendingCount = 0
    }
}

internal data class DanmakuPlanBBudgetDecision(
    val inputWidth: Int,
    val stepMs: Long,
    val inputWidthChanged: Boolean,
)

// 输入宽固定 512：ISNet 模型按 512 导出（skip 连接里烘死了 Resize 目标，见
// DanmakuSegmentationRuntime 的模型注释），resizeTensor 到其它尺寸会让 MNN session
// 永久进入 "Can't run session because not resized" 状态——之后每次推理都失败并回读
// 陈旧输出。预算紧张只允许拉步长，不允许降输入宽。
internal class DanmakuPlanBBudgetPolicy(
    @Suppress("UNUSED_PARAMETER") initialInputWidth: Int = 512,
) {
    val inputWidth: Int = FIXED_INPUT_WIDTH

    fun adapt(
        budgetEmaMs: Double,
        highMotion: Boolean,
        playbackSpeed: Double = 1.0,
    ): DanmakuPlanBBudgetDecision {
        // 倍速播放消耗视频时间是 speed 倍：可持续步长与上限都按 speed 放大
        // （视频时间的步长 ×speed = 墙钟观感密度不变），否则 2x 下推理永远追不上
        // 播放 → 每步被超越 → 永久 reprime 风暴。
        val speed = playbackSpeed.takeIf { it.isFinite() }?.coerceIn(1.0, 4.0) ?: 1.0
        val motionFloor = if (highMotion) STEP_MS_MIN else STEP_MS_DEFAULT
        val budgetFloor = (budgetEmaMs * speed / STEP_SUSTAIN_RATIO).toLong()
        val stepCap = (STEP_MS_MAX * speed).toLong()
        return DanmakuPlanBBudgetDecision(
            inputWidth = inputWidth,
            stepMs = maxOf(motionFloor, budgetFloor).coerceIn(STEP_MS_MIN, stepCap),
            inputWidthChanged = false,
        )
    }

    private companion object {
        const val FIXED_INPUT_WIDTH = 512
        const val STEP_MS_MIN = 140L
        const val STEP_MS_DEFAULT = 280L
        // 旧上限 960ms 会把包夹带和 stale 窗拉得过宽；640ms 是本轮观感上限。
        const val STEP_MS_MAX = 640L
        const val STEP_SUSTAIN_RATIO = 0.8
    }
}
