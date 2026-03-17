package com.geqian.flyplayer.fly_player

enum class ParallelPaneSide(val wireValue: String) {
    LEFT("left"),
    RIGHT("right"),
    FULLSCREEN("fullscreen"),
}

enum class ParallelHostRole(val wireValue: String) {
    PRIMARY("primary"),
    SECONDARY("secondary"),
    FULLSCREEN("fullscreen"),
}

data class ParallelHostContext(
    val surface: String,
    val paneSide: ParallelPaneSide,
    val hostRole: ParallelHostRole,
    val preferredPrimaryPaneSide: ParallelPaneSide,
)
