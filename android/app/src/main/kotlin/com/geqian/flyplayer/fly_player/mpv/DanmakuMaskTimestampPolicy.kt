package com.geqian.flyplayer.fly_player.mpv

internal enum class DanmakuMaskTimestampAction {
    LEGACY,
    BUFFER_MASK,
    BUFFER_EMPTY,
    IGNORE,
}

internal object DanmakuMaskTimestampPolicy {
    fun nextPtsMode(current: Boolean, action: DanmakuMaskTimestampAction): Boolean =
        when (action) {
            DanmakuMaskTimestampAction.BUFFER_MASK,
            DanmakuMaskTimestampAction.BUFFER_EMPTY -> true
            DanmakuMaskTimestampAction.LEGACY -> false
            DanmakuMaskTimestampAction.IGNORE -> current
        }

    fun preserveTimedSample(
        previous: DanmakuDynamicOcclusionState,
        replay: DanmakuDynamicOcclusionState,
    ): DanmakuDynamicOcclusionState {
        if (previous.maskPtsMs == null) return replay
        // Re-emitting a timed bitmap must not manufacture new velocity, step or geometry.
        // Only current control flags change; all fields describing the sample stay together.
        return previous.copy(
            enabled = replay.enabled,
            backend = replay.backend,
            degradationLevel = replay.degradationLevel,
        )
    }

    // null is the live-capture/cache fallback; zero is the first timed video frame.
    fun route(
        ptsMs: Long?,
        emptyStep: Boolean,
        hasRuntimeMask: Boolean,
        seekHold: Boolean,
    ): DanmakuMaskTimestampAction {
        if (ptsMs == null) return DanmakuMaskTimestampAction.LEGACY
        if (ptsMs < 0L || seekHold) return DanmakuMaskTimestampAction.IGNORE
        if (emptyStep) return DanmakuMaskTimestampAction.BUFFER_EMPTY
        if (hasRuntimeMask) return DanmakuMaskTimestampAction.BUFFER_MASK
        // Missing/recycled timed data cannot make an old latest bitmap current again.
        return DanmakuMaskTimestampAction.IGNORE
    }
}
