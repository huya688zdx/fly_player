package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
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

    @Test
    fun mpvSourcePreservesInitialPlaybackSpeed() {
        val source =
            MpvSource.fromMap(
                mapOf(
                    "url" to "https://example.com/video.mp4",
                    "playbackSpeed" to 1.5,
                ),
            )

        assertEquals(1.5, source.playbackSpeed, 0.0)
    }

    @Test
    fun localFileShowsTheWholeFileAsBuffered() {
        assertEquals(
            1_440_000L,
            resolveBufferedPositionMs(
                sourceUrl = "file:///storage/emulated/0/Download/episode.mkv",
                positionMs = 120_000L,
                durationMs = 1_440_000L,
                observedCacheDurationMs = 300_000L,
                persistentCacheBufferedPositionMs = 0L,
            ),
        )
    }

    @Test
    fun networkSourceStillShowsOnlyTheActuallyBufferedRange() {
        assertEquals(
            420_000L,
            resolveBufferedPositionMs(
                sourceUrl = "https://example.com/episode.mkv",
                positionMs = 120_000L,
                durationMs = 1_440_000L,
                observedCacheDurationMs = 300_000L,
                persistentCacheBufferedPositionMs = 0L,
            ),
        )
    }
}
