import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_media_identity.dart';
import 'package:fly_player/services/play_stats/fly_sync_identity.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Optional cross-language check against an isolated instance of the sibling
/// backend. Uses synthetic data only, never a real user's NAS or sample files.
void main() {
  _NetworkBinding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final python = Platform.environment['FLY_TEST_PYTHON'];
  final backend = Platform.environment['FLY_TEST_BACKEND'];
  test(
    'real P2 API binding/catalog/device access and P1 import/revision/deletion agree with Flutter transport',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fly_backend_client_',
      );
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final process = await Process.start(
        python!,
        [
          '-m',
          'uvicorn',
          'fly_data.main:app',
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '--log-level',
          'error',
        ],
        environment: {
          'PYTHONPATH': '${backend!}/backend',
          'FLY_DATA_DIR': '${directory.path}/service',
          'FLY_SETUP_TOKEN': 'synthetic-client-integration-setup',
          'FLY_COOKIE_SECURE': 'false',
        },
      );
      final stdoutSubscription = process.stdout.listen((_) {});
      final stderrSubscription = process.stderr.listen((_) {});
      await databaseFactory.setDatabasesPath('${directory.path}/client');
      final database = SqflitePlayStatsDatabase();
      final db = await database.rawDatabase;
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      final url = 'http://127.0.0.1:$port';
      final bootstrap = FlyDataApi(url);
      FlyDataApi? api;
      try {
        var ready = false;
        for (var attempt = 0; attempt < 100; attempt++) {
          try {
            await bootstrap.get('/setup/status');
            ready = true;
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        expect(ready, isTrue, reason: 'isolated Python API did not start');
        await bootstrap.post('/setup/admin', {
          'setup_token': 'synthetic-client-integration-setup',
          'username': 'clienttest',
          'password': 'Synthetic-Client-Password!',
          'display_name': 'Synthetic client',
          'timezone': 'Asia/Shanghai',
        });
        final service = FlyDataService(
          database: database,
          drainWrites: () async {},
        );
        await service.login(
          serverUrl: url,
          username: 'clienttest',
          password: 'Synthetic-Client-Password!',
          deviceName: 'Synthetic WIN',
        );
        api = FlyDataApi(url, token: service.session!.token);
        final bindingId = await _verifyRealBindingCatalog(api);
        await db.insert('play_history', {
          'history_id': 'history_synthetic_old',
          'video_id': 'v',
          'anime_id': '',
          'season_id': '',
          'title': 'Before enrichment',
          'started_at_ms': 1,
          'ended_at_ms': 100,
          'watched_ms': 10,
        });
        final legacy = (await db.query('play_history')).single;
        final preview = await api.post('/imports/play-history/preview', {
          'schema_version': 'fly-legacy/1',
          'source_key': 'synthetic/client-integration',
          'scope_label': 'Synthetic WIN / scope',
          'device_name': 'Synthetic WIN',
          'captured_at_ms': 100,
          'source_schema_version': 3,
          // Older logical JSON may encode SQLite REAL zero as integer zero.
          'records': [
            {...legacy, 'max_progress': 0},
          ],
          'metadata': <String, dynamic>{},
        });
        await api.post('/imports/play-history/${preview['id']}/commit', {
          'confirm_ownership': true,
        });
        await expectLater(service.confirmCurrentScope(), throwsStateError);
        final remote = (await service.remoteDatasets()).single;
        expect(await service.adopt(remote), 1);
        expect((await service.syncNow())['status'], 'applied');
        expect((await api.get('/stats/overview'))['session_count'], 1);
        await db.update('play_history', {
          'title': 'After enrichment',
          'watched_ms': 50,
        });
        expect((await service.syncNow())['status'], 'applied');
        expect((await api.get('/stats/overview'))['legacy_watched_ms'], 50);
        final newId = newFlySyncId();
        await db.insert('play_history', {
          ...legacy,
          'history_id': newId,
          'watched_ms': 20,
        });
        await db.update(
          'fly_record_provenance',
          {
            'envelope_json': jsonEncode({
              'source_ref': {
                'binding_id': bindingId,
                'backend_kind': 'emby',
                'remote_item_id': 'movie',
              },
            }),
          },
          where: 'history_id=?',
          whereArgs: [newId],
        );
        await service.confirmCurrentScope();
        expect((await service.syncNow())['status'], 'applied');
        expect((await api.get('/stats/overview'))['session_count'], 2);
        final history = await api.get('/history');
        final boundRecord = (history['items'] as List).singleWhere(
          (r) => r['origin_record_id'] == newId,
        );
        expect(
          (await api.get(
            '/history/${boundRecord['id']}',
          ))['source_ref']['binding_id'],
          bindingId,
        );
        final old = (history['items'] as List).singleWhere(
          (row) => row['origin_record_id'] == 'history_synthetic_old',
        );
        final deletion = Dio();
        await deletion.delete<dynamic>(
          '$url/api/v1/history/${old['id']}',
          options: Options(
            headers: {'Authorization': 'Bearer ${service.session!.token}'},
          ),
        );
        deletion.close(force: true);
        await db.update(
          'play_history',
          {'watched_ms': 60},
          where: 'history_id=?',
          whereArgs: ['history_synthetic_old'],
        );
        final receipt = await service.syncNow();
        expect(receipt['status'], 'applied');
        expect(receipt['counts']['tombstoned'], 1);
        expect((await api.get('/stats/overview'))['session_count'], 1);
        await db.delete(
          'play_history',
          where: 'history_id=?',
          whereArgs: [newId],
        );
        expect((await service.syncNow())['status'], 'applied');
        // Missing local rows intentionally do not delete server history.
        expect((await api.get('/stats/overview'))['legacy_watched_ms'], 20);
      } finally {
        bootstrap.close();
        api?.close();
        await db.close();
        process.kill();
        await process.exitCode;
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        await directory.delete(recursive: true);
        SecureCredentialStore.resetBackendForTesting();
      }
    },
    skip: python == null || backend == null,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<String> _verifyRealBindingCatalog(FlyDataApi api) async {
  final media = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final movie = {
    'Id': 'movie',
    'Name': 'Synthetic film',
    'Type': 'Movie',
    'Overview': 'Synthetic catalog detail',
    'ProductionYear': 2026,
    'ProviderIds': {'Tmdb': '123'},
    'MediaSources': [
      {
        'Id': 'version',
        'Name': '1080p',
        'RunTimeTicks': 1000000000,
        'Container': 'mkv',
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'h264', 'Width': 1920, 'Height': 1080},
        ],
      },
    ],
  };
  media.listen((request) async {
    await request.drain<void>();
    final path = request.uri.path;
    Object response;
    if (path == '/System/Info/Public') {
      expect(request.headers.value('X-Emby-Token'), isNull);
      response = {'Id': 'synthetic-media'};
    } else if (path == '/Users/AuthenticateByName') {
      response = {
        'User': {'Id': 'media-user', 'Name': 'media-alice'},
        'AccessToken': 'synthetic-media-token',
        'ServerId': 'synthetic-media',
      };
    } else {
      expect(request.headers.value('X-Emby-Token'), 'synthetic-media-token');
      response = switch (path) {
        '/Sessions' => [
          {
            'DeviceId': request.uri.queryParameters['DeviceId'],
            'UserId': 'media-user',
          },
        ],
        '/Users/media-user' => {'Id': 'media-user', 'Name': 'media-alice'},
        '/Users/media-user/Views' => {
          'Items': [
            {'Id': 'library'},
          ],
        },
        '/Users/media-user/Items' => {
          'Items': [movie],
          'TotalRecordCount': 1,
        },
        '/Users/media-user/Items/movie' => movie,
        _ => <String, dynamic>{},
      };
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  });
  final address = 'http://127.0.0.1:${media.port}';
  try {
    final server = await api.post('/servers', {
      'kind': 'emby',
      'name': 'Synthetic media',
      'addresses': [
        {'purpose': 'nas_api', 'base_url': address, 'priority': 0},
        {'purpose': 'client_lan', 'base_url': address, 'priority': 0},
      ],
    });
    final binding = await api.post('/bindings', {
      'server_id': server['id'],
      'label': 'Synthetic binding',
      'username': 'media-alice',
      'password': 'synthetic-only',
    });
    expect(binding.containsKey('access_token'), isFalse);
    final bindings = await api.get('/bindings');
    expect((bindings['items'] as List).single['id'], binding['id']);
    final access = await api.post('/bindings/${binding['id']}/device-access', {
      'expected_revision': binding['revision'],
    });
    expect(access['access_token'], 'synthetic-media-token');
    await verifyFlyMediaAddress(
      address: address,
      kind: 'emby',
      expectedId: access['server']['remote_server_id'] as String,
    );
    Map<String, dynamic>? finished;
    for (var attempt = 0; attempt < 200; attempt++) {
      final jobs = (await api.get('/jobs'))['items'] as List;
      if (jobs.isNotEmpty &&
          ['succeeded', 'failed', 'cancelled'].contains(jobs.first['status'])) {
        finished = Map<String, dynamic>.from(jobs.first as Map);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      finished?['status'],
      'succeeded',
      reason: 'synthetic catalog job: $finished',
    );
    final rows =
        (await api.get('/media', query: {'binding_id': binding['id']}))['items']
            as List;
    expect(rows.single['remote_item_id'], 'movie');
    final detail = await api.get('/media/${rows.single['id']}');
    expect(detail['overview'], 'Synthetic catalog detail');
    expect(detail['catalog_completeness'], 'confirmed');
    expect(
      detail['sources'].single['versions'].single['remote_media_source_id'],
      'version',
    );
    return binding['id'] as String;
  } finally {
    await media.close(force: true);
  }
}

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}
