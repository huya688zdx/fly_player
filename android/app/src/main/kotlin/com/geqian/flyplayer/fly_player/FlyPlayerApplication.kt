package com.geqian.flyplayer.fly_player

import android.app.Application
import android.os.Process
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.system.exitProcess

class FlyPlayerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FlyPlayerCrashHandler.install(this)
    }
}

private object FlyPlayerCrashHandler : Thread.UncaughtExceptionHandler {
    private const val TAG = "FlyPlayerCrash"
    private const val FILE_NAME = "fly_player_native_crash.log"
    private const val MAX_BYTES = 256 * 1024L

    @Volatile
    private var installed = false

    @Volatile
    private var app: Application? = null

    @Volatile
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    fun install(application: Application) {
        if (installed) {
            return
        }
        synchronized(this) {
            if (installed) {
                return
            }
            app = application
            previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler(this)
            installed = true
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        runCatching {
            appendCrashLog(thread, throwable)
        }.onFailure { error ->
            Log.e(TAG, "Failed to persist uncaught exception", error)
        }

        val handler = previousHandler
        if (handler != null && handler !== this) {
            handler.uncaughtException(thread, throwable)
            return
        }

        Process.killProcess(Process.myPid())
        exitProcess(10)
    }

    private fun appendCrashLog(thread: Thread, throwable: Throwable) {
        val application = app ?: return
        val file = File(application.cacheDir, FILE_NAME)
        file.parentFile?.mkdirs()
        if (file.exists() && file.length() > MAX_BYTES) {
            file.writeText("", Charsets.UTF_8)
        }
        file.appendText(buildCrashBlock(thread, throwable), Charsets.UTF_8)
        Log.e(TAG, "Uncaught exception on thread=${thread.name}", throwable)
    }

    private fun buildCrashBlock(
        thread: Thread,
        throwable: Throwable,
    ): String {
        val stackTrace = StringWriter().also { writer ->
            PrintWriter(writer).use { printWriter ->
                throwable.printStackTrace(printWriter)
            }
        }.toString().trim()
        val timestamp =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        return buildString {
            append("[native] ")
            append(timestamp)
            append(" thread=")
            append(thread.name)
            append(" pid=")
            append(Process.myPid())
            appendLine()
            append(throwable::class.java.name)
            append(": ")
            appendLine(throwable.message ?: "(no message)")
            if (stackTrace.isNotEmpty()) {
                appendLine("stackTrace:")
                appendLine(stackTrace)
            }
            appendLine()
        }
    }
}
