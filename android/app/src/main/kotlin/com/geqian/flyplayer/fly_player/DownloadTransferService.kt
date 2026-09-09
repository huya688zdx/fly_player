package com.geqian.flyplayer.fly_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/** 下载由现有 Dart 队列执行，本服务负责后台通知与下载期间的 CPU 唤醒。 */
class DownloadTransferService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val count = owners.values.sum()
        if (count <= 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(
                CHANNEL, getString(R.string.download_background_channel), NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.download_background_count, count))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(0, 0, true).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FlyPlayer:Downloads")
                .apply { setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L) }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        pauseOwners()
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        pauseOwners()
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "offline_downloads"
        private const val ID = 4208
        private val owners = mutableMapOf<MethodChannel, Int>()

        fun update(context: Context, channel: MethodChannel, count: Int) {
            if (count > 0) owners[channel] = count else owners.remove(channel)
            if (owners.isEmpty()) context.stopService(Intent(context, DownloadTransferService::class.java))
            else ContextCompat.startForegroundService(context, Intent(context, DownloadTransferService::class.java))
        }

        private fun pauseOwners() {
            val channels = owners.keys.toList()
            owners.clear()
            channels.forEach { it.invokeMethod("pauseDownloads", null) }
        }
    }
}
