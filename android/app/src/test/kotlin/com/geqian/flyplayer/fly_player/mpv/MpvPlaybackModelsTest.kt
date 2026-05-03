package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MpvPlaybackModelsTest {
    @Test
    fun mpvSourceReadsExplicitStartPausedFlag() {
        val source =
            MpvSource.fromMap(
                mapOf(
                    "itemGuid" to "item-1",
                    "mediaGuid" to "media-1",
                    "videoGuid" to "video-1",
                    "url" to "https://example.com/video.mp4",
                    "headers" to emptyMap<String, Any?>(),
                    "title" to "Episode 1",
                    "startPaused" to true,
                ),
            )

        assertTrue(source.startPaused)
    }

    @Test
    fun mpvSourceDefaultsStartPausedToFalse() {
        val source =
            MpvSource.fromMap(
                mapOf(
                    "itemGuid" to "item-2",
                    "mediaGuid" to "media-2",
                    "videoGuid" to "video-2",
                    "url" to "https://example.com/video-2.mp4",
                    "headers" to emptyMap<String, Any?>(),
                    "title" to "Episode 2",
                ),
            )

        assertFalse(source.startPaused)
    }
}
