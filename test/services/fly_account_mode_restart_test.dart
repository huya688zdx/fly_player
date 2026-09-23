import 'dart:async';
import 'dart:convert';

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

const _direct = MediaBackendConnection(
  kind: MediaBackendKind.emby,
  serverUrl: 'https://direct.example.test',
  userName: 'local-viewer',
  accessToken: 'direct-token-fixture',
  secret: 'direct-password-fixture',
);

FlyDataSession _session() => FlyDataSession(
  serverUrl: 'https://fly.example.test',
  userId: 'viewer',
  username: 'viewer',
  deviceId: 'device',
  deviceName: 'test',
  token: 'fly-token-fixture',
  installationId: 'installation',
  serviceInstanceId: 'instance',
);

class _ModeService extends FlyDataService {
  _ModeService({this.restoreBarrier})
    : super(
        database: PlayStatsService.instance.database,
        drainWrites: () async {},
      );

  final Completer<void>? restoreBarrier;
  final restoreStarted = Completer<void>();
  bool failLogin = false;
  bool offline = true;
  int refreshCalls = 0;

  @override
  Future<void> restoreSession() async {
    if (!restoreStarted.isCompleted) restoreStarted.complete();
    await restoreBarrier?.future;
    await super.restoreSession();
  }

  @override
  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceName,
    bool rememberPassword = true,
    String? expectedInstanceId,
    String fnEntryToken = '',
    Map<String, String> fnGatewayCookies = const {},
  }) async {
    if (failLogin) throw StateError('fixture login rejected');
    session = _session();
    await _saveSession(session!);
  }

  @override
  Future<void> logout() async {
    session = null;
    await SecureCredentialStore.delete('fly_data_service_session_v1');
    if (offline) throw StateError('fixture offline');
  }

  @override
  Future<void> switchAddress(String value) async {
    refreshCalls++;
    if (offline) throw StateError('fixture offline');
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async => {'items': <Map<String, dynamic>>[]};
}

class _SessionUnavailable extends MemorySecureCredentialBackend {
  bool unavailable = false;
  @override
  Future<SecureCredentialReadResult> read(String key) =>
      unavailable && key == 'fly_data_service_session_v1'
      ? Future.value(const SecureCredentialReadResult.unavailable())
      : super.read(key);
}

Future<void> _saveSession(FlyDataSession session) async {
  await SecureCredentialStore.write(
    'fly_data_service_installation_v1',
    session.installationId,
  );
  await SecureCredentialStore.write(
    'fly_data_service_session_v1',
    jsonEncode(session.toJson()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <FlyAccountController>[];
  late _SessionUnavailable credentials;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    credentials = _SessionUnavailable();
    SecureCredentialStore.setBackendForTesting(credentials);
  });

  tearDown(() async {
    for (final controller in controllers.reversed) {
      controller.dispose();
      controller.nas.dispose();
      controller.backendSession.dispose();
    }
    controllers.clear();
    await PlayStatsService.instance.bindOwnerScope('');
    SecureCredentialStore.resetBackendForTesting();
  });

  Future<FlyAccountController> create({_ModeService? service}) async {
    final controller = FlyAccountController(
      nas: NasProvider(),
      backendSession: BackendSessionProvider(autoLoad: false),
      service: service ?? _ModeService(),
      autoLoad: false,
    );
    controllers.add(controller);
    await controller.nas.reloadSettingsForTesting();
    await controller.backendSession.load();
    return controller;
  }

  test('重建控制器恢复明确选择的本地模式，即使从未登录飞翔', () async {
    final original = await create();
    await original.enterLegacyMode();
    await original.backendSession.saveActive(_direct);
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://direct.example.test',
        userName: 'local-viewer',
        password: 'history-password-fixture',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isTrue);
    expect(restarted.ready, isTrue);
    expect(restarted.session, isNull);
    expect(restarted.activeBindingId, isEmpty);
    expect(
      restarted.backendSession.currentConnection?.accessToken,
      _direct.accessToken,
    );
    expect(
      (await LoginHistoryStore.load()).single.password,
      'history-password-fixture',
    );
    expect(PlayStatsService.instance.hasUnifiedBinding, isFalse);
  });

  test('本地模式重启保留飞翔会话与缓存列表，不自动激活旧绑定或改写直连', () async {
    final original = await create();
    await original.enterLegacyMode();
    final fly = _session();
    await _saveSession(fly);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fly.active.${fly.accountKey}', 'old-binding');
    await prefs.setString(
      'fly.bindings.${fly.accountKey}',
      jsonEncode([
        {'id': 'old-binding', 'revision': 1, 'status': 'active'},
      ]),
    );
    await MediaBackendConnectionStore.saveConnection(
      MediaBackendConnection(
        kind: MediaBackendKind.jellyfin,
        serverUrl: 'https://bound.example.test',
        accessToken: 'bound-token-fixture',
        accountKey: fly.accountKey,
        bindingId: 'old-binding',
        bindingRevision: 1,
      ),
    );
    await original.backendSession.saveActive(_direct);
    final savedSession = await SecureCredentialStore.read(
      'fly_data_service_session_v1',
    );
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isTrue);
    expect(restarted.session?.token, fly.token);
    expect(restarted.bindings.single['id'], 'old-binding');
    expect(restarted.activeBindingId, isEmpty);
    expect(restarted.backendSession.currentConnection?.bindingId, isEmpty);
    expect(
      restarted.backendSession.currentConnection?.accessToken,
      _direct.accessToken,
    );
    expect(
      (await SecureCredentialStore.read('fly_data_service_session_v1')).value,
      savedSession.value,
    );
    expect((restarted.service as _ModeService).refreshCalls, 0);
    expect(PlayStatsService.instance.hasUnifiedBinding, isFalse);
    final stored = await MediaBackendConnectionStore.load();
    expect(
      stored.connections.map((value) => value.accessToken),
      containsAll(['bound-token-fixture', 'direct-token-fixture']),
    );
  });

  test('飞翔安全存储暂不可用不会阻断已选本地模式或删除任何保存的令牌', () async {
    final original = await create();
    await original.enterLegacyMode();
    await original.backendSession.saveActive(_direct);
    await _saveSession(_session());
    final before = await SecureCredentialStore.read(
      'fly_data_service_session_v1',
    );
    credentials.unavailable = true;
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isTrue);
    expect(restarted.ready, isTrue);
    expect(
      restarted.backendSession.currentConnection?.accessToken,
      _direct.accessToken,
    );
    credentials.unavailable = false;
    expect(
      (await SecureCredentialStore.read('fly_data_service_session_v1')).value,
      before.value,
    );
  });

  test('本地模式在等待飞翔安全存储前已通知 gate，不依赖会话读取完成', () async {
    final original = await create();
    await original.enterLegacyMode();
    final barrier = Completer<void>();
    final service = _ModeService(restoreBarrier: barrier);
    final restarted = await create(service: service);
    var announcedLocal = false;
    restarted.addListener(() {
      if (restarted.legacyMode) announcedLocal = true;
    });
    final restore = restarted.restore();
    await service.restoreStarted.future;
    try {
      expect(restarted.legacyMode, isTrue);
      expect(announcedLocal, isTrue);
    } finally {
      barrier.complete();
      await restore;
    }
  });

  test('主动切回飞翔后重启保持飞翔模式', () async {
    final original = await create();
    await original.enterLegacyMode();
    await original.returnToFlyMode();
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString('fly.login_mode'),
      'fly',
    );
  });

  for (final savedMode in [null, 'unexpected']) {
    test('缺失或未知登录模式 $savedMode 不从直连历史推断飞翔账号归属', () async {
      final prefs = await SharedPreferences.getInstance();
      if (savedMode != null) await prefs.setString('fly.login_mode', savedMode);
      await MediaBackendConnectionStore.saveActive(_direct);
      final restarted = await create();
      await restarted.restore();
      expect(restarted.legacyMode, isFalse);
      expect(restarted.session, isNull);
      expect(restarted.activeBindingId, isEmpty);
      expect(restarted.bindings, isEmpty);
      expect(PlayStatsService.instance.hasUnifiedBinding, isFalse);
    });
  }

  for (final offline in [false, true]) {
    test('成功飞翔登录立即保存模式，后续刷新离线=$offline 不撤回登录', () async {
      final service = _ModeService()..offline = offline;
      final original = await create(service: service);
      await original.enterLegacyMode();
      final login = original.login(
        url: 'https://fly.example.test',
        username: 'viewer',
        password: 'fixture',
        deviceName: 'test',
      );
      if (offline) {
        await expectLater(login, throwsStateError);
      } else {
        await login;
      }
      final restarted = await create();
      await restarted.restore();
      expect(restarted.legacyMode, isFalse);
      expect(restarted.session?.token, 'fly-token-fixture');
      expect(
        (await SharedPreferences.getInstance()).getString('fly.login_mode'),
        'fly',
      );
    });
  }

  test('飞翔登录失败保留上次主动选择的本地模式', () async {
    final original = await create(service: _ModeService()..failLogin = true);
    await original.enterLegacyMode();
    await expectLater(
      original.login(
        url: 'https://fly.example.test',
        username: 'viewer',
        password: 'fixture',
        deviceName: 'test',
      ),
      throwsStateError,
    );
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isTrue);
  });

  test('飞翔退出即使远端离线也保存飞翔模式，不恢复本地登录入口', () async {
    final original = await create();
    await original.enterLegacyMode();
    original.service.session = _session();
    await expectLater(original.logout(), throwsStateError);
    final restarted = await create();
    await restarted.restore();
    expect(restarted.legacyMode, isFalse);
    expect(restarted.session, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('fly.login_mode'),
      'fly',
    );
  });
}
