import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(NasProvider.resetBootstrapForTesting);

  test('并发自动加载入口复用同一次成功读取', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _GatedCredentialBackend(
      const SecureCredentialReadResult.missing(),
    );
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    final states = <({bool isReady, bool hasFailure})>[];
    provider.addListener(
      () => states.add((
        isReady: provider.isReady,
        hasFailure: provider.hasLoadFailure,
      )),
    );

    final firstRetry = provider.retryLoad();
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final secondRetry = provider.retryLoad();
    await Future<void>.delayed(Duration.zero);

    expect(backend.readCount, 1);
    expect(states, isEmpty);

    backend.release();
    await Future.wait<void>(<Future<void>>[firstRetry, secondRetry]);

    expect(backend.readCount, 2);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
    expect(states.last, (isReady: true, hasFailure: false));
  });

  test('并发自动加载失败只提交一次状态且下一代可恢复', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _GatedCredentialBackend(
      const SecureCredentialReadResult.unavailable(),
    );
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    final states = <({bool isReady, bool hasFailure})>[];
    provider.addListener(
      () => states.add((
        isReady: provider.isReady,
        hasFailure: provider.hasLoadFailure,
      )),
    );

    final retry = provider.retryLoad();
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(backend.readCount, 1);
    expect(states, isEmpty);

    backend.release();
    await retry;

    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
    expect(states.where((state) => state.hasFailure), hasLength(1));

    backend.startGeneration(const SecureCredentialReadResult.missing());
    final recovery = provider.retryLoad();
    await backend.readStarted.future;
    expect(backend.readCount, 2);
    backend.release();
    await recovery;

    expect(backend.readCount, 3);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
  });

  test('首次凭据不可用时暴露可重试失败并可恢复', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend()..unavailable = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);

    await provider.retryLoad();

    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);

    backend.unavailable = false;
    await provider.retryLoad();

    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
  });

  test('回前台读取安全凭据失败时保留当前 token', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://192.168.1.8:5667',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    backend.unavailable = true;

    await provider.reloadSettingsForTesting();

    expect(provider.token, 'active-token');
    expect(provider.isConfigured, isTrue);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('token 暂不可用时保留整个当前会话快照', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://old-nas.example.test',
      resolvedBaseUrl: 'http://old-resolved.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', 'http://new-nas.example.test');
    await prefs.setString(
      'resolved_base_url',
      'http://new-resolved.example.test',
    );
    await prefs.setString('user_name', 'bob');
    await prefs.setBool('remember_password', false);
    backend.unavailable = true;

    await provider.reloadSettingsForTesting();

    expect(provider.sourceBaseUrl, 'http://old-nas.example.test');
    expect(provider.resolvedBaseUrl, 'http://old-resolved.example.test');
    expect(provider.userName, 'alice');
    expect(provider.password, 'secret');
    expect(provider.token, 'active-token');
    expect(provider.rememberPassword, isTrue);
    expect(provider.isConfigured, isTrue);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('回前台自动迁移写入失败时不泄漏异常并保留当前会话', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://old-nas.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    final prefs = await SharedPreferences.getInstance();
    backend.values.remove('nas_session.token');
    await prefs.setString('token', 'legacy-token');
    backend.failWrite = true;
    final unhandledErrors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await backend.writeAttempt.future;
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => unhandledErrors.add(error));

    expect(unhandledErrors, isEmpty);
    expect(provider.token, 'active-token');
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('回前台自动清理凭据失败时不泄漏异常并保留当前会话', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://old-nas.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_password', false);
    backend.failDelete = true;
    final unhandledErrors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await backend.deleteAttempt.future;
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => unhandledErrors.add(error));

    expect(unhandledErrors, isEmpty);
    expect(provider.password, 'secret');
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isTrue);
  });
}

class _SwitchableCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;
  bool failWrite = false;
  bool failDelete = false;
  Completer<void> writeAttempt = Completer<void>();
  Completer<void> deleteAttempt = Completer<void>();

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (unavailable) return const SecureCredentialReadResult.unavailable();
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) {
      if (!writeAttempt.isCompleted) writeAttempt.complete();
      throw SecureCredentialOperationException('write', key);
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) {
      if (!deleteAttempt.isCompleted) deleteAttempt.complete();
      throw SecureCredentialOperationException('delete', key);
    }
    values.remove(key);
  }
}

class _GatedCredentialBackend implements SecureCredentialBackend {
  _GatedCredentialBackend(SecureCredentialReadResult result) : _result = result;

  SecureCredentialReadResult _result;
  Completer<void> _release = Completer<void>();
  Completer<void> readStarted = Completer<void>();
  int readCount = 0;

  void startGeneration(SecureCredentialReadResult result) {
    _result = result;
    _release = Completer<void>();
    readStarted = Completer<void>();
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    readCount++;
    if (!readStarted.isCompleted) readStarted.complete();
    await _release.future;
    return _result;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
