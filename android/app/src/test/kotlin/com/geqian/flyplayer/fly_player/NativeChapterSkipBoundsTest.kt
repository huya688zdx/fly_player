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
}
