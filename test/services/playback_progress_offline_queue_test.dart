import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/playback_progress_offline_queue.dart';
import 'package:fly_player/utils/app_exception.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/native_reentry_support.dart';

class _LocalNas implements NasProvider {
  _LocalNas(this.baseUrl);
  @override
  final String baseUrl;
  @override
  bool get isConfigured => true;
  @override
  String get token => 'test-token';
  @override
  String get accessCode => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('飞牛无视频轨 GUID 仍上报，恢复联网后新进度替换旧记录', (tester) async {
    await tester.runAsync(() async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      var status = 200;
      server.listen((request) async {
        expect(request.uri.path, '/v/api/v1/play/record');
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"code":0,"data":{}}');
        await request.response.close();
      });
      try {
        final nas = _LocalNas('http://127.0.0.1:${server.port}');
        Map<String, dynamic> progress(int ts) => {
          'itemGuid': 'item',
          'mediaGuid': 'media',
          'ts': ts,
          'duration': 300,
        };
        await PlaybackProgressOfflineQueue.enqueue(progress(90));
        await Future.wait([
          NativeReentrySupport.recordProgress(nas, progress(120)),
          NativeReentrySupport.recordProgress(nas, progress(125)),
        ]);
        expect(requests.map((p) => p['ts']), [120, 125]);
        expect(requests.first.containsKey('video_guid'), isFalse);
        status = 503;
        await NativeReentrySupport.recordProgress(nas, progress(150));
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('playback_progress_offline_queue_v1'),
          isNotNull,
        );
        status = 200;
        await NativeReentrySupport.recordProgress(nas, progress(160));
        expect(requests.map((p) => p['ts']), [120, 125, 150, 160]);
        expect(prefs.getString('playback_progress_offline_queue_v1'), isNull);
      } finally {
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    });
  });

  test('服务器进度重放成功后删除队列项', () async {
    await PlaybackProgressOfflineQueue.enqueueServer(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      positionSeconds: 42,
    );

    Map<String, Object?>? captured;
    await PlaybackProgressOfflineQueue.flushServer((progress) async {
      captured = progress;
    });

    expect(captured, <String, Object?>{
      'itemId': 'item-1',
      'mediaSourceId': 'source-1',
      'positionSeconds': 42,
      'isPaused': false,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('playback_server_progress_offline_queue_v1'),
      isNull,
    );
  });

  test('服务器进度 transient 重放失败时保留队列项', () async {
    await PlaybackProgressOfflineQueue.enqueueServer(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      positionSeconds: 42,
    );

    await PlaybackProgressOfflineQueue.flushServer((_) async {
      throw const AppException(
        kind: AppExceptionKind.transient,
        action: 'test',
        message: 'temporary failure',
      );
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('playback_server_progress_offline_queue_v1'),
      isNotNull,
    );
  });
}
