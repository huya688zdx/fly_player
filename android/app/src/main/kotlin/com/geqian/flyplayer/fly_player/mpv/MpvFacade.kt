package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.view.Surface
import `is`.xyz.mpv.MPVLib

interface MpvFacade {
    fun isAvailable(): Boolean

    fun loadErrorMessage(): String?

    fun isCreated(): Boolean

    fun maybeCreate(context: Context): Boolean

    fun maybeInit(): Boolean

    fun shutdown()

    fun addObserver(observer: MPVLib.EventObserver)

    fun removeObserver(observer: MPVLib.EventObserver)

    fun addLogObserver(observer: MPVLib.LogObserver)

    fun removeLogObserver(observer: MPVLib.LogObserver)

    fun attachSurface(surface: Surface)

    fun detachSurface()

    fun command(command: Array<String>): Int

    fun setOptionString(name: String, value: String): Boolean

    fun setPropertyString(name: String, value: String): Boolean

    fun setPropertyInt(name: String, value: Long): Boolean

    fun setPropertyDouble(name: String, value: Double): Boolean

    fun setPropertyBoolean(name: String, value: Boolean): Boolean

    fun observeProperty(property: String, format: Int): Int

    fun getPropertyString(property: String): String?

    fun getPropertyInt(property: String): Long

    fun getPropertyDouble(property: String): Double

    fun onFileLoaded(): Int

    fun onEndFile(): Int
}

object DefaultMpvFacade : MpvFacade {
    override fun isAvailable(): Boolean = MPVLib.isAvailable()

    override fun loadErrorMessage(): String? = MPVLib.loadErrorMessage()

    override fun isCreated(): Boolean = MPVLib.isCreated()

    override fun maybeCreate(context: Context): Boolean = MPVLib.maybeCreate(context)

    override fun maybeInit(): Boolean = MPVLib.maybeInit()

    override fun shutdown() = MPVLib.shutdown()

    override fun addObserver(observer: MPVLib.EventObserver) = MPVLib.addObserver(observer)

    override fun removeObserver(observer: MPVLib.EventObserver) = MPVLib.removeObserver(observer)

    override fun addLogObserver(observer: MPVLib.LogObserver) = MPVLib.addLogObserver(observer)

    override fun removeLogObserver(observer: MPVLib.LogObserver) = MPVLib.removeLogObserver(observer)

    override fun attachSurface(surface: Surface) = MPVLib.attachSurface(surface)

    override fun detachSurface() = MPVLib.detachSurface()

    override fun command(command: Array<String>): Int = MPVLib.command(command)

    override fun setOptionString(name: String, value: String): Boolean = MPVLib.setOptionString(name, value)

    override fun setPropertyString(name: String, value: String): Boolean = MPVLib.setPropertyString(name, value)

    override fun setPropertyInt(name: String, value: Long): Boolean = MPVLib.setPropertyInt(name, value)

    override fun setPropertyDouble(name: String, value: Double): Boolean = MPVLib.setPropertyDouble(name, value)

    override fun setPropertyBoolean(name: String, value: Boolean): Boolean = MPVLib.setPropertyBoolean(name, value)

    override fun observeProperty(property: String, format: Int): Int = MPVLib.observeProperty(property, format)

    override fun getPropertyString(property: String): String? = MPVLib.getPropertyString(property)

    override fun getPropertyInt(property: String): Long = MPVLib.getPropertyInt(property)

    override fun getPropertyDouble(property: String): Double = MPVLib.getPropertyDouble(property)

    override fun onFileLoaded(): Int = MPVLib.onFileLoaded()

    override fun onEndFile(): Int = MPVLib.onEndFile()
}
