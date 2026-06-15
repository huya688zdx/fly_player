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

    @Test
    fun subtitlePanelTitleMarksExternalAndDefaultTracks() {
        assertEquals(
            "英语-外挂",
            nativePanelSubtitleDisplayTitle(
                mapOf<String, Any?>(
                    "language" to "en",
                    "format" to "ass",
                    "isExternal" to 1,
                ),
            ),
        )
        assertEquals(
            "日语-默认",
            nativePanelSubtitleDisplayTitle(
                mapOf<String, Any?>(
                    "language" to "jpn",
                    "format" to "sup",
                    "isDefault" to 1,
                ),
            ),
        )
    }

    @Test
    fun subtitlePanelSubtitleShowsFormatAndLanguage() {
        assertEquals(
            "ASS  中文",
            nativePanelSubtitleDisplaySubtitle(
                mapOf<String, Any?>(
                    "language" to "chi",
                    "format" to "ass",
                ),
            ),
        )
    }

    @Test
    fun subtitlePanelDeleteOnlyForExternalTracks() {
        assertEquals(
            true,
            nativePanelSubtitleCanRemove(
                mapOf<String, Any?>("guid" to "local:foo", "isExternal" to 1),
            ),
        )
        assertEquals(
            false,
            nativePanelSubtitleCanRemove(
                mapOf<String, Any?>("guid" to "embedded", "isExternal" to 0),
            ),
        )
    }

    @Test
    fun qualityTierRankCollapses4kVariantsToSameTier() {
        // 4k 与 4K HDR 归到同一 2160 档，主面板据此合并、隐藏 4K HDR。
        assertEquals(2160, nativePanelQualityTierRank("4k"))
        assertEquals(2160, nativePanelQualityTierRank("4K HDR"))
        assertEquals(2160, nativePanelQualityTierRank("3840x2160"))
        assertEquals(2160, nativePanelQualityTierRank("2160"))
    }

    @Test
    fun qualityTierRankParsesStandardResolutions() {
        assertEquals(1080, nativePanelQualityTierRank("1080P"))
        assertEquals(1080, nativePanelQualityTierRank("1080"))
        assertEquals(1080, nativePanelQualityTierRank("1920x1080"))
        assertEquals(720, nativePanelQualityTierRank("720P"))
    }

    @Test
    fun qualityTierRankReturnsZeroForUnknown() {
        assertEquals(0, nativePanelQualityTierRank(null))
        assertEquals(0, nativePanelQualityTierRank(""))
        assertEquals(0, nativePanelQualityTierRank("自动"))
    }

    @Test
    fun qualityTierLabelMapsRankToDisplayName() {
        assertEquals("4k", nativePanelQualityTierLabel(2160))
        assertEquals("8k", nativePanelQualityTierLabel(4320))
        assertEquals("1080P", nativePanelQualityTierLabel(1080))
        assertEquals("", nativePanelQualityTierLabel(0))
    }

    @Test
    fun weakNetworkRecommendationChoosesHighestSafeDowngrade() {
        val qualities = listOf(
            mapOf<String, Any?>(
                "mediaGuid" to "m1080",
                "videoGuid" to "v1080",
                "resolution" to "1080p",
                "bitrate" to 8_000_000,
                "source" to "directLink",
                "directLinkQualityIndex" to 0,
            ),
            mapOf<String, Any?>(
                "mediaGuid" to "m720",
                "videoGuid" to "v720",
                "resolution" to "720p",
                "bitrate" to 4_000_000,
                "source" to "directLink",
                "directLinkQualityIndex" to 1,
            ),
            mapOf<String, Any?>(
                "mediaGuid" to "m480",
                "videoGuid" to "v480",
                "resolution" to "480p",
                "bitrate" to 2_000_000,
                "source" to "directLink",
                "directLinkQualityIndex" to 2,
            ),
        )

        val recommendation = nativePanelRecommendWeakNetworkQuality(
            qualities = qualities,
            currentQuality = qualities[0],
            networkSpeedBytesPerSecond = 700_000,
        )

        assertEquals(1, recommendation?.qualityIndex)
        assertEquals("720P", recommendation?.qualityLabel)
        assertEquals("当前网速 684 KB/s", recommendation?.details)
    }

    @Test
    fun weakNetworkRecommendationFallsBackToNextLowerBitrate() {
        val qualities = listOf(
            mapOf<String, Any?>("resolution" to "1080p", "bitrate" to 8_000_000),
            mapOf<String, Any?>("resolution" to "720p", "bitrate" to 4_000_000),
            mapOf<String, Any?>("resolution" to "480p", "bitrate" to 2_000_000),
        )

        val recommendation = nativePanelRecommendWeakNetworkQuality(
            qualities = qualities,
            currentQuality = qualities[0],
            networkSpeedBytesPerSecond = 100_000,
        )

        assertEquals(1, recommendation?.qualityIndex)
        assertEquals("720P", recommendation?.qualityLabel)
    }

    @Test
    fun weakNetworkRecommendationRequiresMeaningfulDowngrade() {
        val qualities = listOf(
            mapOf<String, Any?>("resolution" to "1080p", "bitrate" to 8_000_000),
            mapOf<String, Any?>("resolution" to "1080p high", "bitrate" to 7_000_000),
        )

        val recommendation = nativePanelRecommendWeakNetworkQuality(
            qualities = qualities,
            currentQuality = qualities[0],
            networkSpeedBytesPerSecond = 900_000,
        )

        assertEquals(null, recommendation)
    }

    @Test
    fun autoNextCountdownRequiresAutoPlayEnabledAndNextEpisode() {
        assertEquals(true, nativePanelShouldStartAutoNextCountdown(true, true))
        assertEquals(false, nativePanelShouldStartAutoNextCountdown(false, true))
        assertEquals(false, nativePanelShouldStartAutoNextCountdown(true, false))
    }
}
