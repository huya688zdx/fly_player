import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/settings/danmaku_saved_source_store.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/native_danmaku_prefetch.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _NasServer server;
  var originalCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await _NasServer.start();
    final session = FlyDataSession(
      serverUrl: 'http://127.0.0.1:${server.port}',
      userId: 'viewer',
      username: 'viewer',
      deviceId: 'device',
      deviceName: 'test',
      token: 'synthetic',
      installationId: 'installation',
      serviceInstanceId: 'service',
    );
    FlyDataService.instance.session = session;
    await PlayStatsService.instance.bindOwnerScope(
      PlayStatsService.scopeForBinding(session.accountKey, 'binding'),
    );
    (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
        .bindingReference = {
      'binding_id': 'binding',
    };
    directory = await Directory.systemTemp.createTemp('manual_nas_budget_');
    NativeDanmakuPrefetch.cacheRootOverrideForTest = directory.path;
    originalCalls = 0;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = () async {
      originalCalls++;
      return false;
    };
  });

  tearDown(() async {
    await server.close();
    NativeDanmakuPrefetch.cacheRootOverrideForTest = null;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = null;
    FlyDataService.instance.session = null;
    await PlayStatsService.instance.bindOwnerScope('');
    await directory.delete(recursive: true);
  });

  Future<String?> manual({bool Function()? current}) =>
      NativeDanmakuPrefetch.resolveNasToFile(
        seriesTitle: 'series',
        seasonNumber: 1,
        episodeNumber: 2,
        tmdbId: '',
        itemGuid: 'episode',
        mediaGuid: 'file',
        statsScope: PlayStatsService.instance.currentScope,
        settings: DanmakuSettings.defaults,
        isCurrent: current,
      );

  test(
    'manual default budget accepts a payload after the startup deadline',
    () async {
      final result = manual();
      await server.payloadRequested.future;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      server.releasePayload();

      final path = await result;
      expect(path, isNotNull);
      final payload = jsonDecode(await File(path!).readAsString()) as Map;
      expect(payload['sourceKey'], 'nas:match:1:version');
      expect(payload['commentsCompact'], hasLength(1));
      expect(originalCalls, 0);
      expect(server.requests, [
        'GET /api/v1/danmaku/resolve',
        'GET /api/v1/danmaku/matches/match/payload',
      ]);
    },
  );

  test('自动起播短预算结束后交给播放后查找并丢弃迟到缓存', () async {
    final elapsed = Stopwatch()..start();
    final result = NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: 'series',
      seasonNumber: 1,
      episodeNumber: 2,
      tmdbId: '',
      itemGuid: 'episode',
      mediaGuid: 'file',
      statsScope: PlayStatsService.instance.currentScope,
      settings: DanmakuSettings.defaults.copyWith(
        sourceStrategy: DanmakuSourceStrategy.nasPreferred,
      ),
      store: DanmakuSavedSourceStore(
        directoryPath: '${directory.path}/sources',
      ),
    );
    await server.payloadRequested.future;
    expect(await result, isNull);
    expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(1100));
    expect(elapsed.elapsedMilliseconds, lessThan(5000));
    expect(originalCalls, 0);

    server.releasePayload();
    await server.payloadFinished.future;
    expect(directory.listSync().whereType<File>(), isEmpty);
    expect(originalCalls, 0);
  });

  test(
    'manual delayed payload is discarded after the account changes',
    () async {
      final result = manual();
      await server.payloadRequested.future;
      FlyDataService.instance.session = FlyDataSession.fromJson({
        ...FlyDataService.instance.session!.toJson(),
        'token': 'replacement',
      });
      server.releasePayload();
      expect(await result, isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
      expect(originalCalls, 0);
    },
  );

  test(
    'manual delayed payload is discarded after the media becomes stale',
    () async {
      var current = true;
      final result = manual(current: () => current);
      await server.payloadRequested.future;
      current = false;
      server.releasePayload();
      expect(await result, isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
      expect(originalCalls, 0);
    },
  );
}

class _NasServer {
  _NasServer(this._server) {
    _server.listen((request) => _pending.add(_handle(request)));
  }

  final HttpServer _server;
  final requests = <String>[];
  final _pending = <Future<void>>[];
  final payloadRequested = Completer<void>();
  final payloadFinished = Completer<void>();
  final _payloadGate = Completer<void>();
  int get port => _server.port;

  static Future<_NasServer> start() async =>
      _NasServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  void releasePayload() {
    if (!_payloadGate.isCompleted) _payloadGate.complete();
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri.path}');
    final payload = request.uri.path.endsWith('/payload');
    try {
      if (payload) {
        payloadRequested.complete();
        await _payloadGate.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          payload
              ? {
                  'match_id': 'match',
                  'revision': 1,
                  'version_key': 'version',
                  'items': [
                    {
                      'time_ms': 1000,
                      'color': 0xffffff,
                      'text': 'comment',
                      'mode': 1,
                    },
                  ],
                }
              : {
                  'status': 'ready',
                  'match_id': 'match',
                  'revision': 1,
                  'version_key': 'version',
                  'payload_url':
                      '/api/v1/danmaku/matches/match/payload?revision=1',
                },
        ),
      );
      await request.response.close();
    } on SocketException {
      // A timed-out client may have closed the connection before this response.
    } on HttpException {
      // The automatic path must be allowed to cancel its late response.
    } finally {
      if (payload && !payloadFinished.isCompleted) payloadFinished.complete();
    }
  }

  Future<void> close() async {
    releasePayload();
    await _server.close(force: true);
    await Future.wait(_pending);
  }
}
