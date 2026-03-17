import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';
import 'media_locale_text.dart';

class MediaLocaleStore {
  MediaLocaleStore._();

  static final Map<String, Map<String, dynamic>> _cache =
      <String, Map<String, dynamic>>{};
  static final Map<String, Future<Map<String, dynamic>>> _pending =
      <String, Future<Map<String, dynamic>>>{};

  static Future<Map<String, dynamic>> load(
    NasProvider provider, {
    String locale = 'zh-CN',
    bool forceRefresh = false,
  }) {
    final key = _cacheKey(provider, locale);
    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null && cached.isNotEmpty) {
        return Future<Map<String, dynamic>>.value(cached);
      }
      final inflight = _pending[key];
      if (inflight != null) return inflight;
    }

    final future = FeiniuApi(provider).getMediaLocaleMap(locale: locale).then((
      map,
    ) {
      if (map.isNotEmpty) {
        _cache[key] = map;
      }
      return map;
    }).whenComplete(() {
      _pending.remove(key);
    });

    _pending[key] = future;
    return future;
  }

  static String text(
    Map<String, dynamic>? localeMap,
    String path, {
    required String fallback,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleText.text(
      localeMap ?? const <String, dynamic>{},
      path,
      fallback: fallback,
      params: params,
    );
  }

  static Future<String> loadText(
    NasProvider provider,
    String path, {
    String locale = 'zh-CN',
    required String fallback,
    Map<String, Object?> params = const <String, Object?>{},
    bool forceRefresh = false,
  }) async {
    final localeMap = await load(
      provider,
      locale: locale,
      forceRefresh: forceRefresh,
    );
    return text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  static void clear({
    String? baseUrl,
    String? token,
    String? locale,
  }) {
    if (baseUrl == null && token == null && locale == null) {
      _cache.clear();
      _pending.clear();
      return;
    }
    final keys = _cache.keys.where((key) {
      if (baseUrl != null && !key.contains(baseUrl)) return false;
      if (token != null && !key.contains(token)) return false;
      if (locale != null && !key.endsWith('|$locale')) return false;
      return true;
    }).toList();
    for (final key in keys) {
      _cache.remove(key);
      _pending.remove(key);
    }
  }

  static String _cacheKey(NasProvider provider, String locale) {
    return '${provider.baseUrl}|${provider.token}|$locale';
  }
}
