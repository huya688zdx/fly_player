import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/secure_credential_store.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _AccessService extends FlyDataService {
  _AccessService(this.mediaUrl)
    : super(
        database: PlayStatsService.instance.database,
        drainWrites: () async {},
      ) {
    session = FlyDataSession(
      serverUrl: 'https://fly.example.test',
      userId: 'viewer',
      username: 'viewer',
      deviceId: 'device',
      deviceName: 'test',
      token: 'fly-fixture',
      installationId: 'installation',
      serviceInstanceId: 'instance',
    );
  }
  final String mediaUrl;
  @override
  Future<void> restoreSession() async {}
  @override
  Future<void> switchAddress(String value) async =>
      throw StateError('fixture offline');
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async {
    if (!path.endsWith('/device-access')) {
      throw StateError('Unexpected request');
    }
    return {
      'binding_id': 'binding',
      'binding_revision': 1,
      'remote_username': 'media-viewer',
      'remote_user_id': 'media-user',
      'access_token': 'media-fixture',
      'server': {
        'kind': 'emby',
        'remote_server_id': 'media-instance',
        'addresses': [
          {'purpose': 'client_lan', 'base_url': mediaUrl},
        ],
      },
    };
  }
}

void main() {
  _Binding();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('本地模式直接激活来源成功才保存飞翔模式，并在重启恢复同账号绑定', () async {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    final temp = await Directory.systemTemp.createTemp('fly_activate_mode_');
    await databaseFactory.setDatabasesPath(temp.path);
    final media = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mediaUrl = 'http://127.0.0.1:${media.port}';
    var identity = 'wrong-instance';
    var probes = 0;
    media.listen((request) async {
      expect(request.uri.path, '/System/Info/Public');
      expect(request.headers.value('Authorization'), isNull);
      expect(request.headers.value('X-Emby-Token'), isNull);
      probes++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'Id': identity}));
      await request.response.close();
    });
    final controllers = <FlyAccountController>[];
    Future<FlyAccountController> create() async {
      final account = FlyAccountController(
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        service: _AccessService(mediaUrl),
        autoLoad: false,
      );
      controllers.add(account);
      await account.nas.reloadSettingsForTesting();
      await account.backendSession.load();
      return account;
    }

    try {
      final account = await create();
      final binding = <String, dynamic>{
        'id': 'binding',
        'label': 'Emby',
        'status': 'active',
        'revision': 1,
      };
      account.bindings = [binding];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'fly.bindings.${account.accountKey}',
        jsonEncode([binding]),
      );
      await account.enterLegacyMode();
      await expectLater(account.activate(binding), throwsStateError);
      expect(account.legacyMode, isTrue);
      expect(prefs.getString('fly.login_mode'), 'media');
      expect(account.activeBindingId, isEmpty);

      identity = 'media-instance';
      await account.activate(binding);
      expect(probes, 2);
      expect(account.legacyMode, isFalse);
      expect(account.activeBindingId, 'binding');
      expect(prefs.getString('fly.login_mode'), 'fly');
      final restarted = await create();
      await restarted.restore();
      expect(restarted.legacyMode, isFalse);
      expect(restarted.activeBindingId, 'binding');
      expect(
        restarted.backendSession.currentConnection?.accountKey,
        account.accountKey,
      );
      expect(
        restarted.backendSession.currentConnection?.accessToken,
        'media-fixture',
      );
      expect(
        probes,
        2,
        reason: 'Offline restore uses the saved verified binding',
      );
    } finally {
      for (final account in controllers.reversed) {
        account.dispose();
        account.nas.dispose();
        account.backendSession.dispose();
      }
      await PlayStatsService.instance.bindOwnerScope('');
      await media.close(force: true);
      SecureCredentialStore.resetBackendForTesting();
      await temp.delete(recursive: true);
    }
  });
}
