package com.geqian.flyplayer.fly_player

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

internal const val NATIVE_SUBTITLE_STATE_VERSION = 2

internal val NATIVE_SUBTITLE_IMPORT_EXTENSIONS = setOf(
    "srt",
    "ass",
    "ssa",
    "vtt",
    "sub",
    "ttml",
    "sup",
    "pgs",
)

internal fun nativeSubtitleImportFormatSupported(fileName: String): Boolean {
    val extension = fileName.substringAfterLast('.', "").trim().lowercase()
    return extension in NATIVE_SUBTITLE_IMPORT_EXTENSIONS
}

/** 原生与 Flutter 共享的一条手动导入字幕元数据。 */
internal data class NativeSubtitleEntry(
    val guid: String,
    val mediaGuid: String,
    val itemGuid: String,
    val fileName: String,
    val path: String,
    val format: String,
    val importedAtMs: Long,
) {
    companion object {
        fun fromJson(json: JSONObject): NativeSubtitleEntry = NativeSubtitleEntry(
            guid = json.optString("guid").trim(),
            mediaGuid = json.optString("mediaGuid").trim(),
            itemGuid = json.optString("itemGuid").trim(),
            fileName = json.optString("fileName"),
            path = json.optString("path"),
            format = json.optString("format").trim().lowercase(),
            importedAtMs = json.optLong("importedAtMs"),
        )
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("guid", guid)
        put("mediaGuid", mediaGuid)
        put("itemGuid", itemGuid)
        put("fileName", fileName)
        put("path", path)
        put("format", format)
        put("importedAtMs", importedAtMs)
    }
}

/** 一次完整持久化快照；[root] 用于在改写时保留未知顶层字段。 */
internal data class NativeSubtitleState(
    val entries: List<NativeSubtitleEntry> = emptyList(),
    val selectedByScope: Map<String, String> = emptyMap(),
    val root: JSONObject = JSONObject(),
)

internal data class NativeSubtitleDeleteResult(
    val deleted: Boolean,
    val state: NativeSubtitleState,
    val removed: NativeSubtitleEntry? = null,
)

internal fun nativeSubtitleScopeKey(itemGuid: String, mediaGuid: String): String {
    val item = itemGuid.trim()
    if (item.isNotEmpty()) return "item:$item"
    val media = mediaGuid.trim()
    return if (media.isEmpty()) "" else "media:$media"
}

internal fun decodeNativeSubtitleState(raw: String): NativeSubtitleState {
    val normalized = raw.trim()
    if (normalized.isEmpty()) return NativeSubtitleState()
    return runCatching {
        val root: JSONObject
        val entriesJson: JSONArray
        if (normalized.startsWith("[")) {
            root = JSONObject()
            entriesJson = JSONArray(normalized)
        } else {
            root = JSONObject(normalized)
            entriesJson = root.optJSONArray("entries") ?: JSONArray()
        }
        val entries = buildList {
            for (index in 0 until entriesJson.length()) {
                val entry = entriesJson.optJSONObject(index) ?: continue
                NativeSubtitleEntry.fromJson(entry)
                    .takeIf { it.guid.isNotEmpty() }
                    ?.let(::add)
            }
        }
        val selectedJson = root.optJSONObject("selectedByScope")
        val selected = buildMap {
            if (selectedJson != null) {
                val keys = selectedJson.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val guid = selectedJson.optString(key).trim()
                    if (key.isNotBlank() && guid.isNotEmpty()) put(key, guid)
                }
            }
        }
        NativeSubtitleState(
            entries = entries.sortedByDescending { it.importedAtMs },
            selectedByScope = selected,
            root = root,
        )
    }.getOrElse { NativeSubtitleState() }
}

internal fun encodeNativeSubtitleState(state: NativeSubtitleState): String {
    val root = runCatching { JSONObject(state.root.toString()) }
        .getOrElse { JSONObject() }
    root.put("version", NATIVE_SUBTITLE_STATE_VERSION)
    root.put(
        "entries",
        JSONArray().apply {
            state.entries.forEach { put(it.toJson()) }
        },
    )
    root.put(
        "selectedByScope",
        JSONObject().apply {
            state.selectedByScope.forEach { (scope, guid) ->
                if (scope.isNotBlank() && guid.isNotBlank()) put(scope, guid)
            }
        },
    )
    return root.toString()
}

private fun nativeSubtitleEntriesForLoadArgs(
    state: NativeSubtitleState,
    loadArgs: Map<String, Any?>,
): List<NativeSubtitleEntry> {
    val itemGuid = loadArgs["itemGuid"]?.toString()?.trim().orEmpty()
    val mediaGuid = loadArgs["mediaGuid"]?.toString()?.trim().orEmpty()
    if (itemGuid.isNotEmpty()) {
        val byItem = state.entries.filter { it.itemGuid == itemGuid }
        if (byItem.isNotEmpty()) return byItem
    }
    if (mediaGuid.isNotEmpty()) {
        return state.entries.filter { it.mediaGuid == mediaGuid }
    }
    return emptyList()
}

private fun nativeSubtitleSelectedGuid(
    state: NativeSubtitleState,
    itemGuid: String,
    mediaGuid: String,
): String? {
    val normalizedItem = itemGuid.trim()
    if (normalizedItem.isNotEmpty()) {
        state.selectedByScope["item:$normalizedItem"]?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { return it }
    }
    val normalizedMedia = mediaGuid.trim()
    if (normalizedMedia.isNotEmpty()) {
        return state.selectedByScope["media:$normalizedMedia"]
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }
    return null
}

private fun isManualImportedSubtitleGuid(value: Any?): Boolean =
    value?.toString()?.trim()?.lowercase()?.startsWith("local:sub:") == true

/**
 * 把当前条目的持久化字幕注入播放参数，并恢复该条目最后选择的手动字幕。
 *
 * 这是纯函数，Activity 初始化、切集和切画质必须使用它返回的同一份参数。
 */
@Suppress("UNCHECKED_CAST")
internal fun restoreNativeSubtitleLoadArgs(
    loadArgs: Map<String, Any?>,
    state: NativeSubtitleState,
    fileExists: (String) -> Boolean,
): Map<String, Any?> {
    val restored = HashMap<String, Any?>(loadArgs)
    // 切集/切源的参数可能从上一播放会话带回本地轨。手动导入轨按目标条目从持久化
    // 状态重新注入，先剥离 local:sub: 可避免上一集字幕和文件路径串入下一集。
    val tracks = (loadArgs["subtitleTracks"] as? List<*>)
        ?.filterNot { track ->
            isManualImportedSubtitleGuid((track as? Map<*, *>)?.get("guid"))
        }
        ?.toMutableList()
        ?: mutableListOf<Any?>()
    val files = (loadArgs["localSubtitleFiles"] as? Map<*, *>)
        ?.entries
        ?.mapNotNull { (key, value) ->
            val guid = key?.toString()?.trim().orEmpty()
            val path = value?.toString()?.trim().orEmpty()
            if (guid.isEmpty() || path.isEmpty() || isManualImportedSubtitleGuid(guid)) {
                null
            } else {
                guid to path
            }
        }
        ?.toMap()
        ?.toMutableMap()
        ?: mutableMapOf()
    restored["subtitleTracks"] = tracks
    restored["localSubtitleFiles"] = files
    if (isManualImportedSubtitleGuid(loadArgs["subtitleTrackGuid"])) {
        restored["subtitleTrackGuid"] = null
        restored["preferExternalSubtitle"] = false
    }

    val persisted = nativeSubtitleEntriesForLoadArgs(state, loadArgs)
        .filter { it.path.isNotBlank() && fileExists(it.path) }
    if (persisted.isEmpty()) return restored

    val knownGuids = tracks.mapNotNullTo(mutableSetOf()) {
        (it as? Map<*, *>)?.get("guid")?.toString()?.trim()?.takeIf(String::isNotEmpty)
    }
    for (entry in persisted) {
        files[entry.guid] = entry.path
        if (!knownGuids.add(entry.guid)) continue
        val isBitmap = entry.format == "sup" || entry.format == "pgs"
        tracks.add(
            mapOf<String, Any?>(
                "guid" to entry.guid,
                "title" to entry.fileName,
                "format" to entry.format,
                "codecName" to entry.format,
                "language" to "und",
                "index" to -1 - tracks.size,
                "isDefault" to 0,
                "forced" to 0,
                "isExternal" to 1,
                "extraFile" to 1,
                "isBitmap" to if (isBitmap) 1 else 0,
            ),
        )
    }

    val itemGuid = loadArgs["itemGuid"]?.toString().orEmpty()
    val mediaGuid = loadArgs["mediaGuid"]?.toString().orEmpty()
    val selectedGuid = nativeSubtitleSelectedGuid(state, itemGuid, mediaGuid)
    if (selectedGuid != null && persisted.any { it.guid == selectedGuid }) {
        restored["subtitleTrackGuid"] = selectedGuid
        restored["subtitleTrackIndex"] = null
        restored["preferExternalSubtitle"] = true
    }
    return restored
}

internal fun removeNativeSubtitleFromState(
    state: NativeSubtitleState,
    guid: String,
): NativeSubtitleState {
    val normalized = guid.trim()
    if (normalized.isEmpty()) return state
    return state.copy(
        entries = state.entries.filterNot { it.guid == normalized },
        selectedByScope = state.selectedByScope.filterValues { it != normalized },
    )
}

internal fun deleteNativeSubtitle(
    state: NativeSubtitleState,
    guid: String,
    deleteFile: (String) -> Boolean,
): NativeSubtitleDeleteResult {
    val normalized = guid.trim()
    val entry = state.entries.firstOrNull { it.guid == normalized }
        ?: return NativeSubtitleDeleteResult(deleted = false, state = state)
    if (!deleteFile(entry.path)) {
        return NativeSubtitleDeleteResult(deleted = false, state = state)
    }
    return NativeSubtitleDeleteResult(
        deleted = true,
        state = removeNativeSubtitleFromState(state, normalized),
        removed = entry,
    )
}

/**
 * 手动导入的本地字幕（SAF「+添加」）的持久化与播放参数恢复。
 *
 * Flutter legacy `SharedPreferences` 与本类共享 `FlutterSharedPreferences` 文件和
 * `flutter.manual_local_subtitles_v1` 键；两端统一使用版本化 JSON 对象。
 */
object NativeSubtitleImportStore {
    const val SHARED_PREF_KEY = "flutter.manual_local_subtitles_v1"

    private const val SHARED_PREFS_NAME = "FlutterSharedPreferences"
    private const val SUBTITLES_SUB_DIR = "subtitles"

    fun subtitlesDir(context: Context): File {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, SUBTITLES_SUB_DIR).also { dir ->
            if (!dir.exists()) runCatching { dir.mkdirs() }
        }
    }

    fun copyUriToSubtitlesDir(
        context: Context,
        uri: Uri,
        displayName: String?,
    ): File? {
        val name = displayName ?: "subtitle.srt"
        val ext = name.substringAfterLast('.', "").trim().lowercase().ifEmpty { "srt" }
        val dest = File(subtitlesDir(context), "${UUID.randomUUID()}.$ext")
        return runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                java.io.FileOutputStream(dest).use { output -> input.copyTo(output) }
            } ?: error("无法打开字幕输入流")
            dest
        }.getOrElse {
            // 输入流中途失败时 FileOutputStream 可能已生成半截文件，必须顺手清理。
            runCatching { if (dest.exists()) dest.delete() }
            null
        }
    }

    private fun sharedPrefs(context: Context) =
        context.getSharedPreferences(SHARED_PREFS_NAME, Context.MODE_PRIVATE)

    private fun loadState(context: Context): NativeSubtitleState {
        val raw = runCatching {
            sharedPrefs(context).getString(SHARED_PREF_KEY, null)
        }.getOrNull().orEmpty()
        return decodeNativeSubtitleState(raw)
    }

    private fun saveState(context: Context, state: NativeSubtitleState): Boolean = runCatching {
        sharedPrefs(context).edit()
            .putString(SHARED_PREF_KEY, encodeNativeSubtitleState(state))
            .commit()
    }.getOrDefault(false)

    private fun addEntryToState(
        state: NativeSubtitleState,
        entry: NativeSubtitleEntry,
    ): NativeSubtitleState {
        val displacedGuids = state.entries
            .filter { it.guid == entry.guid || it.path == entry.path }
            .mapTo(mutableSetOf()) { it.guid }
        return state.copy(
            entries = state.entries
                .filterNot { it.guid == entry.guid || it.path == entry.path }
                .plus(entry)
                .sortedByDescending { it.importedAtMs },
            selectedByScope = state.selectedByScope.filterValues { it !in displacedGuids },
        )
    }

    @Synchronized
    internal fun saveEntryAndSelect(context: Context, entry: NativeSubtitleEntry): Boolean {
        if (entry.guid.isEmpty()) return false
        var state = addEntryToState(loadState(context), entry)
        val scope = nativeSubtitleScopeKey(entry.itemGuid, entry.mediaGuid)
        if (scope.isNotEmpty()) {
            state = state.copy(
                selectedByScope = state.selectedByScope + (scope to entry.guid),
            )
        }
        return saveState(context, state)
    }

    @Synchronized
    fun setSelectedGuid(
        context: Context,
        itemGuid: String,
        mediaGuid: String,
        guid: String?,
    ): Boolean {
        val scope = nativeSubtitleScopeKey(itemGuid, mediaGuid)
        if (scope.isEmpty()) return false
        val state = loadState(context)
        val selected = state.selectedByScope.toMutableMap()
        val normalizedGuid = guid?.trim().orEmpty()
        if (normalizedGuid.isEmpty()) {
            selected.remove(scope)
        } else {
            selected[scope] = normalizedGuid
        }
        return saveState(context, state.copy(selectedByScope = selected))
    }

    @Synchronized
    fun deleteEntryAndFile(context: Context, guid: String): Boolean {
        val state = loadState(context)
        val result = deleteNativeSubtitle(
            state = state,
            guid = guid,
            deleteFile = { path ->
                if (path.isBlank()) {
                    true
                } else {
                    runCatching {
                        val file = File(path)
                        !file.exists() || file.delete()
                    }.getOrDefault(false)
                }
            },
        )
        return result.deleted && saveState(context, result.state)
    }

    fun restoreLoadArgs(
        context: Context,
        loadArgs: Map<String, Any?>,
    ): Map<String, Any?> = restoreNativeSubtitleLoadArgs(
        loadArgs = loadArgs,
        state = loadState(context),
        fileExists = { path -> File(path).exists() },
    )
}
