import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _LocalService service;
  late FlyAccountController account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    service = _LocalService()..session = _session();
    account = FlyAccountController(
      nas: NasProvider(),
      backendSession: BackendSessionProvider(autoLoad: false),
      service: service,
      autoLoad: false,
    );
    await account.nas.reloadSettingsForTesting();
    account.bindings = [
      {'id': 'existing'},
    ];
    account.activeBindingId = 'existing';
  });
  tearDown(() {
    account.dispose();
    account.nas.dispose();
    account.backendSession.dispose();
    SecureCredentialStore.resetBackendForTesting();
  });

  test('本机发现禁用时保留现有绑定和激活项', () async {
    final response = await account.loadLocalServices();
    expect(response['enabled'], isFalse);
    expect(service.paths, ['/local-services']);
    expect(account.bindings.single['id'], 'existing');
    expect(account.activeBindingId, 'existing');
  });

  test('旧服务404兼容错误不清空现有来源', () async {
    service.error = StateError('数据服务拒绝请求：http_error');
    await expectLater(account.loadLocalServices(), throwsStateError);
    expect(account.message, contains('升级服务端'));
    expect(account.bindings.single['id'], 'existing');
    expect(account.activeBindingId, 'existing');
  });

  test('管理员登记只提交服务key并返回现有媒体服务器契约', () async {
    service.response = {'id': 'local-feiniu', 'kind': 'feiniu'};
    final result = await account.registerLocalService(
      'feiniu',
      expectedAccountKey: account.accountKey,
      expectedEpoch: account.accountEpoch,
    );
    expect(result['id'], 'local-feiniu');
    expect(service.paths, ['/local-services/register']);
    expect(service.bodies.single, {'key': 'feiniu'});
  });

  test('普通成员不会向服务发送登记请求', () async {
    service.session = _session(role: 'user');
    await expectLater(
      account.registerLocalService(
        'emby',
        expectedAccountKey: account.accountKey,
        expectedEpoch: account.accountEpoch,
      ),
      throwsStateError,
    );
    expect(service.paths, isEmpty);
  });

  test('账号相同但模式epoch改变时拒绝迟到本机发现', () async {
    service.pending = Completer<Map<String, dynamic>>();
    final request = account.loadLocalServices();
    final rejected = expectLater(request, throwsStateError);
    await service.started.future;
    final transition = account.returnToFlyMode();
    service.pending!.complete({'enabled': true, 'items': []});
    await rejected;
    await transition;
    expect(account.bindings.single['id'], 'existing');
  });

  test('换账号后迟到登记结果不能成为当前账号的服务器', () async {
    service.pending = Completer<Map<String, dynamic>>();
    final registration = account.registerLocalService(
      'emby',
      expectedAccountKey: account.accountKey,
      expectedEpoch: account.accountEpoch,
    );
    final rejected = expectLater(registration, throwsStateError);
    await service.started.future;
    service.session = _session(user: 'other');
    service.pending!.complete({'id': 'previous-account-server'});
    await rejected;
    expect(account.servers, isEmpty);
  });

  test('模式切换使排队绑定失效且不发送媒体凭据', () async {
    service.pending = Completer<Map<String, dynamic>>();
    final discovery = account.loadLocalServices();
    final rejectedDiscovery = expectLater(discovery, throwsStateError);
    await service.started.future;
    final binding = account.createBinding({
      'server_id': 'local-feiniu',
      'username': 'fixture',
      'password': 'fixture',
    });
    final rejectedBinding = expectLater(binding, throwsStateError);
    final transition = account.returnToFlyMode();
    service.pending!.complete({'enabled': true, 'items': []});
    await rejectedDiscovery;
    await rejectedBinding;
    await transition;
    expect(service.paths, ['/local-services']);
  });
}

FlyDataSession _session({String role = 'admin', String user = 'viewer'}) =>
    FlyDataSession(
      serverUrl: 'https://fly.example.test',
      userId: user,
      username: user,
      deviceId: 'device',
      deviceName: 'test',
      token: 'fixture',
      installationId: 'install',
      serviceInstanceId: 'instance',
      role: role,
    );

class _LocalService extends FlyDataService {
  _LocalService()
    : super(
        database: PlayStatsService.instance.database,
        drainWrites: () async {},
      );
  final paths = <String>[];
  final bodies = <Object?>[];
  final started = Completer<void>();
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> response = {'enabled': false, 'items': []};
  Object? error;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async {
    paths.add(path);
    bodies.add(body);
    if (!started.isCompleted) started.complete();
    if (error != null) throw error!;
    return pending?.future ?? response;
  }
}
