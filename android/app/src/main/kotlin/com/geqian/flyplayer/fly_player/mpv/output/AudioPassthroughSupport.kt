package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.util.Log

/**
 * 音频位流直通（杜比/DTS）的设备能力探测。
 *
 * mpv 通过 `audio-spdif=ac3,eac3,dts,dts-hd,truehd` 让 AudioTrack 走 passthrough，把压缩位流
 * 原样送给功放/回音壁/电视解码。`auto` 档先探测**当前输出设备**实际支持哪些编码，只对支持的
 * 开直通；`on` 档用户强制全开。两者结果都是给 mpv 的 `audio-spdif` 值（逗号分隔的编码名）。
 */
object AudioPassthroughSupport {

    private const val TAG = "FlyPlayerMpv"

    /** `on`（强制）档下发的完整编码集。 */
    const val ALL_CODECS = "ac3,eac3,dts,dts-hd,truehd"

    /** mpv 编码名 → 对应 AudioFormat 编码常量（探测设备支持用）。 */
    private val CODEC_TO_ENCODINGS: List<Pair<String, List<Int>>> = listOf(
        "ac3" to listOf(AudioFormat.ENCODING_AC3),
        // E-AC3 含 Atmos(JOC) 变体。
        "eac3" to listOf(AudioFormat.ENCODING_E_AC3, 18 /* ENCODING_E_AC3_JOC */),
        "dts" to listOf(AudioFormat.ENCODING_DTS),
        "dts-hd" to listOf(AudioFormat.ENCODING_DTS_HD),
        "truehd" to listOf(AudioFormat.ENCODING_DOLBY_TRUEHD),
    )

    /**
     * 探测当前输出设备支持的 spdif 编码集（mpv `audio-spdif` 值）。无可直通设备/低系统版本返回空串。
     * 优先用 AudioDeviceInfo.encodings（HDMI/eARC/USB 上报），辅以 AudioTrack.isDirectPlaybackSupported。
     */
    fun supportedSpdifCodecs(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return ""
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return ""
        val deviceEncodings = collectDeviceEncodings(audioManager)
        val supported = CODEC_TO_ENCODINGS.mapNotNull { (codec, encodings) ->
            val ok = encodings.any { enc ->
                deviceEncodings.contains(enc) || isDirectPlaybackSupported(enc)
            }
            if (ok) codec else null
        }
        val result = supported.joinToString(",")
        Log.d(TAG, "audio passthrough probe supported=[$result] deviceEncodings=$deviceEncodings")
        return result
    }

    private fun collectDeviceEncodings(audioManager: AudioManager): Set<Int> {
        val encodings = mutableSetOf<Int>()
        runCatching {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: return@runCatching
            for (device in devices) {
                if (!canCarryPassthrough(device)) continue
                // AudioDeviceInfo.getEncodings 返回设备声明支持的编码（可能为空，老设备/驱动不报）。
                for (enc in device.encodings) encodings.add(enc)
            }
        }
        return encodings
    }

    /** 只有外接数字音频链路（HDMI/eARC/USB/数字 line）才可能位流直通；内置喇叭/蓝牙 A2DP 不行。 */
    private fun canCarryPassthrough(device: AudioDeviceInfo): Boolean {
        return when (device.type) {
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC,
            AudioDeviceInfo.TYPE_HDMI_EARC,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            AudioDeviceInfo.TYPE_AUX_LINE,
            -> true
            else -> false
        }
    }

    private fun isDirectPlaybackSupported(encoding: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return runCatching {
            val format = AudioFormat.Builder()
                .setEncoding(encoding)
                .setSampleRate(48_000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
                .build()
            AudioTrack.isDirectPlaybackSupported(format, defaultAudioAttributes())
        }.getOrDefault(false)
    }

    private fun defaultAudioAttributes() =
        android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()
}
