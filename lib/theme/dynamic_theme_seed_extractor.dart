import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _persistentCacheVersion = 'dyn_seed_v1';
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

    final future = _extractUncached(
      imageUrl: imageUrl,
      token: token,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    ).then((seed) {
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
        NetworkImage(
          imageUrl,
          headers: token.trim().isEmpty
              ? const <String, String>{}
              : <String, String>{
                  'Authorization': token,
                  'Trim-MC-token': token,
                },
        ),
        maximumColorCount: 16,
        size: const Size(220, 140),
      );

      final backgroundCandidate = _firstAccepted(<Color?>[
        palette.darkVibrantColor?.color,
        palette.vibrantColor?.color,
        palette.dominantColor?.color,
        palette.mutedColor?.color,
      ]);
      final accentCandidate = _firstAccepted(<Color?>[
        palette.vibrantColor?.color,
        palette.darkVibrantColor?.color,
        palette.lightVibrantColor?.color,
        palette.dominantColor?.color,
        palette.mutedColor?.color,
      ]);

      // When all swatches are filtered (dark/gray/bright images), fall back
      // to the dominant color without filtering so every image gets a theme.
      final fallback = _lastResortCandidate(palette);
      final baseCandidate = backgroundCandidate ?? accentCandidate ?? fallback;
      final actionCandidate = accentCandidate ?? backgroundCandidate ?? fallback;
      if (baseCandidate == null || actionCandidate == null) {
        return null;
      }
      final preferLightSurface = baseCandidate.lightness >= 0.62;

      // When both candidates resolve to the same swatch, apply a hue offset
      // to accent/selection/link seeds so the theme has visual depth.
      final candidatesAreSame = identical(baseCandidate, actionCandidate) ||
          baseCandidate.toColor().toARGB32() == actionCandidate.toColor().toARGB32();
      final accentSource = candidatesAreSame
          ? _shiftHueHsl(actionCandidate, 30)
          : actionCandidate;

      return DynamicThemeSeed(
        backgroundSeed: _backgroundSeedForHsl(
          baseCandidate,
          preferLightSurface: preferLightSurface,
        ),
        accentSeed: _accentSeedForHsl(accentSource),
        selectionSeed: _selectionSeedForHsl(accentSource),
        linkSeed: _linkSeedForHsl(candidatesAreSame
            ? _shiftHueHsl(actionCandidate, -20)
            : actionCandidate),
        preferLightSurface: preferLightSurface,
      );
    } catch (_) {
      return null;
    }
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

  static HSLColor? _firstAccepted(List<Color?> colors) {
    for (final color in colors) {
      final normalized = _normalizeCandidate(color);
      if (normalized != null) return normalized;
    }
    return null;
  }

  /// Fallback when all palette swatches are filtered — use the dominant color
  /// as-is so that every image (dark, gray, bright) still gets a dynamic theme.
  static HSLColor? _lastResortCandidate(PaletteGenerator palette) {
    final color = palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        palette.mutedColor?.color;
    if (color == null) return null;
    return HSLColor.fromColor(color);
  }

  static HSLColor? _normalizeCandidate(Color? color) {
    if (color == null) return null;
    var hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.08) return null;
    if (hsl.lightness < 0.06 || hsl.lightness > 0.90) return null;

    final hue = hsl.hue;
    final isHarshRed = hue <= 10 || hue >= 350;
    if (isHarshRed && hsl.saturation > 0.72) {
      hsl = hsl.withSaturation(0.72);
    }

    return hsl;
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
    return hsl
        .withSaturation((hsl.saturation * 0.84).clamp(0.18, 0.54))
        .withLightness(((hsl.lightness * 0.58) + 0.02).clamp(0.18, 0.36))
        .toColor();
  }

  static Color _accentSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.22, 0.58))
        .withLightness(hsl.lightness.clamp(0.34, 0.56))
        .toColor();
  }

  static Color _selectionSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.24, 0.62))
        .withLightness((hsl.lightness - 0.02).clamp(0.30, 0.52))
        .toColor();
  }

  static Color _linkSeedForHsl(HSLColor hsl) {
    return hsl
        .withSaturation(hsl.saturation.clamp(0.20, 0.54))
        .withLightness((hsl.lightness + 0.08).clamp(0.42, 0.64))
        .toColor();
  }

  static HSLColor _shiftHueHsl(HSLColor hsl, double degrees) {
    return hsl.withHue((hsl.hue + degrees) % 360);
  }
}
