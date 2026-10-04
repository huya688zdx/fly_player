package com.geqian.flyplayer.fly_player

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * HyperOS PowerKeeper 前台限帧自动恢复。
 *
 * 实测（2026-10-04，2410CRP4CC / HyperOS）：com.miui.powerkeeper 在本应用每次进前台后
 * 60~230ms 内直写 secure miui_refresh_rate=60（SettingsProvider 日志可查写入方），
 * 切回桌面再写回 120；display 策略层随之把整机钳到 60Hz，应用侧
 * preferredDisplayModeId / preferredRefreshRate / 帧率类别票均顶不开 primary 钳制
 * （机制与 A/B 证据见 docs/plans/hyperos-cloud-fps-lock.md）。按应用省电策略设为
 * 「无限制」、pm disable-user / pm suspend（shell 权限）均无法阻止该写入。
 *
 * 这里注册 ContentObserver 监听该键：一旦被写低（低于用户在系统设置里选择的
 * user_refresh_rate），在应用已获 WRITE_SECURE_SETTINGS 授权（adb 授予，可选）时
 * 写回用户值。未授权时本类完全休眠（canWrite 即 false），零开销零副作用；
 * 用户主动把刷新率选成 60 时目标值同为 60，不会对抗用户选择。
 */
class HyperosRefreshRateGuard(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var started = false

    private val observer = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            scheduleRestoreIfClamped()
        }
    }

    fun start() {
        if (started || !canWriteSecureSettings()) return
        started = true
        context.contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(KEY_MIUI_REFRESH_RATE),
            false,
            observer,
        )
        // 进前台先自检一次：钳制写入可能发生在 resume 与本类注册之间的窗口期。
        scheduleRestoreIfClamped()
    }

    fun stop() {
        if (!started) return
        started = false
        context.contentResolver.unregisterContentObserver(observer)
        mainHandler.removeCallbacksAndMessages(null)
    }

    private fun scheduleRestoreIfClamped() {
        if (!canWriteSecureSettings()) return
        mainHandler.post {
            val miui = Settings.Secure.getString(context.contentResolver, KEY_MIUI_REFRESH_RATE)
            val user = Settings.Secure.getString(context.contentResolver, KEY_USER_REFRESH_RATE)
            val peak = Settings.System.getString(context.contentResolver, KEY_PEAK_REFRESH_RATE)
            val restoreTo = resolveRestoreTarget(miui, user, peak) ?: return@post
            Settings.Secure.putString(context.contentResolver, KEY_MIUI_REFRESH_RATE, restoreTo)
            Log.i(TAG, "clamped miui_refresh_rate=$miui < target=$restoreTo, restored")
        }
    }

    private fun canWriteSecureSettings(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_SECURE_SETTINGS) ==
            PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "HyperosRateGuard"
        private const val KEY_MIUI_REFRESH_RATE = "miui_refresh_rate"
        private const val KEY_USER_REFRESH_RATE = "user_refresh_rate"
        private const val KEY_PEAK_REFRESH_RATE = "peak_refresh_rate"
        // “明显低于”的容差：60 与 120/144 之间没有合法的中间选择，0.5Hz 足够区分。
        private const val CLAMP_EPSILON_HZ = 0.5f

        /** 钳制判定：miui_refresh_rate 明显低于用户选择/系统峰值时，返回要写回的原样目标串。 */
        internal fun resolveRestoreTarget(
            miuiRefreshRate: String?,
            userRefreshRate: String?,
            systemPeakRefreshRate: String?,
        ): String? {
            val current = miuiRefreshRate?.toFloatOrNull() ?: return null
            val target = listOfNotNull(userRefreshRate, systemPeakRefreshRate)
                .firstOrNull { it.toFloatOrNull() != null }
                ?: return null
            return if (current + CLAMP_EPSILON_HZ < target.toFloat()) target else null
        }
    }
}
