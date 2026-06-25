import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/emby/emby_playback_context.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
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
  });

  final List<Map<String, Object?>> views;
  final List<Map<String, Object?>> items;
  final Map<String, Object?> item;
  final List<Map<String, Object?>> seasons;
  final List<Map<String, Object?>> genres;
  final List<Map<String, Object?>> resumeItems;
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
  String lastPageSortBy = '';
  String lastPageSortOrder = '';
  String lastPageSearchTerm = '';
  String lastPagePersonIds = '';
  // getGenres 入参捕获。
  String? lastGenresParentId;
  String lastGenresIncludeItemTypes = '';
  // getResumeItems 入参捕获。
  int lastResumeLimit = 0;
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
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
    String searchTerm = '',
    String personIds = '',
  }) async {
    lastPageParentId = parentId;
    lastPageStartIndex = startIndex;
    lastPageLimit = limit;
    lastPageIncludeItemTypes = includeItemTypes;
    lastPageGenres = genres;
    lastPageSortBy = sortBy;
    lastPageSortOrder = sortOrder;
    lastPageSearchTerm = searchTerm;
    lastPagePersonIds = personIds;
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
    // 单集:Primary 本身横版剧照,保持不动。
    expect(items[1].primaryImage.url, contains('/Images/Primary?tag=ep1'));
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
    // 收藏计数走 IsFavorite + Movie,Series。
    expect(api.countIncludeItemTypes, contains('Movie,Series'));
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
      },
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final detail = await backend.getItemDetail('m-1');
    expect(api.lastItemId, 'm-1');
    expect(detail.id, 'm-1');
    expect(detail.title, '某电影');
    expect(detail.overview, '简介');
    expect(detail.genreLabels, <String>['科幻']);
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

  test('getCatalogFilterSchema：题材维度 + 四列排序', () async {
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
    expect(schema.dimensions, hasLength(1));
    expect(schema.dimensions.first.key, 'genres');
    expect(schema.dimensions.first.options.map((o) => o.value), <String>[
      '科幻',
      '动作',
    ]);
  });

  test('getCatalogFilterSchema：题材取数失败时退化为仅排序、不抛错', () async {
    final backend = EmbyMediaBackend(
      api: _ThrowingGenresApi(),
      connection: connection,
    );
    final schema = await backend.getCatalogFilterSchema('lib-1');
    expect(schema.dimensions, isEmpty);
    expect(schema.sortOptions, isNotEmpty);
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
              <String, Object?>{'Type': 'Video', 'Index': 0, 'Height': 1080},
              <String, Object?>{
                'Type': 'Audio',
                'Index': 1,
                'DisplayTitle': '国语',
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
    expect(versions.first.label, '1080p');
    expect(versions.first.audioTracks, hasLength(1));
    expect(versions.first.info.path, '/movies/a.mkv');
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
