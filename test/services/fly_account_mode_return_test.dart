import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlyAccountController account;
  late FlyDataService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    service = FlyDataService(
      database: PlayStatsService.instance.database,
      drainWrites: () async {},
    );
    account = FlyAccountController(
      nas: NasProvider(),
      backendSession: BackendSessionProvider(autoLoad: false),
      service: service,
      autoLoad: false,
    );
    await account.nas.reloadSettingsForTesting();
  });
  tearDown(() async {
    account.dispose();
    account.nas.dispose();
    account.backendSession.dispose();
    await PlayStatsService.instance.bindOwnerScope('');
    SecureCredentialStore.resetBackendForTesting();
  });

  test('返回飞翔保留账号与两类已存连接，解除本地统计归属且不冒认绑定', () async {
    service.session = FlyDataSession(
      serverUrl: 'https://fly.example.test',
      userId: 'viewer',
      username: 'viewer',
      deviceId: 'device',
      deviceName: 'test',
      token: 'fly-fixture',
      installationId: 'installation',
      serviceInstanceId: 'instance',
    );
    final session = service.session;
    final bound = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://bound.example.test',
      accessToken: 'bound-fixture',
      accountKey: account.accountKey,
      bindingId: 'bound',
      bindingRevision: 1,
    );
    const direct = MediaBackendConnection(
      kind: MediaBackendKind.jellyfin,
      serverUrl: 'https://direct.example.test',
      accessToken: 'direct-fixture',
      secret: 'direct-password-fixture',
    );
    await MediaBackendConnectionStore.saveActive(bound);
    await account.backendSession.saveActive(direct);
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://media.example.test',
        userName: 'media-user',
        password: 'history-password-fixture',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );
    account.bindings = [
      {'id': 'bound', 'revision': 1, 'status': 'active'},
    ];
    account.activeBindingId = 'stale-bound';
    account.legacyMode = true;
    await PlayStatsService.instance.bindOwnerScope('legacy-local-user');

    await account.returnToFlyMode();

    expect(account.legacyMode, isFalse);
    expect(account.activeBindingId, isEmpty);
    expect(service.session, same(session));
    expect(account.bindings.single['id'], 'bound');
    expect(PlayStatsService.instance.currentScope, isEmpty);
    expect(PlayStatsService.instance.hasUnifiedBinding, isFalse);
    expect(account.backendSession.currentConnection!.bindingId, isEmpty);
    expect(
      account.backendSession.currentConnection!.serverUrl,
      direct.serverUrl,
    );
    final stored = await MediaBackendConnectionStore.load();
    expect(
      stored.connectionFor(MediaBackendKind.jellyfin)!.secret,
      'direct-password-fixture',
    );
    expect(
      stored.connections.map((c) => c.accessToken),
      containsAll(['bound-fixture', 'direct-fixture']),
    );
    expect(
      (await LoginHistoryStore.load()).single.password,
      'history-password-fixture',
    );
  });

  test('已在飞翔模式时返回操作不清除当前绑定', () async {
    account.activeBindingId = 'current';
    account.legacyMode = false;
    await account.returnToFlyMode();
    expect(account.activeBindingId, 'current');
    expect(account.legacyMode, isFalse);
  });
}
