import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/play_stats/native_play_stats_recorder.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Binding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final playB in [false, true]) {
    test(
      'A offline packet is retried after switching to B (playing=$playB) without changing active playback or fetching media tokens',
      () async {
        SharedPreferences.setMockInitialValues({
          'fly.used_bindings.instance|alice': ['a', 'b'],
        });
        SecureCredentialStore.setBackendForTesting(
          MemorySecureCredentialBackend(),
        );
        final temp = await Directory.systemTemp.createTemp('fly_multi_sync_');
        await databaseFactory.setDatabasesPath(temp.path);
        final nas = NasProvider(),
            backend = BackendSessionProvider(autoLoad: false);
        await nas.reloadSettingsForTesting();
        final stats = PlayStatsService.instance;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final packets = <String>[];
        final paths = <String>[];
        var online = false;
        server.listen((request) async {
          final bytes = await utf8.decoder.bind(request).join();
          final body = bytes.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(bytes) as Map;
          final path = request.uri.path;
          paths.add(path);
          final response = switch (path) {
            '/api/v1/system/identity' => {'service_instance_id': 'instance'},
            '/api/v1/me' => {
              'service_instance_id': 'instance',
              'user': {'id': 'alice'},
            },
            '/api/v1/bindings' => {
              'items': [
                {'id': 'a', 'revision': 2, 'status': 'unbound'},
                {'id': 'b', 'revision': 1, 'status': 'active'},
              ],
            },
            '/api/v1/servers' => {'items': []},
            '/api/v1/sync/streams' => {'id': body['id']},
            '/api/v1/sync/datasets' =>
              request.method == 'GET' ? {'items': []} : body,
            '/api/v1/sync/batches' => {
              'status': 'applied',
              'snapshot_seq': body['snapshot_seq'],
              'applied_at_ms': 1,
            },
            _ => <String, dynamic>{},
          };
          if (path == '/api/v1/sync/batches') {
            packets.add(bytes);
            if (!online) request.response.statusCode = 503;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        final service =
            FlyDataService(
                database: stats.database,
                drainWrites: stats.drainForManualSync,
              )
              ..session = FlyDataSession(
                serverUrl: 'http://127.0.0.1:${server.port}',
                userId: 'alice',
                username: 'alice',
                deviceId: 'd',
                deviceName: 'd',
                token: 'fly',
                installationId: 'i',
                serviceInstanceId: 'instance',
              );
        final account = FlyAccountController(
          nas: nas,
          backendSession: backend,
          service: service,
          autoLoad: false,
        )..activeBindingId = 'b';
        final recorder = NativePlayStatsRecorder();
        try {
          await stats.bindMediaBinding(
            accountKey: 'instance|alice',
            bindingId: 'a',
            backendKind: 'emby',
          );
          await (await stats.database.rawDatabase).insert('play_history', {
            'history_id': 'a-fact',
            'video_id': '1',
            'anime_id': '',
            'season_id': '',
            'started_at_ms': 1,
            'ended_at_ms': 2,
            'watched_ms': 1,
          });
          await expectLater(service.syncNow(), throwsStateError);
          final pendingA = packets.single;
          await stats.bindMediaBinding(
            accountKey: 'instance|alice',
            bindingId: 'b',
            backendKind: 'emby',
          );
          final activeScope = stats.currentScope;
          final activeDb = await stats.database.rawDatabase;
          if (playB) {
            await recorder.onLaunch({
              'itemGuid': '1',
              'statsScope': activeScope,
              'durationSeconds': 100,
            });
            await recorder.onProgress({
              'itemGuid': '1',
              'statsScope': activeScope,
              'ts': 0,
              'duration': 100,
            });
            await recorder.onProgress({
              'itemGuid': '1',
              'statsScope': activeScope,
              'ts': 1,
              'duration': 100,
            });
          }
          online = true;
          await account.backgroundRefresh();
          expect(packets.where((p) => p == pendingA), hasLength(2));
          expect(packets, hasLength(playB ? 3 : 2));
          expect(stats.currentScope, activeScope);
          expect(await stats.database.rawDatabase, same(activeDb));
          expect(paths.where((p) => p.endsWith('/device-access')), isEmpty);
          if (playB) {
            await recorder.onProgress({
              'itemGuid': '1',
              'statsScope': activeScope,
              'ts': 2,
              'duration': 100,
            });
            await stats.drainForManualSync();
            expect(
              (await activeDb.query('play_history')).single['watched_ms'],
              2000,
            );
          } else {
            expect(await activeDb.query('play_history'), isEmpty);
          }
        } finally {
          recorder.dispose();
          account.dispose();
          nas.dispose();
          backend.dispose();
          await stats.bindOwnerScope('closed-multi');
          await server.close(force: true);
          await temp.delete(recursive: true);
        }
      },
    );
  }
}
