package com.geqian.flyplayer.fly_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import com.bumptech.glide.Glide
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.load.model.LazyHeaders
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 原生播放壳（[NativePlayerActivity]）专用的前台播放服务 + 系统媒体会话。
 *
 * 与服务于旧 Flutter 壳的 [PlayerNotificationService] 平行、互不复用：那一套命令转发进
 * Flutter，这一套经 [NativeMediaCommandCoordinator] 直达原生壳 playerSurface。
 *
 * 职责：
 *  - 持有 [MediaSessionCompat]：锁屏/通知/蓝牙线控的播停/seek/下一集回调路由到原生壳；
 *  - 前台服务保活：纯听模式切后台仍出声、通知可控；
 *  - 封面经 Glide 异步加载（带 NAS 鉴权头），就绪后回填通知与会话 metadata。
 *
 * 会话状态由 Activity 经 [update] 用 Intent extras 推送（小字段，避免大对象跨进程）。
 */
class NativePlaybackMediaService : Service() {

    private lateinit var mediaSession: MediaSessionCompat
    private val artworkExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var state: SessionState? = null
    private var artworkBitmap: Bitmap? = null
    private var artworkKey: String = ""

    @Volatile
    private var artworkInFlightKey: String? = null

    @Volatile
    private var released = false

    private var startedForeground = false

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        mediaSession = MediaSessionCompat(this, SESSION_TAG).apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onPlay() = NativeMediaCommandCoordinator.dispatchPlay()

                    override fun onPause() = NativeMediaCommandCoordinator.dispatchPause()

                    override fun onSkipToNext() = NativeMediaCommandCoordinator.dispatchNext()

                    override fun onSeekTo(pos: Long) =
                        NativeMediaCommandCoordinator.dispatchSeekTo(pos)

                    override fun onFastForward() =
                        NativeMediaCommandCoordinator.dispatchAction(
                            NativeMediaCommandCoordinator.ACTION_FORWARD,
                        )

                    override fun onRewind() =
                        NativeMediaCommandCoordinator.dispatchAction(
                            NativeMediaCommandCoordinator.ACTION_REWIND,
                        )
                },
            )
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE -> {
                val next = SessionState.fromIntent(intent)
                if (next != null) {
                    val prev = state
                    state = next
                    syncArtwork(next)
                    // 仅在「会影响通知/元数据外观」的字段变化时才重建通知 + 刷 metadata。
                    // 这两件都是主线程重活：buildNotification + startForeground 要 IPC 到
                    // system_server；setMetadata 含封面位图要跨进程 parcel。原先每 ~1s 无脑全做，
                    // 会周期性阻塞主线程几十 ms，卡住原生弹幕的 Choreographer 帧（每隔几秒抖一下）。
                    val heavy = !startedForeground ||
                        prev == null ||
                        prev.title != next.title ||
                        prev.subtitle != next.subtitle ||
                        prev.durationMs != next.durationMs ||
                        prev.isPlaying != next.isPlaying ||
                        prev.canNext != next.canNext
                    if (heavy) {
                        pushSession(next)
                        startForegroundCompat(buildNotification(next))
                    } else {
                        // 纯进度/速度刷新：只更新 PlaybackState（无位图、开销极小）。系统媒体控件
                        // 会据此 position+updateTime+speed 自行外推进度条，无需重建通知。
                        mediaSession.setPlaybackState(buildPlaybackState(next))
                    }
                }
            }

            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
            }

            // 通知动作 / PIP RemoteAction 共用的命令 PendingIntent 都打到本服务。
            else -> NativeMediaCommandCoordinator.dispatchAction(intent?.action)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        released = true
        artworkInFlightKey = null
        artworkExecutor.shutdownNow()
        if (::mediaSession.isInitialized) {
            mediaSession.isActive = false
            mediaSession.release()
        }
        stopForegroundCompat()
        super.onDestroy()
    }

    // ---- 会话 / 通知 ----

    private fun pushSession(s: SessionState) {
        mediaSession.setMetadata(buildMetadata(s, artworkBitmap))
        mediaSession.setPlaybackState(buildPlaybackState(s))
        mediaSession.isActive = true
    }

    private fun buildMetadata(s: SessionState, art: Bitmap?): MediaMetadataCompat {
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, s.title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, s.title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, s.subtitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, s.subtitle)
        if (s.durationMs > 0L) {
            builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, s.durationMs)
        }
        if (art != null) {
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, art)
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, art)
        }
        return builder.build()
    }

    private fun buildPlaybackState(s: SessionState): PlaybackStateCompat {
        val actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_FAST_FORWARD or
            PlaybackStateCompat.ACTION_REWIND or
            (if (s.durationMs > 0L) PlaybackStateCompat.ACTION_SEEK_TO else 0L) or
            (if (s.canNext) PlaybackStateCompat.ACTION_SKIP_TO_NEXT else 0L)
        val playState =
            if (s.isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val speed = if (s.isPlaying) s.speed.coerceAtLeast(0.1f) else 0f
        return PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(
                playState,
                s.positionMs.coerceAtLeast(0L),
                speed,
                SystemClock.elapsedRealtime(),
            )
            .build()
    }

    private fun buildNotification(s: SessionState): Notification {
        val rewind = NotificationCompat.Action(
            android.R.drawable.ic_media_rew,
            getString(R.string.notification_action_rewind_10s),
            commandIntent(NativeMediaCommandCoordinator.ACTION_REWIND, 21),
        )
        val playPause = if (s.isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                getString(R.string.notification_action_pause),
                commandIntent(NativeMediaCommandCoordinator.ACTION_PAUSE, 22),
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                getString(R.string.notification_action_play),
                commandIntent(NativeMediaCommandCoordinator.ACTION_PLAY, 23),
            )
        }
        val forward = NotificationCompat.Action(
            android.R.drawable.ic_media_ff,
            getString(R.string.notification_action_forward_10s),
            commandIntent(NativeMediaCommandCoordinator.ACTION_FORWARD, 24),
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(s.title)
            .setContentText(s.subtitle.ifBlank { getString(R.string.notification_now_playing) })
            .setContentIntent(contentIntent())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOngoing(s.isPlaying)
            .setLargeIcon(artworkBitmap)
            .addAction(rewind)
            .addAction(playPause)
            .addAction(forward)

        val compactIndexes: IntArray
        if (s.canNext) {
            builder.addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    getString(R.string.notification_action_next_episode),
                    commandIntent(NativeMediaCommandCoordinator.ACTION_NEXT, 25),
                ),
            )
            compactIndexes = intArrayOf(0, 1, 2)
        } else {
            compactIndexes = intArrayOf(0, 1, 2)
        }
        builder.setStyle(
            MediaStyle()
                .setMediaSession(mediaSession.sessionToken)
                .setShowActionsInCompactView(*compactIndexes),
        )
        return builder.build()
    }

    private fun commandIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, NativePlaybackMediaService::class.java).apply {
            this.action = action
            `package` = packageName
        }
        return PendingIntent.getService(this, requestCode, intent, pendingIntentFlags())
    }

    private fun contentIntent(): PendingIntent {
        // 不带 loadArgs 唤起原生壳：onNewIntent 见到空 loadArgs 即保留当前播放并置顶。
        val intent = Intent(this, NativePlayerActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        return PendingIntent.getActivity(this, 30, intent, pendingIntentFlags())
    }

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    // ---- 封面异步加载（Glide，带 NAS 鉴权头） ----

    private fun syncArtwork(s: SessionState) {
        val key = "${s.artworkUrl}|${s.artworkAuth}"
        if (s.artworkUrl.isBlank()) {
            artworkKey = ""
            artworkBitmap = null
            return
        }
        if (key == artworkKey && artworkBitmap != null) return
        if (key == artworkInFlightKey) return
        artworkKey = key
        artworkInFlightKey = key
        artworkExecutor.execute {
            val bitmap = runCatching {
                val model: Any = if (s.artworkAuth.isNotEmpty()) {
                    GlideUrl(
                        s.artworkUrl,
                        LazyHeaders.Builder()
                            .addHeader("Authorization", s.artworkAuth)
                            .addHeader("Trim-MC-token", s.artworkAuth)
                            .build(),
                    )
                } else {
                    s.artworkUrl
                }
                Glide.with(applicationContext)
                    .asBitmap()
                    .load(model)
                    .submit(ARTWORK_SIZE, ARTWORK_SIZE)
                    .get()
            }.getOrElse { err ->
                Log.w(TAG, "artwork load failed: ${err.message}")
                null
            }
            if (released || artworkInFlightKey != key || bitmap == null) {
                if (artworkInFlightKey == key) artworkInFlightKey = null
                return@execute
            }
            artworkInFlightKey = null
            // 回主线程刷新会话/通知。
            android.os.Handler(mainLooper).post {
                if (released || artworkKey != key) return@post
                artworkBitmap = bitmap
                val current = state ?: return@post
                mediaSession.setMetadata(buildMetadata(current, bitmap))
                startForegroundCompat(buildNotification(current))
            }
        }
    }

    // ---- 前台/通道 ----

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        startedForeground = true
    }

    private fun stopForegroundCompat() {
        if (!startedForeground) return
        stopForeground(STOP_FOREGROUND_REMOVE)
        startedForeground = false
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_playback_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_playback_description)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    /** 经 Intent extras 传输的会话快照（小字段）。 */
    private data class SessionState(
        val title: String,
        val subtitle: String,
        val artworkUrl: String,
        val artworkAuth: String,
        val isPlaying: Boolean,
        val positionMs: Long,
        val durationMs: Long,
        val speed: Float,
        val canNext: Boolean,
    ) {
        companion object {
            fun fromIntent(intent: Intent): SessionState? {
                val title = intent.getStringExtra("title") ?: return null
                return SessionState(
                    title = title,
                    subtitle = intent.getStringExtra("subtitle").orEmpty(),
                    artworkUrl = intent.getStringExtra("artworkUrl").orEmpty(),
                    artworkAuth = intent.getStringExtra("artworkAuth").orEmpty(),
                    isPlaying = intent.getBooleanExtra("isPlaying", false),
                    positionMs = intent.getLongExtra("positionMs", 0L),
                    durationMs = intent.getLongExtra("durationMs", 0L),
                    speed = intent.getFloatExtra("speed", 1f),
                    canNext = intent.getBooleanExtra("canNext", false),
                )
            }
        }
    }

    companion object {
        private const val TAG = "NativeMediaService"
        private const val SESSION_TAG = "fly_player_native_session"
        private const val CHANNEL_ID = "native_player_playback"
        private const val NOTIFICATION_ID = 3101
        private const val ARTWORK_SIZE = 512

        const val ACTION_UPDATE = "com.geqian.flyplayer.fly_player.media.UPDATE"
        const val ACTION_STOP = "com.geqian.flyplayer.fly_player.media.STOP_SERVICE"

        /** 推送/刷新会话状态并启动前台服务。 */
        fun update(
            context: Context,
            title: String,
            subtitle: String,
            artworkUrl: String,
            artworkAuth: String,
            isPlaying: Boolean,
            positionMs: Long,
            durationMs: Long,
            speed: Float,
            canNext: Boolean,
        ) {
            val intent = Intent(context, NativePlaybackMediaService::class.java).apply {
                action = ACTION_UPDATE
                putExtra("title", title)
                putExtra("subtitle", subtitle)
                putExtra("artworkUrl", artworkUrl)
                putExtra("artworkAuth", artworkAuth)
                putExtra("isPlaying", isPlaying)
                putExtra("positionMs", positionMs)
                putExtra("durationMs", durationMs)
                putExtra("speed", speed)
                putExtra("canNext", canNext)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, NativePlaybackMediaService::class.java).apply {
                        action = ACTION_STOP
                    },
                )
            }
            runCatching {
                context.stopService(Intent(context, NativePlaybackMediaService::class.java))
            }
        }
    }
}
