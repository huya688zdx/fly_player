import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _CountingCredentials extends MemorySecureCredentialBackend {
  int writes = 0;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }
}

class _DeferredResponse {
  final arrived = Completer<void>();
  final release = Completer<void>();
}

class _Fixture {
  final credentials = _CountingCredentials();
  final database = SqflitePlayStatsDatabase();
  final deferred = <String, _DeferredResponse>{};
  final servers = <HttpServer>[];
  final received = <String, List<String?>>{};
  late Directory temp;
  late String url;
  late FlyDataService service;
  String instance = 'instance';
  String user = 'alice';
  String loginToken = 'new-token';

  static final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
  );

  Future<void> open() async {
    temp = await Directory.systemTemp.createTemp('fly_session_refresh_');
    await databaseFactory.setDatabasesPath(temp.path);
    SecureCredentialStore.setBackendForTesting(credentials);
    await SecureCredentialStore.write(
      'fly_data_service_installation_v1',
      'installation',
    );
    credentials.writes = 0;
    url = await addServer();
    service = FlyDataService(database: database, drainWrites: () async {})
      ..session = session();
  }

  FlyDataSession session({
    String instanceId = 'instance',
    List<String>? addresses,
  }) => FlyDataSession(
    serverUrl: url,
    userId: 'alice',
    username: 'alice',
    deviceId: 'device',
    deviceName: 'device',
    token: 'old-token',
    installationId: 'installation',
    serviceInstanceId: instanceId,
    addresses: addresses ?? [url],
  );

  Future<String> addServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    server.listen((request) async {
      final path = request.uri.path;
      received
          .putIfAbsent(path, () => [])
          .add(request.headers.value(HttpHeaders.authorizationHeader));
      await request.drain<void>();
      final gate = deferred[path];
      if (gate != null) {
        gate.arrived.complete();
        await gate.release.future;
      }
      if (path.endsWith('/image')) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      } else {
        request.response.headers.contentType = ContentType.json;
        final Object body = switch (path) {
          '/api/v1/system/identity' => {'service_instance_id': instance},
          '/api/v1/me' => {
            'service_instance_id': instance,
            'user': {'id': user},
          },
          '/api/v1/auth/login' => {
            'service_instance_id': instance,
            'access_token': loginToken,
            'user': {'id': user, 'username': user},
            'device': {'id': 'device', 'name': 'device'},
          },
          _ => {'status': 'ok'},
        };
        request.response.write(jsonEncode(body));
      }
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  _DeferredResponse hold(String path) => deferred[path] = _DeferredResponse();

  Future<void> close() async {
    for (final gate in deferred.values) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
    for (final server in servers) {
      await server.close(force: true);
    }
    await database.bindOwnerScope('closed');
    expect(temp.parent.path, Directory.systemTemp.path);
    await temp.delete(recursive: true);
  }
}

void main() {
  _Binding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late _Fixture fixture;

  setUp(() async {
    fixture = _Fixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  for (final image in [true, false]) {
    test(
      'same-address verification preserves an in-flight ${image ? 'image' : 'JSON request'} without rewriting credentials',
      () async {
        final previous = fixture.service.session;
        final path = image ? '/api/v1/media/held/image' : '/api/v1/delayed';
        final gate = fixture.hold(path);
        final pending = image
            ? expectLater(
                fixture.service.imageBytes('held'),
                completion(orderedEquals(_Fixture.png)),
              )
            : expectLater(
                fixture.service.request('/delayed'),
                completion({'status': 'ok'}),
              );
        await gate.arrived.future;
        await fixture.service.switchAddress(fixture.url);
        gate.release.complete();
        await pending;

        expect(fixture.service.session, same(previous));
        expect(fixture.credentials.writes, 0);
        expect(fixture.received['/api/v1/system/identity'], [null]);
        expect(fixture.received['/api/v1/me'], ['Bearer old-token']);
        expect(fixture.received[path], ['Bearer old-token']);
      },
    );
  }

  for (final change in ['address', 'account', 'token', 'logout']) {
    test('$change change still rejects the previous in-flight image', () async {
      final previous = fixture.service.session;
      final gate = fixture.hold('/api/v1/media/held/image');
      final rejected = expectLater(
        fixture.service.imageBytes('held'),
        throwsStateError,
      );
      await gate.arrived.future;
      switch (change) {
        case 'address':
          final alias = await fixture.addServer();
          await fixture.service.switchAddress(alias);
          expect(fixture.service.session!.serverUrl, alias);
        case 'account':
        case 'token':
          if (change == 'account') fixture.user = 'bob';
          await fixture.service.login(
            serverUrl: fixture.url,
            username: fixture.user,
            password: 'synthetic-password',
            deviceName: 'device',
          );
          expect(fixture.service.session!.userId, fixture.user);
          expect(fixture.service.session!.token, 'new-token');
        case 'logout':
          await fixture.service.logout();
          expect(fixture.service.session, isNull);
      }
      gate.release.complete();
      await rejected;
      expect(fixture.service.session, isNot(same(previous)));
    });
  }

  for (final invalid in ['instance', 'user']) {
    test(
      'unchanged address still rejects a different verified $invalid',
      () async {
        final previous = fixture.service.session;
        if (invalid == 'instance') {
          fixture.instance = 'other-instance';
        } else {
          fixture.user = 'bob';
        }
        await expectLater(
          fixture.service.switchAddress(fixture.url),
          throwsStateError,
        );
        expect(fixture.service.session, same(previous));
        expect(fixture.credentials.writes, 0);
        expect(fixture.received['/api/v1/system/identity'], [null]);
        expect(
          fixture.received['/api/v1/me'],
          invalid == 'instance' ? isNull : ['Bearer old-token'],
        );
      },
    );
  }

  test(
    'legacy same-address verification migrates and replaces the session',
    () async {
      fixture.service.session = fixture.session(instanceId: '');
      final previous = fixture.service.session;
      await expectLater(fixture.service.imageBytes('held'), throwsStateError);
      expect(fixture.received['/api/v1/media/held/image'], isNull);
      final db = await fixture.database.rawDatabase;
      await db.insert('fly_sync_state', {
        'account_key': '${fixture.url}|alice',
        'installation_id': 'installation:device',
        'stream_id': 'stream',
        'next_seq': 1,
      });
      await fixture.service.switchAddress(fixture.url);
      expect(fixture.service.session, isNot(same(previous)));
      expect(fixture.service.session!.accountKey, 'instance|alice');
      expect(
        (await db.query('fly_sync_state')).single['account_key'],
        'instance|alice',
      );
      expect(fixture.credentials.writes, 1);
    },
  );

  test(
    'same-address verification persists a newly completed address set',
    () async {
      fixture.service.session = fixture.session(addresses: []);
      final previous = fixture.service.session;
      final gate = fixture.hold('/api/v1/media/held/image');
      final rejected = expectLater(
        fixture.service.imageBytes('held'),
        throwsStateError,
      );
      await gate.arrived.future;
      await fixture.service.switchAddress(fixture.url);
      gate.release.complete();
      await rejected;
      expect(fixture.service.session, isNot(same(previous)));
      expect(fixture.service.session!.addresses, [fixture.url]);
      expect(fixture.credentials.writes, 1);
      final current = fixture.service.session;
      await fixture.service.switchAddress(fixture.url);
      expect(fixture.service.session, same(current));
      expect(fixture.credentials.writes, 1);
    },
  );
}
