import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 管理设置页搜索使用频次的本地存储。
class SettingsSearchStore {
  static const String _usageKey = 'settings_search_usage_v1';
  static const int _maxEntries = 48;

  /// 创建一个设置搜索统计存储实例。
  const SettingsSearchStore();

  /// 读取各设置项的搜索使用次数。
  Future<Map<String, int>> loadUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usageKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, int>{};
      }
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is num) {
          result[key] = value.toInt();
        }
      }
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  /// 记录一次设置项被命中的使用行为。
  Future<void> recordUse(String id) async {
    if (id.trim().isEmpty) return;
    final next = await loadUsage();
    next.update(id, (value) => value + 1, ifAbsent: () => 1);
    final ranked = next.entries.toList(growable: false)
      ..sort((a, b) {
        final compare = b.value.compareTo(a.value);
        if (compare != 0) return compare;
        return a.key.compareTo(b.key);
      });
    final trimmed = ranked.take(_maxEntries);
    final payload = <String, int>{
      for (final entry in trimmed) entry.key: entry.value,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usageKey, jsonEncode(payload));
  }
}
