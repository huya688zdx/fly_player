import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_login_history_store.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _Secure extends MemorySecureCredentialBackend {
  bool failHistoryWrite = false;
  bool failSessionWrite = false;
  @override
  Future<void> write(String key, String value) async {
    if ((failHistoryWrite && key.startsWith('fly_login_history.password.')) ||
        (failSessionWrite && key == 'fly_data_service_session_v1')) {
      throw StateError('synthetic storage failure');
    }
    await super.write(key, value);
  }
}

class _Fixture {
  late Directory directory;
  late SqflitePlayStatsDatabase database;
  late HttpServer server;
  late HttpServer alias;
  late FlyDataService service;
  final secure = _Secure();
  final paths = <String>[];
  final loginBodies = <Map<String, dynamic>>[];
  String instance = 'synthetic-instance';
  String? responseInstance;
  bool rejectLogin = false;
  bool rejectLogout = false;

  String get url => 'http://127.0.0.1:${server.port}';
  String get aliasUrl => 'http://127.0.0.1:${alias.port}';

  Future<void> open() async {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(secure);
    directory = await Directory.systemTemp.createTemp('fly_history_service_');
    await databaseFactory.setDatabasesPath(directory.path);
    database = SqflitePlayStatsDatabase();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    alias = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_respond);
    alias.listen(_respond);
    service = FlyDataService(database: database, drainWrites: () async {});
  }

  Future<void> _respond(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = raw.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    paths.add(request.uri.path);
    Map<String, dynamic> response;
    switch (request.uri.path) {
      case '/api/v1/system/identity':
        expect(request.headers.value('authorization'), isNull);
        response = {'service_instance_id': instance};
      case '/api/v1/auth/login':
        loginBodies.add(body);
        request.response.statusCode = rejectLogin ? 401 : 200;
        response = rejectLogin
            ? {
                'error': {'code': 'invalid_credentials'},
              }
            : {
                'service_instance_id': responseInstance ?? instance,
                'user': {'id': 'synthetic-user', 'username': 'alice'},
                'device': {
                  'id': 'synthetic-device',
                  'name': 'Server device name',
                },
                'access_token': 'synthetic-session-token',
              };
      case '/api/v1/me':
        response = {
          'service_instance_id': instance,
          'user': {'id': 'synthetic-user', 'username': 'alice'},
        };
      case '/api/v1/auth/logout':
        request.response.statusCode = rejectLogout ? 503 : 200;
        response = rejectLogout
            ? {
                'error': {'code': 'test_unavailable'},
              }
            : {};
      default:
        request.response.statusCode = 404;
        response = {};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  Future<void> login({bool remember = true, String? expected}) => service.login(
    serverUrl: url,
    username: ' alice ',
    password: 'synthetic-password',
    deviceName: 'Test device',
    rememberPassword: remember,
    expectedInstanceId: expected,
  );

  Future<void> close() async {
    await server.close(force: true);
    await alias.close(force: true);
    await (await database.rawDatabase).close();
    final absolute = directory.absolute.path.replaceAll('\\', '/');
    final parent = Directory.systemTemp.absolute.path.replaceAll('\\', '/');
    if (!absolute.startsWith('$parent/fly_history_service_')) {
      throw StateError('Test directory outside expected temporary directory');
    }
    await directory.delete(recursive: true);
    SecureCredentialStore.resetBackendForTesting();
  }
}

void main() {
  _NetworkBinding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  test(
    'successful login persists canonical account and remembered password',
    () async {
      await fixture.login(expected: 'synthetic-instance');
      final row = (await FlyLoginHistoryStore.load()).single;
      expect(row.username, 'alice');
      expect(row.deviceName, 'Server device name');
      expect(row.serverUrl, fixture.url);
      expect(row.serviceInstanceId, 'synthetic-instance');
      expect(row.updatedAtMillis, greaterThan(0));
      expect(row.password, 'synthetic-password');
      expect(fixture.service.loginHistoryWarning, isNull);
      final restored = FlyDataService(
        database: fixture.database,
        drainWrites: () async {},
      );
      await restored.restoreSession();
      expect(restored.session!.username, row.username);
    },
  );

  test('expected instance mismatch never sends login or password', () async {
    await expectLater(
      fixture.login(expected: 'different-instance'),
      throwsStateError,
    );
    expect(fixture.paths, ['/api/v1/system/identity']);
    expect(fixture.loginBodies, isEmpty);
    expect(await FlyLoginHistoryStore.load(), isEmpty);
    expect(fixture.service.session, isNull);
  });

  test('rejected authentication creates no history or session', () async {
    fixture.rejectLogin = true;
    await expectLater(fixture.login(), throwsStateError);
    expect(fixture.loginBodies, hasLength(1));
    expect(await FlyLoginHistoryStore.load(), isEmpty);
    expect(fixture.service.session, isNull);
  });

  test('identity changing in login response creates no history', () async {
    fixture.responseInstance = 'different-response-instance';
    await expectLater(fixture.login(), throwsStateError);
    expect(await FlyLoginHistoryStore.load(), isEmpty);
    expect(fixture.service.session, isNull);
  });

  test(
    'failed secure session save does not create a login history entry',
    () async {
      fixture.secure.failSessionWrite = true;
      await expectLater(fixture.login(), throwsStateError);
      expect(await FlyLoginHistoryStore.load(), isEmpty);
      expect(fixture.service.session, isNull);
    },
  );

  test(
    'history failure exposes warning without failing authenticated session',
    () async {
      fixture.secure.failHistoryWrite = true;
      await fixture.login();
      expect(fixture.service.session, isNotNull);
      expect(fixture.service.loginHistoryWarning, isNotEmpty);
      final restored = FlyDataService(
        database: fixture.database,
        drainWrites: () async {},
      );
      await restored.restoreSession();
      expect(restored.session!.username, 'alice');
      fixture.secure.failHistoryWrite = false;
      await fixture.login();
      expect(fixture.service.loginHistoryWarning, isNull);
      expect(await FlyLoginHistoryStore.load(), hasLength(1));
    },
  );

  test(
    'background verification does not erase a history-save warning',
    () async {
      fixture.secure.failHistoryWrite = true;
      await fixture.login();
      final warning = fixture.service.loginHistoryWarning;
      expect(warning, isNotEmpty);
      await fixture.service.switchAddress(fixture.url);
      expect(fixture.service.loginHistoryWarning, warning);
    },
  );

  test('login without remember removes an earlier saved password', () async {
    await fixture.login();
    await fixture.login(remember: false);
    final row = (await FlyLoginHistoryStore.load()).single;
    expect(row.password, isEmpty);
    expect(row.rememberPassword, isFalse);
  });

  test(
    'logout removes the current session but retains login history',
    () async {
      await fixture.login();
      fixture.rejectLogout = true;
      await expectLater(fixture.service.logout(), throwsStateError);
      expect(fixture.service.session, isNull);
      expect(
        (await fixture.secure.read('fly_data_service_session_v1')).status,
        SecureCredentialReadStatus.missing,
      );
      expect(
        (await FlyLoginHistoryStore.load()).single.password,
        'synthetic-password',
      );
    },
  );

  test(
    'switch to verified alias updates history without carrying its password',
    () async {
      await fixture.login();
      await fixture.service.switchAddress(fixture.aliasUrl);
      final row = (await FlyLoginHistoryStore.load()).single;
      expect(row.serverUrl, fixture.aliasUrl);
      expect(row.deviceName, 'Server device name');
      expect(row.password, isEmpty);
      expect(row.rememberPassword, isFalse);
      expect(fixture.service.session!.serverUrl, fixture.aliasUrl);
      expect(fixture.loginBodies, hasLength(1));
    },
  );

  test(
    'same-address background verification preserves remembered password',
    () async {
      await fixture.login();
      await fixture.service.switchAddress(fixture.url);
      expect(
        (await FlyLoginHistoryStore.load()).single.password,
        'synthetic-password',
      );
    },
  );

  test(
    'failed address identity probe preserves history and does not send bearer',
    () async {
      await fixture.login();
      fixture.paths.clear();
      fixture.instance = 'different-instance';
      await expectLater(
        fixture.service.switchAddress(fixture.aliasUrl),
        throwsStateError,
      );
      expect(fixture.paths, ['/api/v1/system/identity']);
      final row = (await FlyLoginHistoryStore.load()).single;
      expect(row.serverUrl, fixture.url);
      expect(row.password, 'synthetic-password');
    },
  );
}
