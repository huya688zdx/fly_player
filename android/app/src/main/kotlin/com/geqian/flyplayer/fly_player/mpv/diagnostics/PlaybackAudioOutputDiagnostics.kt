package com.geqian.flyplayer.fly_player.mpv

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

data class PlaybackAudioOutputDiagnosticsSnapshot(
    val connectedAudioSummary: String?,
    val usbAudioConnected: Boolean,
    val usbAudioSummary: String?,
    val systemOutputSampleRate: Int?,
    val systemOutputFramesPerBuffer: Int?,
)

class PlaybackAudioOutputDiagnostics(
    private val audioManager: AudioManager?,
) {
    fun snapshot(): PlaybackAudioOutputDiagnosticsSnapshot {
        val devices = currentOutputAudioDevices()
        val usbDevices = devices.filter(::isUsbAudioDevice)
        return PlaybackAudioOutputDiagnosticsSnapshot(
            connectedAudioSummary = devices.joinSummary(),
            usbAudioConnected = usbDevices.isNotEmpty(),
            usbAudioSummary = usbDevices.joinSummary(),
            systemOutputSampleRate = resolveSystemOutputSampleRate(),
            systemOutputFramesPerBuffer = resolveSystemOutputFramesPerBuffer(),
        )
    }

    private fun resolveSystemOutputSampleRate(): Int? {
        val raw = audioManager?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
        return raw?.toIntOrNull()?.takeIf { it > 0 }
    }

    private fun resolveSystemOutputFramesPerBuffer(): Int? {
        val raw = audioManager?.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
        return raw?.toIntOrNull()?.takeIf { it > 0 }
    }

    private fun currentOutputAudioDevices(): List<AudioDeviceInfo> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        val devices = runCatching {
            audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.toList().orEmpty()
        }.getOrDefault(emptyList())
        return devices.filterNot { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE }
    }

    private fun isUsbAudioDevice(device: AudioDeviceInfo): Boolean {
        return when (device.type) {
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            -> true
            else -> false
        }
    }

    private fun describeAudioDevice(device: AudioDeviceInfo): String {
        val typeLabel = when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth audio"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth call"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB accessory audio"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
            AudioDeviceInfo.TYPE_HDMI -> "HDMI"
            AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI ARC"
            AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI eARC"
            AudioDeviceInfo.TYPE_LINE_ANALOG -> "Analog line out"
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Digital line out"
            else -> "Other output"
        }
        val productName = device.productName?.toString()?.trim().orEmpty()
        if (productName.isEmpty()) return typeLabel
        return "$typeLabel: $productName"
    }

    private fun List<AudioDeviceInfo>.joinSummary(): String? {
        if (isEmpty()) return null
        return joinToString(" / ", transform = ::describeAudioDevice)
    }
}
