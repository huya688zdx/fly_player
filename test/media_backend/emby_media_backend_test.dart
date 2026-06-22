import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';

class _FakeEmbyApi extends EmbyApi {
  _FakeEmbyApi({this.views = const [], this.items = const []});

  final List<Map<String, Object?>> views;
  final List<Map<String, Object?>> items;
  String? lastParentId;
  bool lastIsResumable = false;
  bool lastRecursive = false;
  String lastIncludeItemTypes = '';

  @override
  Future<List<Map<String, Object?>>> getUserViews({
    required String serverUrl,
    required String userId,
    required String accessToken,
  }) async => views;

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

  test('getContinueWatching：isResumable 过滤', () async {
    final api = _FakeEmbyApi(
      items: <Map<String, Object?>>[
        <String, Object?>{'Id': 'r-1', 'Name': '续播', 'Type': 'Movie'},
      ],
    );
    final backend = EmbyMediaBackend(api: api, connection: connection);
    final items = await backend.getContinueWatching();
    expect(api.lastIsResumable, isTrue);
    expect(items, hasLength(1));
  });

  test('getHomeSummary：首光阶段返回空 map', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(),
      connection: connection,
    );
    expect(await backend.getHomeSummary(), isEmpty);
  });

  test('未实现方法一律 throw UnsupportedError', () async {
    final backend = EmbyMediaBackend(
      api: _FakeEmbyApi(),
      connection: connection,
    );
    await expectLater(backend.searchItems('x'), throwsUnsupportedError);
    await expectLater(backend.getItemDetail('x'), throwsUnsupportedError);
    await expectLater(backend.getItemSeasons('x'), throwsUnsupportedError);
    await expectLater(backend.getSeasonEpisodes('x'), throwsUnsupportedError);
    await expectLater(
      backend.getCatalogFilterSchema('x'),
      throwsUnsupportedError,
    );
  });
}
