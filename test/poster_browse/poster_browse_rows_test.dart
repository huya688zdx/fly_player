import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/detail/media_source_info.dart';
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
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_loader.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItemCard card(String id) => MediaItemCard(
  id: id,
  title: id,
  type: 'Movie',
  primaryImage: MediaImageRef.empty,
);

FeiniuApi standaloneApi() => _FakeFeiniuApi(NasProvider());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('只有继续观看时仅生成继续观看行', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      catalogs: const <MediaCatalog>[],
    );
    expect(rows, hasLength(1));
    expect(rows[0].kind, PosterBrowseRowKind.continueWatching);
    expect(rows[0].items.map((e) => e.id), ['c1']);
  });

  test('目录为空时不生成目录行', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      catalogs: const <MediaCatalog>[],
    );
    expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
    ]);
  });

  test('全空返回空列表', () {
    final rows = buildPosterBrowseRows(
      continueWatching: const <MediaItemCard>[],
      catalogs: const <MediaCatalog>[],
    );
    expect(rows, isEmpty);
  });

  test('cardFromLibraryItem 保留续播富字段(ts 优先)', () {
    final item = MediaLibraryItem(
      guid: 'g1',
      title: '沙丘',
      tvTitle: '',
      type: 'Movie',
      poster: '/p.jpg',
      posterWidth: 720,
      posterHeight: 1080,
      releaseDate: '2024-03-01',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '8.3',
      overview: 'plot',
      watched: 0,
      watchedTs: 0,
      ts: 1200,
      duration: 6000,
      seasonNumber: 1,
      episodeNumber: 7,
      numberOfSeasons: 2,
      numberOfEpisodes: 13,
      localNumberOfSeasons: 2,
      localNumberOfEpisodes: 11,
      parentGuid: '',
      parentTitle: '',
      ancestorGuid: 'series1',
      ancestorName: '',
      path: '',
    );
    final cardResult = cardFromLibraryItem(item);
    expect(cardResult.id, 'g1');
    expect(cardResult.rating, '8.3');
    expect(cardResult.overview, 'plot');
    expect(cardResult.resumePositionSeconds, 1200);
    expect(cardResult.durationSeconds, 6000);
    expect(cardResult.seriesId, isEmpty);
    expect(cardResult.seasonNumber, 1);
    expect(cardResult.episodeNumber, 7);
    expect(cardResult.numberOfSeasons, 2);
    expect(cardResult.numberOfEpisodes, 13);
    expect(cardResult.localNumberOfSeasons, 2);
    expect(cardResult.localNumberOfEpisodes, 11);
    expect(cardResult.posterWidth, 720);
    expect(cardResult.posterHeight, 1080);
    expect(cardResult.primaryImage.url, '/p.jpg');
  });

  test('cardFromLibraryItem 隔离媒体库根目录与污染标题', () {
    final item = MediaLibraryItem(
      guid: 'episode-3',
      title: '不灭之焰',
      tvTitle: '动漫 TV',
      type: 'Episode',
      poster: '/episode-still.jpg',
      releaseDate: '',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '8',
      overview: '',
      watched: 0,
      watchedTs: 0,
      ts: 120,
      duration: 1380,
      seasonNumber: 1,
      episodeNumber: 3,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: 'season-1',
      parentTitle: '第 1 季',
      ancestorGuid: 'library-root',
      ancestorName: '动漫 TV',
      path: '',
    );

    final result = cardFromLibraryItem(item);

    expect(result.id, 'episode-3');
    expect(result.seriesId, isEmpty);
    expect(result.secondaryTitle, isEmpty);
    expect(result.displayTitle, '不灭之焰');
  });

  test('cardFromLibraryItem：ts 为 0 时回退 watchedTs', () {
    final item = MediaLibraryItem(
      guid: 'g2',
      title: '沙丘2',
      tvTitle: '',
      type: 'Movie',
      poster: '/p2.jpg',
      releaseDate: '',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '',
      overview: '',
      watched: 1,
      watchedTs: 800,
      ts: 0,
      duration: 6000,
      seasonNumber: 0,
      episodeNumber: 0,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: '',
      parentTitle: '',
      ancestorGuid: '',
      ancestorName: '',
      path: '',
    );
    final cardResult = cardFromLibraryItem(item);
    expect(cardResult.resumePositionSeconds, 800);
  });

  group('PosterBrowseLoader.load', () {
    late FeiniuApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final nas = NasProvider();
      addTearDown(nas.dispose);
      api = _FakeFeiniuApi(nas);
    });

    test('继续观看与目录均返回且不请求预览', () async {
      final backend = _FakeMediaBackend(
        catalogs: const <MediaCatalog>[
          MediaCatalog(
            id: 'lib1',
            title: '不应请求的媒体库',
            type: 'movies',
            primaryImage: MediaImageRef.empty,
          ),
        ],
        continueWatching: <MediaItemCard>[card('c1')],
        catalogPreviewItems: <String, List<MediaItemCard>>{
          'lib1': <MediaItemCard>[card('m1')],
        },
      );

      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: api,
      );

      expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
        PosterBrowseRowKind.continueWatching,
        PosterBrowseRowKind.catalog,
      ]);
      expect(backend.getCatalogsCallCount, 1);
      expect(backend.getCatalogPreviewItemsCallCount, 0);
    });

    test('目录为空时仍返回继续观看行', () async {
      final backend = _FakeMediaBackend(
        continueWatching: <MediaItemCard>[card('c1')],
      );

      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: api,
      );

      expect(rows, hasLength(1));
      expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
        PosterBrowseRowKind.continueWatching,
      ]);
      expect(backend.getCatalogsCallCount, 1);
      expect(backend.getCatalogPreviewItemsCallCount, 0);
    });

    test('飞牛返回全部目录并保留目录标题', () async {
      final backend = _FakeMediaBackend(
        kind: MediaBackendKind.feiniu,
        catalogs: const <MediaCatalog>[
          MediaCatalog(
            id: 'movies',
            title: '动漫电影',
            type: 'Movie',
            primaryImage: MediaImageRef.empty,
          ),
          MediaCatalog(
            id: 'anime-tv',
            title: '动漫 TV',
            type: 'TV',
            primaryImage: MediaImageRef.empty,
          ),
          MediaCatalog(
            id: 'series-2',
            title: '其他剧集',
            type: 'Series',
            primaryImage: MediaImageRef.empty,
          ),
        ],
        catalogPreviewItems: <String, List<MediaItemCard>>{
          'anime-tv': <MediaItemCard>[card('series-1')],
        },
      );

      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: api,
      );

      expect(rows, hasLength(3));
      expect(rows[1].kind, PosterBrowseRowKind.catalog);
      expect(rows[1].title, '动漫 TV');
      expect(rows[1].items, isEmpty);
      expect(backend.getCatalogsCallCount, 1);
      expect(backend.getCatalogPreviewItemsCallCount, 0);
      expect(backend.requestedCatalogIds, isEmpty);
      expect(backend.getLatestItemsCallCount, 0);
    });
  });

  test('继续观看在前，并按后端原始顺序保留全部目录元数据', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      catalogs: const <MediaCatalog>[
        MediaCatalog(
          id: 'movies',
          title: '电影库',
          type: 'movies',
          primaryImage: MediaImageRef.empty,
        ),
        MediaCatalog(
          id: 'shows',
          title: '剧集库',
          type: 'tvshows',
          primaryImage: MediaImageRef.empty,
        ),
        MediaCatalog(
          id: 'empty',
          title: '空目录',
          type: 'mixed',
          primaryImage: MediaImageRef.empty,
        ),
      ],
    );

    expect(rows.map((row) => row.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
      PosterBrowseRowKind.catalog,
      PosterBrowseRowKind.catalog,
      PosterBrowseRowKind.catalog,
    ]);
    expect(rows.first.items.map((item) => item.id), <String>['c1']);
    expect(rows.skip(1).map((row) => row.catalogId), <String>[
      'movies',
      'shows',
      'empty',
    ]);
    expect(rows.skip(1).map((row) => row.title), <String>['电影库', '剧集库', '空目录']);
    expect(rows.skip(1).every((row) => row.items.isEmpty), isTrue);
    expect(
      rows
          .skip(1)
          .every((row) => row.loadState == PosterBrowseRowLoadState.idle),
      isTrue,
    );
  });

  test('无继续观看时仍返回全部目录', () {
    final rows = buildPosterBrowseRows(
      continueWatching: const <MediaItemCard>[],
      catalogs: const <MediaCatalog>[
        MediaCatalog(
          id: 'one',
          title: '目录一',
          type: 'movies',
          primaryImage: MediaImageRef.empty,
        ),
        MediaCatalog(
          id: 'two',
          title: '目录二',
          type: 'tvshows',
          primaryImage: MediaImageRef.empty,
        ),
      ],
    );

    expect(rows.map((row) => row.catalogId), <String>['one', 'two']);
    expect(
      rows.every((row) => row.kind == PosterBrowseRowKind.catalog),
      isTrue,
    );
  });

  test('飞牛、Emby 与 Jellyfin 都读取目录且不请求 latest 或 preview', () async {
    for (final kind in <MediaBackendKind>[
      MediaBackendKind.feiniu,
      MediaBackendKind.emby,
      MediaBackendKind.jellyfin,
    ]) {
      final backend = _FakeMediaBackend(
        kind: kind,
        catalogs: const <MediaCatalog>[
          MediaCatalog(
            id: 'catalog',
            title: '目录',
            type: 'tv',
            primaryImage: MediaImageRef.empty,
          ),
        ],
        continueWatching: <MediaItemCard>[card('continue')],
        catalogPreviewItems: <String, List<MediaItemCard>>{
          'catalog': <MediaItemCard>[card('preview')],
        },
      );

      await const PosterBrowseLoader().load(
        backend: backend,
        api: standaloneApi(),
      );

      expect(backend.getCatalogsCallCount, 1, reason: '$kind');
      expect(backend.getLatestItemsCallCount, 0, reason: '$kind');
      expect(backend.getCatalogPreviewItemsCallCount, 0, reason: '$kind');
    }
  });

  test('目录加载失败时仍保留继续观看', () async {
    final backend = _FakeMediaBackend(
      continueWatching: <MediaItemCard>[card('continue')],
      throwCatalogs: true,
    );

    final rows = await const PosterBrowseLoader().load(
      backend: backend,
      api: standaloneApi(),
    );

    expect(rows.map((row) => row.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
    ]);
  });

  test('继续观看加载失败时仍保留目录', () async {
    final backend = _FakeMediaBackend(
      catalogs: const <MediaCatalog>[
        MediaCatalog(
          id: 'catalog',
          title: '目录',
          type: 'tv',
          primaryImage: MediaImageRef.empty,
        ),
      ],
      throwContinueWatching: true,
    );

    final rows = await const PosterBrowseLoader().load(
      backend: backend,
      api: standaloneApi(),
    );

    expect(rows.map((row) => row.catalogId), <String>['catalog']);
  });
}

/// 最小飞牛 API Fake：非飞牛 backend 路径不会调用它，仅满足 [PosterBrowseLoader.load]
/// 的参数类型要求。
class _FakeFeiniuApi extends FeiniuApi {
  _FakeFeiniuApi(super.nasProvider);

  @override
  Future<List<MediaLibraryItem>> getPlayList({
    bool forceRefresh = false,
  }) async => const <MediaLibraryItem>[];
}

/// 最小公共后端 Fake，走非飞牛 kind（服务器族路径），可配置各源数据与单 catalog 失败。
class _FakeMediaBackend extends MediaBackend {
  _FakeMediaBackend({
    this.kind = MediaBackendKind.emby,
    this.catalogs = const <MediaCatalog>[],
    this.continueWatching = const <MediaItemCard>[],
    this.latestItems = const <MediaItemCard>[],
    this.catalogPreviewItems = const <String, List<MediaItemCard>>{},
    this.throwCatalogs = false,
    this.throwContinueWatching = false,
  });

  final MediaBackendKind kind;
  final List<MediaCatalog> catalogs;
  final List<MediaItemCard> continueWatching;
  final List<MediaItemCard> latestItems;
  final Map<String, List<MediaItemCard>> catalogPreviewItems;
  final bool throwCatalogs;
  final bool throwContinueWatching;
  int getCatalogsCallCount = 0;
  int getCatalogPreviewItemsCallCount = 0;
  int getLatestItemsCallCount = 0;
  final List<String> requestedCatalogIds = <String>[];

  @override
  MediaBackendCapabilities get capabilities => kind == MediaBackendKind.feiniu
      ? const MediaBackendCapabilities.feiniu()
      : MediaBackendCapabilities.server(kind: kind);

  @override
  MediaPlaybackSourceBridge get playbackSourceBridge => _NoopBridge();

  @override
  Future<List<MediaCatalog>> getCatalogs() async {
    getCatalogsCallCount += 1;
    if (throwCatalogs) {
      throw StateError('catalogs failed');
    }
    return catalogs;
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) async {
    if (throwContinueWatching) {
      throw StateError('continue watching failed');
    }
    return continueWatching;
  }

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    getCatalogPreviewItemsCallCount += 1;
    requestedCatalogIds.add(catalogId);
    return catalogPreviewItems[catalogId] ?? const <MediaItemCard>[];
  }

  @override
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async {
    getLatestItemsCallCount += 1;
    return latestItems;
  }

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
  Future<MediaDetail> getItemDetail(String itemId) =>
      throw UnimplementedError();

  @override
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) =>
      throw UnimplementedError();

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
