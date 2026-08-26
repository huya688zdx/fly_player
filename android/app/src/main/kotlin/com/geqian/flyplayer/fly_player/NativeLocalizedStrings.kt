package com.geqian.flyplayer.fly_player

import android.content.Context
import androidx.annotation.StringRes
import org.json.JSONObject

/**
 * Flutter 下发的本地化文案表（资源条目名 → 文案模板）。
 *
 * 文案的管理权在 Flutter 侧 l10n（lib/l10n 下的 arb，经
 * lib/services/native_player_localized_strings.dart 构建映射），随 loadArgs 的
 * `localizedStrings` 字段注入原生壳，前台恢复时经 `loadPlayerGlobalSettings`
 * 反向通道刷新。res/values/strings.xml 冻结为兜底：map 缺 key、格式化失败或
 * 尚未注入（如进程冷启动早期）时回退资源值，保证任何时序下都有文案可显示。
 *
 * 模板沿用 Android 位置格式（%1$s / %1$d），命中后用 [String.format] 套参，
 * 与资源路径的 getString(id, args) 行为一致。
 */
object NativeLocalizedStrings {
    @Volatile
    private var strings: Map<String, String> = emptyMap()

    /** 覆盖安装整表。空表忽略（避免异常回包清掉已生效文案）。 */
    fun install(map: Map<String, String>) {
        if (map.isNotEmpty()) strings = map
    }

    /** 从 loadArgs JSON 的 `localizedStrings` 对象安装。 */
    fun installFromJson(obj: JSONObject?) {
        if (obj == null) return
        val map = HashMap<String, String>(obj.length())
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = obj.optString(key)
            if (key.isNotEmpty() && value.isNotEmpty()) map[key] = value
        }
        install(map)
    }

    /** 从 MethodChannel 回包（Map<*, *>）的 `localizedStrings` 值安装。 */
    fun installFromMap(raw: Map<*, *>?) {
        if (raw == null) return
        val map = HashMap<String, String>(raw.size)
        for ((key, value) in raw) {
            val k = key?.toString().orEmpty()
            val v = value?.toString().orEmpty()
            if (k.isNotEmpty() && v.isNotEmpty()) map[k] = v
        }
        install(map)
    }

    fun resolve(context: Context, @StringRes id: Int, vararg formatArgs: Any?): String {
        val map = strings
        if (map.isNotEmpty()) {
            val key = runCatching { context.resources.getResourceEntryName(id) }.getOrNull()
            val template = key?.let(map::get)
            if (!template.isNullOrEmpty()) {
                if (formatArgs.isEmpty()) return template
                runCatching { return String.format(template, *formatArgs) }
                // 格式化失败（下发模板与参数不匹配）→ 落到资源兜底。
            }
        }
        return if (formatArgs.isEmpty()) {
            context.getString(id)
        } else {
            context.getString(id, *formatArgs)
        }
    }
}

/** 用户可见文案统一入口：优先 Flutter 下发文案，缺失回退 strings.xml。 */
fun Context.localizedString(@StringRes id: Int, vararg formatArgs: Any?): String =
    NativeLocalizedStrings.resolve(this, id, *formatArgs)
