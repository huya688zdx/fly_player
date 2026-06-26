import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/emby_api.dart';

void main() {
  test('normalizes server URL without backend-specific fields', () {
    expect(
      EmbyApi.normalizeServerUrl(' emby.example.test/ '),
      'http://emby.example.test',
    );
    expect(
      EmbyApi.normalizeServerUrl('https://emby.example.test///'),
      'https://emby.example.test',
    );
  });

  test('strips Emby web client path / hash route from pasted URL', () {
    // 从浏览器复制的 Emby 网页地址（含 fnos 中转域名）应还原成 API 根地址。
    expect(
      EmbyApi.normalizeServerUrl(
        'https://embyserver4-9.geqian688.fnos.net/web/index.html',
      ),
      'https://embyserver4-9.geqian688.fnos.net',
    );
    expect(
      EmbyApi.normalizeServerUrl(
        'https://emby.example.test/web/index.html#!/home',
      ),
      'https://emby.example.test',
    );
    expect(
      EmbyApi.normalizeServerUrl('https://emby.example.test/web/'),
      'https://emby.example.test',
    );
    // 子路径反代部署（非 /web 客户端路径）应保持不动。
    expect(
      EmbyApi.normalizeServerUrl('https://host.example.test/emby/'),
      'https://host.example.test/emby',
    );
  });

  test('attaches entry-token cookie for .fnos.net hosts', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{'Items': <Object?>[]});
    });
    final api = EmbyApi(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      entryTokenProvider: () => 'entry-abc-123',
    );

    await api.getUserViews(
      serverUrl: 'https://embyserver4-9.geqian688.fnos.net/web/index.html',
      userId: 'user-1',
      accessToken: 'tok',
    );

    expect(captured.headers['Cookie'], contains('entry-token=entry-abc-123'));
  });

  test('does not attach entry-token cookie for direct hosts', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{'Items': <Object?>[]});
    });
    final api = EmbyApi(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      entryTokenProvider: () => 'entry-abc-123',
    );

    await api.getUserViews(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
    );

    expect(captured.headers.containsKey('Cookie'), isFalse);
  });

  test('omits entry-token cookie when provider returns empty', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{'Items': <Object?>[]});
    });
    final api = EmbyApi(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      entryTokenProvider: () => '',
    );

    await api.getUserViews(
      serverUrl: 'https://embyserver4-9.geqian688.fnos.net',
      userId: 'user-1',
      accessToken: 'tok',
    );

    expect(captured.headers.containsKey('Cookie'), isFalse);
  });

  test('loads public system info from normalized server URL', () async {
    final adapter = _FakeDioAdapter((options) {
      expect(options.method, 'GET');
      expect(
        options.uri.toString(),
        'https://emby.example.test/System/Info/Public',
      );
      return const _JsonResponse(<String, Object?>{
        'ServerName': 'Living Room',
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final info = await api.getPublicSystemInfo('https://emby.example.test/');

    expect(info.serverName, 'Living Room');
  });

  test('authenticates by name and keeps only session fields', () async {
    late RequestOptions capturedOptions;
    final adapter = _FakeDioAdapter((options) {
      capturedOptions = options;
      expect(options.method, 'POST');
      expect(
        options.uri.toString(),
        'https://emby.example.test/Users/AuthenticateByName',
      );
      expect(
        options.headers['X-Emby-Authorization'],
        contains('Client=Fly Player'),
      );
      expect(options.data, <String, Object?>{
        'Username': 'alice',
        'Pw': 'secret',
      });
      return const _JsonResponse(<String, Object?>{
        'AccessToken': 'emby-access-token',
        'User': <String, Object?>{'Id': 'user-id', 'Name': 'Alice'},
        'ServerName': 'Living Room',
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final result = await api.authenticateByName(
      serverUrl: 'https://emby.example.test/',
      userName: 'alice',
      password: 'secret',
    );

    expect(capturedOptions.contentType, Headers.jsonContentType);
    expect(result.serverUrl, 'https://emby.example.test');
    expect(result.serverName, 'Living Room');
    expect(result.accessToken, 'emby-access-token');
    expect(result.userId, 'user-id');
    expect(result.userName, 'Alice');
  });

  test('getUserViews 拼 /Users/{uid}/Views + api_key，解析 Items', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[
          <String, Object?>{
            'Id': 'lib-1',
            'Name': '电影',
            'CollectionType': 'movies',
          },
          <String, Object?>{
            'Id': 'lib-2',
            'Name': '剧集',
            'CollectionType': 'tvshows',
          },
        ],
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final views = await api.getUserViews(
      serverUrl: 'https://emby.example.test/',
      userId: 'user-1',
      accessToken: 'tok',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/Users/user-1/Views');
    expect(captured.uri.queryParameters['api_key'], 'tok');
    expect(views, hasLength(2));
    expect(views[0]['Id'], 'lib-1');
    expect(views[1]['CollectionType'], 'tvshows');
  });

  test('getItems 带 ParentId/Limit/Fields 查询，解析 Items', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[
          <String, Object?>{'Id': 'item-1', 'Name': '影片甲', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 1,
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final items = await api.getItems(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      parentId: 'lib-1',
      limit: 20,
      fields: 'Overview,PrimaryImageAspectRatio',
    );

    expect(captured.uri.path, '/Users/user-1/Items');
    expect(captured.uri.queryParameters['api_key'], 'tok');
    expect(captured.uri.queryParameters['ParentId'], 'lib-1');
    expect(captured.uri.queryParameters['Limit'], '20');
    expect(
      captured.uri.queryParameters['Fields'],
      'Overview,PrimaryImageAspectRatio',
    );
    expect(items, hasLength(1));
    expect(items[0]['Id'], 'item-1');
  });

  test('getItems 继续观看：isResumable → Filters=IsResumable', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{'Items': <Object?>[]});
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final items = await api.getItems(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      isResumable: true,
      recursive: true,
      limit: 12,
    );

    expect(captured.uri.queryParameters['Filters'], 'IsResumable');
    expect(captured.uri.queryParameters['Recursive'], 'true');
    expect(items, isEmpty);
  });

  test('getItemCount：Limit=0 + IncludeItemTypes，取 TotalRecordCount', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[],
        'TotalRecordCount': 34,
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final count = await api.getItemCount(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      includeItemTypes: 'Movie',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/Users/user-1/Items');
    expect(captured.uri.queryParameters['api_key'], 'tok');
    expect(captured.uri.queryParameters['Limit'], '0');
    expect(captured.uri.queryParameters['Recursive'], 'true');
    expect(captured.uri.queryParameters['IncludeItemTypes'], 'Movie');
    expect(count, 34);
  });

  test('getItemCount：favoritesOnly → Filters=IsFavorite', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{'TotalRecordCount': 5});
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final count = await api.getItemCount(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      favoritesOnly: true,
      includeItemTypes: 'Movie,Series',
    );

    expect(captured.uri.queryParameters['Filters'], 'IsFavorite');
    expect(captured.uri.queryParameters['IncludeItemTypes'], 'Movie,Series');
    expect(count, 5);
  });

  test(
    'getItem 拼 /Users/{uid}/Items/{id} + api_key/Fields，返回单条目 Map',
    () async {
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return const _JsonResponse(<String, Object?>{
          'Id': 'item-9',
          'Name': '银翼杀手 2049',
          'Type': 'Movie',
          'Overview': '简介文本',
          'Genres': <Object?>['科幻'],
        });
      });
      final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final item = await api.getItem(
        serverUrl: 'https://emby.example.test/',
        userId: 'user-1',
        accessToken: 'tok',
        itemId: 'item-9',
      );

      expect(captured.method, 'GET');
      expect(captured.uri.path, '/Users/user-1/Items/item-9');
      expect(captured.uri.queryParameters['api_key'], 'tok');
      expect(captured.uri.queryParameters['Fields'], contains('People'));
      expect(item['Id'], 'item-9');
      expect(item['Name'], '银翼杀手 2049');
      expect(item['Genres'], <Object?>['科幻']);
    },
  );
  test(
    'getSeasons 拼 /Shows/{id}/Seasons + UserId/api_key/Fields，解析 Items',
    () async {
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return const _JsonResponse(<String, Object?>{
          'Items': <Object?>[
            <String, Object?>{
              'Id': 'season-1',
              'Name': '第 1 季',
              'IndexNumber': 1,
              'ChildCount': 12,
            },
            <String, Object?>{
              'Id': 'season-2',
              'Name': '第 2 季',
              'IndexNumber': 2,
            },
          ],
        });
      });
      final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final seasons = await api.getSeasons(
        serverUrl: 'https://emby.example.test/',
        userId: 'user-1',
        accessToken: 'tok',
        seriesId: 'series-9',
      );

      expect(captured.method, 'GET');
      expect(captured.uri.path, '/Shows/series-9/Seasons');
      expect(captured.uri.queryParameters['api_key'], 'tok');
      expect(captured.uri.queryParameters['UserId'], 'user-1');
      expect(captured.uri.queryParameters['Fields'], 'ItemCounts,UserData');
      expect(seasons, hasLength(2));
      expect(seasons[0]['Id'], 'season-1');
      expect(seasons[1]['IndexNumber'], 2);
    },
  );
}

class _JsonResponse {
  const _JsonResponse(this.body);

  final Map<String, Object?> body;
}

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final _JsonResponse Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
