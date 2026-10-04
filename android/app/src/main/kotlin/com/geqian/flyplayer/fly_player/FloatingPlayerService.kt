package com.geqian.flyplayer.fly_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.roundToInt

/**
 * 悬浮小窗前台服务（悬浮小窗方案 3.2）：承载 `TYPE_APPLICATION_OVERLAY` 窗口，
 * 窗口内容 [FloatingPlayerWindowView] 负责拖动 / 左右吸附 / 边缘拖拽自由缩放，
 * 渲染组（NativePlayerSurface 整体）由播放壳在交接流程中 reparent 进出（方案 3.3）。
 *
 * 能力门控：功能下限 API 26（minSdk=23，低版本不存在该窗口类型）+ `canDrawOverlays`
 * 悬浮窗权限；低版本 / 未授权 / 接入失败一律回退系统 PiP（阶段 1 五键体验）。
 * MIUI/HyperOS 的「后台弹出界面」权限见 [launchOverlayPermissionGuide] 的 TODO。
 *
 * 服务生命周期与播放任务绑定（stopWithTask=true）：划掉播放器任务 = 小窗关闭
 * （方案 3.4 的可接受限制，阶段 3 引擎服务化才解）。
 */
class FloatingPlayerService : Service(), FloatingWindowHost, FloatingPlayerWindowView.Callbacks {

    private var windowView: FloatingPlayerWindowView? = null

    @Volatile
    private var windowAttached = false

    private val windowManager by lazy {
        getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    private var interactionCallback: FloatingWindowHost.Callback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        startForegroundCompat(buildNotification())
        buildWindow()
        instance = this
        Log.i(TAG, "floating window service ready")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 幂等：重复 startForegroundService 只保活窗口，不重建。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        removeWindowInternal()
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ---- 窗口 ----

    private fun buildWindow() {
        if (windowAttached) return
        val view = FloatingPlayerWindowView(this, callbacks = this)
        view.restoreSize(savedWidthDp(this).dp)
        runCatching {
            windowManager.addView(view, view.windowParams)
            windowAttached = true
            windowView = view
        }.onFailure { error ->
            Log.w(TAG, "addView TYPE_APPLICATION_OVERLAY failed", error)
            windowView = null
            windowAttached = false
            // 建窗失败（权限被运行时收回等）：无窗可挂，自停；播放壳的宿主解析超时
            // 会走 abortSurfaceHandoff + enterPip 回退（方案 3.3 失败回退）。
            stopSelf()
        }
    }

    private fun removeWindowInternal() {
        val view = windowView
        windowView = null
        windowAttached = false
        if (view != null) {
            runCatching { windowManager.removeView(view) }
                .onFailure { error -> Log.w(TAG, "removeView failed", error) }
        }
    }

    // ---- FloatingPlayerWindowView.Callbacks（窗口交互回传播放壳） ----

    override fun onExpandRequested() {
        interactionCallback?.onExpandRequested()
    }

    override fun onWindowSizeSettled(widthPx: Int, heightPx: Int) {
        // 记忆上次尺寸（floating_mini_player_size，落 parallel_window_settings 同模式；
        // 存 dp 与密度解耦），并让播放壳按新尺寸重设 android-surface-size（方案 3.3）。
        val density = resources.displayMetrics.density
        saveWidthDp(this, (widthPx / density).roundToInt())
        interactionCallback?.onWindowSizeSettled()
    }

    // ---- FloatingWindowHost（播放壳交接的宿主半边） ----

    override val isActive: Boolean
        get() = windowAttached && windowView != null

    override fun setCallback(callback: FloatingWindowHost.Callback?) {
        interactionCallback = callback
    }

    override fun attachPlayerSurface(surface: View, freezeFrame: Bitmap?): Boolean {
        val view = windowView
        if (!isActive || view == null) return false
        return runCatching {
            view.installPlayerSurface(surface, freezeFrame)
            true
        }.onFailure { error ->
            Log.w(TAG, "attachPlayerSurface failed", error)
        }.getOrDefault(false)
    }

    override fun detachPlayerSurface(surface: View): Boolean {
        val view = windowView
        if (view == null) return false
        return view.takePlayerSurface(surface)
    }

    override fun removeWindow() {
        // 展开回全屏/关闭：窗口移除 + 服务自停（媒体通知由 NativePlaybackMediaService 承载）。
        removeWindowInternal()
        stopSelf()
    }

    // ---- 前台服务（先例 NativePlaybackMediaService.startForegroundCompat） ----

    private fun ensureNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            localizedString(R.string.player_floating_notification_channel),
            NotificationManager.IMPORTANCE_MIN,
        )
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(localizedString(R.string.player_floating_notification_title))
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()

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
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()

    companion object {
        private const val TAG = "FloatingPlayerService"
        private const val CHANNEL_ID = "native_player_floating"
        private const val NOTIFICATION_ID = 42001
        private const val PREFS_NAME = "parallel_window_settings"
        private const val KEY_SIZE = "floating_mini_player_size"

        @Volatile
        private var instance: FloatingPlayerService? = null

        /** 活跃宿主（服务存活且窗口已挂载）；播放壳交接前解析用。 */
        val activeHost: FloatingWindowHost?
            get() = instance?.takeIf { it.isActive }

        /**
         * 能力就绪判定：API 26+ 且已授予悬浮窗权限。
         * MIUI/HyperOS 的「后台弹出界面」另需专项授权（TODO 见 [launchOverlayPermissionGuide]）。
         */
        fun canHostFloatingWindow(context: Context): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Settings.canDrawOverlays(context)

        /** 启动/保活服务（建窗异步，播放壳以 [activeHost] 有界重试解析）。 */
        fun requestEnter(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, FloatingPlayerService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FloatingPlayerService::class.java))
        }

        /**
         * 悬浮窗权限一次性内联引导：跳系统「显示在应用上层」设置页（带应用包名 Uri）。
         *
         * TODO(MIUI/HyperOS，方案 3.2 / 开放问题 2)：MIUI 还要求「后台弹出界面」权限，
         * 否则小窗只在应用前台可见；其设置页组件名各版本有差异，需真机用
         * `adb shell appops get <pkg> SYSTEM_ALERT_WINDOW` 观察授权前后差异后确认，
         * 确认前这里只跳通用悬浮窗设置页，MIUI 特有引导暂缺——未授权后台弹出时
         * 用户感知为小窗不可见，属回退路径（回退系统 PiP 由播放壳入口三态覆盖）。
         */
        fun launchOverlayPermissionGuide(activity: android.app.Activity): Boolean = runCatching {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            true
        }.onFailure { error ->
            Log.w(TAG, "launch overlay permission settings failed", error)
        }.getOrDefault(false)

        /** 记忆上次尺寸（存 dp 与密度解耦；键与方案 3.5/3.6 约定一致）。 */
        fun savedWidthDp(context: Context): Int =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getInt(KEY_SIZE, FloatingPlayerWindowPolicy.DEFAULT_WIDTH_DP)

        private fun saveWidthDp(context: Context, widthDp: Int) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_SIZE, widthDp.coerceAtLeast(FloatingPlayerWindowPolicy.MIN_WIDTH_DP))
                .apply()
        }
    }
}
