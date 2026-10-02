package com.geqian.flyplayer.fly_player

/**
 * 片头/片尾跳过范围（毫秒）；null 表示该侧未识别到，不提示跳过。
 * [outroEndMs] = ED 章节之后若还有其他章节，取下一章节起点（ED 后有正片/彩蛋时只跳片尾曲本身）；
 * ED 是最后一个章节时为 null，此时跳过会走到文件结尾（由连播接管下一集）。
 * [introFromChapter]/[outroFromChapter] 标记该侧范围来自章节识别还是固定时长兜底。
 */
data class NativeChapterSkipBounds(
    val introStartMs: Long? = null,
    val introEndMs: Long? = null,
    val outroStartMs: Long? = null,
    val outroEndMs: Long? = null,
    val introFromChapter: Boolean = false,
    val outroFromChapter: Boolean = false,
)

/** 只匹配明确的片头/片尾章节名；普通编号章节不猜测跳过范围（与桌面端正则一致）。 */
val NATIVE_INTRO_CHAPTER_TITLE = Regex(
    "(^|[^a-z])(op|opening|intro)(?=$|[^a-z])|片头|片頭",
    RegexOption.IGNORE_CASE,
)
val NATIVE_OUTRO_CHAPTER_TITLE = Regex(
    "(^|[^a-z])(ed|ending|outro|credits)(?=$|[^a-z])|片尾",
    RegexOption.IGNORE_CASE,
)

/**
 * 桌面端 desktopPlaybackSkipBounds 的原生移植（毫秒版）：
 * - 章节识别（[chapterEnabled]）：片头章节区间 = 片头章节起点到下一章节起点；片尾起点 = 片尾章节起点；
 * - 固定时长（[fixedDurationEnabled]，秒，与飞牛 play.setConfigByItem 的 skip_opening/skip_ending 一致）：
 *   仅在对应侧未识别到章节时兜底；同时开启时优先使用章节；
 * - 边界清理：片头区间短于 2 秒或越界、片尾起点越界、片头片尾范围重叠时放弃该侧（或双侧）。
 */
fun nativeChapterSkipBounds(
    chapters: List<Map<String, Any?>>?,
    durationMs: Long,
    chapterEnabled: Boolean,
    fixedDurationEnabled: Boolean,
    introSeconds: Int,
    outroSeconds: Int,
): NativeChapterSkipBounds {
    var introStartMs: Long? = null
    var introEndMs: Long? = null
    var outroStartMs: Long? = null
    var outroIndex = -1
    if (chapterEnabled && !chapters.isNullOrEmpty() && durationMs > 0) {
        for (index in chapters.indices) {
            val chapter = chapters[index]
            val startMs = (chapter["timeMs"] as? Number)?.toLong() ?: continue
            if (startMs < 0 || startMs >= durationMs) continue
            val title = chapter["title"]?.toString().orEmpty()
            if (introEndMs == null && index + 1 < chapters.size &&
                NATIVE_INTRO_CHAPTER_TITLE.containsMatchIn(title)
            ) {
                val endMs = (chapters[index + 1]["timeMs"] as? Number)?.toLong()
                if (endMs != null && endMs > startMs && endMs < durationMs) {
                    introStartMs = startMs
                    introEndMs = endMs
                }
            }
            if (outroStartMs == null && NATIVE_OUTRO_CHAPTER_TITLE.containsMatchIn(title)) {
                outroStartMs = startMs
                outroIndex = index
            }
        }
    }
    var introFromChapter = introEndMs != null
    var outroFromChapter = outroStartMs != null
    // ED 之后若还有章节（彩蛋/PV/下集预告），片尾曲的结束边界 = 下一章节起点。
    var outroEndMs: Long? = null
    if (outroIndex >= 0 && outroIndex + 1 < (chapters?.size ?: 0)) {
        val endMs = (chapters!![outroIndex + 1]["timeMs"] as? Number)?.toLong()
        if (endMs != null && outroStartMs != null && endMs > outroStartMs && endMs < durationMs) {
            outroEndMs = endMs
        }
    }
    if (fixedDurationEnabled && durationMs > 0) {
        if (introEndMs == null && introSeconds > 0) {
            introStartMs = 0L
            introEndMs = introSeconds * 1000L
        }
        if (outroStartMs == null && outroSeconds > 0) {
            outroStartMs = durationMs - outroSeconds * 1000L
        }
    }
    if (introEndMs != null && (introEndMs <= 2_000L || introEndMs >= durationMs)) {
        introStartMs = null
        introEndMs = null
        introFromChapter = false
    }
    if (outroStartMs != null && (outroStartMs <= 0L || outroStartMs >= durationMs)) {
        outroStartMs = null
        outroFromChapter = false
    }
    if (outroStartMs == null) outroEndMs = null
    if (introEndMs != null && outroStartMs != null && introEndMs >= outroStartMs) {
        introStartMs = null
        introEndMs = null
        outroStartMs = null
        outroEndMs = null
        introFromChapter = false
        outroFromChapter = false
    }
    return NativeChapterSkipBounds(
        introStartMs = introStartMs,
        introEndMs = introEndMs,
        outroStartMs = outroStartMs,
        outroEndMs = outroEndMs,
        introFromChapter = introFromChapter,
        outroFromChapter = outroFromChapter,
    )
}
