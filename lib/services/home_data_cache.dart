import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../models/media_item.dart';
import '../models/media_library_item.dart';

// compute() 入口（顶层函数）：把大 JSON 的编/解码放进 isolate，不阻塞 UI 线程。
String _encodeHomeJson(Map<String, dynamic> payload) => jsonEncode(payload);
Map<String, dynamic>? _decodeHomeJson(String raw) {
  final value = jsonDecode(raw);
  return value is Map<String, dynamic> ? value : null;
}

/// Persistent cache for the home page data so subsequent loads show content
/// immediately while fresh data is fetched in the background.
///
/// 实现说明：缓存以**独立 JSON 文件**存储（不再塞进 SharedPreferences）。
/// 旧实现把整页大 JSON 写进 prefs，导致 app 内**任意** SharedPreferences.getInstance()
/// 都要把整个 prefs map 做 UTF8 解码（实测 533ms 卡死 UI 线程，播放期间撞上即弹幕卡顿）。
/// 现改为文件存储 + isolate(compute) 编解码：彻底移出 prefs、且不占 UI 线程。
class HomeDataCache {
  static const String _fileName = 'home_data_cache.json';

  // 旧版本残留在 SharedPreferences 里的大 blob，启动后一次性清掉，消除 prefs 膨胀。
  static const List<String> _legacyPrefsKeys = <String>[
    'home_cache_categories',
    'home_cache_items',
    'home_cache_summary',
    'home_cache_continue',
    'home_cache_cached_at',
  ];

  HomeDataCache._();

  static Future<String>? _pathFuture;
  static Future<String> _filePath() {
    return _pathFuture ??= () async {
      final dir = await getDatabasesPath();
      return '$dir/$_fileName';
    }();
  }

  /// Save a complete home data snapshot.
  static Future<void> save({
    required List<MediaItem> categories,
    required Map<String, List<MediaLibraryItem>> itemsByCategory,
    required Map<String, dynamic> mediaSummary,
    required List<MediaLibraryItem> continueWatching,
  }) async {
    try {
      final payload = <String, dynamic>{
        'categories': categories.map((c) => c.toJson()).toList(),
        'items': itemsByCategory.map(
          (k, v) => MapEntry(k, v.map((i) => i.toJson()).toList()),
        ),
        'summary': mediaSummary,
        'continue': continueWatching.map((i) => i.toJson()).toList(),
        'cachedAt': DateTime.now().toIso8601String(),
      };
      final json = await compute(_encodeHomeJson, payload);
      final path = await _filePath();
      // 先写临时文件再原子 rename，避免半写损坏。
      final tmp = File('$path.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(path);
      unawaited(_purgeLegacyPrefs());
    } catch (error) {
      debugPrint('[HOME_CACHE] save failed: $error');
    }
  }

  /// Returns cached data, or null if nothing is cached or malformed.
  static Future<HomeDataSnapshot?> load() async {
    unawaited(_purgeLegacyPrefs());
    try {
      final path = await _filePath();
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = await compute(_decodeHomeJson, raw);
      if (decoded == null) return null;

      final catsList = ((decoded['categories'] as List?) ?? const <dynamic>[])
          .map((d) => MediaItem.fromJson(d as Map<String, dynamic>))
          .toList(growable: false);
      final itemsRaw = decoded['items'];
      if (catsList.isEmpty && itemsRaw == null) return null;

      final itemsMap = <String, List<MediaLibraryItem>>{};
      final itemsDecoded =
          (itemsRaw as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      for (final entry in itemsDecoded.entries) {
        itemsMap[entry.key] = ((entry.value as List?) ?? const <dynamic>[])
            .map((d) => MediaLibraryItem.fromJson(d as Map<String, dynamic>))
            .toList(growable: false);
      }

      final summary =
          (decoded['summary'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final continueList = ((decoded['continue'] as List?) ?? const <dynamic>[])
          .map((d) => MediaLibraryItem.fromJson(d as Map<String, dynamic>))
          .toList(growable: false);

      final cachedAt =
          DateTime.tryParse(decoded['cachedAt'] as String? ?? '') ??
          DateTime.now();

      return HomeDataSnapshot(
        categories: catsList,
        itemsByCategory: itemsMap,
        mediaSummary: summary,
        continueWatching: continueList,
        cachedAt: cachedAt,
      );
    } catch (error) {
      debugPrint('[HOME_CACHE] load failed: $error');
      await clear();
      return null;
    }
  }

  /// Remove all cached data for this key scope.
  static Future<void> clear() async {
    try {
      final path = await _filePath();
      final file = File(path);
      if (await file.exists()) await file.delete();
      final tmp = File('$path.tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (error) {
      debugPrint('[HOME_CACHE] clear failed: $error');
    }
    unawaited(_purgeLegacyPrefs());
  }

  static bool _legacyPurged = false;
  static Future<void> _purgeLegacyPrefs() async {
    if (_legacyPurged) return;
    _legacyPurged = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _legacyPrefsKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {
      _legacyPurged = false;
    }
  }
}

/// Immutable snapshot returned by [HomeDataCache.load].
class HomeDataSnapshot {
  final List<MediaItem> categories;
  final Map<String, List<MediaLibraryItem>> itemsByCategory;
  final Map<String, dynamic> mediaSummary;
  final List<MediaLibraryItem> continueWatching;
  final DateTime cachedAt;

  const HomeDataSnapshot({
    required this.categories,
    required this.itemsByCategory,
    required this.mediaSummary,
    required this.continueWatching,
    required this.cachedAt,
  });

  bool get isEmpty => categories.isEmpty;

  /// Compare two category item lists for equality.
  static bool _itemsEqual(List<MediaLibraryItem> a, List<MediaLibraryItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].guid != b[i].guid || a[i].ts != b[i].ts) return false;
    }
    return true;
  }

  /// Whether [other] represents the same visible data.
  bool isSameAs(HomeDataSnapshot other) {
    if (categories.length != other.categories.length) return false;
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].id != other.categories[i].id) return false;
      final aItems = itemsByCategory[categories[i].id];
      final bItems = other.itemsByCategory[other.categories[i].id];
      if (aItems == null && bItems == null) continue;
      if (aItems == null || bItems == null) return false;
      if (!_itemsEqual(aItems, bItems)) return false;
    }
    return true;
  }
}
