package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.view.Surface
import `is`.xyz.mpv.MPVLib
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoAdjustmentControllerTest {
    @Test
    fun applyTreatsRejectedOptionalPropertiesAsNonFatal() {
        val fake = FakeMpvFacade(rejectedProperties = setOf("hue"))
        val controller = VideoAdjustmentController(fake)

        controller.update(
            mapOf(
                "settings" to mapOf(
                    "brightness" to 10.0,
                    "hue" to 20.0,
                ),
            ),
        )

        assertTrue(controller.apply(initialized = true, available = true))
        assertEquals(10.0, fake.appliedProperties["brightness"])
        assertEquals(20.0, fake.appliedProperties["hue"])
    }

    private class FakeMpvFacade(
        private val rejectedProperties: Set<String> = emptySet(),
    ) : MpvFacade {
        val appliedProperties = linkedMapOf<String, Double>()

        override fun isAvailable(): Boolean = true

        override fun loadErrorMessage(): String? = null

        override fun isCreated(): Boolean = true

        override fun maybeCreate(context: Context): Boolean = true

        override fun maybeInit(): Boolean = true

        override fun shutdown() = Unit

        override fun addObserver(observer: MPVLib.EventObserver) = Unit

        override fun removeObserver(observer: MPVLib.EventObserver) = Unit

        override fun addLogObserver(observer: MPVLib.LogObserver) = Unit

        override fun removeLogObserver(observer: MPVLib.LogObserver) = Unit

        override fun attachSurface(surface: Surface) = Unit

        override fun detachSurface() = Unit

        override fun command(command: Array<String>): Int = 0

        override fun setOptionString(name: String, value: String): Boolean = true

        override fun setPropertyString(name: String, value: String): Boolean = true

        override fun setPropertyInt(name: String, value: Long): Boolean = true

        override fun setPropertyDouble(name: String, value: Double): Boolean {
            appliedProperties[name] = value
            return name !in rejectedProperties
        }

        override fun setPropertyBoolean(name: String, value: Boolean): Boolean = true

        override fun observeProperty(property: String, format: Int): Int = 0

        override fun getPropertyString(property: String): String? = null

        override fun getPropertyInt(property: String): Long = 0L

        override fun getPropertyDouble(property: String): Double = 0.0

        override fun onStartFile(): Int = 0

        override fun onFileLoaded(): Int = 0

        override fun onEndFile(): Int = 0
    }
}
