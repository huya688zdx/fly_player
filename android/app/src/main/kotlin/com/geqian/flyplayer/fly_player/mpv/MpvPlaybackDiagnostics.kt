package com.geqian.flyplayer.fly_player.mpv

data class MpvPlaybackDiagnosticsSnapshot(
    val playback: Map<String, Any?>,
    val source: Map<String, Any?>,
    val output: Map<String, Any?>,
    val display: Map<String, Any?>,
    val windowColorMode: String,
)

object MpvPlaybackDiagnosticsBuilder {
    fun build(
        snapshot: MpvPlaybackDiagnosticsSnapshot,
        mpv: MpvFacade = DefaultMpvFacade,
    ): Map<String, Any?> {
        val output = LinkedHashMap(snapshot.output)
        output["windowColorMode"] = snapshot.windowColorMode
        val mpvInfo = linkedMapOf<String, Any?>(
            "vo" to safeGetPropertyString(mpv, "vo"),
            "hwdecCurrent" to safeGetPropertyString(mpv, "hwdec-current"),
            "path" to safeGetPropertyString(mpv, "path"),
            "displayDepth" to safeGetPropertyInt(mpv, "display-depth"),
            "targetColorspaceHint" to safeGetPropertyString(mpv, "target-colorspace-hint"),
            "targetPrim" to safeGetPropertyString(mpv, "target-prim"),
            "targetTrc" to safeGetPropertyString(mpv, "target-trc"),
            "toneMapping" to safeGetPropertyString(mpv, "tone-mapping"),
            "scale" to safeGetPropertyString(mpv, "scale"),
            "cscale" to safeGetPropertyString(mpv, "cscale"),
            "dscale" to safeGetPropertyString(mpv, "dscale"),
            "tscale" to safeGetPropertyString(mpv, "tscale"),
            "interpolation" to safeGetPropertyString(mpv, "interpolation"),
            "correctDownscaling" to safeGetPropertyString(mpv, "correct-downscaling"),
            "sigmoidUpscaling" to safeGetPropertyString(mpv, "sigmoid-upscaling"),
            "deband" to safeGetPropertyString(mpv, "deband"),
            "videoSync" to safeGetPropertyString(mpv, "video-sync"),
            "videoFormat" to safeGetPropertyString(mpv, "video-format"),
            "videoCodec" to safeGetPropertyString(mpv, "video-codec"),
            "audioCodec" to safeGetPropertyString(mpv, "audio-codec-name"),
            "videoParamsW" to safeGetPropertyInt(mpv, "video-params/w"),
            "videoParamsH" to safeGetPropertyInt(mpv, "video-params/h"),
            "videoParamsPixelformat" to safeGetPropertyString(mpv, "video-params/pixelformat"),
            "videoParamsHwPixelformat" to safeGetPropertyString(mpv, "video-params/hw-pixelformat"),
            "videoParamsColorlevels" to safeGetPropertyString(mpv, "video-params/colorlevels"),
            "videoParamsPrimaries" to safeGetPropertyString(mpv, "video-params/primaries"),
            "videoParamsGamma" to safeGetPropertyString(mpv, "video-params/gamma"),
            "videoParamsColormatrix" to safeGetPropertyString(mpv, "video-params/colormatrix"),
            "videoParamsSigPeak" to safeGetPropertyDouble(mpv, "video-params/sig-peak"),
            "videoOutParamsPixelformat" to safeGetPropertyString(mpv, "video-out-params/pixelformat"),
            "videoOutParamsColorlevels" to safeGetPropertyString(mpv, "video-out-params/colorlevels"),
            "videoOutParamsPrimaries" to safeGetPropertyString(mpv, "video-out-params/primaries"),
            "videoOutParamsGamma" to safeGetPropertyString(mpv, "video-out-params/gamma"),
            "videoOutParamsColormatrix" to safeGetPropertyString(mpv, "video-out-params/colormatrix"),
            "videoOutParamsSigPeak" to safeGetPropertyDouble(mpv, "video-out-params/sig-peak"),
        )
        return linkedMapOf(
            "playback" to snapshot.playback,
            "source" to snapshot.source,
            "output" to output,
            "display" to snapshot.display,
            "mpv" to mpvInfo,
        )
    }

    private fun safeGetPropertyString(mpv: MpvFacade, property: String): String? {
        return runCatching { mpv.getPropertyString(property) }
            .getOrNull()
            ?.trim()
            ?.takeUnless { it.isEmpty() || it == "-" }
    }

    private fun safeGetPropertyInt(mpv: MpvFacade, property: String): Long? {
        return sanitizeMpvIntProperty(
            property = property,
            value = runCatching { mpv.getPropertyInt(property) }.getOrNull(),
        )
    }

    private fun safeGetPropertyDouble(mpv: MpvFacade, property: String): Double? {
        return sanitizeMpvDoubleProperty(
            property = property,
            value = runCatching { mpv.getPropertyDouble(property) }.getOrNull(),
        )
    }
}
