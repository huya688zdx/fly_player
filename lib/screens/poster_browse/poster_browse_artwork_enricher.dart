import 'dart:collection';

import '../../media_backend/detail/media_detail.dart';
import '../../media_backend/detail/media_season_summary.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';

/// 海报浏览页按卡片稳定父级关系懒加载到的补全素材。
class PosterBrowseEnrichment {
  final MediaDetail? itemDetail;
  final MediaDetail? seriesDetail;
  final MediaSeasonSummary? season;
  final String resolvedSeriesId;
  final bool hasLookupFailure;

  const PosterBrowseEnrichment({
    this.itemDetail,
    this.seriesDetail,
    this.season,
    this.resolvedSeriesId = '',
    this.hasLookupFailure = false,
  });

  bool get isFailure =>
      hasLookupFailure ||
      (itemDetail == null && seriesDetail == null && season == null);
}

/// 海报浏览页素材懒补全器。
///
/// 缓存只以实例的 [sessionKey] 为边界，不跨会话共享；同 key 并发请求共享同一个
/// Future，避免焦点快速移动时重复打详情接口。
class PosterBrowseArtworkEnricher {
  PosterBrowseArtworkEnricher({
    required this.backend,
    required this.sessionKey,
    int maxEntries = 80,
    this.failureTtl = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : maxEntries = maxEntries < 0 ? 0 : maxEntries,
       _now = now ?? DateTime.now;

  final MediaBackend backend;
  final String sessionKey;
  final int maxEntries;
  final Duration failureTtl;
  final DateTime Function() _now;

  final LinkedHashMap<String, PosterBrowseEnrichment> _cache =
      LinkedHashMap<String, PosterBrowseEnrichment>();
  final Map<String, Future<PosterBrowseEnrichment>> _inFlight =
      <String, Future<PosterBrowseEnrichment>>{};
  final Map<String, _TemporaryFailure> _temporaryFailures =
      <String, _TemporaryFailure>{};
  int _clearGeneration = 0;

  /// 测试可见：当前成功 LRU 缓存条目数。
  int get cacheLength => _cache.length;

  Future<PosterBrowseEnrichment> enrich(MediaItemCard card) {
    final key = _cacheKey(card);
    final temporaryFailure = _temporaryFailures[key];
    if (temporaryFailure != null) {
      if (_now().isBefore(temporaryFailure.expiresAt)) {
        return Future<PosterBrowseEnrichment>.value(temporaryFailure.result);
      }
      _temporaryFailures.remove(key);
    }

    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future<PosterBrowseEnrichment>.value(cached);
    }

    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final requestGeneration = _clearGeneration;
    late final Future<PosterBrowseEnrichment> future;
    future = _load(card)
        .then((result) {
          final stillCurrent =
              requestGeneration == _clearGeneration &&
              identical(_inFlight[key], future);
          if (!stillCurrent) {
            return result;
          }
          if (result.isFailure) {
            _temporaryFailures[key] = _TemporaryFailure(
              result: result,
              expiresAt: _now().add(failureTtl),
            );
          } else {
            _temporaryFailures.remove(key);
            _cache[key] = result;
            _trimCache();
          }
          return result;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], future)) {
            _inFlight.remove(key);
          }
        });
    _inFlight[key] = future;
    return future;
  }

  Future<void> prefetchWindow(
    List<MediaItemCard> items,
    int center, {
    int radius = 2,
  }) async {
    final indices = windowIndices(
      center: center,
      length: items.length,
      radius: radius,
    );
    await Future.wait<void>(
      indices.map((index) async {
        try {
          await enrich(items[index]);
        } catch (_) {
          // 预取是旁路优化，单项失败不影响窗口内其他条目。
        }
      }),
    );
  }

  static List<int> windowIndices({
    required int center,
    required int length,
    int radius = 2,
  }) {
    if (length <= 0) {
      return const <int>[];
    }
    final indices = <int>[];
    final seen = <int>{};
    final safeRadius = radius.clamp(0, length);
    for (var offset = -safeRadius; offset <= safeRadius; offset += 1) {
      final index = _positiveModulo(center + offset, length);
      if (seen.add(index)) {
        indices.add(index);
      }
    }
    return indices;
  }

  void clear() {
    _clearGeneration += 1;
    _cache.clear();
    _inFlight.clear();
    _temporaryFailures.clear();
  }

  String _cacheKey(MediaItemCard card) => '$sessionKey|${card.id.trim()}';

  Future<PosterBrowseEnrichment> _load(MediaItemCard card) async {
    final itemDetailLookup = await _loadDetail(card.id);
    final detailSeriesId = itemDetailLookup.value?.seriesId.trim() ?? '';
    final seriesId = detailSeriesId.isNotEmpty
        ? detailSeriesId
        : card.seriesId.trim();
    final cardId = card.id.trim();
    final shouldLoadSeries = seriesId.isNotEmpty && seriesId != cardId;

    Future<_Lookup<MediaDetail>>? seriesDetailFuture;
    Future<_Lookup<List<MediaSeasonSummary>>>? seasonsFuture;
    if (shouldLoadSeries) {
      seriesDetailFuture = _loadDetail(seriesId);
      seasonsFuture = _loadSeasons(seriesId);
    }

    final seriesDetailLookup = seriesDetailFuture == null
        ? const _Lookup<MediaDetail>.empty()
        : await seriesDetailFuture;
    final seasonsLookup = seasonsFuture == null
        ? const _Lookup<List<MediaSeasonSummary>>.value(<MediaSeasonSummary>[])
        : await seasonsFuture;
    final season = _matchSeason(
      seasonsLookup.value ?? const <MediaSeasonSummary>[],
      card.seasonNumber,
    );
    final unresolvedEpisodeSeries =
        itemDetailLookup.value?.type.trim().toLowerCase() == 'episode' &&
        seriesId.isEmpty;

    return PosterBrowseEnrichment(
      itemDetail: itemDetailLookup.value,
      seriesDetail: seriesDetailLookup.value,
      season: season,
      resolvedSeriesId: seriesId,
      hasLookupFailure:
          itemDetailLookup.failed ||
          seriesDetailLookup.failed ||
          seasonsLookup.failed ||
          unresolvedEpisodeSeries,
    );
  }

  Future<_Lookup<MediaDetail>> _loadDetail(String itemId) async {
    try {
      return _Lookup<MediaDetail>.value(await backend.getItemDetail(itemId));
    } catch (_) {
      return const _Lookup<MediaDetail>.failed();
    }
  }

  Future<_Lookup<List<MediaSeasonSummary>>> _loadSeasons(
    String seriesId,
  ) async {
    try {
      return _Lookup<List<MediaSeasonSummary>>.value(
        await backend.getItemSeasons(seriesId),
      );
    } catch (_) {
      return const _Lookup<List<MediaSeasonSummary>>.failed();
    }
  }

  MediaSeasonSummary? _matchSeason(
    List<MediaSeasonSummary> seasons,
    int seasonNumber,
  ) {
    for (final season in seasons) {
      if (season.seasonNumber == seasonNumber) {
        return season;
      }
    }
    return null;
  }

  void _trimCache() {
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static int _positiveModulo(int value, int length) {
    final remainder = value % length;
    return remainder < 0 ? remainder + length : remainder;
  }
}

class _Lookup<T> {
  final T? value;
  final bool failed;

  const _Lookup.value(this.value) : failed = false;
  const _Lookup.empty() : value = null, failed = false;
  const _Lookup.failed() : value = null, failed = true;
}

class _TemporaryFailure {
  final PosterBrowseEnrichment result;
  final DateTime expiresAt;

  const _TemporaryFailure({required this.result, required this.expiresAt});
}
