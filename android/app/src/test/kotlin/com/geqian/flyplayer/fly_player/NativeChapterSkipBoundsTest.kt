package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 片头片尾跳过范围推断：与桌面端 desktopPlaybackSkipBounds 语义对齐。 */
class NativeChapterSkipBoundsTest {
    private fun chapter(timeMs: Long, title: String) =
        mapOf<String, Any?>("timeMs" to timeMs, "title" to title)

    @Test
    fun opEdNamedChaptersProduceSkipBounds() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "前情提要"),
                chapter(30_000, "OP"),
                chapter(125_000, "正片"),
                chapter(1_290_000, "ED"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertEquals(30_000L, bounds.introStartMs)
        assertEquals(125_000L, bounds.introEndMs)
        assertEquals(1_290_000L, bounds.outroStartMs)
        // ED 是最后一个章节：片尾跳过一直覆盖到文件结尾。
        assertNull(bounds.outroEndMs)
        assertTrue(bounds.introFromChapter)
        assertTrue(bounds.outroFromChapter)
    }

    @Test
    fun outroSkipsOnlyTheSongWhenContentFollowsEd() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "OP"),
                chapter(90_000, "正片"),
                chapter(1_300_000, "ED"),
                chapter(1_400_000, "预告"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertEquals(1_300_000L, bounds.outroStartMs)
        // ED 后还有预告章节：片尾只跳到下一章节起点，不进下一集。
        assertEquals(1_400_000L, bounds.outroEndMs)
    }

    @Test
    fun numberedChaptersAreNotGuessed() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "Chapter 01"),
                chapter(90_000, "Chapter 02"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertNull(bounds.introStartMs)
        assertNull(bounds.introEndMs)
        assertNull(bounds.outroStartMs)
    }

    @Test
    fun fixedDurationNeedsItsOwnToggle() {
        val chapters = listOf(
            chapter(30_000, "OP"),
            chapter(125_000, "正片"),
        )
        val noFallback = nativeChapterSkipBounds(
            emptyList(),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertNull(noFallback.introEndMs)
        assertNull(noFallback.outroStartMs)
        val mixed = nativeChapterSkipBounds(
            chapters,
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = true,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertEquals(30_000L, mixed.introStartMs)
        assertEquals(125_000L, mixed.introEndMs)
        assertTrue(mixed.introFromChapter)
        assertEquals(1_320_000L, mixed.outroStartMs)
        assertFalse(mixed.outroFromChapter)
        val fixedOnly = nativeChapterSkipBounds(
            chapters,
            durationMs = 1_440_000,
            chapterEnabled = false,
            fixedDurationEnabled = true,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertEquals(0L, fixedOnly.introStartMs)
        assertEquals(120_000L, fixedOnly.introEndMs)
        assertFalse(fixedOnly.introFromChapter)
        assertEquals(1_320_000L, fixedOnly.outroStartMs)
    }

    @Test
    fun chineseAndCaseInsensitiveTitlesMatch() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "Opening"),
                chapter(90_000, "正片"),
                chapter(1_400_000, "片尾"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 0,
            outroSeconds = 0,
        )
        assertEquals(0L, bounds.introStartMs)
        assertEquals(90_000L, bounds.introEndMs)
        assertEquals(1_400_000L, bounds.outroStartMs)
    }

    @Test
    fun tooShortOrOutOfBoundsRangesAreDropped() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "OP"),
                chapter(1_000, "正片"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 0,
            outroSeconds = 0,
        )
        assertNull(bounds.introEndMs)
    }

    @Test
    fun overlappingIntroAndOutroDropsBoth() {
        val bounds = nativeChapterSkipBounds(
            listOf(
                chapter(0, "OP"),
                chapter(1_400_000, "ED"),
                chapter(1_430_000, "正片"),
            ),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 0,
            outroSeconds = 0,
        )
        assertNull(bounds.introEndMs)
        assertNull(bounds.outroStartMs)
    }

    private fun bounds() = nativeChapterSkipBounds(
        listOf(
            chapter(30_000, "OP"),
            chapter(125_000, "正片"),
            chapter(1_300_000, "ED"),
            chapter(1_400_000, "预告"),
        ),
        durationMs = 1_440_000,
        chapterEnabled = true,
        fixedDurationEnabled = false,
        introSeconds = 120,
        outroSeconds = 120,
    )

    @Test
    fun autoAdvanceWaitsForCountdownFromShownPosition() {
        // 提示在 88s 出现：倒计时 5s 归零点 = 出现位置 + 5s（在片头区间内）。
        val at = nativeSkipAutoAdvanceAtMs(
            intro = true, bounds(), shownPosMs = 88_000L, countdownMs = 5_000L, durationMs = 1_440_000,
        )
        assertEquals(93_000L, at)
    }

    @Test
    fun autoAdvanceNeverBeforeWindowStartAndNeverPastWindowEnd() {
        // 出现位置 + 倒计时早于片头起点时，等到起点才自动跳。
        val early = nativeSkipAutoAdvanceAtMs(
            intro = true, bounds(), shownPosMs = 20_000L, countdownMs = 5_000L, durationMs = 1_440_000,
        )
        assertEquals(30_000L, early)
        // 片头剩余区间比倒计时短时，在片头终点执行。
        val short = nativeSkipAutoAdvanceAtMs(
            intro = true, bounds(), shownPosMs = 120_000L, countdownMs = 10_000L, durationMs = 1_440_000,
        )
        assertEquals(125_000L, short)
    }

    @Test
    fun autoAdvanceOutroTriggersAfterCountdownAndCoversToFileEnd() {
        // 片尾倒计时归零在 ED 起点后 5 秒触发；跳过目标（outroEnd）由跳过范围决定。
        val at = nativeSkipAutoAdvanceAtMs(
            intro = false, bounds(), shownPosMs = 1_296_000L, countdownMs = 5_000L, durationMs = 1_440_000,
        )
        assertEquals(1_301_000L, at)
        // ED 是最后一章时覆盖到文件结尾，归零点最晚不超过结尾。
        val lastEd = nativeChapterSkipBounds(
            listOf(chapter(30_000, "OP"), chapter(125_000, "正片"), chapter(1_300_000, "ED")),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        val toEnd = nativeSkipAutoAdvanceAtMs(
            intro = false, lastEd, shownPosMs = 1_438_000L, countdownMs = 5_000L, durationMs = 1_440_000,
        )
        assertEquals(1_440_000L, toEnd)
    }

    @Test
    fun missingSideRangeReturnsNullForAutoAdvance() {
        val empty = nativeChapterSkipBounds(
            emptyList(),
            durationMs = 1_440_000,
            chapterEnabled = true,
            fixedDurationEnabled = false,
            introSeconds = 120,
            outroSeconds = 120,
        )
        assertNull(nativeSkipAutoAdvanceAtMs(true, empty, 0L, 5_000L, 1_440_000))
        assertNull(nativeSkipAutoAdvanceAtMs(false, empty, 0L, 5_000L, 1_440_000))
    }

    @Test
    fun seekSnapsOnlyWithinSmallRadius() {
        val markers = listOf(30_000L, 125_000L, 1_300_000L)
        // 3 秒内贴到标记。
        assertEquals(125_000L, snapSeekTargetMs(123_500L, markers))
        assertEquals(30_000L, snapSeekTargetMs(31_800L, markers))
        // 超出 3 秒保持原落点，微调不受吸附影响。
        assertEquals(120_000L, snapSeekTargetMs(120_000L, markers))
        assertEquals(1_303_001L, snapSeekTargetMs(1_303_001L, markers))
        // 无标记时原样返回。
        assertEquals(60_000L, snapSeekTargetMs(60_000L, emptyList()))
    }
}
