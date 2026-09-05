import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/detail/media_source_info.dart';
import 'package:fly_player/media_backend/detail/media_source_version.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_playback_resolution.dart';
import 'package:fly_player/media_backend/playback/media_playback_source_bridge.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_artwork_enricher.dart';

void main() {
  MediaItemCard card({
    required String id,
    String title = '标题',
    String type = 'Movie',
    String seriesId = '',
    int seasonNumber = 0,
  }) {
    return MediaItemCard(
      id: id,
      title: title,
      type: type,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      primaryImage: const MediaImageRef(url: 'primary'),
    );
  }

  MediaDetail detail(String id, {String type = 'Movie', String seriesId = ''}) {
    return MediaDetail(
      id: id,
      type: type,
      seriesId: seriesId,
      title: '详情 $id',
      primaryImage: MediaImageRef(url: 'detail-$id'),
    );
  }

  MediaSeasonSummary season(String id, int number) {
    return MediaSeasonSummary(
      id: id,
      title: '第 $number 季',
      seasonNumber: number,
      primaryImage: MediaImageRef(url: 'season-$id'),
    );
  }

  test('episode 反查 item detail、series detail 和精确 season，且各只调用一次', () async {
    final itemDetail = detail('episode-1', type: 'Episode');
    final seriesDetail = detail('series-1', type: 'TV');
    final season2 = season('season-2', 2);
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        'episode-1': itemDetail,
        'series-1': seriesDetail,
      },
      seasons: <String, List<MediaSeasonSummary>>{
        'series-1': <MediaSeasonSummary>[season('season-1', 1), season2],
      },
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    final result = await enricher.enrich(
      card(
        id: 'episode-1',
        type: 'Episode',
        seriesId: ' series-1 ',
        seasonNumber: 2,
      ),
    );

    expect(result.itemDetail, same(itemDetail));
    expect(result.seriesDetail, same(seriesDetail));
    expect(result.season, same(season2));
    expect(backend.detailCalls['episode-1'], 1);
    expect(backend.detailCalls['series-1'], 1);
    expect(backend.seasonCalls['series-1'], 1);
  });

  test('item detail 的真实 seriesId 覆盖卡片错误祖先关系', () async {
    final itemDetail = detail(
      'episode-1',
      type: 'Episode',
      seriesId: 'series-1',
    );
    final seriesDetail = detail('series-1', type: 'TV');
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        'episode-1': itemDetail,
        'series-1': seriesDetail,
      },
      seasons: const <String, List<MediaSeasonSummary>>{'series-1': []},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    final result = await enricher.enrich(
      card(
        id: 'episode-1',
        type: 'Movie',
        seriesId: 'library-root',
        seasonNumber: 1,
      ),
    );

    expect(result.resolvedSeriesId, 'series-1');
    expect(result.seriesDetail, same(seriesDetail));
    expect(backend.detailCalls['library-root'], isNull);
    expect(backend.detailCalls['series-1'], 1);
    expect(backend.seasonCalls['series-1'], 1);
  });

  test('同 key 并发合并为同一个 Future 结果，底层只请求一次', () async {
    final completer = Completer<MediaDetail>();
    final backend = _FakeMediaBackend(
      detailCompleters: <String, Completer<MediaDetail>>{' item-1 ': completer},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    final futureA = enricher.enrich(card(id: ' item-1 '));
    final futureB = enricher.enrich(card(id: 'item-1'));
    expect(backend.detailCalls[' item-1 '], 1);

    completer.complete(detail('item-1'));
    final results = await Future.wait(<Future<PosterBrowseEnrichment>>[
      futureA,
      futureB,
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(backend.detailCalls['item-1'], isNull);
  });

  test('windowIndices 支持循环、短列表去重和空列表；prefetch 只请求去重窗口', () async {
    expect(
      PosterBrowseArtworkEnricher.windowIndices(center: 0, length: 6),
      <int>[4, 5, 0, 1, 2],
    );
    expect(
      PosterBrowseArtworkEnricher.windowIndices(center: 0, length: 2),
      <int>[0, 1],
    );
    expect(
      PosterBrowseArtworkEnricher.windowIndices(
        center: 0,
        length: 6,
        radius: 1,
      ),
      <int>[5, 0, 1],
    );
    expect(
      PosterBrowseArtworkEnricher.windowIndices(center: 0, length: 0),
      isEmpty,
    );

    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        for (final id in <String>['a', 'b', 'c', 'd', 'e', 'f']) id: detail(id),
      },
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    await enricher.prefetchWindow(<MediaItemCard>[
      card(id: 'a'),
      card(id: 'b'),
      card(id: 'c'),
      card(id: 'd'),
      card(id: 'e'),
      card(id: 'f'),
    ], 0);

    expect(backend.detailCalls, <String, int>{
      'e': 1,
      'f': 1,
      'a': 1,
      'b': 1,
      'c': 1,
    });
  });

  test('LRU maxEntries=2 命中会刷新顺序，写入 C 后逐出 B', () async {
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        'a': detail('a'),
        'b': detail('b'),
        'c': detail('c'),
      },
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
      maxEntries: 2,
    );

    await enricher.enrich(card(id: 'a'));
    await enricher.enrich(card(id: 'b'));
    await enricher.enrich(card(id: 'a'));
    await enricher.enrich(card(id: 'c'));
    await enricher.enrich(card(id: 'b'));

    expect(enricher.cacheLength, 2);
    expect(backend.detailCalls['a'], 1);
    expect(backend.detailCalls['b'], 2);
    expect(backend.detailCalls['c'], 1);
  });

  test('全空失败进入短期负缓存，TTL 内不重试，过期后重试', () async {
    var current = DateTime(2026, 7, 28, 10);
    final backend = _FakeMediaBackend(failingDetailIds: <String>{'missing'});
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
      failureTtl: const Duration(seconds: 30),
      now: () => current,
    );

    final first = await enricher.enrich(card(id: 'missing'));
    final second = await enricher.enrich(card(id: 'missing'));
    current = current.add(const Duration(seconds: 31));
    final third = await enricher.enrich(card(id: 'missing'));

    expect(first.itemDetail, isNull);
    expect(second.itemDetail, isNull);
    expect(third.itemDetail, isNull);
    expect(backend.detailCalls['missing'], 2);
  });

  test('item 成功但 series detail 异常时返回 item 并按短 TTL 重试父级', () async {
    var current = DateTime(2026, 7, 28, 11);
    final itemDetail = detail('episode-1', type: 'Episode');
    final seriesDetail = detail('series-1', type: 'TV');
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{'episode-1': itemDetail},
      failingDetailIds: <String>{'series-1'},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
      failureTtl: const Duration(seconds: 30),
      now: () => current,
    );
    final target = card(
      id: 'episode-1',
      type: 'Episode',
      seriesId: 'series-1',
      seasonNumber: 1,
    );

    final first = await enricher.enrich(target);
    final second = await enricher.enrich(target);
    backend.failingDetailIds.remove('series-1');
    backend.details['series-1'] = seriesDetail;
    current = current.add(const Duration(seconds: 31));
    final third = await enricher.enrich(target);

    expect(first.itemDetail, same(itemDetail));
    expect(first.seriesDetail, isNull);
    expect(first.hasLookupFailure, isTrue);
    expect(second.itemDetail, same(itemDetail));
    expect(second.seriesDetail, isNull);
    expect(third.itemDetail, same(itemDetail));
    expect(third.seriesDetail, same(seriesDetail));
    expect(third.hasLookupFailure, isFalse);
    expect(backend.detailCalls['episode-1'], 2);
    expect(backend.detailCalls['series-1'], 2);
  });

  test('单集详情暂未解析出 seriesId 时进入短缓存并在 TTL 后重试', () async {
    var current = DateTime(2026, 7, 29, 10);
    final unresolved = detail('episode-1', type: 'Episode');
    final resolved = detail('episode-1', type: 'Episode', seriesId: 'series-1');
    final seriesDetail = detail('series-1', type: 'TV');
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{'episode-1': unresolved},
      seasons: const <String, List<MediaSeasonSummary>>{'series-1': []},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
      failureTtl: const Duration(seconds: 30),
      now: () => current,
    );
    final target = card(id: 'episode-1', type: 'Episode');

    final first = await enricher.enrich(target);
    final second = await enricher.enrich(target);
    backend.details['episode-1'] = resolved;
    backend.details['series-1'] = seriesDetail;
    current = current.add(const Duration(seconds: 31));
    final third = await enricher.enrich(target);

    expect(first.itemDetail, same(unresolved));
    expect(first.hasLookupFailure, isTrue);
    expect(second.itemDetail, same(unresolved));
    expect(third.itemDetail, same(resolved));
    expect(third.seriesDetail, same(seriesDetail));
    expect(third.hasLookupFailure, isFalse);
    expect(backend.detailCalls['episode-1'], 2);
    expect(backend.detailCalls['series-1'], 1);
  });

  test('seasons 异常按部分失败短缓存，正常空 seasons 不算失败', () async {
    var current = DateTime(2026, 7, 28, 12);
    final itemDetail = detail('episode-1', type: 'Episode');
    final seriesDetail = detail('series-1', type: 'TV');
    final season1 = season('season-1', 1);
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        'episode-1': itemDetail,
        'series-1': seriesDetail,
      },
      seasons: <String, List<MediaSeasonSummary>>{},
      failingSeasonIds: <String>{'series-1'},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
      failureTtl: const Duration(seconds: 30),
      now: () => current,
    );
    final target = card(
      id: 'episode-1',
      type: 'Episode',
      seriesId: 'series-1',
      seasonNumber: 1,
    );

    final first = await enricher.enrich(target);
    final second = await enricher.enrich(target);
    backend.failingSeasonIds.remove('series-1');
    backend.seasons['series-1'] = <MediaSeasonSummary>[season1];
    current = current.add(const Duration(seconds: 31));
    final third = await enricher.enrich(target);

    expect(first.itemDetail, same(itemDetail));
    expect(first.seriesDetail, same(seriesDetail));
    expect(first.season, isNull);
    expect(first.hasLookupFailure, isTrue);
    expect(second.hasLookupFailure, isTrue);
    expect(third.season, same(season1));
    expect(third.hasLookupFailure, isFalse);
    expect(backend.seasonCalls['series-1'], 2);

    final emptySeasonsBackend = _FakeMediaBackend(
      details: <String, MediaDetail>{
        'episode-2': detail('episode-2', type: 'Episode'),
        'series-2': detail('series-2', type: 'TV'),
      },
      seasons: const <String, List<MediaSeasonSummary>>{'series-2': []},
    );
    final emptySeasonsEnricher = PosterBrowseArtworkEnricher(
      backend: emptySeasonsBackend,
      sessionKey: 'session-a',
      failureTtl: const Duration(seconds: 30),
      now: () => current,
    );

    final emptySeasons = await emptySeasonsEnricher.enrich(
      card(
        id: 'episode-2',
        type: 'Episode',
        seriesId: 'series-2',
        seasonNumber: 1,
      ),
    );

    expect(emptySeasons.season, isNull);
    expect(emptySeasons.hasLookupFailure, isFalse);
    await emptySeasonsEnricher.enrich(
      card(
        id: 'episode-2',
        type: 'Episode',
        seriesId: 'series-2',
        seasonNumber: 1,
      ),
    );
    expect(emptySeasonsBackend.seasonCalls['series-2'], 1);
  });

  test('不同 session 实例不共享缓存', () async {
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{'a': detail('a')},
    );
    final sessionA = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );
    final sessionB = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-b',
    );

    await sessionA.enrich(card(id: 'a'));
    await sessionB.enrich(card(id: 'a'));
    await sessionA.enrich(card(id: 'a'));

    expect(backend.detailCalls['a'], 2);
  });

  test('clear 后清理 cache、inFlight 和 negative，下次会重新请求', () async {
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{'a': detail('a')},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    await enricher.enrich(card(id: 'a'));
    enricher.clear();
    await enricher.enrich(card(id: 'a'));

    expect(enricher.cacheLength, 1);
    expect(backend.detailCalls['a'], 2);
  });

  test('clear 后旧 inFlight 完成不会重新回填缓存', () async {
    final oldCompleter = Completer<MediaDetail>();
    final backend = _FakeMediaBackend(
      details: <String, MediaDetail>{'a': detail('a')},
      detailCompleters: <String, Completer<MediaDetail>>{' a ': oldCompleter},
    );
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: 'session-a',
    );

    final oldFuture = enricher.enrich(card(id: ' a '));
    enricher.clear();
    oldCompleter.complete(detail('old'));
    await oldFuture;

    expect(enricher.cacheLength, 0);
    await enricher.enrich(card(id: 'a'));

    expect(enricher.cacheLength, 1);
    expect(backend.detailCalls[' a '], 1);
    expect(backend.detailCalls['a'], 1);
  });
}

class _FakeMediaBackend extends MediaBackend {
  _FakeMediaBackend({
    this.details = const <String, MediaDetail>{},
    this.seasons = const <String, List<MediaSeasonSummary>>{},
    this.failingDetailIds = const <String>{},
    this.failingSeasonIds = const <String>{},
    this.detailCompleters = const <String, Completer<MediaDetail>>{},
  });

  final Map<String, MediaDetail> details;
  final Map<String, List<MediaSeasonSummary>> seasons;
  final Set<String> failingDetailIds;
  final Set<String> failingSeasonIds;
  final Map<String, Completer<MediaDetail>> detailCompleters;
  final Map<String, int> detailCalls = <String, int>{};
  final Map<String, int> seasonCalls = <String, int>{};

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.server(kind: MediaBackendKind.emby);

  @override
  MediaPlaybackSourceBridge get playbackSourceBridge => _NoopBridge();

  @override
  Future<List<MediaCatalog>> getCatalogs() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getHomeSummary() => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> searchItems(String query) =>
      throw UnimplementedError();

  @override
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(String catalogId) =>
      throw UnimplementedError();

  @override
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query) =>
      throw UnimplementedError();

  @override
  Future<MediaDetail> getItemDetail(String itemId) async {
    detailCalls[itemId] = (detailCalls[itemId] ?? 0) + 1;
    final completer = detailCompleters[itemId];
    if (completer != null) {
      return completer.future;
    }
    if (failingDetailIds.contains(itemId) || !details.containsKey(itemId)) {
      throw Exception('detail missing: $itemId');
    }
    return details[itemId]!;
  }

  @override
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSourceVersion>> getItemSourceVersions(String itemId) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) async {
    seasonCalls[seriesId] = (seasonCalls[seriesId] ?? 0) + 1;
    if (failingSeasonIds.contains(seriesId)) {
      throw Exception('seasons missing: $seriesId');
    }
    return seasons[seriesId] ?? const <MediaSeasonSummary>[];
  }

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) =>
      throw UnimplementedError();

  @override
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request) =>
      throw UnimplementedError();
}

class _NoopBridge implements MediaPlaybackSourceBridge {
  @override
  Future<MediaPlaybackSourceResult> assemblePlaybackSource({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required MediaPlaybackBackendContext? context,
    required AppLocalizations l10n,
  }) => throw UnimplementedError();
}
