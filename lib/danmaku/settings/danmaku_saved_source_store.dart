import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../models/danmaku_saved_source.dart';

class DanmakuSavedSourceStore {
  // 旧版本把保存源(实测 70KB)塞进 SharedPreferences → 每次 getInstance/reload 都解码
  // 整个 prefs map（AppThemeProvider 每 1.5s reload 一次撞上即卡顿）。改文件存储 + 迁移。
  static const String _prefKey = 'player_danmaku_saved_sources_v1';
  static const String _fileName = 'danmaku_saved_sources_v1.json';
  static const String _autoMatchBlockedByMediaKey = 'autoMatchBlockedByMedia';
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  const DanmakuSavedSourceStore();

  ValueListenable<int> get changes => _revision;

  /// 启动时主动触发一次：把旧 SharedPreferences 里的 70KB blob 迁移到文件并删除该
  /// prefs key，使 prefs map 从一开始就是干净的(不必等首次进播放器才懒迁移)。
  Future<void> ensureMigratedFromPrefs() async {
    await _readRaw();
  }

  Future<List<DanmakuSavedSource>> loadAll() async {
    final payload = await _loadPayload();
    final rawSources =
        (payload['sources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  DanmakuSavedSource.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.sourceKey.trim().isNotEmpty)
            .toList(growable: false)
          ..sort(
            (left, right) => right.updatedAtMs.compareTo(left.updatedAtMs),
          );
    return rawSources;
  }

  Future<List<DanmakuSavedSource>> loadForMedia(String mediaKey) async {
    if (mediaKey.trim().isEmpty) return const <DanmakuSavedSource>[];
    final payload = await _loadPayload();
    final rawSources =
        (payload['sources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  DanmakuSavedSource.fromJson(Map<String, dynamic>.from(item)),
            )
            .where(
              (item) =>
                  item.mediaKey == mediaKey && item.sourceKey.trim().isNotEmpty,
            )
            .toList(growable: false)
          ..sort(
            (left, right) => right.updatedAtMs.compareTo(left.updatedAtMs),
          );
    return rawSources;
  }

  Future<String?> loadActiveSourceKey(String mediaKey) async {
    if (mediaKey.trim().isEmpty) return null;
    final payload = await _loadPayload();
    final activeByMedia = Map<String, dynamic>.from(
      payload['activeByMedia'] as Map? ?? const {},
    );
    final value = activeByMedia[mediaKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String?> loadAutoMatchBlockedReason(String mediaKey) async {
    if (mediaKey.trim().isEmpty) return null;
    final payload = await _loadPayload();
    final blockedByMedia = Map<String, dynamic>.from(
      payload[_autoMatchBlockedByMediaKey] as Map? ?? const {},
    );
    final value = blockedByMedia[mediaKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveSource(DanmakuSavedSource source) async {
    final payload = await _loadPayload();
    final sources = (payload['sources'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              DanmakuSavedSource.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (item) =>
              item.sourceKey != source.sourceKey ||
              item.mediaKey != source.mediaKey,
        )
        .toList(growable: true);
    sources.add(source);
    sources.sort(
      (left, right) => right.updatedAtMs.compareTo(left.updatedAtMs),
    );
    final limited = <DanmakuSavedSource>[];
    final countsByMedia = <String, int>{};
    for (final item in sources) {
      final count = countsByMedia[item.mediaKey] ?? 0;
      if (count >= 12) continue;
      countsByMedia[item.mediaKey] = count + 1;
      limited.add(item);
    }
    payload['sources'] = limited
        .map((item) => item.toJson())
        .toList(growable: false);
    final activeByMedia = Map<String, dynamic>.from(
      payload['activeByMedia'] as Map? ?? const {},
    );
    activeByMedia[source.mediaKey] = source.sourceKey;
    payload['activeByMedia'] = activeByMedia;
    final blockedByMedia = Map<String, dynamic>.from(
      payload[_autoMatchBlockedByMediaKey] as Map? ?? const {},
    );
    blockedByMedia.remove(source.mediaKey);
    payload[_autoMatchBlockedByMediaKey] = blockedByMedia;
    await _savePayload(payload);
    _notifyChanged();
  }

  Future<void> removeSource({
    required String mediaKey,
    required String sourceKey,
  }) async {
    final payload = await _loadPayload();
    final sources = (payload['sources'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              DanmakuSavedSource.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (item) => !(item.mediaKey == mediaKey && item.sourceKey == sourceKey),
        )
        .toList(growable: false);
    payload['sources'] = sources
        .map((item) => item.toJson())
        .toList(growable: false);
    final activeByMedia = Map<String, dynamic>.from(
      payload['activeByMedia'] as Map? ?? const {},
    );
    if ((activeByMedia[mediaKey]?.toString() ?? '') == sourceKey) {
      activeByMedia.remove(mediaKey);
    }
    payload['activeByMedia'] = activeByMedia;
    await _savePayload(payload);
    _notifyChanged();
  }

  Future<void> setActiveSourceKey({
    required String mediaKey,
    required String? sourceKey,
  }) async {
    final payload = await _loadPayload();
    final activeByMedia = Map<String, dynamic>.from(
      payload['activeByMedia'] as Map? ?? const {},
    );
    final normalized = sourceKey?.trim() ?? '';
    if (normalized.isEmpty) {
      activeByMedia.remove(mediaKey);
    } else {
      activeByMedia[mediaKey] = normalized;
    }
    payload['activeByMedia'] = activeByMedia;
    await _savePayload(payload);
    _notifyChanged();
  }

  Future<void> saveAutoMatchBlockedReason({
    required String mediaKey,
    required String reason,
  }) async {
    final normalizedMediaKey = mediaKey.trim();
    final normalizedReason = reason.trim();
    if (normalizedMediaKey.isEmpty || normalizedReason.isEmpty) return;
    final payload = await _loadPayload();
    final blockedByMedia = Map<String, dynamic>.from(
      payload[_autoMatchBlockedByMediaKey] as Map? ?? const {},
    );
    blockedByMedia[normalizedMediaKey] = normalizedReason;
    payload[_autoMatchBlockedByMediaKey] = blockedByMedia;
    await _savePayload(payload);
    _notifyChanged();
  }

  Future<void> clearAutoMatchBlockedReason(String mediaKey) async {
    final normalizedMediaKey = mediaKey.trim();
    if (normalizedMediaKey.isEmpty) return;
    final payload = await _loadPayload();
    final blockedByMedia = Map<String, dynamic>.from(
      payload[_autoMatchBlockedByMediaKey] as Map? ?? const {},
    );
    if (blockedByMedia.remove(normalizedMediaKey) == null) {
      return;
    }
    payload[_autoMatchBlockedByMediaKey] = blockedByMedia;
    await _savePayload(payload);
    _notifyChanged();
  }

  Future<void> clearAll() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    unawaited(_purgeLegacyPref());
    _notifyChanged();
  }

  static Future<String>? _pathFuture;
  Future<File> _file() async {
    final path = await (_pathFuture ??= () async {
      final dir = await getDatabasesPath();
      return '$dir/$_fileName';
    }());
    return File(path);
  }

  Map<String, dynamic> _emptyPayload() => <String, dynamic>{
    'sources': <dynamic>[],
    'activeByMedia': <String, dynamic>{},
    _autoMatchBlockedByMediaKey: <String, dynamic>{},
  };

  Future<Map<String, dynamic>> _loadPayload() async {
    final raw = await _readRaw();
    if (raw == null || raw.trim().isEmpty) return _emptyPayload();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return _emptyPayload();
    return Map<String, dynamic>.from(decoded);
  }

  /// 优先读文件；文件不存在则从旧 SharedPreferences 迁移一次并删除该 prefs 大 blob。
  Future<String?> _readRaw() async {
    final file = await _file();
    if (await file.exists()) return file.readAsString();
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_prefKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await file.writeAsString(legacy, flush: true);
      }
      if (prefs.containsKey(_prefKey)) await prefs.remove(_prefKey);
      return legacy;
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePayload(Map<String, dynamic> payload) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _purgeLegacyPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefKey)) await prefs.remove(_prefKey);
    } catch (_) {}
  }

  void _notifyChanged() {
    _revision.value++;
  }
}
