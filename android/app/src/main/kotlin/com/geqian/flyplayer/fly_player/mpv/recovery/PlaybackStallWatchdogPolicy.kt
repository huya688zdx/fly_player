package com.geqian.flyplayer.fly_player.mpv

/**
 * 播放中 time-pos 冻结看门狗（纯策略，JVM 单测）。
 *
 * 背景：mpv 核心在 seek 后偶发挂死——事件循环停摆、time-pos 不再推进，但进程与
 * 播放线程都活着，既有的日志/属性驱动恢复（[PlaybackRecoveryOrchestrator]）收不到
 * 任何信号，只能靠外部对账：明明处于"正在播放"状态（未暂停、非缓冲、非 seek 恢复
 * 期），位置却冻结超过阈值，就判定核心挂死并触发一次重载恢复。
 *
 * 判定口径：
 *  - 资格由调用方给出（初始化完成、源已载入、未暂停、非缓冲、无源切换等）；
 *    不合资格时冻结计时清零——暂停/缓冲下位置本来就不动，不是挂死。
 *  - seek/恢复期（seekingOrRestoring）用更长的独立阈值：慢网络 seek 本身可能吃
 *    数秒，但 seek 后挂死恰是主要病灶，不能整段豁免。
 *  - 片尾 [eofGuardMs] 内位置停住交给 eof 路径，不算挂死。
 *  - 触发后有冷却，且每个源最多触发 [maxRecoveriesPerSource] 次——重载治不好的
 *    挂死反复重载只会循环闪断，到顶后放弃并由日志留痕。
 */
class PlaybackStallWatchdogPolicy(
    private val stallTimeoutMs: Long = STALL_TIMEOUT_MS,
    private val seekStallTimeoutMs: Long = SEEK_STALL_TIMEOUT_MS,
    private val recoveryCooldownMs: Long = RECOVERY_COOLDOWN_MS,
    private val maxRecoveriesPerSource: Int = MAX_RECOVERIES_PER_SOURCE,
    private val eofGuardMs: Long = EOF_GUARD_MS,
) {
    data class Sample(
        val eligible: Boolean,
        val seekingOrRestoring: Boolean,
        val positionMs: Long,
        val durationMs: Long,
        val nowUptimeMs: Long,
    )

    data class Verdict(
        val triggerRecovery: Boolean,
        val stalledForMs: Long,
        val attempt: Int,
    )

    private var lastPositionMs = Long.MIN_VALUE
    private var lastProgressAtMs = 0L
    private var lastRecoveryAtMs = 0L
    private var recoveryCount = 0

    /** 换源时重置冻结计时与本源的恢复配额。 */
    fun onSourceChanged() {
        resetStallClock()
        lastRecoveryAtMs = 0L
        recoveryCount = 0
    }

    fun onSample(sample: Sample): Verdict {
        if (!sample.eligible) {
            resetStallClock()
            return Verdict(triggerRecovery = false, stalledForMs = 0L, attempt = recoveryCount)
        }
        if (sample.durationMs > 0L &&
            sample.positionMs >= (sample.durationMs - eofGuardMs).coerceAtLeast(0L)
        ) {
            resetStallClock()
            return Verdict(triggerRecovery = false, stalledForMs = 0L, attempt = recoveryCount)
        }
        // lastPositionMs 的 MIN_VALUE 哨兵即"计时未起"；不可再拿 lastProgressAtMs==0
        // 兜底判未初始化——uptime 时钟从 0 起步时会把每次采样都当首采样，计时永远不走。
        if (sample.positionMs != lastPositionMs) {
            lastPositionMs = sample.positionMs
            lastProgressAtMs = sample.nowUptimeMs
            return Verdict(triggerRecovery = false, stalledForMs = 0L, attempt = recoveryCount)
        }
        val stalledForMs = sample.nowUptimeMs - lastProgressAtMs
        val timeoutMs = if (sample.seekingOrRestoring) seekStallTimeoutMs else stallTimeoutMs
        if (stalledForMs < timeoutMs) {
            return Verdict(triggerRecovery = false, stalledForMs = stalledForMs, attempt = recoveryCount)
        }
        if (recoveryCount >= maxRecoveriesPerSource) {
            return Verdict(triggerRecovery = false, stalledForMs = stalledForMs, attempt = recoveryCount)
        }
        if (lastRecoveryAtMs > 0L && sample.nowUptimeMs - lastRecoveryAtMs < recoveryCooldownMs) {
            return Verdict(triggerRecovery = false, stalledForMs = stalledForMs, attempt = recoveryCount)
        }
        recoveryCount += 1
        lastRecoveryAtMs = sample.nowUptimeMs
        // 触发后重开计时：重载生效前位置仍冻结，不重开会在冷却结束的下一拍立刻再触发。
        resetStallClock()
        return Verdict(triggerRecovery = true, stalledForMs = stalledForMs, attempt = recoveryCount)
    }

    private fun resetStallClock() {
        lastPositionMs = Long.MIN_VALUE
        lastProgressAtMs = 0L
    }

    companion object {
        const val STALL_TIMEOUT_MS = 8_000L
        const val SEEK_STALL_TIMEOUT_MS = 15_000L
        const val RECOVERY_COOLDOWN_MS = 30_000L
        const val MAX_RECOVERIES_PER_SOURCE = 2
        const val EOF_GUARD_MS = 2_000L
        const val TICK_INTERVAL_MS = 2_000L
    }
}
