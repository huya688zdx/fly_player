import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/nas_image_headers.dart';
import '../utils/swallowed_error_logger.dart';

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
  // v3：真莫奈管线（Celebi 量化 + CAM16 Score），seed 为 Score 排名原色不再 HSL clamp；
  // 旧 v2 缓存按自制 HSL 评分产出，需失效。
  static const String _persistentCacheVersion = 'dyn_seed_v3';
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

  // 真莫奈管线：图像缩至 ≤112×112 → Celebi 量化 128 色（Wu+WSMeans，Lab 空间）→
  // CAM16 Score 评分排名（Android 12 壁纸取色原版算法，material_color_utilities 官方实现）。
  // Score 第一名即 Monet source color，直接作为 accent/background seed（不做 HSL clamp，
  // 色调调和交给下游 ColorScheme.fromSeed 的 HCT 音调映射）；selection/link 取 Score
  // 排名第 2/3 色（互异色相由 Score 内置的 hue 分散逻辑保证），不足时退回第一名。
  static Future<DynamicThemeSeed?> _extractUncached({
    required String imageUrl,
    required String token,
  }) async {
    if (imageUrl.trim().isEmpty) {
      return null;
    }

    try {
      Int32List? pixels;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        pixels = await _samplePixelsOnAndroid(imageUrl: imageUrl, token: token);
      }
      pixels ??= await _pixelsFromProvider(
        ResizeImage(
          NetworkImage(
            imageUrl,
            headers: nasImageHeaders(token, url: imageUrl),
          ),
          width: _monetMaxDimension,
          height: _monetMaxDimension,
          policy: ResizeImagePolicy.fit,
        ),
      );
      if (pixels == null || pixels.isEmpty) {
        return null;
      }
      final encoded = await compute(_monetSeedsFromPixels, pixels);
      if (encoded == null) {
        return null;
      }
      return DynamicThemeSeed(
        backgroundSeed: Color(encoded[1] & 0xFFFFFFFF),
        accentSeed: Color(encoded[2] & 0xFFFFFFFF),
        selectionSeed: Color(encoded[3] & 0xFFFFFFFF),
        linkSeed: Color(encoded[4] & 0xFFFFFFFF),
        preferLightSurface: encoded[0] != 0,
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

  static const int _monetMaxDimension = 112;
  static const int _monetQuantizeColors = 128;

  /// isolate 入口：像素 → Celebi 量化 → Score 排名。
  /// 返回 [preferLight, background, accent, selection, link]，无有效像素时返回 null。
  static Future<List<int>?> _monetSeedsFromPixels(Int32List rawPixels) async {
    // Monet 只吃不透明像素（海报圆角/信封边的透明区不参与量化）。
    final opaque = <int>[];
    for (final pixel in rawPixels) {
      if ((pixel >> 24) & 0xFF == 0xFF) {
        opaque.add(pixel);
      }
    }
    if (opaque.isEmpty) {
      return null;
    }

    final quantized = await QuantizerCelebi().quantize(
      opaque,
      _monetQuantizeColors,
    );
    final colorToCount = quantized.colorToCount;
    if (colorToCount.isEmpty) {
      return null;
    }

    // 人口加权亮度判定亮/暗表面（与旧版一致，允许亮色海报出亮主题）。
    var totalPopulation = 0.0;
    var weightedLuminance = 0.0;
    colorToCount.forEach((argb, count) {
      final r = ((argb >> 16) & 0xFF) / 255.0;
      final g = ((argb >> 8) & 0xFF) / 255.0;
      final b = (argb & 0xFF) / 255.0;
      weightedLuminance += (0.2126 * r + 0.7152 * g + 0.0722 * b) * count;
      totalPopulation += count;
    });
    final preferLightSurface =
        totalPopulation > 0 && (weightedLuminance / totalPopulation) >= 0.60;

    // Score 会滤掉低彩度/低占比色并按色相分散排名；全灰图像时回退 Google Blue，
    // 与 Android 原生莫奈的兜底行为一致。
    final ranked = Score.score(colorToCount);
    final source = ranked.first;
    final selection = ranked.length > 1 ? ranked[1] : source;
    final link = ranked.length > 2
        ? ranked[2]
        : (ranked.length > 1 ? ranked[1] : source);
    return <int>[preferLightSurface ? 1 : 0, source, source, selection, link];
  }

  /// 解出 ImageProvider 的 ARGB 像素（已由 ResizeImage 缩到莫奈采样尺寸）。
  static Future<Int32List?> _pixelsFromProvider(ImageProvider provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(info);
        } else {
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace ?? StackTrace.current);
        }
      },
    );
    stream.addListener(listener);
    final info = await completer.future;
    try {
      final byteData = await info.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (byteData == null) {
        return null;
      }
      final rgba = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final count = rgba.length ~/ 4;
      final pixels = Int32List(count);
      for (var i = 0; i < count; i++) {
        final offset = i * 4;
        pixels[i] =
            (rgba[offset + 3] << 24) |
            (rgba[offset] << 16) |
            (rgba[offset + 1] << 8) |
            rgba[offset + 2];
      }
      return pixels;
    } finally {
      info.dispose();
      // 采样图不该占用 Flutter 图片缓存位（页面展示走的是原尺寸 URL 键）。
      unawaited(provider.evict());
    }
  }

  static Future<Int32List?> _samplePixelsOnAndroid({
    required String imageUrl,
    required String token,
  }) async {
    try {
      final raw = await _themeSamplerChannel.invokeMapMethod<String, dynamic>(
        'sampleImagePixels',
        <String, dynamic>{'imageUrl': imageUrl, 'token': token},
      );
      final pixels = raw?['pixels'];
      if (pixels is Int32List && pixels.isNotEmpty) {
        return pixels;
      }
      return null;
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
      // seed 常在进场转场内解析入库，debounce 到点仍可能撞转场/动画帧；
      // 全量 jsonEncode + prefs 写入挂到调度器空闲位执行（帧忙时自动顺延；
      // 退出前的 flushPendingWrites 仍走直写兜底，两边幂等）。
      SchedulerBinding.instance.scheduleTask<void>(() {
        unawaited(_persistSeedCache());
      }, Priority.idle);
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
}
