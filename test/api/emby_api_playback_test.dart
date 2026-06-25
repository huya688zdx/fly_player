import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/emby_api.dart';

void main() {
  // buildStreamUrl 是纯字符串构造（不发请求），用任意 Dio 即可。
  final api = EmbyApi(dio: Dio(BaseOptions()));

  test('buildStreamUrl 拼 Static=true + MediaSourceId + api_key', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test/',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      accessToken: 'tok',
    );
    final uri = Uri.parse(url);
    expect(uri.host, 'emby.example.test');
    expect(uri.path, '/Videos/item-9/stream');
    expect(uri.queryParameters['Static'], 'true');
    expect(uri.queryParameters['MediaSourceId'], 'src-3');
    expect(uri.queryParameters['api_key'], 'tok');
  });

  test('buildStreamUrl 带 container 时路径拼成 stream.<container>', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      accessToken: 'tok',
      container: 'mkv',
    );
    expect(Uri.parse(url).path, '/Videos/item-9/stream.mkv');
  });

  test('buildStreamUrl 空 mediaSourceId 时省略该参数', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test',
      itemId: 'item-9',
      mediaSourceId: '',
      accessToken: 'tok',
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters.containsKey('MediaSourceId'), isFalse);
    expect(uri.queryParameters['Static'], 'true');
    expect(uri.queryParameters['api_key'], 'tok');
  });

  test(
    'reportPlaybackProgress POST /Sessions/Playing/Progress + PositionTicks',
    () async {
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return const _JsonResponse(<String, Object?>{});
      });
      final progressApi = EmbyApi(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      await progressApi.reportPlaybackProgress(
        serverUrl: 'https://emby.example.test/',
        userId: 'user-1',
        accessToken: 'tok',
        itemId: 'item-9',
        mediaSourceId: 'src-3',
        positionTicks: 6000000000, // 600s
        isPaused: true,
      );

      expect(captured.method, 'POST');
      expect(captured.uri.path, '/Sessions/Playing/Progress');
      expect(captured.uri.queryParameters['api_key'], 'tok');
      final body = captured.data as Map<String, Object?>;
      expect(body['ItemId'], 'item-9');
      expect(body['MediaSourceId'], 'src-3');
      expect(body['PositionTicks'], 6000000000);
      expect(body['IsPaused'], true);
    },
  );

  test('reportPlaybackProgress 负位置归零、空源省略', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{});
    });
    final progressApi = EmbyApi(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
    );

    await progressApi.reportPlaybackProgress(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      itemId: 'item-9',
      mediaSourceId: '',
      positionTicks: -5,
    );

    final body = captured.data as Map<String, Object?>;
    expect(body['PositionTicks'], 0);
    expect(body.containsKey('MediaSourceId'), isFalse);
  });
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
