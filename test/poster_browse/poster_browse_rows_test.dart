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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('三类行按序组装，空行整行剔除', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: const <MediaItemCard>[], // 空 → 隐藏
      catalogs: const <MediaCatalog>[
        MediaCatalog(
          id: 'lib1',
          title: '电影库',
          type: 'movies',
          primaryImage: MediaImageRef.empty,
        ),
        MediaCatalog(
          id: 'lib2',
          title: '空库',
          type: 'tvshows',
          primaryImage: MediaImageRef.empty,
        ),
      ],
      catalogItems: <String, List<MediaItemCard>>{
        'lib1': <MediaItemCard>[card('m1'), card('m2')],
        'lib2': const <MediaItemCard>[], // 空 → 隐藏
      },
    );
    expect(rows, hasLength(2));
    expect(rows[0].kind, PosterBrowseRowKind.continueWatching);
    expect(rows[1].kind, PosterBrowseRowKind.catalog);
    expect(rows[1].catalogId, 'lib1');
    expect(rows[1].catalogTitle, '电影库');
    expect(rows[1].items.map((e) => e.id), ['m1', 'm2']);
  });

  test('最近添加行在继续观看之后、媒体库之前', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: <MediaItemCard>[card('l1')],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
    );
    expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
      PosterBrowseRowKind.latest,
    ]);
  });

  test('全空返回空列表', () {
    final rows = buildPosterBrowseRows(
      continueWatching: const <MediaItemCard>[],
      latestItems: const <MediaItemCard>[],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
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
      releaseDate: '2024-03-01',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '8.3',
      overview: 'plot',
      watched: 0,
      watchedTs: 0,
      ts: 1200,
      duration: 6000,
      seasonNumber: 0,
      episodeNumber: 0,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
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
    expect(cardResult.seriesId, 'series1');
    expect(cardResult.primaryImage.url, '/p.jpg');
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

    test('单 catalog 失败只影响该行', () async {
      final backend = _FakeMediaBackend(
        catalogs: const <MediaCatalog>[
          MediaCatalog(
            id: 'ok',
            title: '正常库',
            type: 'movies',
            primaryImage: MediaImageRef.empty,
          ),
          MediaCatalog(
            id: 'bad',
            title: '异常库',
            type: 'movies',
            primaryImage: MediaImageRef.empty,
          ),
        ],
        continueWatching: <MediaItemCard>[card('c1')],
        latestItems: <MediaItemCard>[card('l1')],
        catalogPreviewItems: <String, List<MediaItemCard>>{
          'ok': <MediaItemCard>[card('m1')],
        },
        failingCatalogIds: const <String>{'bad'},
      );

      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: api,
      );

      expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
        PosterBrowseRowKind.continueWatching,
        PosterBrowseRowKind.latest,
        PosterBrowseRowKind.catalog,
      ]);
      expect(rows.last.catalogId, 'ok');
      expect(rows.last.items.map((e) => e.id), <String>['m1']);
    });

    test('catalogs 为空时仍返回继续观看/最近添加行', () async {
      final backend = _FakeMediaBackend(
        continueWatching: <MediaItemCard>[card('c1')],
        latestItems: <MediaItemCard>[card('l1')],
      );

      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: api,
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
        PosterBrowseRowKind.continueWatching,
        PosterBrowseRowKind.latest,
      ]);
    });
  });
}

/// 最小飞牛 API Fake：非飞牛 backend 路径不会调用它，仅满足 [PosterBrowseLoader.load]
/// 的参数类型要求。
class _FakeFeiniuApi extends FeiniuApi {
  _FakeFeiniuApi(super.nasProvider);
}

/// 最小公共后端 Fake，走非飞牛 kind（服务器族路径），可配置各源数据与单 catalog 失败。
class _FakeMediaBackend extends MediaBackend {
  _FakeMediaBackend({
    this.catalogs = const <MediaCatalog>[],
    this.continueWatching = const <MediaItemCard>[],
    this.latestItems = const <MediaItemCard>[],
    this.catalogPreviewItems = const <String, List<MediaItemCard>>{},
    this.failingCatalogIds = const <String>{},
  });

  final List<MediaCatalog> catalogs;
  final List<MediaItemCard> continueWatching;
  final List<MediaItemCard> latestItems;
  final Map<String, List<MediaItemCard>> catalogPreviewItems;
  final Set<String> failingCatalogIds;

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.server(kind: MediaBackendKind.emby);

  @override
  MediaPlaybackSourceBridge get playbackSourceBridge => _NoopBridge();

  @override
  Future<List<MediaCatalog>> getCatalogs() async => catalogs;

  @override
  Future<Map<String, dynamic>> getHomeSummary() => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) async => continueWatching;

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    if (failingCatalogIds.contains(catalogId)) {
      throw Exception('boom: $catalogId');
    }
    return catalogPreviewItems[catalogId] ?? const <MediaItemCard>[];
  }

  @override
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async =>
      latestItems;

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
