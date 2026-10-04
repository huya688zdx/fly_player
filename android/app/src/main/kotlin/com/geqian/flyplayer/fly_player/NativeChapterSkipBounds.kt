package com.geqian.flyplayer.fly_player

import kotlin.math.abs

/**
 * 片头/片尾跳过范围（毫秒）；null 表示该侧未识别到，不提示跳过。
 * [outroEndMs] = ED 章节之后若还有其他章节，取下一章节起点（ED 后有正片/彩蛋时只跳片尾曲本身）；
 * ED 是最后一个章节时为 null，此时跳过会走到文件结尾（由连播接管下一集）。
 * [introFromChapter]/[outroFromChapter] 标记该侧范围来自章节识别还是固定时长兜底；
 * [introFromPattern]/[outroFromPattern] 标记该侧范围来自编号章节的时长规律推测。
 */
data class NativeChapterSkipBounds(
    val introStartMs: Long? = null,
    val introEndMs: Long? = null,
    val outroStartMs: Long? = null,
    val outroEndMs: Long? = null,
    val introFromChapter: Boolean = false,
    val outroFromChapter: Boolean = false,
    val introFromPattern: Boolean = false,
    val outroFromPattern: Boolean = false,
)

/** 只匹配明确的片头/片尾章节名；普通编号章节不猜命名（与桌面端正则一致），改由规律推测兜底。 */
val NATIVE_INTRO_CHAPTER_TITLE = Regex(
    "(^|[^a-z])(op|opening|intro)(?=$|[^a-z])|片头|片頭",
    RegexOption.IGNORE_CASE,
)
val NATIVE_OUTRO_CHAPTER_TITLE = Regex(
    "(^|[^a-z])(ed|ending|outro|credits)(?=$|[^a-z])|片尾",
    RegexOption.IGNORE_CASE,
)

// 编号章节规律推测的窗口（行业惯例：动漫 OP/ED ≈90 秒；网剧规范片头≤90 秒、片尾≤180 秒）。
private const val PATTERN_MIN_DURATION_MS = 15L * 60_000L
private const val PATTERN_OP_START_MAX_MS = 75_000L
private const val PATTERN_OP_LENGTH_MIN_MS = 60_000L
private const val PATTERN_OP_LENGTH_MAX_MS = 105_000L
private const val PATTERN_ED_START_FROM_END_MIN_MS = 70_000L
private const val PATTERN_ED_START_FROM_END_MAX_MS = 190_000L
private const val PATTERN_ED_LENGTH_MIN_MS = 60_000L
private const val PATTERN_ED_LENGTH_MAX_MS = 185_000L

private fun chapterTimeMs(chapter: Map<String, Any?>): Long? =
    (chapter["timeMs"] as? Number)?.toLong()

/** OP 候选：开头 75 秒内开始、块长 60–105 秒的章节（动漫 OP≈90s，剧集片头≤90s）。 */
private fun patternOpCandidate(
    chapters: List<Map<String, Any?>>,
    durationMs: Long,
): Pair<Long, Long>? {
    for (index in 0 until chapters.size - 1) {
        val startMs = chapterTimeMs(chapters[index]) ?: continue
        val endMs = chapterTimeMs(chapters[index + 1]) ?: continue
        if (startMs < 0 || startMs > PATTERN_OP_START_MAX_MS) continue
        if (endMs <= startMs || endMs >= durationMs) continue
        val lengthMs = endMs - startMs
        if (lengthMs in PATTERN_OP_LENGTH_MIN_MS..PATTERN_OP_LENGTH_MAX_MS) {
            return startMs to endMs
        }
    }
    return null
}

/** ED 候选：距结尾 70–190 秒内开始、块长 60–185 秒的章节（动漫 ED≈90s，剧集片尾≤180s）。 */
private fun patternEdCandidate(
    chapters: List<Map<String, Any?>>,
    durationMs: Long,
): Pair<Long, Long>? {
    for (index in chapters.indices) {
        val startMs = chapterTimeMs(chapters[index]) ?: continue
        if (startMs < durationMs - PATTERN_ED_START_FROM_END_MAX_MS) continue
        if (startMs > durationMs - PATTERN_ED_START_FROM_END_MIN_MS) continue
        val endMs = if (index + 1 < chapters.size) {
            chapterTimeMs(chapters[index + 1]) ?: continue
        } else {
            durationMs
        }
        val lengthMs = endMs - startMs
        if (lengthMs in PATTERN_ED_LENGTH_MIN_MS..PATTERN_ED_LENGTH_MAX_MS) {
            return startMs to endMs
        }
    }
    return null
}

/**
 * 桌面端 desktopPlaybackSkipBounds 的原生移植（毫秒版）：
 * - 章节识别（[chapterEnabled]）：片头章节区间 = 片头章节起点到下一章节起点；片尾起点 = 片尾章节起点；
 * - 编号章节规律推测：命名识别不到时按行业惯例的块长/位置推测（动漫 OP/ED≈90s、网剧片头≤90s 片尾≤180s），
 *   双侧都有依据才启用，单侧命中不猜；
 * - 固定时长（[fixedDurationEnabled]，秒，与飞牛 play.setConfigByItem 的 skip_opening/skip_ending 一致）：
 *   仅在对应侧前两层都未命中时兜底；优先级 命名章节 > 规律推测 > 固定时长；
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
    val namedIntroFound = introEndMs != null
    val namedOutroFound = outroStartMs != null
    var introFromPattern = false
    var outroFromPattern = false
    // ED 之后若还有章节（彩蛋/PV/下集预告），片尾曲的结束边界 = 下一章节起点。
    var outroEndMs: Long? = null
    if (outroIndex >= 0 && outroIndex + 1 < (chapters?.size ?: 0)) {
        val endMs = (chapters!![outroIndex + 1]["timeMs"] as? Number)?.toLong()
        if (endMs != null && outroStartMs != null && endMs > outroStartMs && endMs < durationMs) {
            outroEndMs = endMs
        }
    }
    // 编号章节规律推测（动漫/剧集通用布局）：双侧都有依据（命名识别或规律命中）才启用，
    // 单侧命中不猜，避免把真实内容误判成片头片尾。
    if (chapterEnabled && durationMs >= PATTERN_MIN_DURATION_MS &&
        !chapters.isNullOrEmpty() && chapters.size >= 3
    ) {
        val op = patternOpCandidate(chapters, durationMs)
        val ed = patternEdCandidate(chapters, durationMs)
        if ((introEndMs != null || op != null) && (outroStartMs != null || ed != null)) {
            if (introEndMs == null && op != null) {
                introStartMs = op.first
                introEndMs = op.second
                introFromPattern = true
            }
            if (outroStartMs == null && ed != null) {
                outroStartMs = ed.first
                // ED 章节后还有内容时只跳到下一章节起点；是最后一章则覆盖到文件结尾。
                outroEndMs = ed.second.takeIf { it < durationMs }
                outroFromPattern = true
            }
        }
    }
    var introFromChapter = namedIntroFound
    var outroFromChapter = namedOutroFound
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
        introFromPattern = false
    }
    if (outroStartMs != null && (outroStartMs <= 0L || outroStartMs >= durationMs)) {
        outroStartMs = null
        outroFromChapter = false
        outroFromPattern = false
    }
    if (outroStartMs == null) outroEndMs = null
    if (introEndMs != null && outroStartMs != null && introEndMs >= outroStartMs) {
        introStartMs = null
        introEndMs = null
        outroStartMs = null
        outroEndMs = null
        introFromChapter = false
        outroFromChapter = false
        introFromPattern = false
        outroFromPattern = false
    }
    return NativeChapterSkipBounds(
        introStartMs = introStartMs,
        introEndMs = introEndMs,
        outroStartMs = outroStartMs,
        outroEndMs = outroEndMs,
        introFromChapter = introFromChapter,
        outroFromChapter = outroFromChapter,
        introFromPattern = introFromPattern,
        outroFromPattern = outroFromPattern,
    )
}

/**
 * 自动跳过模式下的执行时间点（毫秒）：提示出现位置 + 倒计时，但不早于范围起点、
 * 不晚于范围终点（范围比倒计时短时在终点执行）。倒计时基于播放位置，暂停即冻结。
 * 与桌面端 desktopSkipAutoAdvanceAt 语义一致；该侧未识别到范围时返回 null。
 */
fun nativeSkipAutoAdvanceAtMs(
    intro: Boolean,
    bounds: NativeChapterSkipBounds,
    shownPosMs: Long,
    countdownMs: Long,
    durationMs: Long,
): Long? {
    if (intro) {
        val endMs = bounds.introEndMs ?: return null
        val startMs = bounds.introStartMs ?: 0L
        return maxOf(startMs, shownPosMs + countdownMs).coerceAtMost(endMs)
    }
    val startMs = bounds.outroStartMs ?: return null
    val endMs = bounds.outroEndMs ?: durationMs
    return maxOf(startMs, shownPosMs + countdownMs).coerceAtMost(endMs)
}

/**
 * 拖动进度条的轻微吸附：落点距章节线或跳过窗口边界不足 [radiusMs] 时贴到该标记，
 * 只在很靠近时生效，远离标记的微调不受影响。无命中时原样返回（与桌面端
 * snapSeekTargetToMarkers 语义一致）。
 */
fun snapSeekTargetMs(
    targetMs: Long,
    markerCandidatesMs: List<Long>,
    radiusMs: Long = 3_000L,
): Long {
    var bestMs = targetMs
    var bestDelta = radiusMs
    for (marker in markerCandidatesMs) {
        val delta = abs(marker - targetMs)
        if (delta < bestDelta) {
            bestDelta = delta
            bestMs = marker
        }
    }
    return bestMs
}
