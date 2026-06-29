package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import android.util.Log
import com.geqian.flyplayer.fly_player.R

/**
 * 手机端「杜比全景声 / 空间音频」能力探测。
 *
 * 手机自带喇叭/耳机上的 Atmos，不是位流直通（那条只走 HDMI/eARC，见 [AudioPassthroughSupport]），
 * 而是 Android 12L+ 的 **Spatializer（空间音频）**：系统把多声道 PCM 虚拟化成沉浸声场。
 * 要触发它有两个前提：
 *   1. 设备有可用且已开启的 Spatializer（本探针判定）；
 *   2. 播放器输出的是**多声道** PCM，而不是提前下混的立体声——否则系统拿不到声床可虚拟化。
 *
 * 所以非直通链路里，一旦探到 Spatializer 可用，就让 mpv 输出原生多声道（见
 * MpvAdvancedSettingsController.applyAudioProcessing），把 Atmos 声床交给系统渲染。
 */
object AudioSpatializerSupport {

    private const val TAG = "FlyPlayerMpv"

    data class Probe(
        val supported: Boolean,
        val available: Boolean,
        val enabled: Boolean,
        val immersiveLevel: String,
        val canSpatialize51: Boolean,
    ) {
        /** 诊断面板用的一行摘要。 */
        fun summary(context: Context): String = when {
            !supported -> context.getString(R.string.mpv_spatializer_unsupported)
            !available -> context.getString(R.string.mpv_spatializer_hardware_unavailable)
            !enabled -> context.getString(R.string.mpv_spatializer_disabled)
            canSpatialize51 -> context.getString(R.string.mpv_spatializer_enabled, immersiveLevel)
            else -> context.getString(R.string.mpv_spatializer_enabled_not_virtualizable)
        }

        /** 满足触发条件：可用 + 已开启 + 能虚拟化 5.1。 */
        fun shouldOutputMultichannel(): Boolean = available && enabled && canSpatialize51
    }

    fun probe(context: Context): Probe {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S_V2) {
            return Probe(
                supported = false,
                available = false,
                enabled = false,
                immersiveLevel = "—",
                canSpatialize51 = false,
            )
        }
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return Probe(false, false, false, "—", false)
        return runCatching {
            val spatializer = audioManager.spatializer
            val available = spatializer.isAvailable
            val enabled = spatializer.isEnabled
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val format51 = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(48_000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
                .build()
            val canSpatialize = available && spatializer.canBeSpatialized(attributes, format51)
            val probe = Probe(
                supported = true,
                available = available,
                enabled = enabled,
                immersiveLevel = immersiveLevelLabel(context, spatializer.immersiveAudioLevel),
                canSpatialize51 = canSpatialize,
            )
            Log.d(
                TAG,
                "spatializer probe available=$available enabled=$enabled level=${probe.immersiveLevel} canSpatialize5.1=$canSpatialize",
            )
            probe
        }.getOrElse { error ->
            Log.w(TAG, "spatializer probe failed", error)
            Probe(false, false, false, "—", false)
        }
    }

    /** 是否应让 mpv 输出多声道交系统空间音频虚拟化。 */
    fun prefersMultichannelOutput(context: Context): Boolean = probe(context).shouldOutputMultichannel()

    // Spatializer 沉浸级别常量值（部分常量在 compileSdk 上不可见，用字面值）：
    // 0=NONE 1=MULTICHANNEL 2=MCHAN_BED_PLUS_OBJECTS(声床+对象，即真 Atmos)。
    private fun immersiveLevelLabel(context: Context, level: Int): String = when (level) {
        0 -> context.getString(R.string.mpv_spatializer_level_none)
        1 -> context.getString(R.string.mpv_spatializer_level_multichannel)
        2 -> context.getString(R.string.mpv_spatializer_level_bed_objects)
        else -> context.getString(R.string.mpv_spatializer_level_unknown, level)
    }
}
