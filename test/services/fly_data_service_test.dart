import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  _NetworkTestBinding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'service URL rejects embedded credentials and redirects are not followed',
    () {
      expect(normalizeServerUrl('http://nas:8787/'), 'http://nas:8787');
      expect(
        normalizeServerUrl('https://test.fnos.net/app/fly-data-service/'),
        'https://test.fnos.net/app/fly-data-service',
      );
      expect(
        () => normalizeServerUrl('https://test.fnos.net/app/other'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUrl('http://user:password@nas:8787'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUrl('http://nas:8787/?token=x'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUrl('file:///database'),
        throwsFormatException,
      );
    },
  );

  test('FN 入口凭据仅发送到所选应用，授权页和跨源请求可安全失败', () async {
    const url = 'https://test.fnos.net/app/fly-data-service';
    final dio = Dio();
    final api = FlyDataApi(
      url,
      token: 'fly-token',
      fnEntryToken: 'entry-fixture',
      dio: dio,
    );
    final sent = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          sent.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: request.path == '/me'
                  ? {'user': 'fixture'}
                  : '<html>FN Connect</html>',
            ),
          );
        },
      ),
    );
    try {
      await api.get('/me');
      expect(sent.single.uri.toString(), '$url/api/v1/me');
      expect(sent.single.headers['Cookie'], 'entry-token=entry-fixture');
      expect(sent.single.headers['Authorization'], 'Bearer fly-token');
      expect(sent.single.followRedirects, isFalse);
      await expectLater(
        api.get('/system/identity'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            '授权提示',
            flyFnAccessMessage,
          ),
        ),
      );
      for (final path in [
        'https://other.fnos.net/app/fly-data-service/api/v1/me',
        'https://test.fnos.net/api/v1/me',
        '/../../other',
      ]) {
        await expectLater(api.get(path), throwsStateError);
      }
      expect(sent, hasLength(2));
    } finally {
      api.close();
    }
  });

  test(
    'real HTTP failure retains original bytes; snapshot drains writes and releases its transaction before HTTP',
    () async {
      final directory = await Directory.systemTemp.createTemp('fly_http_test_');
      await databaseFactory.setDatabasesPath(directory.path);
      final database = SqflitePlayStatsDatabase();
      final db = await database.rawDatabase;
      final secure = MemorySecureCredentialBackend();
      SecureCredentialStore.setBackendForTesting(secure);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final packets = <String>[];
      final installations = <String>[];
      final datasets = <Map<String, dynamic>>[];
      var drained = false;
      var identityChecked = false;
      server.listen((request) async {
        try {
          final bytes = await utf8.decoder.bind(request).join();
          final body = bytes.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(bytes) as Map<String, dynamic>;
          Map<String, dynamic> response;
          switch (request.uri.path.replaceFirst('/app/fly-data-service', '')) {
            case '/api/v1/system/identity':
              expect(request.headers.value('authorization'), isNull);
              identityChecked = true;
              response = {'service_instance_id': 'instance-test'};
            case '/api/v1/auth/login':
              expect(identityChecked, isTrue);
              installations.add(body['installation_id'] as String);
              response = {
                'service_instance_id': 'instance-test',
                'user': {'id': 'u1', 'username': 'test'},
                'device': {'id': 'd1', 'name': 'test device'},
                'access_token': 'test-session',
              };
            case '/api/v1/sync/streams':
              response = {'id': body['id'], 'last_applied_seq': 0};
            case '/api/v1/sync/datasets':
              if (request.method == 'POST') datasets.add(body);
              response = request.method == 'GET'
                  ? {'items': datasets, 'next_cursor': null}
                  : body;
            case '/api/v1/sync/batches':
              packets.add(bytes);
              expect(drained, isTrue);
              // This write would deadlock if snapshot still held its transaction.
              await db
                  .update('play_history', {'watched_ms': 50})
                  .timeout(const Duration(seconds: 5));
              if (packets.length == 1) {
                request.response.statusCode = 503;
                response = {
                  'error': {'code': 'temporarily_unavailable'},
                };
              } else {
                response = {
                  'id': 'receipt',
                  'status': 'applied',
                  'snapshot_seq': body['snapshot_seq'],
                  'applied_at_ms': 123,
                };
              }
            default:
              request.response.statusCode = 404;
              response = {
                'error': {'code': 'unknown_path'},
              };
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        } catch (error) {
          request.response.statusCode = 500;
          await request.response.close();
          rethrow;
        }
      });
      final service = FlyDataService(
        database: database,
        drainWrites: () async {
          if (!drained) {
            await db.insert('play_history', {
              'history_id': 'history_old',
              'video_id': 'v',
              'anime_id': '',
              'season_id': '',
              'started_at_ms': 1,
              'ended_at_ms': 100,
              'watched_ms': 10,
            });
          }
          drained = true;
        },
      );
      try {
        final url = 'http://127.0.0.1:${server.port}';
        await service.login(
          serverUrl: url,
          username: 'test',
          password: 'test-only-password',
          deviceName: 'test device',
        );
        final account = service.session!.accountKey;
        await service.confirmCurrentScope();
        await expectLater(service.syncNow(), throwsStateError);
        final pending = (await service.store.state(account))!['pending_json'];
        expect(pending, packets.single);
        await service.syncNow();
        expect(packets, hasLength(2));
        expect(packets[1], packets[0]);
        expect((await service.store.state(account))!['pending_json'], isNull);
        final restored = FlyDataService(
          database: database,
          drainWrites: () async {},
        );
        await restored.restoreSession();
        expect(
          restored.session!.installationId,
          service.session!.installationId,
        );
        await restored.login(
          serverUrl: '$url/app/fly-data-service/',
          username: 'test',
          password: 'test-only-password',
          deviceName: 'test device',
        );
        expect(installations.toSet(), hasLength(1));
        final reopened = FlyDataService(
          database: database,
          drainWrites: () async {},
        );
        await reopened.restoreSession();
        expect(reopened.session!.serverUrl, '$url/app/fly-data-service');
        final saved = await secure.read('fly_data_service_session_v1');
        expect(saved.value, isNot(contains('test-only-password')));
        await restored.syncNow();
        final latest = jsonDecode(packets.last) as Map;
        expect(latest['snapshot_seq'], 2);
        expect(latest['records'][0]['legacy_payload']['watched_ms'], 50);
        // This test server rejects logout. The local token must still be removed.
        await expectLater(restored.logout(), throwsStateError);
        expect(restored.session, isNull);
        expect(
          (await secure.read('fly_data_service_session_v1')).status,
          SecureCredentialReadStatus.missing,
        );
      } finally {
        await server.close(force: true);
        await db.close();
        await directory.delete(recursive: true);
        SecureCredentialStore.resetBackendForTesting();
      }
    },
  );
}

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}
