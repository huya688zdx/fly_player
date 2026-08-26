import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只覆写 getItems，记录最近一次调用参数，供断言排序/过滤/字段口径。
class _LatestCaptureApi extends EmbyApi {
  String lastSortBy = '';
  String lastSortOrder = '';
  String lastIncludeItemTypes = '';
  bool lastRecursive = false;
  int? lastLimit;
  String lastFields = '';

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
    lastSortBy = sortBy;
    lastSortOrder = sortOrder;
    lastIncludeItemTypes = includeItemTypes;
    lastRecursive = recursive;
    lastLimit = limit;
    lastFields = fields;
    return <Map<String, Object?>>[
      <String, Object?>{'Id': 'a', 'Name': 'A', 'Type': 'Movie'},
    ];
  }
}

/// 只覆写 getItemsPage，记录最近一次 payload，供断言排序字段/全局查询口径；
/// [shouldThrow] 模拟服务端失败，验证行降级隐藏。
class _LatestFeiniuApi extends FeiniuApi {
  _LatestFeiniuApi(super.nasProvider);

  Map<String, dynamic>? lastPayload;
  bool shouldThrow = false;

  @override
  Future<ItemListPage> getItemsPage(Map<String, dynamic> payload) async {
    lastPayload = payload;
    if (shouldThrow) throw Exception('boom');
    return ItemListPage(
      items: <MediaLibraryItem>[_libraryItem(guid: 'a')],
      total: 1,
    );
  }
}

MediaLibraryItem _libraryItem({required String guid}) {
  return MediaLibraryItem(
    guid: guid,
    title: '条目',
    tvTitle: '',
    type: 'Movie',
    poster: '',
    releaseDate: '',
    firstAirDate: '',
    lastAirDate: '',
    voteAverage: '',
    overview: '',
    watched: 0,
    watchedTs: 0,
    ts: 0,
    duration: 0,
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmbyMediaBackend.getLatestItems', () {
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
    );

    test('按 DateCreated 倒序拉取 Movie,Series，字段含 Overview', () async {
      final api = _LatestCaptureApi();
      final backend = EmbyMediaBackend(api: api, connection: connection);

      final items = await backend.getLatestItems(limit: 12);

      expect(api.lastSortBy, 'DateCreated');
      expect(api.lastSortOrder, 'Descending');
      expect(api.lastIncludeItemTypes, 'Movie,Series');
      expect(api.lastRecursive, isTrue);
      expect(api.lastLimit, 12);
      expect(api.lastFields, contains('Overview'));
      expect(items, hasLength(1));
      expect(items.first.id, 'a');
    });
  });

  group('FeiniuMediaBackend.getLatestItems', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

    test('按 create_time DESC 全局查询（不带 ancestor_guid）', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final api = _LatestFeiniuApi(nas);
      final backend = FeiniuMediaBackend(api);

      final items = await backend.getLatestItems(limit: 15);

      final payload = api.lastPayload!;
      expect(payload['sort_column'], 'create_time');
      expect(payload['sort_type'], 'DESC');
      expect(payload['page_size'], 15);
      // 全局查询：不带 ancestor_guid（否则会被限定到某个目录下）。
      expect(payload.containsKey('ancestor_guid'), isFalse);
      expect((payload['tags'] as Map)['type'], const <String>['Movie', 'TV']);
      expect(items, hasLength(1));
      expect(items.first.id, 'a');
    });

    test('请求失败返回空列表（行降级隐藏）', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final api = _LatestFeiniuApi(nas)..shouldThrow = true;
      final backend = FeiniuMediaBackend(api);

      final items = await backend.getLatestItems(limit: 15);

      expect(items, isEmpty);
    });
  });
}
