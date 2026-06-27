package com.geqian.flyplayer.fly_player

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlayerActivityPanelModelsTest {
    @Test
    fun episodeViewModeMapsFeiniuPlaylistViewTypes() {
        assertEquals(0, nativePanelEpisodeViewModeFromType("card"))
        assertEquals(1, nativePanelEpisodeViewModeFromType("button"))
        assertEquals(0, nativePanelEpisodeViewModeFromType(null))
        assertEquals("card", nativePanelPlaylistViewTypeFromEpisodeMode(0))
        assertEquals("button", nativePanelPlaylistViewTypeFromEpisodeMode(1))
    }

    @Test
    fun episodePickerDataSelectsRequestedSeasonWhenPresent() {
        val data = nativePanelEpisodePickerData(
            selectedSeasonGuid = "s2",
            viewType = "button",
            seasons = listOf(
                mapOf<String, Any?>("seasonGuid" to "s1", "seasonLabel" to "第1季"),
                mapOf<String, Any?>("seasonGuid" to "s2", "seasonLabel" to "第2季"),
            ),
            episodes = listOf(
                mapOf<String, Any?>("itemGuid" to "e1", "episodeNumber" to 1),
            ),
            fallbackEpisodes = emptyList(),
        )

        assertEquals("s2", data.selectedSeasonGuid)
        assertEquals(1, data.viewMode)
        assertEquals(true, data.seasons[1]["selected"])
        assertEquals("e1", data.episodes[0]["itemGuid"])
    }

    @Test
    fun episodePickerDataFallsBackToExistingEpisodes() {
        val data = nativePanelEpisodePickerData(
            selectedSeasonGuid = "",
            viewType = "card",
            seasons = emptyList(),
            episodes = emptyList(),
            fallbackEpisodes = listOf(
                mapOf<String, Any?>(
                    "itemGuid" to "cached",
                    "seasonGuid" to "cachedSeason",
                    "episodeNumber" to 3,
                ),
            ),
        )

        assertEquals("cachedSeason", data.selectedSeasonGuid)
        assertEquals(0, data.viewMode)
        assertEquals("cached", data.episodes[0]["itemGuid"])
    }

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
        assertEquals(false, nativePanelShouldStartAutoNextCountdown(true, true, episodeSwitchInFlight = true))
        assertEquals(false, nativePanelShouldStartAutoNextCountdown(true, true, suppressedForCurrent = true))
    }

    @Test
    fun completedOverlayWaitsForPlaybackEnded() {
        assertEquals(
            false,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = false,
                hasNextEpisode = true,
                playbackEnded = false,
                insideCompletionWindow = true,
                positionMs = 67_000,
                durationMs = 72_000,
            ),
        )
        assertEquals(
            false,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = true,
                hasNextEpisode = true,
                playbackEnded = false,
                insideCompletionWindow = true,
                positionMs = 67_000,
                durationMs = 72_000,
            ),
        )
        assertEquals(
            false,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = true,
                hasNextEpisode = false,
                playbackEnded = false,
                insideCompletionWindow = true,
                positionMs = 67_000,
                durationMs = 72_000,
            ),
        )
        assertEquals(
            true,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = true,
                hasNextEpisode = true,
                playbackEnded = true,
                insideCompletionWindow = false,
                positionMs = 10_000,
                durationMs = 72_000,
            ),
        )
        assertEquals(
            true,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = false,
                hasNextEpisode = true,
                playbackEnded = false,
                insideCompletionWindow = false,
                positionMs = 71_400,
                durationMs = 72_000,
            ),
        )
    }

    @Test
    fun playbackBehaviorUsesFlutterSharedPreferenceKeys() {
        assertEquals("flutter.player_auto_rotate_enabled", NATIVE_PLAYER_AUTO_ROTATE_PREF_KEY)
        assertEquals("flutter.player_auto_play_enabled", NATIVE_PLAYER_AUTO_PLAY_PREF_KEY)
        assertEquals(
            "flutter.player_next_episode_preload_enabled",
            NATIVE_PLAYER_NEXT_EPISODE_PRELOAD_PREF_KEY,
        )
    }

    @Test
    fun nextEpisodePreloadRequiresAutoPlayEnabled() {
        assertEquals(true, nativePanelCanPreloadNextEpisode(true, true))
        assertEquals(false, nativePanelCanPreloadNextEpisode(false, true))
        assertEquals(false, nativePanelCanPreloadNextEpisode(true, false))
    }

    @Test
    fun episodeSwitchSkipsPreloadedResultWithoutDanmakuFile() {
        val danmakuFile = File.createTempFile("native-preload-danmaku", ".json").apply {
            writeText("""{"comments":[]}""")
        }
        assertEquals(
            false,
            nativePanelShouldUsePreloadedEpisodeResult(
                linkedMapOf<String, Any?>("loadArgs" to "{}"),
            ),
        )
        assertEquals(
            false,
            nativePanelShouldUsePreloadedEpisodeResult(
                linkedMapOf<String, Any?>("loadArgs" to "{}", "danmakuFile" to ""),
            ),
        )
        assertEquals(
            false,
            nativePanelShouldUsePreloadedEpisodeResult(
                linkedMapOf<String, Any?>(
                    "loadArgs" to "{}",
                    "danmakuFile" to "${danmakuFile.absolutePath}.missing",
                ),
            ),
        )
        assertEquals(
            true,
            nativePanelShouldUsePreloadedEpisodeResult(
                linkedMapOf<String, Any?>(
                    "loadArgs" to "{}",
                    "danmakuFile" to danmakuFile.absolutePath,
                ),
            ),
        )
        danmakuFile.delete()
    }

    @Test
    fun episodeSwitchBypassesPreloadedResultWhenDanmakuIsEnabled() {
        val result = linkedMapOf<String, Any?>("loadArgs" to "{}")
        assertEquals(false, nativePanelShouldUsePreloadedEpisodeResultForSwitch(result, true))
        assertEquals(true, nativePanelShouldUsePreloadedEpisodeResultForSwitch(result, false))
    }

    @Test
    fun autoEpisodeSwitchForcesPlaybackToStart() {
        val original = linkedMapOf<String, Any?>(
            "url" to "https://example.invalid/video.mp4",
            "startPaused" to true,
        )

        val autoPlayArgs = nativePanelLoadArgsForEpisodeSwitch(original, autoPlayAfterLoad = true)
        val manualArgs = nativePanelLoadArgsForEpisodeSwitch(original, autoPlayAfterLoad = false)

        assertEquals(false, autoPlayArgs["startPaused"])
        assertEquals(true, manualArgs["startPaused"])
    }

    @Test
    fun episodeVersionsRequireMultipleMediaGuids() {
        val singleVersion = listOf(
            mapOf<String, Any?>("mediaGuid" to "m1", "resolution" to "1080P", "bitrate" to 8_000_000),
            mapOf<String, Any?>("mediaGuid" to "m1", "resolution" to "720P", "bitrate" to 4_000_000),
        )
        val multiVersion = listOf(
            mapOf<String, Any?>("mediaGuid" to "m1", "resolution" to "1080P", "bitrate" to 8_000_000),
            mapOf<String, Any?>("mediaGuid" to "m2", "resolution" to "1080P", "bitrate" to 7_000_000),
        )

        assertEquals(emptyList<NativeEpisodeVersionEntry>(), nativePanelEpisodeVersionEntries(singleVersion))
        assertEquals(2, nativePanelEpisodeVersionEntries(multiVersion).size)
    }

    @Test
    fun episodeVersionsKeepOriginalOrHighestBitratePerMediaGuid() {
        val qualities = listOf(
            mapOf<String, Any?>(
                "mediaGuid" to "m1",
                "resolution" to "720P",
                "bitrate" to 4_000_000,
                "source" to "serverSession",
            ),
            mapOf<String, Any?>(
                "mediaGuid" to "m1",
                "resolution" to "1080P",
                "bitrate" to 8_000_000,
                "source" to "originalProxy",
            ),
            mapOf<String, Any?>(
                "mediaGuid" to "m2",
                "resolution" to "1080P",
                "bitrate" to 7_000_000,
                "source" to "serverSession",
            ),
        )

        val versions = nativePanelEpisodeVersionEntries(qualities)

        assertEquals(2, versions.size)
        assertEquals(1, versions[0].sourceIndex)
        // 副标题不再写来源，改为 分辨率 · 视频时长 · 码率。
        assertEquals(
            "1080P · 24:42 · 8 Mbps",
            nativePanelEpisodeVersionSummary(versions[0].quality, "24:42"),
        )
    }

    @Test
    fun bitrateLabelKeepsFractionInsteadOfRoundingToZero() {
        assertEquals("0.64 Mbps", nativePanelBitrateLabel(640_000))
        assertEquals("0.99 Mbps", nativePanelBitrateLabel(999_999))
        assertEquals("17 Mbps", nativePanelBitrateLabel(17_000_000))
    }

    @Test
    fun episodeVersionTitleUsesSourceFileNameWhenPresent() {
        assertEquals(
            "BDRip.mkv",
            nativePanelEpisodeVersionTitle(
                mapOf<String, Any?>("fileName" to "BDRip.mkv"),
                0,
            ),
        )
        assertEquals(
            "版本 2",
            nativePanelEpisodeVersionTitle(mapOf<String, Any?>(), 1),
        )
    }

    @Test
    fun bitmapSubtitleStaysEmbeddedEvenWhenFlaggedExternal() {
        // 复刻 SUP 切换 bug：服务端把内嵌 PGS/SUP 位图轨额外抽取并标成 isExternal/extraFile，
        // 但位图只能作为内嵌轨播放——必须判为「不走外挂文件」，否则切到它会误下发错误 .ass。
        assertEquals(
            false,
            nativeSubtitleUsesExternalFile(
                mapOf<String, Any?>(
                    "guid" to "pgs1",
                    "codecName" to "hdmv_pgs_subtitle",
                    "isBitmap" to 1,
                    "isExternal" to 1,
                    "extraFile" to 1,
                ),
            ),
        )
        assertEquals(
            false,
            nativeSubtitleUsesExternalFile(
                mapOf<String, Any?>("guid" to "sup1", "format" to "sup", "extraFile" to 1),
            ),
        )
    }

    @Test
    fun textSubtitleUsesExternalFileOnlyWhenFlaggedOrLocal() {
        // 普通内嵌文本字幕（ass，无外挂标志）→ 走内嵌轨。
        assertEquals(
            false,
            nativeSubtitleUsesExternalFile(
                mapOf<String, Any?>("guid" to "ass1", "format" to "ass"),
            ),
        )
        // 服务端抽取的外挂文本字幕（extraFile/isExternal）→ 走外挂文件。
        assertEquals(
            true,
            nativeSubtitleUsesExternalFile(
                mapOf<String, Any?>("guid" to "ass2", "format" to "ass", "extraFile" to 1),
            ),
        )
        // 用户「+添加」的本地字幕（local: guid）→ 始终走外挂文件。
        assertEquals(
            true,
            nativeSubtitleUsesExternalFile(
                mapOf<String, Any?>("guid" to "local:sub:123", "format" to "srt"),
            ),
        )
    }
}
