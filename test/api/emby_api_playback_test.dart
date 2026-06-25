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

  test(
    'reportPlaybackStart POST /Sessions/Playing + PlayMethod/CanSeek',
    () async {
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return const _JsonResponse(<String, Object?>{});
      });
      final api2 = EmbyApi(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );
      await api2.reportPlaybackStart(
        serverUrl: 'https://emby.example.test',
        userId: 'user-1',
        accessToken: 'tok',
        itemId: 'item-9',
        mediaSourceId: 'src-3',
        positionTicks: 6000000000,
      );
      expect(captured.method, 'POST');
      expect(captured.uri.path, '/Sessions/Playing');
      final body = captured.data as Map<String, Object?>;
      expect(body['ItemId'], 'item-9');
      expect(body['MediaSourceId'], 'src-3');
      expect(body['PositionTicks'], 6000000000);
      expect(body['PlayMethod'], 'DirectStream');
      expect(body['CanSeek'], true);
      // PlaybackStart 不带 Progress 专属字段。
      expect(body.containsKey('EventName'), isFalse);
    },
  );

  test('reportPlaybackStopped POST /Sessions/Playing/Stopped', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{});
    });
    final api2 = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);
    await api2.reportPlaybackStopped(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      positionTicks: 1200000000,
    );
    expect(captured.uri.path, '/Sessions/Playing/Stopped');
    final body = captured.data as Map<String, Object?>;
    expect(body['PositionTicks'], 1200000000);
    expect(body['PlayMethod'], 'DirectStream');
  });

  test('reportPlaybackProgress 带 PlayMethod/CanSeek + EventName', () async {
    late RequestOptions captured;
    final adapter = _FakeDioAdapter((options) {
      captured = options;
      return const _JsonResponse(<String, Object?>{});
    });
    final api2 = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);
    await api2.reportPlaybackProgress(
      serverUrl: 'https://emby.example.test',
      userId: 'user-1',
      accessToken: 'tok',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      positionTicks: 6000000000,
    );
    final body = captured.data as Map<String, Object?>;
    expect(body['PlayMethod'], 'DirectStream');
    expect(body['CanSeek'], true);
    expect(body['EventName'], 'TimeUpdate');
  });

  test('buildSubtitleUrl 拼 /Subtitles/{index}/Stream.<ext> + api_key', () {
    final url = api.buildSubtitleUrl(
      serverUrl: 'https://emby.example.test/',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      streamIndex: 4,
      accessToken: 'tok',
      format: 'ass',
    );
    final uri = Uri.parse(url);
    expect(uri.path, '/Videos/item-9/src-3/Subtitles/4/Stream.ass');
    expect(uri.queryParameters['api_key'], 'tok');
  });

  test('downloadSubtitleText 经 dio 取字幕全文（plain）', () async {
    late RequestOptions captured;
    const subtitleText = '1\n00:00:01,000 --> 00:00:02,000\n你好\n';
    final adapter = _TextDioAdapter((options) {
      captured = options;
      return subtitleText;
    });
    final subApi = EmbyApi(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
    );

    final text = await subApi.downloadSubtitleText(
      serverUrl: 'https://emby.example.test',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      streamIndex: 4,
      accessToken: 'tok',
      format: 'srt',
    );
    expect(text, subtitleText);
    expect(captured.uri.path, '/Videos/item-9/src-3/Subtitles/4/Stream.srt');
  });
}

class _TextDioAdapter implements HttpClientAdapter {
  _TextDioAdapter(this.handler);

  final String Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(handler(options), 200);
  }

  @override
  void close({bool force = false}) {}
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
