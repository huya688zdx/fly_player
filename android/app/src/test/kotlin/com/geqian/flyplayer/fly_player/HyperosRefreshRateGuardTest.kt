package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** PowerKeeper 前台限帧钳制判定：miui_refresh_rate 被写低时才恢复，且不对抗用户选择。 */
class HyperosRefreshRateGuardTest {

    private fun target(miui: String?, user: String?, peak: String?): String? =
        HyperosRefreshRateGuard.resolveRestoreTarget(miui, user, peak)

    @Test
    fun clampedBelowUserSettingRestoresUserValue() {
        assertEquals("120", target(miui = "60", user = "120", peak = null))
    }

    @Test
    fun fallsBackToSystemPeakWhenUserMissing() {
        assertEquals("120", target(miui = "60", user = null, peak = "120"))
    }

    @Test
    fun notClampedWhenEqualOrAbove() {
        assertNull(target(miui = "120", user = "120", peak = null))
        assertNull(target(miui = "144", user = "120", peak = "120"))
    }

    @Test
    fun userChosenLowRateIsNotFought() {
        assertNull(target(miui = "60", user = "60", peak = null))
    }

    @Test
    fun missingOrInvalidInputsDoNothing() {
        assertNull(target(miui = null, user = "120", peak = null))
        assertNull(target(miui = "abc", user = "120", peak = null))
        assertNull(target(miui = "60", user = null, peak = null))
        assertNull(target(miui = "60", user = "abc", peak = "oops"))
    }

    @Test
    fun fractionalValuesCompareNumericallyAndKeepOriginalString() {
        assertEquals("119.9", target(miui = "60", user = "119.9", peak = null))
        assertNull(target(miui = "119.5", user = "120", peak = null))
    }
}
