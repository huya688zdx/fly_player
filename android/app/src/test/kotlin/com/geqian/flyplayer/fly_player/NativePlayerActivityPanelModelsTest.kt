package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlayerActivityPanelModelsTest {
    @Test
    fun audioSummaryUsesSelectedGuid() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "a1", "title" to "AAC", "language" to "zh"),
            mapOf<String, Any?>("guid" to "a2", "title" to "DTS", "language" to "jpn"),
        )

        assertEquals("DTS · 日语", nativePanelAudioSummary(tracks, "a2"))
    }

    @Test
    fun subtitleSummaryTreatsEmptyGuidAsOff() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "简体中文", "language" to "zh"),
        )

        assertEquals("关闭", nativePanelSubtitleSummary(tracks, ""))
    }

    @Test
    fun subtitleSummaryFallsBackToTrackLabel() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "Main Subtitle", "language" to "chi"),
        )

        assertEquals("Main Subtitle · 中文", nativePanelSubtitleSummary(tracks, "s1"))
    }

    @Test
    fun languageOnlyTrackLabelMapsCommonCodes() {
        assertEquals("英语", nativePanelTrackLabel(mapOf<String, Any?>("language" to "en")))
    }

    @Test
    fun qualitySummaryShowsOriginalWhenOriginalMode() {
        assertEquals(
            "原画",
            nativePanelQualitySummary(
                playbackMode = "originalQuality",
                currentResolution = "3840x2160",
            ),
        )
    }

    @Test
    fun qualitySummaryExtractsVerticalResolution() {
        assertEquals(
            "1080P",
            nativePanelQualitySummary(
                playbackMode = "transcode",
                currentResolution = "1920x1080",
            ),
        )
    }

    @Test
    fun imageUrlResolverKeepsLocalFileUriForDownloadedEpisodes() {
        assertEquals(
            "file:///storage/emulated/0/Download/FlyPlayer/cover.jpg",
            nativePanelResolveImageUrl(
                "file:///storage/emulated/0/Download/FlyPlayer/cover.jpg",
                "https://nas.example.com/video.m3u8",
            ),
        )
    }

    @Test
    fun imageUrlResolverBuildsNasImageUrlForRelativePath() {
        assertEquals(
            "https://nas.example.com/v/api/v1/sys/img/p/movie.jpg?w=320",
            nativePanelResolveImageUrl(
                "/p/movie.jpg",
                "https://nas.example.com/v/api/v1/video/stream",
            ),
        )
    }

    @Test
    fun episodeLabelIncludesEpisodeNumberAndTitle() {
        assertEquals(
            "第9集  选手宣誓",
            nativePanelEpisodeLabel(
                mapOf<String, Any?>(
                    "episodeNumber" to 9,
                    "title" to "选手宣誓",
                ),
            ),
        )
    }
}
