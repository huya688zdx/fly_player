package com.geqian.flyplayer.fly_player.mpv

import android.os.SystemClock
import android.util.Log
import java.io.File

class TrackSelectionController(
    private val mpv: MpvFacade = DefaultMpvFacade,
) {
    companion object {
        private const val DEFAULT_SUBTITLE_POSITION = 92
        private const val MAX_TRACK_SCAN_COUNT = 64
        private const val EMPTY_TRACK_SCAN_BREAK_THRESHOLD = 8
        private const val BOGUS_PURGE_RETRY_COOLDOWN_MS = 1800L
        // 同一外挂字幕路径在该窗口内被反复要求重挂时跳过 purge+sub-add，打断
        // 「内嵌 PGS/SUP 轨选择」与「服务端外挂 .ass 重挂」互相覆盖的振荡风暴。
        private const val EXTERNAL_SUBTITLE_READD_COOLDOWN_MS = 1500L
    }

    private var pendingAudioDelay = 0.0
    private var pendingSubtitleDelay = 0.0
    private var pendingSubtitlePosition = DEFAULT_SUBTITLE_POSITION
    private var pendingSubtitleScale = 1.0
    private var pendingExternalSubtitlePath: String? = null
    private var activeExternalSubtitlePath: String? = null
    private var pendingPlaybackSpeed: Double = 1.0
    private var pendingAudioTrackIndex: Int? = null
    private var pendingSubtitleTrackIndex: Int? = null
    private var pendingPreferExternalSubtitle: Boolean = false
    private var pendingSubtitleGuid: String? = null
    private var lastBogusPurgeAbortElapsedMs: Long = 0L
    private var lastExternalSubAddPath: String? = null
    private var lastExternalSubAddElapsedMs: Long = 0L

    fun onLoadRequested(source: MpvSource) {
        purgeExternalSubtitleTracks()
        // External subtitle restoration is driven by the Flutter side after the
        // new source is ready. Carrying the previous external path across loads
        // here causes the native restore coordinator to sub-add the same file a
        // second time, which then triggers extra refresh seeks and visible
        // subtitle stutter.
        activeExternalSubtitlePath = null
        pendingPlaybackSpeed = source.playbackSpeed
        pendingAudioTrackIndex = source.audioTrackIndex
        pendingSubtitleTrackIndex = source.subtitleTrackIndex
        pendingPreferExternalSubtitle = source.preferExternalSubtitle
        pendingSubtitleGuid = source.subtitleTrackGuid
        pendingExternalSubtitlePath = null
        // 新源：清掉重挂冷却记忆，避免跨集复用同一 .ass 路径时误跳过首次挂载。
        lastExternalSubAddPath = null
        lastExternalSubAddElapsedMs = 0L
    }

    fun onSubtitleTrackSelectedManually() {
        pendingExternalSubtitlePath = null
        activeExternalSubtitlePath = null
        purgeExternalSubtitleTracks(force = true)
    }

    fun onFileLoaded() {
        runCatching {
            mpv.setPropertyDouble("speed", pendingPlaybackSpeed)
        }
        runCatching {
            mpv.setPropertyDouble("audio-delay", pendingAudioDelay)
        }
        runCatching {
            mpv.setPropertyDouble("sub-delay", pendingSubtitleDelay)
        }
        runCatching {
            mpv.setPropertyInt("sub-pos", pendingSubtitlePosition.toLong())
        }
        runCatching {
            mpv.setPropertyDouble("sub-scale", pendingSubtitleScale)
        }
        runCatching {
            mpv.setPropertyString("sub-ass-override", "scale")
        }
        pendingAudioTrackIndex?.let { index ->
            runCatching { mpv.setPropertyInt("aid", index.toLong()) }
        }
        when {
            pendingPreferExternalSubtitle &&
                pendingExternalSubtitlePath?.isNotBlank() == true -> runCatching {
                // Only disable the current subtitle track when an external file is
                // actually ready to be mounted. Otherwise the UI may still show the
                // selected subtitle while mpv has already been forced to sid=no.
                mpv.setPropertyString("sid", "no")
            }
            pendingSubtitleTrackIndex != null -> runCatching {
                val index = pendingSubtitleTrackIndex!!
                if (index < 0) {
                    mpv.setPropertyString("sid", "no")
                } else {
                    mpv.setPropertyInt("sid", index.toLong())
                }
            }
            // Leave subtitle selection to mpv when no explicit choice is provided.
            pendingSubtitleGuid.isNullOrBlank() -> Unit
        }
    }

    fun queueExternalSubtitle(path: String, initialized: Boolean): Boolean {
        if (!initialized || path.isBlank()) return false
        pendingExternalSubtitlePath = path
        return true
    }

    fun applyPendingExternalSubtitle(): Boolean {
        val path = pendingExternalSubtitlePath?.takeIf { it.isNotBlank() } ?: return false
        val existingTrackIds = findExternalSubtitleTrackIds(path)
        if (existingTrackIds.isNotEmpty()) {
            val primaryTrackId = existingTrackIds.first()
            if (existingTrackIds.size > 1) {
                existingTrackIds.drop(1).forEach { duplicateTrackId ->
                    runCatching {
                        mpv.command(arrayOf("sub-remove", duplicateTrackId.toString()))
                    }
                }
            }
            val selectedExisting = runCatching {
                mpv.setPropertyInt("sid", primaryTrackId.toLong())
            }.getOrDefault(false)
            if (selectedExisting) {
                Log.d("FlyPlayerMpv", "reuse external subtitle path=$path sid=$primaryTrackId")
                activeExternalSubtitlePath = path
                pendingExternalSubtitlePath = null
                return true
            }
        }
        if (activeExternalSubtitlePath == path) {
            pendingExternalSubtitlePath = null
            return true
        }
        // 振荡保护：同一外挂路径刚 sub-add 过、却又（被竞争的内嵌轨选择 purge 后）要求重挂，
        // 说明正处于「PGS/SUP 内嵌 ↔ 外挂 .ass」互相覆盖的 ping-pong。冷却窗口内不再
        // purge+sub-add，清掉 pending 让竞争中的内嵌选择先稳定，避免反复 sub-add 抖动/卡顿。
        val now = SystemClock.elapsedRealtime()
        if (
            path == lastExternalSubAddPath &&
            lastExternalSubAddElapsedMs > 0L &&
            now - lastExternalSubAddElapsedMs < EXTERNAL_SUBTITLE_READD_COOLDOWN_MS
        ) {
            Log.d(
                "FlyPlayerMpv",
                "skip external subtitle re-add within cooldown ms=${now - lastExternalSubAddElapsedMs} path=$path",
            )
            pendingExternalSubtitlePath = null
            return false
        }
        val success = runCatching {
            purgeExternalSubtitleTracks(force = true)
            Log.d("FlyPlayerMpv", "sub-add path=$path")
            runCatching {
                mpv.setPropertyString("sid", "no")
            }
            mpv.command(
                arrayOf(
                    "sub-add",
                    path,
                    "select",
                ),
            ) >= 0
        }.getOrDefault(false)
        if (success) {
            activeExternalSubtitlePath = path
            pendingExternalSubtitlePath = null
            lastExternalSubAddPath = path
            lastExternalSubAddElapsedMs = SystemClock.elapsedRealtime()
        }
        return success
    }

    fun clearPendingExternalSubtitle() {
        pendingExternalSubtitlePath = null
    }

    fun hasPendingExternalSubtitle(): Boolean {
        return pendingExternalSubtitlePath?.isNotBlank() == true
    }

    fun setSubtitleDelay(delay: Double): Boolean {
        pendingSubtitleDelay = delay
        return true
    }

    fun setAudioDelay(delay: Double): Boolean {
        pendingAudioDelay = delay
        return true
    }

    fun setSubtitlePosition(position: Int): Boolean {
        pendingSubtitlePosition = position.coerceIn(0, 100)
        return true
    }

    fun setSubtitleScale(scale: Double): Boolean {
        pendingSubtitleScale = scale.coerceIn(0.5, 2.5)
        return true
    }

    fun resetSubtitleStyle() {
        pendingSubtitleDelay = 0.0
        pendingSubtitlePosition = DEFAULT_SUBTITLE_POSITION
        pendingSubtitleScale = 1.0
    }

    fun reset() {
        purgeExternalSubtitleTracks(force = true)
        pendingExternalSubtitlePath = null
        activeExternalSubtitlePath = null
        pendingAudioTrackIndex = null
        pendingSubtitleTrackIndex = null
        pendingPreferExternalSubtitle = false
        pendingSubtitleGuid = null
    }

    private fun purgeExternalSubtitleTracks(force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (
            !force &&
            activeExternalSubtitlePath == null &&
            pendingExternalSubtitlePath.isNullOrBlank() &&
            lastBogusPurgeAbortElapsedMs > 0L &&
            now - lastBogusPurgeAbortElapsedMs < BOGUS_PURGE_RETRY_COOLDOWN_MS
        ) {
            Log.d(
                "FlyPlayerMpv",
                "skip repeated bogus external subtitle purge cooldownMs=${now - lastBogusPurgeAbortElapsedMs}",
            )
            return
        }
        val count = runCatching { mpv.getPropertyInt("track-list/count") }
            .getOrDefault(0L)
            .coerceIn(0L, MAX_TRACK_SCAN_COUNT.toLong())
            .toInt()
        if (count <= 0) return
        val externalIds = mutableListOf<Int>()
        var emptyStreak = 0
        // 同 findExternalSubtitleTrackIds：用字幕序号当作 sid/sub-remove 目标，绕开脏读 id。
        var subtitleOrdinal = 0
        for (index in 0 until count) {
            val type = runCatching { mpv.getPropertyString("track-list/$index/type") }
                .getOrNull()
                ?.trim()
                ?.lowercase()
            if (type.isNullOrEmpty()) {
                emptyStreak += 1
                if (shouldAbortBogusTrackScan(
                        index = index,
                        emptyStreak = emptyStreak,
                        foundTracks = externalIds.isNotEmpty(),
                    )
                ) {
                    lastBogusPurgeAbortElapsedMs = now
                    Log.d(
                        "FlyPlayerMpv",
                        "skip bogus external subtitle purge count=$count afterEmptyStreak=$emptyStreak",
                    )
                    break
                }
                continue
            }
            emptyStreak = 0
            if (type != "sub") continue
            subtitleOrdinal += 1
            val externalPath = runCatching {
                mpv.getPropertyString("track-list/$index/external-filename")
            }
                .getOrNull()
                ?.trim()
                .orEmpty()
            val external = externalPath.isNotEmpty() ||
                (runCatching { mpv.getPropertyString("track-list/$index/external") }
                    .getOrNull()
                    ?.trim()
                    ?.lowercase()
                    ?.let { it == "yes" || it == "true" || it == "1" }
                    ?: false)
            if (!external) continue
            externalIds += subtitleOrdinal
        }
        if (externalIds.isNotEmpty()) {
            lastBogusPurgeAbortElapsedMs = 0L
        }
        // 降序移除：sub-remove 会让后续字幕轨的序号前移，先移除大序号可保证小序号仍有效。
        for (trackId in externalIds.sortedDescending()) {
            runCatching {
                mpv.command(arrayOf("sub-remove", trackId.toString()))
            }
        }
    }

    private fun findExternalSubtitleTrackIds(path: String): List<Int> {
        val normalizedPath = normalizeExternalSubtitlePath(path)
        val fallbackTitle = File(path).name.trim().lowercase()
        val count = runCatching { mpv.getPropertyInt("track-list/count") }
            .getOrDefault(0L)
            .coerceIn(0L, MAX_TRACK_SCAN_COUNT.toLong())
            .toInt()
        if (count <= 0) return emptyList()
        val trackIds = mutableListOf<Int>()
        var emptyStreak = 0
        // mpv 的 sid 等于「同类型字幕轨里的 1-based 顺序号」，与 `track-list/$index/id`
        // 等价，但后者在轨道列表改写瞬间会脏读出越界垃圾值。这里按 readRuntimeTrackEntries
        // 的做法用字幕序号代替，彻底绕开脏读 id。
        var subtitleOrdinal = 0
        for (index in 0 until count) {
            val type = runCatching { mpv.getPropertyString("track-list/$index/type") }
                .getOrNull()
                ?.trim()
                ?.lowercase()
            if (type.isNullOrEmpty()) {
                emptyStreak += 1
                if (shouldAbortBogusTrackScan(
                        index = index,
                        emptyStreak = emptyStreak,
                        foundTracks = trackIds.isNotEmpty(),
                    )
                ) {
                    Log.d(
                        "FlyPlayerMpv",
                        "skip bogus external subtitle reuse scan count=$count afterEmptyStreak=$emptyStreak found=${trackIds.size}",
                    )
                    // 中止即列表结尾/脏读边界：保留已按字幕序号收集的有效结果（序号不会是垃圾），
                    // 已找到的外挂轨可直接复用，避免误丢后又重复 sub-add。
                    break
                }
                continue
            }
            emptyStreak = 0
            if (type != "sub") continue
            subtitleOrdinal += 1
            val externalPath = runCatching {
                mpv.getPropertyString("track-list/$index/external-filename")
            }
                .getOrNull()
                ?.trim()
                .orEmpty()
            val external = externalPath.isNotEmpty() ||
                (runCatching { mpv.getPropertyString("track-list/$index/external") }
                    .getOrNull()
                    ?.trim()
                    ?.lowercase()
                    ?.let { it == "yes" || it == "true" || it == "1" }
                    ?: false)
            if (!external) continue
            val title = runCatching { mpv.getPropertyString("track-list/$index/title") }
                .getOrNull()
                ?.trim()
                ?.lowercase()
                .orEmpty()
            val normalizedExternalPath = normalizeExternalSubtitlePath(externalPath)
            val pathMatches = normalizedExternalPath.isNotEmpty() &&
                normalizedExternalPath == normalizedPath
            val titleMatches = title.isNotEmpty() && title == fallbackTitle
            if (!pathMatches && !titleMatches) continue
            // 用字幕序号作为 sid（避开脏读的 track-list/$index/id）。
            trackIds += subtitleOrdinal
        }
        return trackIds
    }

    private fun normalizeExternalSubtitlePath(path: String): String {
        return path.trim().replace('\\', '/').lowercase()
    }

    private fun shouldAbortBogusTrackScan(
        index: Int,
        emptyStreak: Int,
        foundTracks: Boolean,
    ): Boolean {
        if (foundTracks && emptyStreak >= 3) {
            return true
        }
        return index >= (EMPTY_TRACK_SCAN_BREAK_THRESHOLD - 1) &&
            emptyStreak >= EMPTY_TRACK_SCAN_BREAK_THRESHOLD
    }
}
