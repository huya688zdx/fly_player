import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'dynamic_theme_mapper.dart';
import 'dynamic_theme_seed_extractor.dart';
import '../utils/swallowed_error_logger.dart';

class DynamicThemeRuntimeController {
  DynamicThemeRuntimeController._();

  // v6 / v2：配合 Monet 式取色升级（互异色相分配 + 柔和 clamp），让页级 seed 缓存失效重算。
  static const String _cacheVersion = 'dyn_v6';
  static const String _persistentCacheVersion = 'dyn_page_seed_v2';
  static const String _persistentCachePrefsKey =
      'dynamic_theme_page_seed_cache_v1';
  static const int _maxSeedCacheEntries = 256;
  static const Duration _persistDebounceDelay = Duration(milliseconds: 120);

  static final DynamicThemeRuntimeController instance =
      DynamicThemeRuntimeController._();

  final LinkedHashMap<String, DynamicThemeSeed> _pageSeedCache =
      LinkedHashMap<String, DynamicThemeSeed>();
  final Map<String, Future<DynamicThemeSeed?>> _inflight =
      <String, Future<DynamicThemeSeed?>>{};
  Future<void>? _persistentCacheLoadFuture;
  Timer? _persistTimer;
  bool _persistentCacheLoaded = false;
  bool _persistScheduled = false;

  DynamicThemeSeed? cachedSeedFor(String key, {String imageUrl = ''}) {
    final normalizedKey = _normalizedKey(key);
    final cached = normalizedKey.isEmpty
        ? null
        : _touchPageSeedCache(normalizedKey);
    if (cached != null) {
      return cached;
    }
    _primePersistentCacheLoad();
    final imageCached = DynamicThemeSeedExtractor.cachedSeedForImageUrl(
      imageUrl,
    );
    if (imageCached != null && normalizedKey.isNotEmpty) {
      _storePageSeedCache(normalizedKey, imageCached);
    }
    return imageCached;
  }

  Future<DynamicThemeSeed?> restoreCachedSeed({
    required String key,
    required String imageUrl,
  }) async {
    final normalizedKey = _normalizedKey(key);
    var cached = normalizedKey.isEmpty
        ? null
        : _touchPageSeedCache(normalizedKey);
    if (cached != null) {
      return cached;
    }
    await _ensurePersistentCacheLoaded();
    cached = normalizedKey.isEmpty ? null : _touchPageSeedCache(normalizedKey);
    if (cached != null) {
      return cached;
    }
    final imageCached =
        await DynamicThemeSeedExtractor.restoreCachedSeedForImageUrl(imageUrl);
    if (imageCached != null && normalizedKey.isNotEmpty) {
      _storePageSeedCache(normalizedKey, imageCached);
    }
    return imageCached;
  }

  Future<DynamicThemeSeed?> getOrResolve({
    required String key,
    required String imageUrl,
    required String token,
  }) {
    final normalizedKey = _normalizedKey(key);
    if (normalizedKey.isEmpty || imageUrl.trim().isEmpty) {
      return Future<DynamicThemeSeed?>.value(null);
    }
    final cached = cachedSeedFor(key, imageUrl: imageUrl);
    if (cached != null) {
      return Future<DynamicThemeSeed?>.value(cached);
    }
    final pending = _inflight[normalizedKey];
    if (pending != null) {
      return pending;
    }

    final future =
        DynamicThemeSeedExtractor.extract(
          imageUrl: imageUrl,
          token: token,
        ).then((seed) {
          if (seed != null) {
            _storePageSeedCache(normalizedKey, seed);
          }
          _inflight.remove(normalizedKey);
          return seed;
        });

    _inflight[normalizedKey] = future;
    return future;
  }

  AppThemeColors mapCachedOrNull({
    required String key,
    required AppThemeColors baseColors,
    required AppDynamicThemeIntensity intensity,
  }) {
    final seed = cachedSeedFor(key);
    if (seed == null) return baseColors;
    return DynamicThemeMapper.map(
      baseColors: baseColors,
      seed: seed,
      intensity: intensity,
    );
  }

  void primePageSeed({
    required String key,
    String sourceKey = '',
    String imageUrl = '',
    DynamicThemeSeed? seed,
  }) {
    final normalizedKey = _normalizedKey(key);
    if (normalizedKey.isEmpty) {
      return;
    }
    final resolvedSeed =
        seed ??
        (sourceKey.trim().isNotEmpty
            ? cachedSeedFor(sourceKey, imageUrl: imageUrl)
            : null) ??
        cachedSeedFor(key, imageUrl: imageUrl);
    if (resolvedSeed == null) {
      return;
    }
    _storePageSeedCache(normalizedKey, resolvedSeed);
  }

  Future<void> warmUpPersistentCache() async {
    await _ensurePersistentCacheLoaded();
  }

  int estimatePersistentCacheBytes(SharedPreferences prefs) {
    final raw = prefs.getString(_persistentCachePrefsKey);
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    return utf8.encode(_persistentCachePrefsKey).length +
        utf8.encode(raw).length;
  }

  int countPersistentCacheEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_persistentCachePrefsKey);
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return 0;
      }
      final entries = decoded['entries'];
      return entries is List ? entries.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCachedSeeds({SharedPreferences? prefs}) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistScheduled = false;
    _pageSeedCache.clear();
    _inflight.clear();
    _persistentCacheLoaded = true;
    _persistentCacheLoadFuture = null;
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    await targetPrefs.remove(_persistentCachePrefsKey);
  }

  String _normalizedKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    return '$_cacheVersion:$trimmed';
  }

  DynamicThemeSeed? _touchPageSeedCache(String normalizedKey) {
    final cached = _pageSeedCache.remove(normalizedKey);
    if (cached != null) {
      _pageSeedCache[normalizedKey] = cached;
    }
    return cached;
  }

  void _storePageSeedCache(String normalizedKey, DynamicThemeSeed seed) {
    _pageSeedCache.remove(normalizedKey);
    _pageSeedCache[normalizedKey] = seed;
    while (_pageSeedCache.length > _maxSeedCacheEntries) {
      final eldestKey = _pageSeedCache.keys.first;
      _pageSeedCache.remove(eldestKey);
    }
    _schedulePersistentCacheWrite();
  }

  void _primePersistentCacheLoad() {
    if (_persistentCacheLoaded || _persistentCacheLoadFuture != null) {
      return;
    }
    unawaited(_ensurePersistentCacheLoaded());
  }

  Future<void> _ensurePersistentCacheLoaded() async {
    if (_persistentCacheLoaded) {
      return;
    }
    final pending = _persistentCacheLoadFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _loadPersistentCache();
    _persistentCacheLoadFuture = future;
    await future;
  }

  Future<void> _loadPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentCachePrefsKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      if ((decoded['version'] ?? '').toString() != _persistentCacheVersion) {
        return;
      }
      final entries = decoded['entries'];
      if (entries is! List) {
        return;
      }
      for (final entry in entries) {
        if (entry is! Map) {
          continue;
        }
        final key = entry['key']?.toString().trim() ?? '';
        final seed = _seedFromJson(entry);
        if (key.isEmpty || seed == null) {
          continue;
        }
        _pageSeedCache.remove(key);
        _pageSeedCache[key] = seed;
      }
      while (_pageSeedCache.length > _maxSeedCacheEntries) {
        _pageSeedCache.remove(_pageSeedCache.keys.first);
      }
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'restore dynamic theme runtime cache',
        error: error,
        stackTrace: stackTrace,
        source: 'dynamic_theme_runtime_controller',
      );
    } finally {
      _persistentCacheLoaded = true;
      _persistentCacheLoadFuture = null;
    }
  }

  void _schedulePersistentCacheWrite() {
    _persistScheduled = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounceDelay, () {
      _persistTimer = null;
      unawaited(_persistSeedCache());
    });
  }

  Future<void> _persistSeedCache({SharedPreferences? prefs}) async {
    if (!_persistScheduled) {
      return;
    }
    _persistScheduled = false;
    try {
      final targetPrefs = prefs ?? await SharedPreferences.getInstance();
      final payload = <String, Object?>{
        'version': _persistentCacheVersion,
        'entries': _pageSeedCache.entries
            .map(
              (entry) => <String, Object?>{
                'key': entry.key,
                ..._seedToJson(entry.value),
              },
            )
            .toList(growable: false),
      };
      await targetPrefs.setString(
        _persistentCachePrefsKey,
        jsonEncode(payload),
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'persist dynamic theme runtime cache',
        error: error,
        stackTrace: stackTrace,
        source: 'dynamic_theme_runtime_controller',
      );
    }
  }

  Map<String, Object?> _seedToJson(DynamicThemeSeed seed) {
    return <String, Object?>{
      'backgroundSeed': seed.backgroundSeed.toARGB32(),
      'accentSeed': seed.accentSeed.toARGB32(),
      'selectionSeed': seed.selectionSeed.toARGB32(),
      'linkSeed': seed.linkSeed.toARGB32(),
      'preferLightSurface': seed.preferLightSurface,
    };
  }

  DynamicThemeSeed? _seedFromJson(Map raw) {
    final backgroundValue = raw['backgroundSeed'];
    final accentValue = raw['accentSeed'];
    final selectionValue = raw['selectionSeed'];
    final linkValue = raw['linkSeed'];
    if (backgroundValue is! int ||
        accentValue is! int ||
        selectionValue is! int ||
        linkValue is! int) {
      return null;
    }
    return DynamicThemeSeed(
      backgroundSeed: Color(backgroundValue & 0xFFFFFFFF),
      accentSeed: Color(accentValue & 0xFFFFFFFF),
      selectionSeed: Color(selectionValue & 0xFFFFFFFF),
      linkSeed: Color(linkValue & 0xFFFFFFFF),
      preferLightSurface: (raw['preferLightSurface'] as bool?) ?? false,
    );
  }
}
