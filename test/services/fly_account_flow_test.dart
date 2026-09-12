import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _OfflineService extends FlyDataService {
  _OfflineService()
    : super(
        database: PlayStatsService.instance.database,
        drainWrites: () async {},
      );
  @override
  Future<void> restoreSession() async {}
  @override
  Future<void> switchAddress(String url) async => throw StateError('offline');
}

void main() {
  _Binding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final kind in ['emby', 'feiniu']) {
    test(
      '$kind web bindings isolate access, reject wrong media identity and remove invalid credentials',
      () async {
        SharedPreferences.setMockInitialValues({});
        SecureCredentialStore.setBackendForTesting(
          MemorySecureCredentialBackend(),
        );
        final temp = await Directory.systemTemp.createTemp('fly_accounts_');
        await databaseFactory.setDatabasesPath(temp.path);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final root = 'http://127.0.0.1:${server.port}';
        final mediaServer = {
          'id': 'server',
          'kind': kind,
          'remote_server_id': 'media-instance',
          'name': 'Emby',
          'addresses': [
            {'purpose': 'client_remote', 'base_url': root, 'priority': 0},
          ],
        };
        final bindings = [
          for (final id in ['one', 'two'])
            {
              'id': id,
              'server_id': 'server',
              'server': mediaServer,
              'label': id,
              'remote_user_id': id,
              'remote_username': id,
              'status': 'active',
              'revision': 1,
            },
        ];
        var mediaIdentity = 'media-instance';
        server.listen((request) async {
          final text = await utf8.decoder.bind(request).join();
          final body = text.isEmpty ? {} : jsonDecode(text) as Map;
          Object response;
          if (request.uri.path == '/System/Info/Public' ||
              request.uri.path == '/v/api/v1/server/info') {
            expect(request.headers.value('Authorization'), isNull);
            expect(request.headers.value('X-Emby-Token'), isNull);
            response = kind == 'feiniu'
                ? {
                    'code': 0,
                    'data': {'guid': mediaIdentity},
                  }
                : {'Id': mediaIdentity};
          } else if (request.uri.path.endsWith('/system/identity')) {
            expect(request.headers.value('Authorization'), isNull);
            response = {'service_instance_id': 'instance'};
          } else if (request.uri.path.endsWith('/auth/login')) {
            response = {
              'service_instance_id': 'instance',
              'access_token': 'fly-token',
              'user': {'id': 'alice', 'username': 'alice', 'role': 'admin'},
              'device': {'id': 'device', 'name': 'device'},
            };
          } else if (request.uri.path.endsWith('/me')) {
            response = {
              'service_instance_id': 'instance',
              'user': {'id': 'alice'},
            };
          } else if (request.uri.path.endsWith('/bindings')) {
            response = {'items': bindings};
          } else if (request.uri.path.endsWith('/servers')) {
            response = {
              'items': [mediaServer],
            };
          } else if (request.uri.path.endsWith('/device-access')) {
            final id = request.uri.path.split('/')[4];
            expect(body['expected_revision'], 1);
            response = {
              'binding_id': id,
              'binding_revision': 1,
              'server': mediaServer,
              'remote_user_id': id,
              'remote_username': id,
              'access_token': 'media-$id',
            };
          } else {
            response = {};
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        final nas = NasProvider(),
            backend = BackendSessionProvider(autoLoad: false);
        await nas.reloadSettingsForTesting();
        final stats = PlayStatsService.instance;
        final service = FlyDataService(
          database: stats.database,
          drainWrites: stats.drainForManualSync,
        );
        final account = FlyAccountController(
          nas: nas,
          backendSession: backend,
          service: service,
          autoLoad: false,
        );
        try {
          await account.login(
            url: root,
            username: 'alice',
            password: 'password',
            deviceName: 'device',
          );
          expect(account.bindings, hasLength(2));
          mediaIdentity = 'wrong';
          await expectLater(
            account.activate(account.bindings[0]),
            throwsStateError,
          );
          expect(account.activeBindingId, isEmpty);
          expect(backend.isConfigured, isFalse);
          mediaIdentity = 'media-instance';
          await account.activate(account.bindings[0]);
          final firstScope = stats.currentScope;
          await account.activate(account.bindings[1]);
          expect(stats.currentScope, isNot(firstScope));
          expect(backend.currentConnection!.accessToken, 'media-two');
          expect(
            (await MediaBackendConnectionStore.load()).connections.where(
              (e) => e.bindingId.isNotEmpty,
            ),
            hasLength(2),
          );
          bindings[0]['status'] = 'unbound';
          await account.refresh();
          expect(backend.currentConnection!.accessToken, 'media-two');
          expect(
            (await MediaBackendConnectionStore.load()).connections.where(
              (e) => e.bindingId == 'one',
            ),
            isEmpty,
          );
          if (kind == 'feiniu') {
            expect(nas.token, 'media-two');
            bindings[1]['status'] = 'unbound';
            await account.refresh();
            expect(nas.token, isEmpty);
            expect(nas.isConfigured, isFalse);
            expect(
              (await SecureCredentialStore.read('nas_session.token')).value,
              isEmpty,
            );
            await account.enterLegacyMode();
            expect(nas.isConfigured, isFalse);
          }
        } finally {
          account.dispose();
          nas.dispose();
          backend.dispose();
          await stats.bindOwnerScope('closed');
          await server.close(force: true);
          await temp.delete(recursive: true);
        }
      },
    );
  }
  test(
    'offline restore with missing current-account access clears foreign active backend',
    () async {
      SharedPreferences.setMockInitialValues({
        'fly.active.instance|bob': 'binding-b',
        'fly.bindings.instance|bob': jsonEncode([
          {'id': 'binding-b', 'status': 'active', 'revision': 1},
        ]),
      });
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      final temp = await Directory.systemTemp.createTemp(
        'fly_restore_missing_',
      );
      await databaseFactory.setDatabasesPath(temp.path);
      final nas = NasProvider(),
          backend = BackendSessionProvider(autoLoad: false);
      await nas.reloadSettingsForTesting();
      await backend.saveActive(
        const MediaBackendConnection(
          kind: MediaBackendKind.emby,
          serverUrl: 'https://a.example',
          accountKey: 'instance|alice',
          bindingId: 'binding-a',
          bindingRevision: 1,
          accessToken: 'alice-media',
        ),
      );
      final service = _OfflineService()
        ..session = FlyDataSession(
          serverUrl: 'https://fly.example',
          userId: 'bob',
          username: 'bob',
          deviceId: 'device',
          deviceName: 'device',
          token: 'bob-fly',
          installationId: 'install',
          serviceInstanceId: 'instance',
        );
      final account = FlyAccountController(
        nas: nas,
        backendSession: backend,
        service: service,
        autoLoad: false,
      );
      try {
        await account.restore();
        expect(account.ready, isTrue);
        expect(account.activeBindingId, isEmpty);
        expect(backend.isConfigured, isFalse);
        expect(backend.currentConnection?.accountKey, isNot('instance|alice'));
        expect(nas.isConfigured, isFalse);
      } finally {
        account.dispose();
        nas.dispose();
        backend.dispose();
        await PlayStatsService.instance.bindOwnerScope('closed-restore');
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'wrong instance receives no bearer and cannot replace the saved address',
    () async {
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String?>[];
      server.listen((request) async {
        received.add(request.headers.value('authorization'));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'service_instance_id': 'wrong'}));
        await request.response.close();
      });
      final service = FlyDataService(
        database: SqflitePlayStatsDatabase(),
        drainWrites: () async {},
      );
      service.session = FlyDataSession(
        serverUrl: 'https://saved.example',
        userId: 'alice',
        username: 'alice',
        deviceId: 'd',
        deviceName: 'd',
        token: 'never-send',
        installationId: 'install',
        serviceInstanceId: 'right',
      );
      try {
        await expectLater(
          service.switchAddress('http://127.0.0.1:${server.port}'),
          throwsStateError,
        );
        expect(received, [null]);
        expect(service.session!.serverUrl, 'https://saved.example');
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'P1 logout then login migrates confirmed owner and immutable pending bytes; verified alias keeps identity',
    () async {
      final secure = MemorySecureCredentialBackend();
      SecureCredentialStore.setBackendForTesting(secure);
      await SecureCredentialStore.write(
        'fly_data_service_installation_v1',
        'install',
      );
      final temp = await Directory.systemTemp.createTemp('fly_alias_');
      await databaseFactory.setDatabasesPath(temp.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final alias = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      void serve(HttpServer server) => server.listen((request) async {
        await request.drain<void>();
        final data = request.uri.path.endsWith('/system/identity')
            ? {'service_instance_id': 'same'}
            : request.uri.path.endsWith('/me')
            ? {
                'service_instance_id': 'same',
                'user': {'id': 'alice'},
              }
            : request.uri.path.endsWith('/auth/login')
            ? {
                'service_instance_id': 'same',
                'access_token': 'token',
                'user': {'id': 'alice', 'username': 'alice'},
                'device': {'id': 'd1', 'name': 'device'},
              }
            : <String, dynamic>{};
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      serve(server);
      serve(alias);
      final url = 'http://127.0.0.1:${server.port}';
      final database = SqflitePlayStatsDatabase();
      final db = await database.rawDatabase;
      const pending = '{ "packet": "keep exact bytes" }';
      await db.insert('fly_sync_state', {
        'account_key': '$url|alice',
        'installation_id': 'install:d1',
        'stream_id': 'stream',
        'next_seq': 2,
        'pending_json': pending,
      });
      await db.update('fly_datasets', {'confirmed_account': '$url|alice'});
      final service = FlyDataService(
        database: database,
        drainWrites: () async {},
      );
      service.session = FlyDataSession(
        serverUrl: url,
        userId: 'alice',
        username: 'alice',
        deviceId: 'd1',
        deviceName: 'device',
        token: 'old-token',
        installationId: 'install',
      );
      try {
        await service.logout();
        await service.login(
          serverUrl: url,
          username: 'alice',
          password: 'pw',
          deviceName: 'device',
        );
        expect(service.session!.accountKey, 'same|alice');
        var state = (await db.query('fly_sync_state')).single;
        expect(state['account_key'], 'same|alice');
        expect(state['pending_json'], pending);
        expect(state['next_seq'], 2);
        expect(
          (await db.query(
            'fly_datasets',
          )).every((r) => r['confirmed_account'] == 'same|alice'),
          isTrue,
        );
        await service.switchAddress('http://127.0.0.1:${alias.port}');
        state = (await db.query('fly_sync_state')).single;
        expect(service.session!.accountKey, 'same|alice');
        expect(state['pending_json'], pending);
      } finally {
        await database.bindOwnerScope('closed');
        await server.close(force: true);
        await alias.close(force: true);
        await temp.delete(recursive: true);
      }
    },
  );
}
