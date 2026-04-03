package com.geqian.flyplayer.fly_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

class PlayerNotificationService : Service() {
    private lateinit var playbackSessionManager: PlaybackSessionManager

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        playbackSessionManager =
            PlaybackSessionManager(this) {
                startForegroundCompat(playbackSessionManager.buildNotification())
            }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_START_OR_UPDATE -> {
                val payload = PlaybackSessionPayload.fromIntent(intent) ?: return START_NOT_STICKY
                playbackSessionManager.updateSession(payload)
                startForegroundCompat(playbackSessionManager.buildNotification())
            }

            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (::playbackSessionManager.isInitialized) {
            playbackSessionManager.release()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Playback",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Playback controls"
                setShowBadge(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "player_playback"
        private const val ACTION_START_OR_UPDATE = "com.geqian.flyplayer.fly_player.action.PLAYBACK_START_OR_UPDATE"
        private const val ACTION_STOP = "com.geqian.flyplayer.fly_player.action.PLAYBACK_STOP"
        private const val NOTIFICATION_ID = 3001

        fun startOrUpdate(
            context: Context,
            payload: PlaybackSessionPayload,
        ) {
            val intent =
                Intent(context, PlayerNotificationService::class.java).apply {
                    action = ACTION_START_OR_UPDATE
                    putExtras(payload.toBundle())
                }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, PlayerNotificationService::class.java).apply {
                        action = ACTION_STOP
                    },
                )
            }
            context.stopService(Intent(context, PlayerNotificationService::class.java))
        }
    }
}
