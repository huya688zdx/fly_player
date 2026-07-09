import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/nas_image_headers.dart';
import '../utils/swallowed_error_logger.dart';

class _ScoredSwatch {
  final Color color;
  final HSLColor hsl;
  final double score;

  const _ScoredSwatch({
    required this.color,
    required this.hsl,
    required this.score,
  });
}

@immutable
class DynamicThemeSeed {
  final Color backgroundSeed;
  final Color accentSeed;
  final Color selectionSeed;
  final Color linkSeed;
  final bool preferLightSurface;

  const DynamicThemeSeed({
    required this.backgroundSeed,
    required this.accentSeed,
    required this.selectionSeed,
    required this.linkSeed,
    required this.preferLightSurface,
  });
}

class DynamicThemeSeedExtractor {
  const DynamicThemeSeedExtractor._();

  static const int _maxSeedCacheEntries = 256;
  // v2：Monet 式评分 + 互异色相分配 + 柔和 clamp（旧 v1 缓存按 vibrant/muted+hue-shift，需失效）。
  static const String _persistentCacheVersion = 'dyn_seed_v2';
  static const String _persistentCachePrefsKey = 'dynamic_theme_seed_cache_v1';
  static const Duration _persistDebounceDelay = Duration(milliseconds: 120);
  static const MethodChannel _themeSamplerChannel = MethodChannel(
    'fly_player/theme_sampler',
  );
  static final LinkedHashMap<String, DynamicThemeSeed> _seedCache =
      LinkedHashMap<String, DynamicThemeSeed>();
  static final Map<String, Future<DynamicThemeSeed?>> _inflight =
      <String, Future<DynamicThemeSeed?>>{};
  static Future<void>? _persistentCacheLoadFuture;
  static Timer? _persistTimer;
  static bool _persistentCacheLoaded = false;
  static bool _persistScheduled = false;

  static DynamicThemeSeed? cachedSeedForImageUrl(String imageUrl) {
    final normalizedImageKey = normalizeImageIdentity(imageUrl);
    if (normalizedImageKey.isEmpty) {
      return null;
    }
    _primePersistentCacheLoad();
    return _touchSeedCache(normalizedImageKey);
  }

  static Future<void> warmUpPersistentCache() async {
    await _ensurePersistentCacheLoaded();
  }

  static Future<DynamicThemeSeed?> restoreCachedSeedForImageUrl(
    String imageUrl,
  ) async {
    final normalizedImageKey = normalizeImageIdentity(imageUrl);
    if (normalizedImageKey.isEmpty) {
      return null;
    }
    final cached = _touchSeedCache(normalizedImageKey);
    if (cached != null) {
      return cached;
    }
    await _ensurePersistentCacheLoaded();
    return _touchSeedCache(normalizedImageKey);
  }

  static int estimatePersistentCacheBytes(SharedPreferences prefs) {
    final raw = prefs.getString(_persistentCachePrefsKey);
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    return utf8.encode(_persistentCachePrefsKey).length +
        utf8.encode(raw).length;
  }

  static int countPersistentCacheEntries(SharedPreferences prefs) {
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

  static Future<void> clearCache({SharedPreferences? prefs}) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistScheduled = false;
    _seedCache.clear();
    _inflight.clear();
    _persistentCacheLoaded = true;
    _persistentCacheLoadFuture = null;
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    await targetPrefs.remove(_persistentCachePrefsKey);
  }

  static Future<void> flushPendingWrites({SharedPreferences? prefs}) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (!_persistScheduled) {
      return;
    }
    await _persistSeedCache(prefs: prefs);
  }

  static String normalizeImageIdentity(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      final uri = Uri.parse(trimmed);
      if (!uri.hasScheme || uri.host.trim().isEmpty) {
        return trimmed;
      }
      final filteredQuery = <String, String>{};
      final entries = uri.queryParameters.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        if (entry.key == 'w') {
          continue;
        }
        final value = entry.value.trim();
        if (value.isEmpty) {
          continue;
        }
        filteredQuery[entry.key] = value;
      }
      return uri
          .replace(
            queryParameters: filteredQuery.isEmpty ? null : filteredQuery,
            fragment: null,
          )
          .toString();
    } catch (_) {
      return trimmed;
    }
  }

  static Future<DynamicThemeSeed?> extract({
    required String imageUrl,
    required String token,
  }) async {
    final normalizedImageKey = normalizeImageIdentity(imageUrl);
    if (normalizedImageKey.isNotEmpty) {
      await _ensurePersistentCacheLoaded();
      final cached = _touchSeedCache(normalizedImageKey);
      if (cached != null) {
        return cached;
      }
      final pending = _inflight[normalizedImageKey];
      if (pending != null) {
        return pending;
      }
    }

    final future = _extractUncached(imageUrl: imageUrl, token: token)
        .timeout(const Duration(seconds: 10), onTimeout: () => null)
        .then((seed) {
          if (normalizedImageKey.isNotEmpty) {
            _inflight.remove(normalizedImageKey);
            if (seed != null) {
              _storeSeedCache(normalizedImageKey, seed);
            }
          }
          return seed;
        });
    if (normalizedImageKey.isNotEmpty) {
      _inflight[normalizedImageKey] = future;
    }
    return future;
  }

  static Future<DynamicThemeSeed?> _extractUncached({
    required String imageUrl,
    required String token,
  }) async {
    if (imageUrl.trim().isEmpty) {
      return null;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final nativeSeed = await _extractOnAndroid(
          imageUrl: imageUrl,
          token: token,
        );
        if (nativeSeed != null) return nativeSeed;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl, headers: nasImageHeaders(token, url: imageUrl)),
        maximumColorCount: 24,
        size: const Size(220, 140),
      );

      // Monet 式取色（与原生 ThemeColorSampler 同算法）：对全部量化 swatch 评分（彩度×人口），
      // accent 取最高分；selection/link 取与已选色相距离够远的真实图像色，无第二色相则退回同
      // 色相不同明度（不再用人工 hue-shift）。4 seed 下游喂 ColorScheme.fromSeed（HCT）。
      final swatches = palette.paletteColors;
      if (swatches.isEmpty) return null;

      var totalPopulation = 0.0;
      var weightedLuminance = 0.0;
      final scored = <_ScoredSwatch>[];
      for (final pc in swatches) {
        final hsl = HSLColor.fromColor(pc.color);
        totalPopulation += pc.population;
        weightedLuminance += _relativeLuminance(pc.color) * pc.population;
        scored.add(
          _ScoredSwatch(
            color: pc.color,
            hsl: hsl,
            score: _chromaScore(hsl, pc.population),
          ),
        );
      }
      scored.sort((a, b) => b.score.compareTo(a.score));

      final preferLightSurface =
          totalPopulation > 0 && (weightedLuminance / totalPopulation) >= 0.60;

      final dominant = swatches
          .reduce((a, b) => a.population >= b.population ? a : b)
          .color;
      final colorful = scored
          .where((s) => s.hsl.saturation >= 0.12)
          .toList(growable: false);
      final accent =
          (colorful.isNotEmpty ? colorful.first : scored.first).color;
      final accentHue = HSLColor.fromColor(accent).hue;

      final selectionSwatch = _firstWhereOrNull(
        colorful,
        (s) => _hueDistance(s.hsl.hue, accentHue) >= _minDistinctHue,
      );
      final selectionHue = selectionSwatch?.hsl.hue ?? accentHue;
      final linkSwatch = _firstWhereOrNull(
        colorful,
        (s) =>
            _hueDistance(s.hsl.hue, accentHue) >= _minDistinctHue &&
            _hueDistance(s.hsl.hue, selectionHue) >= _minDistinctHue,
      );

      final selectionSource =
          selectionSwatch?.color ?? _tonalSibling(accent, -0.06);
      final linkSource = linkSwatch?.color ?? _tonalSibling(accent, 0.10);

      return DynamicThemeSeed(
        backgroundSeed: _backgroundSeedForHsl(
          HSLColor.fromColor(dominant),
          preferLightSurface: preferLightSurface,
        ),
        accentSeed: _accentSeedForHsl(HSLColor.fromColor(accent)),
        selectionSeed: _selectionSeedForHsl(
          HSLColor.fromColor(selectionSource),
        ),
        linkSeed: _linkSeedForHsl(HSLColor.fromColor(linkSource)),
        preferLightSurface: preferLightSurface,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'extract dynamic theme seed',
        id: normalizeImageIdentity(imageUrl),
        error: error,
        stackTrace: stackTrace,
        source: 'dynamic_theme_seed_extractor',
      );
      return null;
    }
  }

  static const double _minDistinctHue = 32;

  static double _chromaScore(HSLColor hsl, int population) {
    final toneFalloff = 1.0 - ((hsl.lightness - 0.5).abs() * 0.7);
    final chroma = hsl.saturation * toneFalloff;
    final popWeight = math.log(1.0 + population);
    final grayPenalty = hsl.saturation < 0.10 ? 0.12 : 1.0;
    final extremePenalty = (hsl.lightness < 0.06 || hsl.lightness > 0.94)
        ? 0.4
        : 1.0;
    return chroma * popWeight * grayPenalty * extremePenalty;
  }

  static double _relativeLuminance(Color color) {
    final r = ((color.toARGB32() >> 16) & 0xFF) / 255.0;
    final g = ((color.toARGB32() >> 8) & 0xFF) / 255.0;
    final b = (color.toARGB32() & 0xFF) / 255.0;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double _hueDistance(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  static Color _tonalSibling(Color color, double deltaLightness) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + deltaLightness).clamp(0.12, 0.88))
        .toColor();
  }

  static _ScoredSwatch? _firstWhereOrNull(
    List<_ScoredSwatch> list,
    bool Function(_ScoredSwatch) test,
  ) {
    for (final item in list) {
      if (test(item)) return item;
    }
    return null;
  }

  static DynamicThemeSeed? _touchSeedCache(String normalizedImageKey) {
    final cached = _seedCache.remove(normalizedImageKey);
    if (cached != null) {
      _seedCache[normalizedImageKey] = cached;
    }
    return cached;
  }

  static void _storeSeedCache(
    String normalizedImageKey,
    DynamicThemeSeed seed,
  ) {
    _seedCache.remove(normalizedImageKey);
    _seedCache[normalizedImageKey] = seed;
    while (_seedCache.length > _maxSeedCacheEntries) {
      _seedCache.remove(_seedCache.keys.first);
    }
    _schedulePersistentCacheWrite();
  }

  static void _primePersistentCacheLoad() {
    if (_persistentCacheLoaded || _persistentCacheLoadFuture != null) {
      return;
    }
    unawaited(_ensurePersistentCacheLoaded());
  }

  static Future<void> _ensurePersistentCacheLoaded() async {
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

  static Future<void> _loadPersistentCache() async {
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
      final version = decoded['version']?.toString() ?? '';
      if (version != _persistentCacheVersion) {
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
        _seedCache.remove(key);
        _seedCache[key] = seed;
      }
      while (_seedCache.length > _maxSeedCacheEntries) {
        _seedCache.remove(_seedCache.keys.first);
      }
    } catch (_) {
      // Ignore cache restore failures and fall back to live extraction.
    } finally {
      _persistentCacheLoaded = true;
      _persistentCacheLoadFuture = null;
    }
  }

  static void _schedulePersistentCacheWrite() {
    _persistScheduled = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounceDelay, () {
      _persistTimer = null;
      unawaited(_persistSeedCache());
    });
  }

  static Future<void> _persistSeedCache({SharedPreferences? prefs}) async {
    if (!_persistScheduled) {
      return;
    }
    _persistScheduled = false;
    try {
      final targetPrefs = prefs ?? await SharedPreferences.getInstance();
      final payload = <String, Object?>{
        'version': _persistentCacheVersion,
        'entries': _seedCache.entries
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
    } catch (_) {
      // Ignore cache persistence failures and keep runtime cache only.
    }
  }

  static Map<String, Object?> _seedToJson(DynamicThemeSeed seed) {
    return <String, Object?>{
      'backgroundSeed': seed.backgroundSeed.toARGB32(),
      'accentSeed': seed.accentSeed.toARGB32(),
      'selectionSeed': seed.selectionSeed.toARGB32(),
      'linkSeed': seed.linkSeed.toARGB32(),
      'preferLightSurface': seed.preferLightSurface,
    };
  }

  static DynamicThemeSeed? _seedFromJson(Map raw) {
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

  static Future<DynamicThemeSeed?> _extractOnAndroid({
    required String imageUrl,
    required String token,
  }) async {
    try {
      final raw = await _themeSamplerChannel.invokeMapMethod<String, dynamic>(
        'extractDynamicThemeSeed',
        <String, dynamic>{'imageUrl': imageUrl, 'token': token},
      );
      if (raw == null) return null;
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
    } catch (_) {
      return null;
    }
  }

  static Color _backgroundSeedForHsl(
    HSLColor hsl, {
    required bool preferLightSurface,
  }) {
    if (preferLightSurface) {
      return hsl
          .withSaturation((hsl.saturation * 0.42).clamp(0.08, 0.22))
          .withLightness((hsl.lightness * 0.92).clamp(0.74, 0.90))
          .toColor();
    }
    // 柔和：暗表面彩度上限收一档。
    return hsl
        .withSaturation((hsl.saturation * 0.80).clamp(0.16, 0.48))
        .withLightness(((hsl.lightness * 0.58) + 0.02).clamp(0.18, 0.36))
        .toColor();
  }

  // 柔和舒适：强调/选中/链接彩度上限整体收一档（与原生 ThemeColorSampler 对齐）。
  static Color _accentSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.20, 0.50))
        .withLightness(hsl.lightness.clamp(0.34, 0.56))
        .toColor();
  }

  static Color _selectionSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.22, 0.52))
        .withLightness((hsl.lightness - 0.02).clamp(0.30, 0.52))
        .toColor();
  }

  static Color _linkSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.48))
        .withLightness((hsl.lightness + 0.08).clamp(0.42, 0.64))
        .toColor();
  }
}
