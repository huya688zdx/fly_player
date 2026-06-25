import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/emby_api.dart';

void main() {
  test('getItemPage 拼 StartIndex/Limit/SortBy/Genres，解析 Items + 总数', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[
          <String, Object?>{'Id': 'm-1', 'Name': '片甲', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 87,
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final page = await api.getItemPage(
      serverUrl: 'https://emby.example.test/',
      userId: 'user-1',
      accessToken: 'tok',
      parentId: 'lib-1',
      startIndex: 100,
      limit: 50,
      includeItemTypes: 'Series',
      genres: '科幻|动作',
      sortBy: 'CommunityRating',
      sortOrder: 'Ascending',
      fields: 'Overview',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/Users/user-1/Items');
    expect(captured.uri.queryParameters['api_key'], 'tok');
    expect(captured.uri.queryParameters['ParentId'], 'lib-1');
    expect(captured.uri.queryParameters['StartIndex'], '100');
    expect(captured.uri.queryParameters['Limit'], '50');
    expect(captured.uri.queryParameters['Recursive'], 'true');
    expect(captured.uri.queryParameters['IncludeItemTypes'], 'Series');
    expect(captured.uri.queryParameters['Genres'], '科幻|动作');
    expect(captured.uri.queryParameters['SortBy'], 'CommunityRating');
    expect(captured.uri.queryParameters['SortOrder'], 'Ascending');
    expect(page.items, hasLength(1));
    expect(page.items[0]['Id'], 'm-1');
    expect(page.totalRecordCount, 87);
  });

  test('getItemPage：StartIndex=0 不下发；总数缺失时回退条目数', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[
          <String, Object?>{'Id': 'a'},
          <String, Object?>{'Id': 'b'},
        ],
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final page = await api.getItemPage(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
    );

    expect(captured.uri.queryParameters.containsKey('StartIndex'), isFalse);
    // TotalRecordCount 缺失 → 回退当前页条目数。
    expect(page.totalRecordCount, 2);
  });

  test('getItemPage：searchTerm → SearchTerm 查询参数', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[],
        'TotalRecordCount': 0,
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    await api.getItemPage(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      searchTerm: '银翼杀手',
      includeItemTypes: 'Movie,Series,Episode',
      limit: 60,
    );

    expect(captured.uri.path, '/Users/user-1/Items');
    expect(captured.uri.queryParameters['SearchTerm'], '银翼杀手');
    expect(
      captured.uri.queryParameters['IncludeItemTypes'],
      'Movie,Series,Episode',
    );
  });

  test('getItemPage：personIds → PersonIds 查询参数', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[],
        'TotalRecordCount': 0,
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    await api.getItemPage(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      personIds: 'pp-1',
      includeItemTypes: 'Movie,Series',
    );

    expect(captured.uri.queryParameters['PersonIds'], 'pp-1');
    expect(captured.uri.queryParameters['IncludeItemTypes'], 'Movie,Series');
  });

  test('getResumeItems 拼 /Items/Resume + MediaTypes=Video，解析 Items', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{
        'Items': <Object?>[
          <String, Object?>{'Id': 'r-1', 'Name': '续播', 'Type': 'Movie'},
        ],
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final items = await api.getResumeItems(
      serverUrl: 'https://emby.example.test/',
      userId: 'user-1',
      accessToken: 'tok',
      limit: 20,
      fields: 'Overview',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/Users/user-1/Items/Resume');
    expect(captured.uri.queryParameters['api_key'], 'tok');
    expect(captured.uri.queryParameters['Limit'], '20');
    expect(captured.uri.queryParameters['Recursive'], 'true');
    expect(captured.uri.queryParameters['MediaTypes'], 'Video');
    expect(items, hasLength(1));
    expect(items[0]['Id'], 'r-1');
  });

  test(
    'getGenres 拼 /Genres + UserId/ParentId/IncludeItemTypes，解析 Items',
    () async {
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return const _JsonResponse(<String, Object?>{
          'Items': <Object?>[
            <String, Object?>{'Id': 'g-1', 'Name': '科幻'},
            <String, Object?>{'Id': 'g-2', 'Name': '动作'},
          ],
        });
      });
      final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final genres = await api.getGenres(
        serverUrl: 'https://emby.example.test/',
        userId: 'user-1',
        accessToken: 'tok',
        parentId: 'lib-1',
        includeItemTypes: 'Movie,Series',
      );

      expect(captured.method, 'GET');
      expect(captured.uri.path, '/Genres');
      expect(captured.uri.queryParameters['api_key'], 'tok');
      expect(captured.uri.queryParameters['UserId'], 'user-1');
      expect(captured.uri.queryParameters['ParentId'], 'lib-1');
      expect(captured.uri.queryParameters['IncludeItemTypes'], 'Movie,Series');
      expect(captured.uri.queryParameters['Recursive'], 'true');
      expect(genres, hasLength(2));
      expect(genres[0]['Name'], '科幻');
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
