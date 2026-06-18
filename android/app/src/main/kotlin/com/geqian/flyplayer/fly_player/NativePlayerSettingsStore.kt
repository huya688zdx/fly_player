package com.geqian.flyplayer.fly_player

import android.content.Context
import org.json.JSONObject

/**
 * 原生播放壳的播放设置持久化（SharedPreferences + JSON）。
 *
 * 每个设置分组（mpv 高级参数 / 画面调整 / 字幕样式 / 音频微调 / 弹幕显示 / 遮罩 /
 * 片头片尾 / 画面杂项）各以一条 JSON 记录存盘，下次进入播放器恢复——对齐 Flutter
 * 端 `mpv_settings_store` 的「记住设置」体验。
 *
 * 取/存都按「白名单」合并：只认 [defaults] 里存在的 key，避免脏数据塞进镜像。
 */
class NativePlayerSettingsStore(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 读取分组：以 [defaults] 为底，仅覆盖其中已存在的 key（类型沿用 JSON 解析结果）。 */
    fun loadMap(key: String, defaults: Map<String, Any?>): LinkedHashMap<String, Any?> {
        val merged = LinkedHashMap<String, Any?>(defaults)
        val raw = prefs.getString(key, null) ?: return merged
        runCatching {
            val json = JSONObject(raw)
            for (k in json.keys()) {
                if (!merged.containsKey(k)) continue
                val v = json.get(k)
                merged[k] = if (v == JSONObject.NULL) null else v
            }
        }
        return merged
    }

    fun saveMap(key: String, value: Map<String, Any?>) {
        runCatching {
            prefs.edit().putString(key, JSONObject(value).toString()).apply()
        }
    }

    fun loadString(key: String): String? = prefs.getString(key, null)

    fun saveString(key: String, value: String) {
        runCatching { prefs.edit().putString(key, value).apply() }
    }

    companion object {
        private const val PREFS_NAME = "native_player_settings"
        const val KEY_MPV_ADVANCED = "mpv_advanced"
        const val KEY_VIDEO_ADJUST = "video_adjust"
        const val KEY_SUBTITLE_STYLE = "subtitle_style"
        const val KEY_AUDIO_ADJUST = "audio_adjust"
        const val KEY_OCCLUSION = "occlusion_config"
        const val KEY_INTRO_OUTRO = "intro_outro"
        const val KEY_PLAYBACK_BEHAVIOR = "playback_behavior"
        const val KEY_VIDEO_MISC = "video_misc"
        const val KEY_DANMAKU = "danmaku_settings"
        const val KEY_BOOKMARKS = "bookmarks_v1"
        const val KEY_DANMAKU_SOURCES = "danmaku_sources_v1"
    }
}
