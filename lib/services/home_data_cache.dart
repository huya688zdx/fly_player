import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/media_library_item.dart';

/// Persistent cache for the home page data so subsequent loads show content
/// immediately while fresh data is fetched in the background.
class HomeDataCache {
  static const String _categoriesKey = 'home_cache_categories';
  static const String _itemsByCategoryKey = 'home_cache_items';
  static const String _summaryKey = 'home_cache_summary';
  static const String _continueWatchingKey = 'home_cache_continue';
  static const String _cachedAtKey = 'home_cache_cached_at';

  HomeDataCache._();

  /// Save a complete home data snapshot.
  static Future<void> save({
    required List<MediaItem> categories,
    required Map<String, List<MediaLibraryItem>> itemsByCategory,
    required Map<String, dynamic> mediaSummary,
    required List<MediaLibraryItem> continueWatching,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<void>>[
      prefs.setString(
        _categoriesKey,
        jsonEncode(categories.map((c) => c.toJson()).toList()),
      ),
      prefs.setString(
        _itemsByCategoryKey,
        jsonEncode(
          itemsByCategory.map(
            (k, v) => MapEntry(k, v.map((i) => i.toJson()).toList()),
          ),
        ),
      ),
      prefs.setString(_summaryKey, jsonEncode(mediaSummary)),
      prefs.setString(
        _continueWatchingKey,
        jsonEncode(continueWatching.map((i) => i.toJson()).toList()),
      ),
      prefs.setString(_cachedAtKey, DateTime.now().toIso8601String()),
    ]);
  }

  /// Returns cached data, or null if nothing is cached or malformed.
  static Future<HomeDataSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final catsRaw = prefs.getString(_categoriesKey);
    final itemsRaw = prefs.getString(_itemsByCategoryKey);
    if (catsRaw == null || itemsRaw == null) return null;
    final summaryRaw = prefs.getString(_summaryKey);
    final continueRaw = prefs.getString(_continueWatchingKey);
    final cachedAtRaw = prefs.getString(_cachedAtKey);

    try {
      final catsList = (jsonDecode(catsRaw) as List)
          .map((d) => MediaItem.fromJson(d as Map<String, dynamic>))
          .toList(growable: false);

      final itemsMap = <String, List<MediaLibraryItem>>{};
      final itemsDecoded = jsonDecode(itemsRaw) as Map<String, dynamic>;
      for (final entry in itemsDecoded.entries) {
        itemsMap[entry.key] = (entry.value as List)
            .map(
              (d) => MediaLibraryItem.fromJson(d as Map<String, dynamic>),
            )
            .toList(growable: false);
      }

      final summary = summaryRaw != null
          ? jsonDecode(summaryRaw) as Map<String, dynamic>
          : <String, dynamic>{};

      final continueList = continueRaw != null
          ? (jsonDecode(continueRaw) as List)
              .map(
                (d) => MediaLibraryItem.fromJson(d as Map<String, dynamic>),
              )
              .toList(growable: false)
          : <MediaLibraryItem>[];

      final cachedAt = cachedAtRaw != null
          ? DateTime.tryParse(cachedAtRaw)
          : null;

      return HomeDataSnapshot(
        categories: catsList,
        itemsByCategory: itemsMap,
        mediaSummary: summary,
        continueWatching: continueList,
        cachedAt: cachedAt ?? DateTime.now(),
      );
    } catch (error) {
      debugPrint('[HOME_CACHE] load failed: $error');
      await clear();
      return null;
    }
  }

  /// Remove all cached data for this key scope.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<void>>[
      prefs.remove(_categoriesKey),
      prefs.remove(_itemsByCategoryKey),
      prefs.remove(_summaryKey),
      prefs.remove(_continueWatchingKey),
      prefs.remove(_cachedAtKey),
    ]);
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
  static bool _itemsEqual(
    List<MediaLibraryItem> a,
    List<MediaLibraryItem> b,
  ) {
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
