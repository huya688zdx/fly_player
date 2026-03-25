import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/danmaku_saved_source.dart';

class DanmakuSavedSourceStore {
  static const String _prefKey = 'player_danmaku_saved_sources_v1';
  static const String _autoMatchBlockedByMediaKey = 'autoMatchBlockedByMedia';
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  const DanmakuSavedSourceStore();

  ValueListenable<int> get changes => _revision;

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    _notifyChanged();
  }

  Future<Map<String, dynamic>> _loadPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey) ?? '';
    if (raw.trim().isEmpty) {
      return <String, dynamic>{
        'sources': <dynamic>[],
        'activeByMedia': <String, dynamic>{},
        _autoMatchBlockedByMediaKey: <String, dynamic>{},
      };
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, dynamic>{
        'sources': <dynamic>[],
        'activeByMedia': <String, dynamic>{},
        _autoMatchBlockedByMediaKey: <String, dynamic>{},
      };
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _savePayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(payload));
  }

  void _notifyChanged() {
    _revision.value++;
  }
}
