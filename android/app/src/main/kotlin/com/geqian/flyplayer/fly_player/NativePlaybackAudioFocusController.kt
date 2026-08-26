package com.geqian.flyplayer.fly_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * 原生播放壳的音频焦点 + 拔耳机暂停控制器。
 *
 * 旧 Flutter 壳的系统媒体集成完全没接到 [NativePlayerActivity]，导致：来电/其他 App 抢
 * 焦点不会暂停、拔耳机继续外放、纯听切后台被系统掐断。本控制器把这一层补到原生壳上，
 * 命令通过构造回调直达 [NativePlayerSurface]（不经 Flutter）。
 *
 * 焦点策略（对齐计划 Phase 1）：
 *  - LOSS（永久，如其他播放器抢占）→ 暂停，不自动恢复；
 *  - LOSS_TRANSIENT（来电等短暂）→ 暂停并记录，焦点恢复时续播；
 *  - LOSS_TRANSIENT_CAN_DUCK（导航播报等）→ 临时压低音量，恢复时还原；
 *  - GAIN → 若此前因短暂丢失而暂停则续播，并还原 duck 音量。
 */
class NativePlaybackAudioFocusController(
    context: Context,
    private val onShouldPause: () -> Unit,
    private val onMayResume: () -> Unit,
    private val onDuck: () -> Unit,
    private val onRestoreFromDuck: () -> Unit,
) {
    private val appContext = context.applicationContext
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var hasFocus = false
    // 仅当因「短暂丢失」而暂停时置 true，焦点回来才自动续播；用户/永久丢失暂停不自动恢复。
    private var pausedByTransientLoss = false
    private var ducking = false

    private var focusRequest: AudioFocusRequest? = null
    private var noisyReceiverRegistered = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                Log.d(TAG, "focus LOSS")
                hasFocus = false
                pausedByTransientLoss = false
                if (ducking) {
                    ducking = false
                    onRestoreFromDuck()
                }
                onShouldPause()
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                Log.d(TAG, "focus LOSS_TRANSIENT")
                if (ducking) {
                    ducking = false
                    onRestoreFromDuck()
                }
                pausedByTransientLoss = true
                onShouldPause()
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                Log.d(TAG, "focus CAN_DUCK")
                if (!ducking) {
                    ducking = true
                    onDuck()
                }
            }

            AudioManager.AUDIOFOCUS_GAIN -> {
                Log.d(TAG, "focus GAIN")
                hasFocus = true
                if (ducking) {
                    ducking = false
                    onRestoreFromDuck()
                }
                if (pausedByTransientLoss) {
                    pausedByTransientLoss = false
                    onMayResume()
                }
            }
        }
    }

    val isHeld: Boolean
        get() = hasFocus

    /** 请求音频焦点（幂等：已持有直接返回 true）。播放开始前调用。 */
    fun ensureFocus(): Boolean {
        if (hasFocus) return true
        val granted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs =
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                val request =
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(attrs)
                        .setWillPauseWhenDucked(false)
                        .setOnAudioFocusChangeListener(focusListener)
                        .build()
                focusRequest = request
                audioManager.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    focusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
            }
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        Log.d(TAG, "ensureFocus granted=$hasFocus")
        return hasFocus
    }

    /** 释放音频焦点（暂停/销毁时调用）。 */
    fun abandon() {
        if (!hasFocus && focusRequest == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        hasFocus = false
        pausedByTransientLoss = false
        ducking = false
    }

    /** 注册「拔耳机/断开蓝牙音频」广播：收到即暂停（系统会把声音切回外放，避免突然公放）。 */
    fun registerBecomingNoisy() {
        if (noisyReceiverRegistered) return
        appContext.registerReceiver(
            becomingNoisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
        )
        noisyReceiverRegistered = true
    }

    fun unregisterBecomingNoisy() {
        if (!noisyReceiverRegistered) return
        runCatching { appContext.unregisterReceiver(becomingNoisyReceiver) }
        noisyReceiverRegistered = false
    }

    private val becomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                Log.d(TAG, "AUDIO_BECOMING_NOISY → pause")
                pausedByTransientLoss = false
                onShouldPause()
            }
        }
    }

    /** Activity 销毁时一次性清理。 */
    fun release() {
        abandon()
        unregisterBecomingNoisy()
    }

    companion object {
        private const val TAG = "NativeAudioFocus"
    }
}
