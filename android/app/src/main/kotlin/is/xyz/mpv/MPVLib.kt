package `is`.xyz.mpv

import android.content.Context
import android.view.Surface
import java.util.concurrent.CopyOnWriteArrayList

object MPVLib {
    private const val EVENT_PROPERTY = 1
    private const val EVENT_FILE_LOADED = 8
    private const val EVENT_END_FILE = 7

    private val observers = CopyOnWriteArrayList<EventObserver>()
    private val logObservers = CopyOnWriteArrayList<LogObserver>()
    private var created = false
    private var initialized = false
    private var loadError: Throwable? = null

    init {
        try {
            System.loadLibrary("mpv")
            System.loadLibrary("player")
        } catch (error: Throwable) {
            loadError = error
        }
    }

    fun isAvailable(): Boolean = loadError == null

    fun loadErrorMessage(): String? = loadError?.message ?: loadError?.javaClass?.simpleName

    @Synchronized
    fun maybeCreate(context: Context): Boolean {
        if (!isAvailable()) return false
        if (created) return true
        create(context.applicationContext)
        created = true
        initialized = false
        return true
    }

    @Synchronized
    fun maybeInit(): Boolean {
        if (!isAvailable()) return false
        if (!created) return false
        if (initialized) return true
        init()
        initialized = true
        return true
    }

    fun isCreated(): Boolean = isAvailable() && created

    fun isInitialized(): Boolean = isAvailable() && created && initialized

    @Synchronized
    fun shutdown() {
        if (!isAvailable()) {
            created = false
            initialized = false
            return
        }
        if (created) {
            runCatching { destroy() }
        }
        created = false
        initialized = false
    }

    fun addObserver(observer: EventObserver) {
        observers += observer
    }

    fun removeObserver(observer: EventObserver) {
        observers -= observer
    }

    fun addLogObserver(observer: LogObserver) {
        logObservers += observer
    }

    fun removeLogObserver(observer: LogObserver) {
        logObservers -= observer
    }

    @JvmStatic
    fun eventProperty(property: String) {
        for (observer in observers) {
            observer.eventProperty(property)
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Long) {
        for (observer in observers) {
            observer.eventProperty(property, value)
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Boolean) {
        for (observer in observers) {
            observer.eventProperty(property, value)
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: String) {
        for (observer in observers) {
            observer.eventProperty(property, value)
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Double) {
        for (observer in observers) {
            observer.eventProperty(property, value)
        }
    }

    @JvmStatic
    fun event(eventId: Int) {
        for (observer in observers) {
            observer.event(eventId)
        }
    }

    @JvmStatic
    fun logMessage(prefix: String, level: Int, text: String) {
        for (observer in logObservers) {
            observer.logMessage(prefix, level, text)
        }
    }

    fun onFileLoaded(): Int = EVENT_FILE_LOADED

    fun onEndFile(): Int = EVENT_END_FILE

    fun propertyEvent(): Int = EVENT_PROPERTY

    external fun create(context: Context)

    external fun destroy()

    external fun init()

    external fun attachSurface(surface: Surface)

    external fun detachSurface()

    external fun command(command: Array<String>): Int

    external fun setOptionString(name: String, value: String): Boolean

    external fun setPropertyString(name: String, value: String): Boolean

    external fun setPropertyInt(name: String, value: Long): Boolean

    external fun setPropertyDouble(name: String, value: Double): Boolean

    external fun setPropertyBoolean(name: String, value: Boolean): Boolean

    external fun observeProperty(property: String, format: Int): Int

    external fun getPropertyString(property: String): String?

    external fun getPropertyInt(property: String): Long

    external fun getPropertyDouble(property: String): Double

    interface EventObserver {
        fun eventProperty(property: String) = Unit

        fun eventProperty(property: String, value: Long) = Unit

        fun eventProperty(property: String, value: Boolean) = Unit

        fun eventProperty(property: String, value: String) = Unit

        fun eventProperty(property: String, value: Double) = Unit

        fun event(eventId: Int) = Unit
    }

    interface LogObserver {
        fun logMessage(prefix: String, level: Int, text: String)
    }
}
