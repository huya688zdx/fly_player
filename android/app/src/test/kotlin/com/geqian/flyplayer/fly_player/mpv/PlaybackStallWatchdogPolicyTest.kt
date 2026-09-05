package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackStallWatchdogPolicyTest {
    private fun policy(
        stallTimeoutMs: Long = 8_000L,
        seekStallTimeoutMs: Long = 15_000L,
        recoveryCooldownMs: Long = 30_000L,
        maxRecoveriesPerSource: Int = 2,
    ) = PlaybackStallWatchdogPolicy(
        stallTimeoutMs = stallTimeoutMs,
        seekStallTimeoutMs = seekStallTimeoutMs,
        recoveryCooldownMs = recoveryCooldownMs,
        maxRecoveriesPerSource = maxRecoveriesPerSource,
    )

    private fun sample(
        eligible: Boolean = true,
        seekingOrRestoring: Boolean = false,
        positionMs: Long = 60_000L,
        durationMs: Long = 1_200_000L,
        nowUptimeMs: Long,
    ) = PlaybackStallWatchdogPolicy.Sample(
        eligible = eligible,
        seekingOrRestoring = seekingOrRestoring,
        positionMs = positionMs,
        durationMs = durationMs,
        nowUptimeMs = nowUptimeMs,
    )

    @Test
    fun `位置推进时不触发`() {
        val watchdog = policy()
        assertFalse(watchdog.onSample(sample(positionMs = 1_000L, nowUptimeMs = 0L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(positionMs = 3_000L, nowUptimeMs = 2_000L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(positionMs = 5_000L, nowUptimeMs = 4_000L)).triggerRecovery)
    }

    @Test
    fun `位置冻结超时后触发一次恢复`() {
        val watchdog = policy()
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 0L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 4_000L)).triggerRecovery)
        val verdict = watchdog.onSample(sample(nowUptimeMs = 8_000L))
        assertTrue(verdict.triggerRecovery)
        assertEquals(8_000L, verdict.stalledForMs)
        assertEquals(1, verdict.attempt)
    }

    @Test
    fun `触发后计时重开且冷却期内不再触发`() {
        val watchdog = policy()
        watchdog.onSample(sample(nowUptimeMs = 0L))
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 8_000L)).triggerRecovery)
        // 冷却 30s 内即使继续冻结也不触发（8s 超时在 16s 处再次满足，但冷却拦住）。
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 10_000L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 20_000L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 36_000L)).triggerRecovery)
        // 冷却结束且冻结继续 → 第二次触发。
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 44_000L)).triggerRecovery)
    }

    @Test
    fun `同源触发次数封顶`() {
        val watchdog = policy(recoveryCooldownMs = 0L, maxRecoveriesPerSource = 2)
        watchdog.onSample(sample(nowUptimeMs = 0L))
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 8_000L)).triggerRecovery)
        // 触发后计时重开：16s 处是重开后的首采样，24s 处才再满 8s 超时。
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 16_000L)).triggerRecovery)
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 24_000L)).triggerRecovery)
        // 第三次到点：配额用尽，不再触发。
        watchdog.onSample(sample(nowUptimeMs = 32_000L))
        val verdict = watchdog.onSample(sample(nowUptimeMs = 40_000L))
        assertFalse(verdict.triggerRecovery)
        assertEquals(2, verdict.attempt)
    }

    @Test
    fun `换源重置配额`() {
        val watchdog = policy(recoveryCooldownMs = 0L, maxRecoveriesPerSource = 1)
        watchdog.onSample(sample(nowUptimeMs = 0L))
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 8_000L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 16_000L)).triggerRecovery)
        watchdog.onSourceChanged()
        watchdog.onSample(sample(nowUptimeMs = 20_000L))
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 28_000L)).triggerRecovery)
    }

    @Test
    fun `不合资格时冻结计时清零`() {
        val watchdog = policy()
        watchdog.onSample(sample(nowUptimeMs = 0L))
        // 中途暂停（不合资格）→ 计时清零。
        assertFalse(watchdog.onSample(sample(eligible = false, nowUptimeMs = 6_000L)).triggerRecovery)
        // 恢复资格后从头计时：距重新计时仅 4s，不触发。
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 8_000L)).triggerRecovery)
        assertFalse(watchdog.onSample(sample(nowUptimeMs = 12_000L)).triggerRecovery)
        assertTrue(watchdog.onSample(sample(nowUptimeMs = 16_000L)).triggerRecovery)
    }

    @Test
    fun `seek 恢复期用更长阈值`() {
        val watchdog = policy()
        watchdog.onSample(sample(seekingOrRestoring = true, nowUptimeMs = 0L))
        // 8s 冻结在 seek 期不触发（普通阈值不适用）。
        assertFalse(
            watchdog.onSample(sample(seekingOrRestoring = true, nowUptimeMs = 8_000L)).triggerRecovery,
        )
        // 15s 到 → 触发。
        assertTrue(
            watchdog.onSample(sample(seekingOrRestoring = true, nowUptimeMs = 15_000L)).triggerRecovery,
        )
    }

    @Test
    fun `片尾冻结不触发`() {
        val watchdog = policy()
        watchdog.onSample(sample(positionMs = 1_199_000L, nowUptimeMs = 0L))
        assertFalse(
            watchdog.onSample(sample(positionMs = 1_199_000L, nowUptimeMs = 20_000L)).triggerRecovery,
        )
    }

    @Test
    fun `时长未知时片尾豁免不生效仍可触发`() {
        val watchdog = policy()
        watchdog.onSample(sample(durationMs = 0L, nowUptimeMs = 0L))
        assertTrue(watchdog.onSample(sample(durationMs = 0L, nowUptimeMs = 8_000L)).triggerRecovery)
    }
}
