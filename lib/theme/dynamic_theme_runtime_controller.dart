import 'app_theme.dart';
import 'dynamic_theme_mapper.dart';
import 'dynamic_theme_seed_extractor.dart';

class DynamicThemeRuntimeController {
  DynamicThemeRuntimeController._();

  static const String _cacheVersion = 'dyn_v4';
  static const int _maxSeedCacheEntries = 64;

  static final DynamicThemeRuntimeController instance =
      DynamicThemeRuntimeController._();

  final Map<String, DynamicThemeSeed> _seedCache = <String, DynamicThemeSeed>{};
  final Map<String, Future<DynamicThemeSeed?>> _inflight =
      <String, Future<DynamicThemeSeed?>>{};

  DynamicThemeSeed? cachedSeedFor(String key) {
    final normalizedKey = _normalizedKey(key);
    if (normalizedKey.isEmpty) return null;
    final cached = _seedCache.remove(normalizedKey);
    if (cached != null) {
      _seedCache[normalizedKey] = cached;
    }
    return cached;
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
    final cached = _seedCache[normalizedKey];
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
            _seedCache.remove(normalizedKey);
            _seedCache[normalizedKey] = seed;
            _trimSeedCache();
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

  String _normalizedKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    return '$_cacheVersion:$trimmed';
  }

  void _trimSeedCache() {
    while (_seedCache.length > _maxSeedCacheEntries) {
      final eldestKey = _seedCache.keys.first;
      _seedCache.remove(eldestKey);
    }
  }
}
