import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_source_info.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/emby/emby_playback_context.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';

class _FakeEmbyApi extends EmbyApi {
  _FakeEmbyApi({
    this.views = const [],
    this.items = const [],
    this.item = const <String, Object?>{},
    this.seasons = const [],
    this.genres = const [],
    this.countByIncludeItemTypes = const <String, int>{},
    this.favoriteCount = 0,
    this.pageItems = const [],
    this.pageTotal = 0,
    this.resumeItems = const [],
    this.nextUpItems = const [],
  });

  final List<Map<String, Object?>> views;
  final List<Map<String, Object?>> items;
  final Map<String, Object?> item;
  final List<Map<String, Object?>> seasons;
  final List<Map<String, Object?>> genres;
  final List<Map<String, Object?>> resumeItems;
  final List<Map<String, Object?>> nextUpItems;
  // 计数桩：键=IncludeItemTypes（如 'Movie'/'Series'），值=TotalRecordCount。
  final Map<String, int> countByIncludeItemTypes;
  final int favoriteCount;
  // 分页查询桩。
  final List<Map<String, Object?>> pageItems;
  final int pageTotal;
  String? lastParentId;
  String? lastItemId;
  String? lastSeasonsSeriesId;
  bool lastIsResumable = false;
  bool lastRecursive = false;
  String lastIncludeItemTypes = '';
  final List<String> countIncludeItemTypes = <String>[];
  bool lastCountFavoritesOnly = false;
  // getItemPage 入参捕获。
  String? lastPageParentId;
  int lastPageStartIndex = 0;
  int? lastPageLimit;
  String lastPageIncludeItemTypes = '';
  String lastPageGenres = '';
  String lastPageYears = '';
  String lastPageFilters = '';
  String lastPageSeriesStatus = '';
  String lastPageSortBy = '';
  String lastPageSortOrder = '';
  String lastPageSearchTerm = '';
  String lastPagePersonIds = '';
  bool lastPageFavoritesOnly = false;
  // getGenres 入参捕获。
  String? lastGenresParentId;
  String lastGenresIncludeItemTypes = '';
  // getResumeItems 入参捕获。
  int lastResumeLimit = 0;
  // getNextUpEpisodes 入参捕获 + 调用计数。
  String? lastNextUpSeriesId;
  int lastNextUpLimit = 0;
  String lastNextUpFields = '';
  int nextUpCalls = 0;
  // reportPlaybackProgress 入参捕获。
  String? lastProgressItemId;
  String? lastProgressMediaSourceId;
  int? lastProgressPositionTicks;
  bool? lastProgressIsPaused;
  // downloadSubtitleText 桩 + 入参捕获。
  String subtitleText = '';
  String? lastSubtitleItemId;
  String? lastSubtitleMediaSourceId;
  int? lastSubtitleStreamIndex;
  String? lastSubtitleFormat;

  @override
  Future<String> downloadSubtitleText({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required int streamIndex,
    required String accessToken,
    String format = 'srt',
  }) async {
    lastSubtitleItemId = itemId;
    lastSubtitleMediaSourceId = mediaSourceId;
    lastSubtitleStreamIndex = streamIndex;
    lastSubtitleFormat = format;
    return subtitleText;
  }

  // PlaybackStart/Stopped 入参捕获。
  final List<String> playSessionCalls = <String>[];
  int? lastStartPositionTicks;
  int? lastStoppedPositionTicks;

  @override
  Future<void> reportPlaybackStart({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    int positionTicks = 0,
  }) async {
    playSessionCalls.add('start:$itemId');
    lastStartPositionTicks = positionTicks;
  }

  @override
  Future<void> reportPlaybackStopped({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
  }) async {
    playSessionCalls.add('stopped:$itemId');
    lastStoppedPositionTicks = positionTicks;
  }

  @override
  Future<void> reportPlaybackProgress({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
    bool isPaused = false,
  }) async {
    lastProgressItemId = itemId;
    lastProgressMediaSourceId = mediaSourceId;
    lastProgressPositionTicks = positionTicks;
    lastProgressIsPaused = isPaused;
  }

  @override
  Future<int> getItemCount({
    required String serverUrl,
    required String userId,
    required String accessToken,
    bool recursive = true,
    bool favoritesOnly = false,
    String includeItemTypes = '',
  }) async {
    countIncludeItemTypes.add(includeItemTypes);
    lastCountFavoritesOnly = favoritesOnly;
    if (favoritesOnly) return favoriteCount;
    return countByIncludeItemTypes[includeItemTypes] ?? 0;
  }

  @override
  Future<List<Map<String, Object?>>> getUserViews({
    required String serverUrl,
    required String userId,
    required String accessToken,
  }) async => views;

  @override
  Future<Map<String, Object?>> getItem({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    String fields = '',
  }) async {
    lastItemId = itemId;
    return item;
  }

  @override
  Future<List<Map<String, Object?>>> getItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    int? limit,
    bool isResumable = false,
    bool recursive = false,
    String includeItemTypes = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
  }) async {
    lastParentId = parentId;
    lastIsResumable = isResumable;
    lastRecursive = recursive;
    lastIncludeItemTypes = includeItemTypes;
    return items;
  }

  @override
  Future<List<Map<String, Object?>>> getSeasons({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String seriesId,
    String fields = 'ItemCounts,UserData',
  }) async {
    lastSeasonsSeriesId = seriesId;
    return seasons;
  }

  @override
  Future<EmbyItemPage> getItemPage({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    int startIndex = 0,
    int? limit,
    bool recursive = true,
    String includeItemTypes = '',
    String genres = '',
    String years = '',
    String filters = '',
    String seriesStatus = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
    String searchTerm = '',
    String personIds = '',
    bool favoritesOnly = false,
  }) async {
    lastPageParentId = parentId;
    lastPageStartIndex = startIndex;
    lastPageLimit = limit;
    lastPageIncludeItemTypes = includeItemTypes;
    lastPageGenres = genres;
    lastPageYears = years;
    lastPageFilters = filters;
    lastPageSeriesStatus = seriesStatus;
    lastPageSortBy = sortBy;
    lastPageSortOrder = sortOrder;
    lastPageSearchTerm = searchTerm;
    lastPagePersonIds = personIds;
    lastPageFavoritesOnly = favoritesOnly;
    return EmbyItemPage(items: pageItems, totalRecordCount: pageTotal);
  }

  @override
  Future<List<Map<String, Object?>>> getGenres({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    String includeItemTypes = '',
  }) async {
    lastGenresParentId = parentId;
    lastGenresIncludeItemTypes = includeItemTypes;
    return genres;
  }

  @override
  Future<List<Map<String, Object?>>> getResumeItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    int limit = 20,
    String fields = '',
  }) async {
    lastResumeLimit = limit;
    return resumeItems;
  }

  @override
  Future<List<Map<String, Object?>>> getNextUpEpisodes({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String seriesId = '',
    int limit = 1,
    String fields = 'Overview,UserData,MediaStreams',
  }) async {
    nextUpCalls++;
    lastNextUpSeriesId = seriesId;
    lastNextUpLimit = limit;
    lastNextUpFields = fields;
    return nextUpItems;
  }
}

void main() {
  const connection = MediaBackendConnection(
    kind: MediaBackendKind.emby,
    serverUrl: 'https://emby.example.test',
    userId: 'user-1',
    accessToken: 'tok',
  );

  test('capabilities：kind=emby，飞牛专属能力全关', () {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(),
      connection: connection,
    );
    final caps = backend.capabilities;
    expect(caps.kind, MediaBackendKind.emby);
    expect(caps.supportsDownloadTasks, isFalse);
    expect(caps.supportsFnConnect, isFalse);
    expect(caps.supportsIntroOutroConfig, isFalse);
  });

  test('getCatalogs：Views → MediaCatalog', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(
        views: <Map<String, Object?>>[
          <String, Object?>{
            'Id': 'lib-1',
            'Name': '电影',
            'CollectionType': 'movies',
          },
        ],
      ),
      connection: connection,
    );
    final catalogs = await backend.getCatalogs();
    expect(catalogs, hasLength(1));
    expect(catalogs[0].id, 'lib-1');
    expect(catalogs[0].type, 'movies');
  });

  test('getCatalogPreviewItems：按 parentId 取条目', () async {
    final api = _FakeEmbyApi(
      items: <Map<String, Object?>>[
        <String, Object?>{'Id': 'item-1', 'Name': '影片', 'Type': 'Movie'},
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final items = await backend.getCatalogPreviewItems('lib-1', limit: 10);
    expect(api.lastParentId, 'lib-1');
    // 拍平库下文件夹、直出影片/剧集（否则首页显示无封面的中间文件夹）。
    expect(api.lastRecursive, isTrue);
    expect(api.lastIncludeItemTypes, 'Movie,Series');
    expect(items, hasLength(1));
    expect(items[0].id, 'item-1');
  });

  test('getContinueWatching：走 /Items/Resume；电影续播卡用 backdrop', () async {
    final api = _FakeEmbyApi(
      resumeItems: <Map<String, Object?>>[
        <String, Object?>{
          'Id': 'r-1',
          'Name': '续播电影',
          'Type': 'Movie',
          'ImageTags': <String, Object?>{'Primary': 'p1'},
          'BackdropImageTags': <Object?>['b1'],
          'RunTimeTicks': 72000000000, // 7200s
          'UserData': <String, Object?>{'PlaybackPositionTicks': 18000000000},
          'MediaStreams': <Object?>[
            // 宽银幕 4K：宽 3840 / 高仅 1604。按宽度应判 4K（按高度会误判成 2K）。
            <String, Object?>{'Type': 'Video', 'Width': 3840, 'Height': 1604},
          ],
        },
        <String, Object?>{
          'Id': 'r-2',
          'Name': '续播单集',
          'Type': 'Episode',
          'ImageTags': <String, Object?>{'Primary': 'ep1'},
          'BackdropImageTags': <Object?>['bep'],
        },
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final items = await backend.getContinueWatching();
    expect(api.lastResumeLimit, 20);
    expect(items, hasLength(2));
    // 电影:横版卡用 backdrop 顶替 Primary。
    expect(items[0].primaryImage.url, contains('/Images/Backdrop?tag=b1'));
    // 续看进度位 + 清晰度角标随卡片带出（首页进度条 / 右下角分辨率）。
    expect(items[0].resumePositionSeconds, 1800);
    expect(items[0].durationSeconds, 7200);
    expect(items[0].resolutions, <String>['4K']);
    // 单集:Primary 本身横版剧照,保持不动。
    expect(items[1].primaryImage.url, contains('/Images/Primary?tag=ep1'));
  });

  test('getNextUpItems：全局 NextUp 映射为公共单集卡片', () async {
    final api = _FakeEmbyApi(
      nextUpItems: <Map<String, Object?>>[
        <String, Object?>{
          'Id': 'ep-10',
          'Name': '第十集',
          'Type': 'Episode',
          'SeriesId': 'series-1',
          'SeriesName': '白箱',
          'ParentIndexNumber': 1,
          'IndexNumber': 10,
          'RunTimeTicks': 14400000000,
          'UserData': <String, Object?>{'PlaybackPositionTicks': 3000000000},
        },
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);

    final items = await backend.getNextUpItems(limit: 8);

    expect(api.lastNextUpSeriesId, '');
    expect(api.lastNextUpLimit, 8);
    expect(
      api.lastNextUpFields,
      'PrimaryImageAspectRatio,Overview,PremiereDate,CommunityRating,MediaStreams,Genres',
    );
    expect(items, hasLength(1));
    expect(items.first.id, 'ep-10');
    expect(items.first.type, 'Episode');
    expect(items.first.seriesId, 'series-1');
    expect(items.first.secondaryTitle, '白箱');
    expect(items.first.seasonNumber, 1);
    expect(items.first.episodeNumber, 10);
    expect(items.first.durationSeconds, 1440);
    expect(items.first.resumePositionSeconds, 300);
  });

  test('searchItems：SearchTerm + Movie,Series,Episode', () async {
    final api = _FakeEmbyApi(
      pageItems: <Map<String, Object?>>[
        <String, Object?>{'Id': 's-1', 'Name': '命中', 'Type': 'Movie'},
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final results = await backend.searchItems('  关键词  ');
    expect(api.lastPageSearchTerm, '关键词');
    expect(api.lastPageIncludeItemTypes, 'Movie,Series,Episode');
    expect(results, hasLength(1));
    expect(results.first.id, 's-1');
  });

  test('searchItems：空查询直接返回空、不打网络', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final results = await backend.searchItems('   ');
    expect(results, isEmpty);
    expect(api.lastPageSearchTerm, '');
  });

  test('getPersonItems：PersonIds + Movie,Series → 卡片', () async {
    final api = _FakeEmbyApi(
      pageItems: <Map<String, Object?>>[
        <String, Object?>{'Id': 'w-1', 'Name': '作品', 'Type': 'Movie'},
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final works = await backend.getPersonItems('  pp-1  ');
    expect(api.lastPagePersonIds, 'pp-1');
    expect(api.lastPageIncludeItemTypes, 'Movie,Series');
    expect(works, hasLength(1));
    expect(works.first.id, 'w-1');
  });

  test('getPersonItems：空 id 直接返回空', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    expect(await backend.getPersonItems('  '), isEmpty);
    expect(api.lastPagePersonIds, '');
  });

  test(
    'queryFavoriteItems：favoritesOnly + 全部 Tab=Movie,Series,Episode',
    () async {
      final api = _FakeEmbyApi(
        pageItems: <Map<String, Object?>>[
          <String, Object?>{'Id': 'f-1', 'Name': '收藏', 'Type': 'Movie'},
        ],
        pageTotal: 1,
      );
      final backend = EmbyMediaBackend(api: api, connection: connection);
      final page = await backend.queryFavoriteItems(
        const MediaCatalogQuery(catalogId: ''),
      );
      expect(api.lastPageFavoritesOnly, isTrue);
      expect(api.lastPageIncludeItemTypes, 'Movie,Series,Episode');
      expect(page.items, hasLength(1));
      expect(page.items.first.id, 'f-1');
      expect(page.total, 1);
    },
  );

  test('queryFavoriteItems：person Tab → IncludeItemTypes=Person', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.queryFavoriteItems(
      const MediaCatalogQuery(
        catalogId: '',
        selection: <String, List<String>>{
          'type': <String>['person'],
        },
      ),
    );
    expect(api.lastPageFavoritesOnly, isTrue);
    expect(api.lastPageIncludeItemTypes, 'Person');
  });

  test('getHomeSummary：按类型 TotalRecordCount 拼计数，total=电影+电视剧', () async {
    final api = _FakeEmbyApi(
      countByIncludeItemTypes: const <String, int>{'Movie': 34, 'Series': 12},
      favoriteCount: 5,
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final summary = await backend.getHomeSummary();
    expect(summary['movie'], 34);
    expect(summary['tv'], 12);
    expect(summary['total'], 46);
    expect(summary['favorite'], 5);
    expect(summary['other'], 0);
    // 收藏计数走 IsFavorite + Movie,Series,Episode(含单集,否则只收藏单集时首页显示 0)。
    expect(api.countIncludeItemTypes, contains('Movie,Series,Episode'));
    expect(api.lastCountFavoritesOnly, isTrue);
  });

  test('getItemDetail：getItem → MediaDetail', () async {
    final api = _FakeEmbyApi(
      item: <String, Object?>{
        'Id': 'm-1',
        'Name': '某电影',
        'Type': 'Movie',
        'Overview': '简介',
        'Genres': <Object?>['科幻'],
        // 地区原样透传（英文国名 / ISO code），本地化在渲染层（RegionNameLocalizer）做。
        'ProductionLocations': <Object?>['Japan', 'United States'],
      },
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final detail = await backend.getItemDetail('m-1');
    expect(api.lastItemId, 'm-1');
    expect(detail.id, 'm-1');
    expect(detail.title, '某电影');
    expect(detail.overview, '简介');
    expect(detail.genreLabels, <String>['科幻']);
    expect(detail.regionLabels, <String>['Japan', 'United States']);
  });

  test('getItemDetail：单集带剧名/季/集（供详情头部面包屑）', () async {
    final api = _FakeEmbyApi(
      item: <String, Object?>{
        'Id': 'ep-11',
        'Name': '诸行无常',
        'Type': 'Episode',
        'SeriesName': '平家物语',
        'ParentIndexNumber': 1,
        'IndexNumber': 11,
      },
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final detail = await backend.getItemDetail('ep-11');
    expect(detail.type.toLowerCase(), 'episode');
    expect(detail.title, '诸行无常');
    expect(detail.parentTitle, '平家物语');
    expect(detail.seasonNumber, 1);
    expect(detail.episodeNumber, 11);
  });

  test('getItemSeasons：/Shows/{id}/Seasons → MediaSeasonSummary', () async {
    final api = _FakeEmbyApi(
      seasons: <Map<String, Object?>>[
        <String, Object?>{
          'Id': 'season-1',
          'Name': '第 1 季',
          'IndexNumber': 1,
          'ChildCount': 12,
        },
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final result = await backend.getItemSeasons('series-9');
    expect(api.lastSeasonsSeriesId, 'series-9');
    expect(result, hasLength(1));
    expect(result.first.id, 'season-1');
    expect(result.first.seasonNumber, 1);
    expect(result.first.numberOfEpisodes, 12);
  });

  test('getSeasonEpisodes：ParentId=季 + IncludeItemTypes=Episode', () async {
    final api = _FakeEmbyApi(
      items: <Map<String, Object?>>[
        <String, Object?>{
          'Id': 'ep-1',
          'Name': '第一集',
          'IndexNumber': 1,
          'ParentIndexNumber': 1,
        },
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final result = await backend.getSeasonEpisodes('season-1');
    expect(api.lastParentId, 'season-1');
    expect(api.lastIncludeItemTypes, 'Episode');
    expect(result, hasLength(1));
    expect(result.first.id, 'ep-1');
    expect(result.first.episodeNumber, 1);
  });

  test('queryCatalogItems：StartIndex 分页 + 类型/排序映射 + 总数透传', () async {
    final api = _FakeEmbyApi(
      pageItems: <Map<String, Object?>>[
        <String, Object?>{'Id': 'm-1', 'Name': '片甲', 'Type': 'Movie'},
        <String, Object?>{'Id': 'm-2', 'Name': '片乙', 'Type': 'Movie'},
      ],
      pageTotal: 42,
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final page = await backend.queryCatalogItems(
      const MediaCatalogQuery(
        catalogId: 'lib-1',
        selection: <String, List<String>>{
          'type': <String>['TV'],
          'genres': <String>['科幻', '动作'],
        },
        sortField: 'vote_average',
        sortType: 'ASC',
        page: 3,
        pageSize: 50,
      ),
    );
    expect(api.lastPageParentId, 'lib-1');
    // page=3, pageSize=50 → StartIndex=100。
    expect(api.lastPageStartIndex, 100);
    expect(api.lastPageLimit, 50);
    // 'TV' → Series。
    expect(api.lastPageIncludeItemTypes, 'Series');
    // 题材名以 | 连接。
    expect(api.lastPageGenres, '科幻|动作');
    // vote_average → CommunityRating；ASC → Ascending。
    expect(api.lastPageSortBy, 'CommunityRating');
    expect(api.lastPageSortOrder, 'Ascending');
    expect(page.items, hasLength(2));
    expect(page.items[0].id, 'm-1');
    expect(page.total, 42);
  });

  test('queryCatalogItems：空类型 → Movie,Series；create_time/DESC 默认映射', () async {
    final api = _FakeEmbyApi(pageItems: const [], pageTotal: 0);
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.queryCatalogItems(
      const MediaCatalogQuery(catalogId: '', page: 1, pageSize: 50),
    );
    expect(api.lastPageIncludeItemTypes, 'Movie,Series');
    // page=1 → StartIndex=0。
    expect(api.lastPageStartIndex, 0);
    expect(api.lastPageSortBy, 'DateCreated');
    expect(api.lastPageSortOrder, 'Descending');
    expect(api.lastPageGenres, '');
  });

  test('getCatalogFilterSchema：影视分类 + 题材 + 发行年份 + 四列排序', () async {
    final api = _FakeEmbyApi(
      genres: <Map<String, Object?>>[
        <String, Object?>{'Id': 'g-1', 'Name': '科幻'},
        <String, Object?>{'Id': 'g-2', 'Name': '动作'},
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final schema = await backend.getCatalogFilterSchema('lib-1');
    expect(api.lastGenresParentId, 'lib-1');
    expect(schema.sortOptions.map((o) => o.field), <String>[
      'create_time',
      'release_date',
      'title',
      'vote_average',
    ]);
    // 影视分类 / 题材 / 发行年份 + Emby 原生：观看状态 / 收藏 / 剧集状态。
    expect(schema.dimensions.map((d) => d.key), <String>[
      'type',
      'genres',
      'decade',
      'watched',
      'favorite',
      'status',
    ]);
    expect(
      schema.dimensions.firstWhere((d) => d.key == 'favorite').kind,
      MediaFilterDimensionKind.favorite,
    );
    final status = schema.dimensions.firstWhere((d) => d.key == 'status');
    expect(status.kind, MediaFilterDimensionKind.seriesStatus);
    expect(status.options.map((o) => o.value), <String>['Continuing', 'Ended']);
    final type = schema.dimensions.firstWhere((d) => d.key == 'type');
    expect(type.kind, MediaFilterDimensionKind.mediaType);
    expect(type.options.map((o) => o.value), <String>['Movie', 'TV']);
    final genresDim = schema.dimensions.firstWhere((d) => d.key == 'genres');
    expect(genresDim.kind, MediaFilterDimensionKind.genre);
    expect(genresDim.options.map((o) => o.value), <String>['科幻', '动作']);
    final decade = schema.dimensions.firstWhere((d) => d.key == 'decade');
    expect(decade.kind, MediaFilterDimensionKind.decade);
    // 首项为当前年（Recent），随后是十年代 token（如 2020s）。
    expect(decade.options.first.value, 'Recent');
    expect(
      decade.options
          .skip(1)
          .every((o) => RegExp(r'^\d{4}s$').hasMatch(o.value)),
      isTrue,
    );
  });

  test('getCatalogFilterSchema：题材取数失败时仍保留影视分类/发行年份、不抛错', () async {
    final backend = EmbyMediaBackend(
      api: _ThrowingGenresApi(),
      connection: connection,
    );
    final schema = await backend.getCatalogFilterSchema('lib-1');
    // 题材取数失败只丢 genres 维度，其余维度仍在。
    expect(schema.dimensions.map((d) => d.key), <String>[
      'type',
      'decade',
      'watched',
      'favorite',
      'status',
    ]);
    expect(schema.sortOptions, isNotEmpty);
  });

  test('queryCatalogItems：观看/收藏/剧集状态 → Emby Filters/SeriesStatus', () async {
    final api = _FakeEmbyApi(pageItems: const [], pageTotal: 0);
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.queryCatalogItems(
      const MediaCatalogQuery(
        catalogId: 'lib-1',
        selection: <String, List<String>>{
          'watched': <String>['1'],
          'favorite': <String>['1'],
          'status': <String>['Continuing'],
        },
        page: 1,
        pageSize: 50,
      ),
    );
    final filters = api.lastPageFilters.split(',');
    expect(filters, containsAll(<String>['IsPlayed', 'IsFavorite']));
    expect(api.lastPageSeriesStatus, 'Continuing');
  });

  test('queryCatalogItems：decade 选择映射为 Emby Years（含展开十年代）', () async {
    final api = _FakeEmbyApi(pageItems: const [], pageTotal: 0);
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.queryCatalogItems(
      const MediaCatalogQuery(
        catalogId: 'lib-1',
        selection: <String, List<String>>{
          'decade': <String>['2010s'],
        },
        page: 1,
        pageSize: 50,
      ),
    );
    final years = api.lastPageYears.split(',');
    expect(years.first, '2010');
    expect(years.last, '2019');
    expect(years, hasLength(10));
  });

  test('getItemSourceVersions：getItem(MediaSources) → 版本列表', () async {
    final api = _FakeEmbyApi(
      item: <String, Object?>{
        'Id': 'm-1',
        'DateCreated': '2024-01-01T00:00:00Z',
        'MediaSources': <Object?>[
          <String, Object?>{
            'Id': 'src-1',
            'Path': '/movies/a.mkv',
            'Container': 'mkv',
            'MediaStreams': <Object?>[
              <String, Object?>{
                'Type': 'Video',
                'Index': 0,
                'Codec': 'hevc',
                'Width': 1920,
                'Height': 1080,
                'BitDepth': 10,
                'Profile': 'Main 10',
              },
              <String, Object?>{
                'Type': 'Audio',
                'Index': 1,
                'DisplayTitle': '国语',
                'Codec': 'eac3',
                'Channels': 6,
                'SampleRate': 48000,
              },
            ],
          },
        ],
      },
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final versions = await backend.getItemSourceVersions('m-1');
    expect(api.lastItemId, 'm-1');
    expect(versions, hasLength(1));
    expect(versions.first.id, 'src-1');
    expect(versions.first.label, '1080');
    expect(versions.first.audioTracks, hasLength(1));
    expect(versions.first.info.path, '/movies/a.mkv');
    // 逐字段明细（喂飞牛同款 MediaDetailOverlayPage）已随源信息带出。
    final videoFields = versions.first.info.videoStreams.first.fields;
    String fieldValue(MediaInfoFieldKey key) =>
        videoFields.firstWhere((f) => f.key == key).value;
    expect(fieldValue(MediaInfoFieldKey.encoder), 'HEVC');
    expect(fieldValue(MediaInfoFieldKey.profile), 'Main 10');
    expect(fieldValue(MediaInfoFieldKey.resolution), '1920 * 1080');
    expect(fieldValue(MediaInfoFieldKey.bitDepth), '10 bit');
    final audioFields = versions.first.info.audioStreams.first.fields;
    expect(
      audioFields.firstWhere((f) => f.key == MediaInfoFieldKey.channels).value,
      '6 ch',
    );
  });

  Map<String, Object?> playbackItem() => <String, Object?>{
    'Id': 'item-5',
    'Name': '测试电影',
    'Type': 'Movie',
    'RunTimeTicks': 72000000000, // 7200s
    'ProviderIds': <String, Object?>{'Tmdb': '12345'},
    'UserData': <String, Object?>{
      'PlaybackPositionTicks': 6000000000, // 600s
      'Played': false,
    },
    'MediaSources': <Object?>[
      <String, Object?>{
        'Id': 'src-1',
        'Container': 'mkv',
        'DefaultAudioStreamIndex': 1,
        'DefaultSubtitleStreamIndex': 3,
        'MediaStreams': <Object?>[
          <String, Object?>{
            'Type': 'Video',
            'Index': 0,
            'Codec': 'hevc',
            'Width': 1920,
            'Height': 1080,
            'BitDepth': 10,
          },
          <String, Object?>{
            'Type': 'Audio',
            'Index': 1,
            'Codec': 'eac3',
            'Language': 'eng',
            'DisplayTitle': 'English',
          },
          <String, Object?>{'Type': 'Audio', 'Index': 2, 'Codec': 'aac'},
          <String, Object?>{
            'Type': 'Subtitle',
            'Index': 3,
            'Codec': 'subrip',
            'DisplayTitle': '简中',
            'IsExternal': false,
          },
        ],
      },
    ],
  };

  test('getPlayback：直链直播 bundle + 默认轨 + 续播位 + Emby 上下文', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(item: playbackItem()),
      connection: connection,
    );
    final resolution = await backend.getPlayback(
      const MediaPlaybackRequest(itemId: 'item-5'),
    );
    final bundle = resolution.bundle;
    expect(bundle.itemId, 'item-5');
    expect(bundle.title, '测试电影');
    expect(bundle.tmdbId, '12345');
    expect(bundle.durationSeconds, 7200);
    // 续播位取 UserData.PlaybackPositionTicks（600s）。
    expect(bundle.startPosition, const Duration(seconds: 600));

    final source = bundle.selectedSource;
    expect(source.delivery, MediaPlaybackDeliveryKind.directLink);
    expect(source.id, 'src-1');
    expect(source.width, 1920);
    // 直链含 stream.mkv + MediaSourceId + api_key。
    expect(source.url, contains('/Videos/item-5/stream.mkv'));
    expect(source.url, contains('MediaSourceId=src-1'));
    // 直连地址（非 fnos）不带 entry-token cookie。
    expect(source.headers.containsKey('Cookie'), isFalse);

    expect(bundle.selectedAudioTrack?.id, '1');
    expect(bundle.selectedSubtitleTrack?.id, '3');
    expect(bundle.audioTracks, hasLength(2));
    expect(bundle.subtitleTracks, hasLength(1));
    expect(resolution.backendContext, isA<EmbyPlaybackContext>());
  });

  test('getPlayback：fnos 中转域注入 entry-token cookie', () async {
    const fnosConnection = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://embyserver.geqian688.fnos.net',
      userId: 'user-1',
      accessToken: 'tok',
      entryToken: 'ENTRY-123',
    );
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(item: playbackItem()),
      connection: fnosConnection,
    );
    final resolution = await backend.getPlayback(
      const MediaPlaybackRequest(itemId: 'item-5'),
    );
    expect(
      resolution.bundle.selectedSource.headers['Cookie'],
      contains('entry-token=ENTRY-123'),
    );
  });

  test('getPlayback：startFromBeginning 归零续播位', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(item: playbackItem()),
      connection: connection,
    );
    final resolution = await backend.getPlayback(
      const MediaPlaybackRequest(itemId: 'item-5', startFromBeginning: true),
    );
    expect(resolution.bundle.startPosition, Duration.zero);
  });

  test('getPlayback：无 MediaSources 抛错', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(item: <String, Object?>{'Id': 'item-5', 'Name': '空源'}),
      connection: connection,
    );
    await expectLater(
      backend.getPlayback(const MediaPlaybackRequest(itemId: 'item-5')),
      throwsStateError,
    );
  });

  test('reportPlaybackProgress：秒 → 100ns ticks 回写', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.reportPlaybackProgress(
      itemId: 'item-5',
      mediaSourceId: 'src-1',
      positionSeconds: 600,
      isPaused: true,
    );
    expect(api.lastProgressItemId, 'item-5');
    expect(api.lastProgressMediaSourceId, 'src-1');
    expect(api.lastProgressPositionTicks, 6000000000); // 600 * 1e7
    expect(api.lastProgressIsPaused, isTrue);
  });

  test('reportPlaybackProgress：负秒归零', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.reportPlaybackProgress(
      itemId: 'item-5',
      mediaSourceId: 'src-1',
      positionSeconds: -3,
    );
    expect(api.lastProgressPositionTicks, 0);
  });

  test('reportPlaybackStart/Stopped：秒 → ticks 透传', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    await backend.reportPlaybackStart(
      itemId: 'item-5',
      mediaSourceId: 'src-1',
      positionSeconds: 60,
    );
    await backend.reportPlaybackStopped(
      itemId: 'item-5',
      mediaSourceId: 'src-1',
      positionSeconds: 120,
    );
    expect(api.playSessionCalls, <String>['start:item-5', 'stopped:item-5']);
    expect(api.lastStartPositionTicks, 600000000);
    expect(api.lastStoppedPositionTicks, 1200000000);
  });

  test('resolveExternalSubtitleFile：解码 guid → 下载落临时文件', () async {
    final api = _FakeEmbyApi()
      ..subtitleText = '1\n00:00:01,000 --> 00:00:02,000\n你好\n';
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final path = await backend.resolveExternalSubtitleFile(
      'emby:sub:item-5:src-1:4',
      format: 'subrip',
    );
    expect(path, isNotNull);
    expect(api.lastSubtitleItemId, 'item-5');
    expect(api.lastSubtitleMediaSourceId, 'src-1');
    expect(api.lastSubtitleStreamIndex, 4);
    // subrip 映射成 srt 扩展名。
    expect(api.lastSubtitleFormat, 'srt');
    expect(path!.endsWith('.srt'), isTrue);
    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), api.subtitleText);
    await file.delete();
  });

  test('resolveExternalSubtitleFile：非外挂 guid 返回 null（不下载）', () async {
    final api = _FakeEmbyApi();
    final backend = EmbyMediaBackend(api: api, connection: connection);
    expect(await backend.resolveExternalSubtitleFile('3'), isNull);
    expect(api.lastSubtitleItemId, isNull);
  });

  test('resolveExternalSubtitleFile：空字幕文本返回 null', () async {
    final api = _FakeEmbyApi()..subtitleText = '   ';
    final backend = EmbyMediaBackend(api: api, connection: connection);
    expect(
      await backend.resolveExternalSubtitleFile('emby:sub:item-5:src-1:4'),
      isNull,
    );
  });

  test('resolveSeriesPlaybackTarget：有进度的集优先续看', () async {
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1), _season('s2', 2)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[
          _ep('s1e1', watched: true),
          _ep('s1e2', resume: 300),
          _ep('s1e3'),
        ],
        's2': <MediaEpisodeSummary>[_ep('s2e1')],
      },
    );
    expect(await backend.resolveSeriesPlaybackTarget('series-1'), 's1e2');
  });

  test('resolveSeriesPlaybackTarget：无进度 → 首个未看', () async {
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[
          _ep('s1e1', watched: true),
          _ep('s1e2', watched: true),
          _ep('s1e3'),
        ],
      },
    );
    expect(await backend.resolveSeriesPlaybackTarget('series-1'), 's1e3');
  });

  test('resolveSeriesNextUpEpisode：返回含季/集号的摘要（供按键文案）', () async {
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[
          _ep('s1e1', season: 1, episode: 1, watched: true),
          _ep('s1e2', season: 1, episode: 3, resume: 300),
        ],
      },
    );
    final ep = await backend.resolveSeriesNextUpEpisode('series-1');
    expect(ep?.id, 's1e2');
    expect(ep?.seasonNumber, 1);
    expect(ep?.episodeNumber, 3);
  });

  test('resolveSeriesPlaybackTarget：全看完 → 首集；无季 → 空', () async {
    final allWatched = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[
          _ep('s1e1', watched: true),
          _ep('s1e2', watched: true),
        ],
      },
    );
    expect(await allWatched.resolveSeriesPlaybackTarget('series-1'), 's1e1');
    final noSeasons = _SeriesTargetBackend(
      const <MediaSeasonSummary>[],
      const <String, List<MediaEpisodeSummary>>{},
    );
    expect(await noSeasons.resolveSeriesPlaybackTarget('series-1'), '');
  });

  test('resolveSeriesNextUpEpisode：NextUp 命中 → 直接用首条，不扫季', () async {
    final api = _FakeEmbyApi(
      nextUpItems: <Map<String, Object?>>[
        <String, Object?>{
          'Id': 's3e5',
          'Name': '第五集',
          'ParentIndexNumber': 3,
          'IndexNumber': 5,
        },
      ],
    );
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1), _season('s2', 2)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[_ep('s1e1')],
        's2': <MediaEpisodeSummary>[_ep('s2e1')],
      },
      api: api,
    );
    final ep = await backend.resolveSeriesNextUpEpisode('series-1');
    expect(ep?.id, 's3e5');
    expect(ep?.seasonNumber, 3);
    expect(ep?.episodeNumber, 5);
    expect(api.lastNextUpSeriesId, 'series-1');
    expect(api.lastNextUpLimit, 1);
    // 快路径命中即返回：一次逐季往返都不该发生。
    expect(backend.seasonsCalls, 0);
    expect(backend.episodeCalls, isEmpty);
  });

  test('resolveSeriesNextUpEpisode：NextUp 抛错 → 吞掉并回退逐季扫描', () async {
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[_season('s1', 1)],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[_ep('s1e1', watched: true), _ep('s1e2')],
      },
      api: _ThrowingNextUpApi(),
    );
    expect((await backend.resolveSeriesNextUpEpisode('series-1'))?.id, 's1e2');
    expect(backend.seasonsCalls, 1);
    expect(backend.episodeCalls, <String>['s1']);
  });

  test('resolveSeriesNextUpEpisode：NextUp 空结果 → 首个未看即停，不再拉后续季', () async {
    final api = _FakeEmbyApi();
    final backend = _SeriesTargetBackend(
      <MediaSeasonSummary>[
        _season('s1', 1),
        _season('s2', 2),
        _season('s3', 3),
      ],
      <String, List<MediaEpisodeSummary>>{
        's1': <MediaEpisodeSummary>[_ep('s1e1', watched: true), _ep('s1e2')],
        's2': <MediaEpisodeSummary>[_ep('s2e1')],
        's3': <MediaEpisodeSummary>[_ep('s3e1')],
      },
      api: api,
    );
    expect((await backend.resolveSeriesNextUpEpisode('series-1'))?.id, 's1e2');
    expect(api.nextUpCalls, 1);
    // 首季即命中首个未看 → s2/s3 不该被拉取。
    expect(backend.episodeCalls, <String>['s1']);
  });
}

MediaSeasonSummary _season(String id, int number) => MediaSeasonSummary(
  id: id,
  title: '',
  seasonNumber: number,
  primaryImage: MediaImageRef.empty,
);

MediaEpisodeSummary _ep(
  String id, {
  bool watched = false,
  int resume = 0,
  int season = 1,
  int episode = 1,
}) => MediaEpisodeSummary(
  id: id,
  title: id,
  seasonNumber: season,
  episodeNumber: episode,
  primaryImage: MediaImageRef.empty,
  watched: watched,
  resumePositionSeconds: resume,
);

/// 覆写中立季/集查询返回 fixture，钉住 resolveSeriesPlaybackTarget 的续看/首集选取逻辑
/// （不触 api/mapper）。
class _SeriesTargetBackend extends EmbyMediaBackend {
  _SeriesTargetBackend(
    this.seasonsFixture,
    this.episodesBySeason, {
    EmbyApi? api,
  }) : super(
         api: api ?? _FakeEmbyApi(),
         connection: const MediaBackendConnection(
           kind: MediaBackendKind.emby,
           serverUrl: 'https://emby.example.test',
           userId: 'user-1',
           accessToken: 'tok',
         ),
       );

  final List<MediaSeasonSummary> seasonsFixture;
  final Map<String, List<MediaEpisodeSummary>> episodesBySeason;
  // 逐季扫描的往返计数：钉「NextUp 命中不扫季」「首个未看即停」两条省往返断言。
  int seasonsCalls = 0;
  final List<String> episodeCalls = <String>[];

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) async {
    seasonsCalls++;
    return seasonsFixture;
  }

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) async {
    episodeCalls.add(seasonId);
    return episodesBySeason[seasonId] ?? const <MediaEpisodeSummary>[];
  }
}

/// NextUp 端点不可用（网络/版本缺失）的桩：验证异常被吞、起播回退逐季扫描。
class _ThrowingNextUpApi extends _FakeEmbyApi {
  @override
  Future<List<Map<String, Object?>>> getNextUpEpisodes({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String seriesId = '',
    int limit = 1,
    String fields = 'Overview,UserData,MediaStreams',
  }) async {
    throw StateError('next up endpoint unavailable');
  }
}

class _ThrowingGenresApi extends _FakeEmbyApi {
  @override
  Future<List<Map<String, Object?>>> getGenres({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    String includeItemTypes = '',
  }) async {
    throw StateError('genres endpoint unavailable');
  }
}
