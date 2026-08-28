package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.res.Resources
import android.app.Application
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlayerActivityPanelModelsTest {
    private val testContext: Context = object : Application() {
        private val testResources = object : Resources(
            null,
            null,
            null,
        ) {
            override fun getString(resId: Int): String = when (resId) {
            R.string.player_language_unknown -> "未知"
            R.string.player_language_arabic -> "阿拉伯语"
            R.string.player_language_japanese -> "日语"
            R.string.player_language_chinese -> "中文"
            R.string.player_language_english -> "英语"
            R.string.player_language_korean -> "韩语"
            R.string.player_track_off -> "关闭"
            R.string.player_original_quality -> "原画"
            R.string.player_track_generic -> "轨道"
            R.string.player_track_default -> "默认"
            R.string.player_track_unselected -> "未选择"
            R.string.player_subtitle_generic -> "字幕"
            R.string.player_subtitle_external -> "外挂"
            R.string.player_version_generic -> "版本"
            R.string.player_untitled -> "未命名"
            else -> error("未覆盖的测试资源: $resId")
            }

            override fun getString(resId: Int, vararg formatArgs: Any): String = when (resId) {
            R.string.player_track_number_format -> "轨道 ${formatArgs[0]}"
            R.string.player_episode_number -> "第${formatArgs[0]}集"
            R.string.player_version_number -> "版本 ${formatArgs[0]}"
            R.string.player_current_speed -> "当前网速 ${formatArgs[0]}"
            R.string.player_current_speed_resume -> "当前网速 ${formatArgs[0]} · 预计恢复 ${formatArgs[1]}秒"
                else -> getString(resId)
            }
        }

        override fun getResources(): Resources = testResources
    }

    @Test
    fun playbackSpeedLabelReflectsSelectedSpeed() {
        assertEquals("1.5x", nativePanelPlaybackSpeedLabel(1.5))
        assertEquals("2.0x", nativePanelPlaybackSpeedLabel(2.0))
        assertEquals("0.75x", nativePanelPlaybackSpeedLabel(0.75))
    }

    @Test
    fun primaryControlsRemoveManualReloadEntry() {
        val source = File(
            "src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt",
        ).readText()

        assertFalse(source.contains("makeEntryButton(localizedString(R.string.player_action_reload)"))
        assertTrue(source.contains("speedButton = makeEntryButton(\"1.0x\")"))
        assertTrue(source.contains("R.drawable.ic_player_episode_grid"))
    }

    @Test
    fun danmakuCurrentResultRequiresSameSeasonAndEpisode() {
        assertFalse(
            nativePanelDanmakuResultIsCurrent(
                resultEpisodeNumber = 1,
                currentEpisodeNumber = 1,
                matchesCurrentSeason = false,
            ),
        )
        assertTrue(
            nativePanelDanmakuResultIsCurrent(
                resultEpisodeNumber = 1,
                currentEpisodeNumber = 1,
                matchesCurrentSeason = true,
            ),
        )
    }

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
    fun episodeRefreshMergeCompletesDownloadedFallbackWithNetworkPosters() {
        val merge = nativePanelMergeEpisodeRefresh(
            currentEpisodes = listOf(
                mapOf<String, Any?>(
                    "itemGuid" to "e2",
                    "episodeNumber" to 2,
                    "poster" to "file:///downloads/e2-cover.jpg",
                    "downloaded" to true,
                ),
            ),
            refreshedEpisodes = listOf(
                mapOf<String, Any?>(
                    "itemGuid" to "e1",
                    "episodeNumber" to 1,
                    "poster" to "https://nas.example.com/e1.jpg",
                    "imageAuth" to "token",
                    "downloaded" to false,
                ),
                mapOf<String, Any?>(
                    "itemGuid" to "e2",
                    "episodeNumber" to 2,
                    "poster" to "file:///downloads/e2-cover.jpg",
                    "downloaded" to true,
                ),
                mapOf<String, Any?>(
                    "itemGuid" to "e3",
                    "episodeNumber" to 3,
                    "poster" to "https://nas.example.com/e3.jpg",
                    "imageAuth" to "token",
                    "downloaded" to false,
                ),
            ),
        )

        assertEquals(true, merge.changed)
        assertEquals(listOf("e1", "e2", "e3"), merge.episodes.map { it["itemGuid"] })
        assertEquals("https://nas.example.com/e1.jpg", merge.episodes[0]["poster"])
        assertEquals("file:///downloads/e2-cover.jpg", merge.episodes[1]["poster"])
        assertEquals("token", merge.episodes[2]["imageAuth"])
    }

    @Test
    fun episodeRefreshMergeDoesNotClearExistingPosterWithEmptyIncomingValue() {
        val merge = nativePanelMergeEpisodeRefresh(
            currentEpisodes = listOf(
                mapOf<String, Any?>(
                    "itemGuid" to "e1",
                    "poster" to "https://nas.example.com/e1.jpg",
                    "imageAuth" to "token",
                    "watched" to 0,
                ),
            ),
            refreshedEpisodes = listOf(
                mapOf<String, Any?>(
                    "itemGuid" to "e1",
                    "poster" to "",
                    "imageAuth" to "",
                    "watched" to 1,
                ),
            ),
        )

        assertEquals(true, merge.changed)
        assertEquals("https://nas.example.com/e1.jpg", merge.episodes[0]["poster"])
        assertEquals("token", merge.episodes[0]["imageAuth"])
        assertEquals(1, merge.episodes[0]["watched"])
    }

    @Test
    fun episodeRefreshRenderDecisionSkipsStableSettledContent() {
        assertEquals(false, nativePanelShouldRenderEpisodeRefresh(wasLoading = false, contentChanged = false))
        assertEquals(true, nativePanelShouldRenderEpisodeRefresh(wasLoading = true, contentChanged = false))
        assertEquals(true, nativePanelShouldRenderEpisodeRefresh(wasLoading = false, contentChanged = true))
    }

    @Test
    fun audioSummaryUsesSelectedGuid() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "a1", "title" to "AAC", "language" to "zh"),
            mapOf<String, Any?>("guid" to "a2", "title" to "DTS", "language" to "jpn"),
        )

        assertEquals("DTS · 日语", nativePanelAudioSummary(testContext, tracks, "a2"))
    }

    @Test
    fun subtitleSummaryTreatsEmptyGuidAsOff() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "简体中文", "language" to "zh"),
        )

        assertEquals("关闭", nativePanelSubtitleSummary(testContext, tracks, ""))
    }

    @Test
    fun subtitleSummaryFallsBackToTrackLabel() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "Main Subtitle", "language" to "chi"),
        )

        assertEquals("Main Subtitle · 中文", nativePanelSubtitleSummary(testContext, tracks, "s1"))
    }

    @Test
    fun languageOnlyTrackLabelMapsCommonCodes() {
        assertEquals("英语", nativePanelTrackLabel(testContext, mapOf<String, Any?>("language" to "en")))
    }

    @Test
    fun qualitySummaryShowsOriginalWhenOriginalMode() {
        assertEquals(
            "原画",
            nativePanelQualitySummary(
                context = testContext,
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
                context = testContext,
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
                testContext,
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
                testContext,
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
                testContext,
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
                testContext,
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
            context = testContext,
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
            context = testContext,
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
            context = testContext,
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
        // 用户取消本集连播倒计时后：连播视同不生效，末秒兜底照常弹完成层
        assertEquals(
            true,
            nativePanelShouldShowCompletedOverlay(
                autoPlayEnabled = true,
                hasNextEpisode = true,
                playbackEnded = false,
                insideCompletionWindow = false,
                positionMs = 71_400,
                durationMs = 72_000,
                autoNextSuppressedForCurrent = true,
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
                autoNextSuppressedForCurrent = true,
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
    fun topEdgePullDownIsReservedForSystemBars() {
        assertEquals(
            true,
            nativePanelShouldLetSystemHandleTopPullDown(
                startY = 12f,
                statusBarInsetPx = 24,
                density = 1f,
            ),
        )
        assertEquals(
            true,
            nativePanelShouldLetSystemHandleTopPullDown(
                startY = 64f,
                statusBarInsetPx = 24,
                density = 1f,
            ),
        )
        assertEquals(
            false,
            nativePanelShouldLetSystemHandleTopPullDown(
                startY = 96f,
                statusBarInsetPx = 24,
                density = 1f,
            ),
        )
    }

    @Test
    fun gestureDirectionWaitsUntilIntentIsClear() {
        assertEquals(
            NATIVE_GESTURE_MODE_PENDING,
            nativePanelResolveGestureMode(
                dx = 30f,
                dy = 8f,
                startX = 300f,
                startRawY = 300f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
        assertEquals(
            NATIVE_GESTURE_MODE_PENDING,
            nativePanelResolveGestureMode(
                dx = 48f,
                dy = 54f,
                startX = 300f,
                startRawY = 300f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
    }

    @Test
    fun gestureDirectionLocksOnlyToDominantAxis() {
        assertEquals(
            NATIVE_GESTURE_MODE_SEEK,
            nativePanelResolveGestureMode(
                dx = 90f,
                dy = 20f,
                startX = 300f,
                startRawY = 300f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
        assertEquals(
            NATIVE_GESTURE_MODE_BRIGHTNESS,
            nativePanelResolveGestureMode(
                dx = 15f,
                dy = -90f,
                startX = 300f,
                startRawY = 300f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
        assertEquals(
            NATIVE_GESTURE_MODE_VOLUME,
            nativePanelResolveGestureMode(
                dx = 15f,
                dy = 90f,
                startX = 1500f,
                startRawY = 300f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
    }

    @Test
    fun topEdgeGestureNeverBecomesPlaybackControl() {
        assertEquals(
            NATIVE_GESTURE_MODE_SYSTEM,
            nativePanelResolveGestureMode(
                dx = 80f,
                dy = 100f,
                startX = 300f,
                startRawY = 40f,
                viewportWidth = 1920,
                viewportHeight = 1080,
                touchSlop = 24,
                statusBarInsetPx = 24,
                density = 3f,
            ),
        )
    }

    @Test
    fun cancelledGestureNeverCommitsSeek() {
        assertEquals(
            true,
            nativePanelShouldCommitSeekGesture(
                gestureMode = NATIVE_GESTURE_MODE_SEEK,
                cancelled = false,
            ),
        )
        assertEquals(
            false,
            nativePanelShouldCommitSeekGesture(
                gestureMode = NATIVE_GESTURE_MODE_SEEK,
                cancelled = true,
            ),
        )
        assertEquals(
            false,
            nativePanelShouldCommitSeekGesture(
                gestureMode = NATIVE_GESTURE_MODE_BRIGHTNESS,
                cancelled = false,
            ),
        )
    }
    @Test
    fun gestureBrightnessStartsFromCurrentWindowOrSystemBrightness() {
        assertEquals(
            0.72f,
            nativePanelResolveGestureBrightness(
                windowBrightness = 0.72f,
                systemBrightness = 128,
            ),
        )
        assertEquals(
            128f / 255f,
            nativePanelResolveGestureBrightness(
                windowBrightness = -1f,
                systemBrightness = 128,
            ),
        )
    }

    @Test
    fun autoPipRequiresEnabledPlaybackAndSupportedDevice() {
        assertEquals(
            true,
            nativePanelShouldAutoEnterPip(
                pipAutoEnter = true,
                pipSupported = true,
                paused = false,
                alreadyInPip = false,
                finishing = false,
            ),
        )
        assertEquals(false, nativePanelShouldAutoEnterPip(true, true, paused = true, false, false))
        assertEquals(false, nativePanelShouldAutoEnterPip(true, false, paused = false, false, false))
        assertEquals(false, nativePanelShouldAutoEnterPip(false, true, paused = false, false, false))
        assertEquals(false, nativePanelShouldAutoEnterPip(true, true, paused = false, true, false))
        assertEquals(false, nativePanelShouldAutoEnterPip(true, true, paused = false, false, true))
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
            nativePanelEpisodeVersionSummary(testContext, versions[0].quality, "24:42"),
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
                testContext,
                mapOf<String, Any?>("fileName" to "BDRip.mkv"),
                0,
            ),
        )
        assertEquals(
            "版本 2",
            nativePanelEpisodeVersionTitle(testContext, mapOf<String, Any?>(), 1),
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
