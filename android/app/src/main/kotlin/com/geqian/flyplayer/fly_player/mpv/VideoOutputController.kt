package com.geqian.flyplayer.fly_player.mpv

import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.util.Locale

private const val VIDEO_OUTPUT_TAG = "FlyPlayerMpv"
private const val VIDEO_OUTPUT_GPU = "gpu"
private const val VIDEO_OUTPUT_NONE = "null"
private const val VIDEO_HWDEC_DEFAULT = "mediacodec,auto-safe"
private const val VIDEO_HWDEC_HDR_COPY = "mediacodec-copy"
private const val VIDEO_HWDEC_DISABLED = "no"
private const val VIDEO_ASPECT_OVERRIDE_NONE = "no"
private const val VIDEO_ASPECT_MODE_FIT = "fit"
private const val VIDEO_ASPECT_MODE_FILL = "fill"
private const val VIDEO_ASPECT_MODE_4X3 = "4:3"
private const val VIDEO_ASPECT_MODE_16X9 = "16:9"
private const val VIDEO_ASPECT_MODE_21X9 = "21:9"
private const val VIDEO_TONE_MAPPING = "bt.2390"
private const val VIDEO_TARGET_PRIM_SDR = "bt.709"
private const val VIDEO_TARGET_TRC_SDR = "bt.1886"

class VideoOutputController(
    private val surfaceView: SurfaceView,
    private val hostActivity: Activity?,
    val displayProfile: DisplayProfile,
    val deviceProfile: DeviceProfile,
    private val runOnMainThread: (() -> Unit) -> Unit,
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    var surfaceReady = false
        private set
    var surfaceAttached = false
        private set
    var videoOutputReady = false
        private set
    var videoTrackSuspended = false
        private set
    var activeHwdecMode = VIDEO_HWDEC_DEFAULT
        private set
    var forcedHwdecMode: String? = null
        private set
    private var userHwdecMode: String? = null
    private var displayAspectRatioMode = VIDEO_ASPECT_MODE_FIT
    var forcedColorPipeline: VideoColorPipeline? = null
        private set
    var activeColorPipeline = VideoColorPipeline.SDR
        private set

    fun resetForSourceLoad() {
        forcedHwdecMode = null
        forcedColorPipeline = null
        activeColorPipeline = VideoColorPipeline.SDR
    }

    fun onDispose() {
        surfaceAttached = false
        videoOutputReady = false
        videoTrackSuspended = false
        activeColorPipeline = VideoColorPipeline.SDR
        applyWindowColorMode(VideoColorPipeline.SDR)
    }

    fun onSurfaceCreated(holder: SurfaceHolder): Boolean {
        surfaceReady = true
        return runCatching {
            mpv.attachSurface(holder.surface)
            surfaceAttached = true
            videoOutputReady = false
            true
        }.onFailure { error ->
            Log.e(VIDEO_OUTPUT_TAG, "surfaceCreated attach failed", error)
        }.getOrDefault(false)
    }

    fun onSurfaceDestroyed(initialized: Boolean, available: Boolean) {
        surfaceReady = false
        surfaceAttached = false
        videoOutputReady = false
        if (!initialized || !available) return
        runCatching {
            mpv.setPropertyString("vid", "no")
            videoTrackSuspended = true
            mpv.setPropertyString("vo", VIDEO_OUTPUT_NONE)
            mpv.detachSurface()
        }.onFailure { error ->
            Log.e(VIDEO_OUTPUT_TAG, "suspendVideoOutputForSurfaceLoss failed", error)
        }
        applyWindowColorMode(VideoColorPipeline.SDR)
    }

    fun hasUsableVideoOutputTarget(): Boolean {
        return surfaceReady && surfaceAttached && currentSurfaceValid()
    }

    fun isSurfaceValid(): Boolean = currentSurfaceValid()

    fun preferredHwdecMode(source: MpvSource): String {
        if (userHwdecMode == VIDEO_HWDEC_DISABLED) {
            return VIDEO_HWDEC_DISABLED
        }
        forcedHwdecMode?.let { return it }
        return if (source.isHdrLikely() && deviceProfile.isLikelyMali) {
            VIDEO_HWDEC_HDR_COPY
        } else {
            VIDEO_HWDEC_DEFAULT
        }
    }

    fun setDecoderMode(mode: String?): Boolean {
        val normalized = mode?.trim()?.lowercase(Locale.US)
        val nextUserMode = when (normalized) {
            "software", "soft", VIDEO_HWDEC_DISABLED -> VIDEO_HWDEC_DISABLED
            else -> null
        }
        val changed =
            userHwdecMode != nextUserMode ||
                forcedHwdecMode != null
        userHwdecMode = nextUserMode
        forcedHwdecMode = null
        return changed
    }

    fun setDisplayAspectRatioMode(
        mode: String?,
        initialized: Boolean,
        available: Boolean,
    ): Boolean {
        val normalized = when (mode?.trim()?.lowercase(Locale.US)) {
            VIDEO_ASPECT_MODE_FILL -> VIDEO_ASPECT_MODE_FILL
            VIDEO_ASPECT_MODE_4X3 -> VIDEO_ASPECT_MODE_4X3
            VIDEO_ASPECT_MODE_16X9 -> VIDEO_ASPECT_MODE_16X9
            VIDEO_ASPECT_MODE_21X9 -> VIDEO_ASPECT_MODE_21X9
            else -> VIDEO_ASPECT_MODE_FIT
        }
        val changed = displayAspectRatioMode != normalized
        displayAspectRatioMode = normalized
        if (initialized && available) {
            applyDisplayAspectRatioMode()
        }
        return changed
    }

    fun preferredColorPipeline(source: MpvSource): VideoColorPipeline {
        forcedColorPipeline?.let { return it }
        if (!source.isHdrLikely()) return VideoColorPipeline.SDR
        return if (displayProfile.supportsHdr) {
            VideoColorPipeline.HDR_DIRECT
        } else {
            VideoColorPipeline.HDR_TONEMAP_SDR
        }
    }

    fun shouldForceSourceReloadAfterSurfaceRestore(source: MpvSource): Boolean {
        return source.isHdrLikely() && deviceProfile.isLikelyMali
    }

    fun restoreVideoTrackAfterSurfaceReady(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        if (!videoTrackSuspended) return true
        return runCatching {
            mpv.setPropertyString("vid", "auto")
            videoTrackSuspended = false
            true
        }.onFailure { error ->
            Log.e(VIDEO_OUTPUT_TAG, "restoreVideoTrackAfterSurfaceReady failed", error)
        }.getOrDefault(false)
    }

    fun ensureVideoTrackSelected(initialized: Boolean, available: Boolean): Boolean {
        if (!initialized || !available) return false
        return runCatching {
            mpv.setPropertyString("vid", "auto")
            videoTrackSuspended = false
            true
        }.onFailure { error ->
            Log.e(VIDEO_OUTPUT_TAG, "ensureVideoTrackSelected failed", error)
        }.getOrDefault(false)
    }

    fun ensureVideoOutputReady(
        initialized: Boolean,
        available: Boolean,
        source: MpvSource,
    ): Boolean {
        if (!initialized || !available) return false
        if (!hasUsableVideoOutputTarget()) return false
        val targetHwdecMode = preferredHwdecMode(source)
        val targetColorPipeline = preferredColorPipeline(source)
        return runCatching {
            if (activeHwdecMode != targetHwdecMode) {
                mpv.setPropertyString("hwdec", targetHwdecMode)
                activeHwdecMode = targetHwdecMode
            }
            applyColorPipeline(targetColorPipeline)
            applyWindowColorMode(targetColorPipeline)
            mpv.setPropertyString("vo", VIDEO_OUTPUT_GPU)
            mpv.setPropertyBoolean("force-window", true)
            applyDisplayAspectRatioMode()
            videoOutputReady = true
            Log.i(
                VIDEO_OUTPUT_TAG,
                "video pipeline hwdec=$activeHwdecMode colorPipeline=$activeColorPipeline hdr=${source.isHdrLikely()} mali=${deviceProfile.isLikelyMali} displayHdr=${displayProfile.supportsHdr} source=[${source.debugSummary()}]",
            )
            true
        }.onFailure { error ->
            videoOutputReady = false
            Log.e(
                VIDEO_OUTPUT_TAG,
                "ensureVideoOutputReady failed hwdec=$targetHwdecMode colorPipeline=$targetColorPipeline",
                error,
            )
        }.getOrDefault(false)
    }

    fun recoverVideoOutputOnly(
        reason: String,
        initialized: Boolean,
        available: Boolean,
    ) {
        if (!initialized || !available) return
        if (!surfaceReady || !currentSurfaceValid()) {
            Log.w(VIDEO_OUTPUT_TAG, "skip video output recovery reason=$reason surfaceReady=$surfaceReady")
            return
        }
        runCatching {
            if (!surfaceAttached) {
                mpv.attachSurface(surfaceView.holder.surface)
                surfaceAttached = true
            }
            videoOutputReady = false
        }.onFailure { error ->
            Log.e(VIDEO_OUTPUT_TAG, "recoverVideoOutput failed reason=$reason", error)
        }
    }

    fun maybeTriggerHdrHwdecFallback(source: MpvSource, lowerMessage: String): Boolean {
        val riskyBufferFormat =
            lowerMessage.contains("unsupported format") || lowerMessage.contains("invalid base format")
        if (!riskyBufferFormat) return false
        if (!source.isHdrLikely()) return false
        if (preferredHwdecMode(source) != VIDEO_HWDEC_HDR_COPY) {
            forcedHwdecMode = VIDEO_HWDEC_HDR_COPY
            Log.w(
                VIDEO_OUTPUT_TAG,
                "forcing hdr hwdec fallback to $forcedHwdecMode after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
            )
            return true
        }
        if (preferredColorPipeline(source) != VideoColorPipeline.HDR_TONEMAP_SDR) {
            forcedColorPipeline = VideoColorPipeline.HDR_TONEMAP_SDR
            Log.w(
                VIDEO_OUTPUT_TAG,
                "forcing hdr color fallback to $forcedColorPipeline after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
            )
            return true
        }
        return false
    }

    fun maybeTriggerSoftwareDecoderFallback(source: MpvSource, lowerMessage: String): Boolean {
        if (preferredHwdecMode(source) == VIDEO_HWDEC_DISABLED) return false
        val hardwareDecodeFailure =
            (lowerMessage.contains("mediacodec") &&
                (
                    lowerMessage.contains("failed") ||
                        lowerMessage.contains("error") ||
                        lowerMessage.contains("unsupported") ||
                        lowerMessage.contains("invalid")
                )) ||
                lowerMessage.contains("hardware decoding failed") ||
                lowerMessage.contains("failed to initialize decoder") ||
                lowerMessage.contains("failed to configure codec") ||
                lowerMessage.contains("codec type is not supported by mediacodec") ||
                lowerMessage.contains("hwdec") && lowerMessage.contains("failed")
        if (!hardwareDecodeFailure) return false
        userHwdecMode = VIDEO_HWDEC_DISABLED
        forcedHwdecMode = null
        Log.w(
            VIDEO_OUTPUT_TAG,
            "forcing software decoder fallback after log=\"$lowerMessage\" source=[${source.debugSummary()}]",
        )
        return true
    }

    fun currentWindowColorMode(): String {
        val activity = hostActivity ?: return "unknown"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        return when (activity.window.colorMode) {
            ActivityInfo.COLOR_MODE_DEFAULT -> "DEFAULT"
            ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT -> "WIDE_COLOR_GAMUT"
            ActivityInfo.COLOR_MODE_HDR -> "HDR"
            else -> activity.window.colorMode.toString()
        }
    }

    private fun currentSurfaceValid(): Boolean {
        return runCatching { surfaceView.holder.surface?.isValid == true }.getOrDefault(false)
    }

    private fun applyWindowColorMode(targetColorPipeline: VideoColorPipeline) {
        val activity = hostActivity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val colorMode = when (targetColorPipeline) {
            VideoColorPipeline.HDR_DIRECT -> ActivityInfo.COLOR_MODE_HDR
            VideoColorPipeline.HDR_TONEMAP_SDR ->
                if (displayProfile.supportsWideColorGamut) {
                    ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT
                } else {
                    ActivityInfo.COLOR_MODE_DEFAULT
                }
            VideoColorPipeline.SDR -> ActivityInfo.COLOR_MODE_DEFAULT
        }
        runOnMainThread {
            runCatching {
                if (activity.window.colorMode != colorMode) {
                    activity.window.colorMode = colorMode
                    Log.i(VIDEO_OUTPUT_TAG, "window colorMode=$colorMode pipeline=$targetColorPipeline")
                }
            }.onFailure { error ->
                Log.w(VIDEO_OUTPUT_TAG, "applyWindowColorMode failed pipeline=$targetColorPipeline", error)
            }
        }
    }

    private fun applyDisplayAspectRatioMode() {
        when (displayAspectRatioMode) {
            VIDEO_ASPECT_MODE_FILL -> {
                mpv.setPropertyString("video-aspect-override", VIDEO_ASPECT_OVERRIDE_NONE)
                mpv.setPropertyDouble("panscan", 1.0)
            }
            VIDEO_ASPECT_MODE_4X3,
            VIDEO_ASPECT_MODE_16X9,
            VIDEO_ASPECT_MODE_21X9 -> {
                mpv.setPropertyString("video-aspect-override", displayAspectRatioMode)
                mpv.setPropertyDouble("panscan", 0.0)
            }
            else -> {
                mpv.setPropertyString("video-aspect-override", VIDEO_ASPECT_OVERRIDE_NONE)
                mpv.setPropertyDouble("panscan", 0.0)
            }
        }
    }

    private fun applyColorPipeline(targetColorPipeline: VideoColorPipeline) {
        if (activeColorPipeline == targetColorPipeline) return
        when (targetColorPipeline) {
            VideoColorPipeline.SDR -> {
                mpv.setPropertyString("target-prim", "auto")
                mpv.setPropertyString("target-trc", "auto")
                mpv.setPropertyString("target-colorspace-hint", "auto")
                mpv.setPropertyString("tone-mapping", "auto")
                mpv.setPropertyString("gamut-mapping-mode", "auto")
            }
            VideoColorPipeline.HDR_DIRECT -> {
                mpv.setPropertyString("target-prim", "auto")
                mpv.setPropertyString("target-trc", "auto")
                mpv.setPropertyString("target-colorspace-hint", "yes")
                mpv.setPropertyString("tone-mapping", "auto")
                mpv.setPropertyString("gamut-mapping-mode", "auto")
            }
            VideoColorPipeline.HDR_TONEMAP_SDR -> {
                mpv.setPropertyString("target-colorspace-hint", "auto")
                mpv.setPropertyString("target-prim", VIDEO_TARGET_PRIM_SDR)
                mpv.setPropertyString("target-trc", VIDEO_TARGET_TRC_SDR)
                mpv.setPropertyString("tone-mapping", VIDEO_TONE_MAPPING)
                mpv.setPropertyString("gamut-mapping-mode", "clip")
            }
        }
        activeColorPipeline = targetColorPipeline
    }
}
