import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(NasProvider.resetBootstrapForTesting);

  test('mutation 后的加载不会加入 mutation 前的阻塞代次', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'http://old-nas.example.test',
      'user_name': 'old-user',
    });
    final backend = _ControlledCredentialBackend()
      ..blockNextRead(SecureCredentialReadResult.found('old-token'));
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    backend.blockNextWrite();

    final update = provider.updateSettings(
      baseUrl: 'http://new-nas.example.test',
      userName: 'new-user',
      password: 'new-password',
      token: 'new-token',
    );
    var secondLoadCompleted = false;
    final secondLoad = provider.retryLoad()
      ..then((_) => secondLoadCompleted = true);

    backend.releaseRead();
    await backend.writeStarted.future;
    await _drainMicrotasks();

    expect(secondLoadCompleted, isFalse);

    backend.releaseWrite();
    await Future.wait<void>(<Future<void>>[update, secondLoad]);

    expect(backend.readCount, 4);
    expect(provider.sourceBaseUrl, 'http://new-nas.example.test');
    expect(provider.token, 'new-token');
  });

  test('阻塞加载完成后 updateSettings 的新登录不会被旧快照覆盖', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'http://old-nas.example.test',
      'user_name': 'old-user',
    });
    final backend = _ControlledCredentialBackend()
      ..blockNextRead(SecureCredentialReadResult.found('old-token'));
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    final blockedLoad = provider.retryLoad();

    final update = provider.updateSettings(
      baseUrl: 'http://new-nas.example.test',
      userName: 'new-user',
      password: 'new-password',
      token: 'new-token',
    );
    await _drainMicrotasks();
    final writesWhileLoadBlocked = backend.writeCount;

    backend.releaseRead();
    await Future.wait<void>(<Future<void>>[blockedLoad, update]);

    expect(writesWhileLoadBlocked, 0);
    expect(provider.sourceBaseUrl, 'http://new-nas.example.test');
    expect(provider.userName, 'new-user');
    expect(provider.token, 'new-token');
  });

  test('阻塞加载完成后 logout 不会被旧 token 恢复', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _ControlledCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const embeddingChannel = MethodChannel('fly_player/embedding');
    messenger.setMockMethodCallHandler(embeddingChannel, (_) async => null);
    addTearDown(
      () => messenger.setMockMethodCallHandler(embeddingChannel, null),
    );
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://nas.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    backend.blockNextRead(SecureCredentialReadResult.found('active-token'));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await backend.readStarted.future;
    final blockedLoad = provider.retryLoad();

    final logout = provider.logout();
    await _drainMicrotasks();
    final deletesWhileLoadBlocked = backend.deleteCount;

    backend.releaseRead();
    await Future.wait<void>(<Future<void>>[blockedLoad, logout]);

    expect(deletesWhileLoadBlocked, 0);
    expect(provider.token, isEmpty);
    expect(provider.isConfigured, isFalse);
  });

  test('updateToken 写入期间的恢复加载等待完整 mutation', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _ControlledCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    await provider.updateSettings(
      baseUrl: 'http://nas.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'old-token',
    );
    backend.blockNextWrite();

    final update = provider.updateToken('new-token');
    await backend.writeStarted.future;
    final readsBeforeResume = backend.readCount;
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final resumedLoad = provider.retryLoad();
    await _drainMicrotasks();
    final readsDuringMutation = backend.readCount - readsBeforeResume;

    backend.releaseWrite();
    await Future.wait<void>(<Future<void>>[update, resumedLoad]);

    expect(readsDuringMutation, 0);
    expect(provider.token, 'new-token');
    expect(backend.values['nas_session.token'], 'new-token');
  });

  test('mutation 写入失败后队列仍可继续执行', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.reloadSettingsForTesting();
    backend.failWrite = true;

    await expectLater(
      provider.updateToken('failed-token'),
      throwsA(isA<SecureCredentialOperationException>()),
    );

    backend.failWrite = false;
    await provider.updateToken('recovered-token');

    expect(provider.token, 'recovered-token');
    expect(backend.values['nas_session.token'], 'recovered-token');
  });

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

Future<void> _drainMicrotasks() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  SecureCredentialReadResult? _blockedReadResult;
  Completer<void>? _readRelease;
  Completer<void>? _writeRelease;
  Completer<void> readStarted = Completer<void>();
  Completer<void> writeStarted = Completer<void>();
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;

  void blockNextRead(SecureCredentialReadResult result) {
    _blockedReadResult = result;
    _readRelease = Completer<void>();
    readStarted = Completer<void>();
  }

  void releaseRead() {
    final release = _readRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  void blockNextWrite() {
    _writeRelease = Completer<void>();
    writeStarted = Completer<void>();
  }

  void releaseWrite() {
    final release = _writeRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    readCount++;
    final blockedResult = _blockedReadResult;
    final release = _readRelease;
    if (blockedResult != null && release != null) {
      _blockedReadResult = null;
      if (!readStarted.isCompleted) readStarted.complete();
      await release.future;
      if (identical(_readRelease, release)) _readRelease = null;
      return blockedResult;
    }
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    final release = _writeRelease;
    if (release != null) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await release.future;
      if (identical(_writeRelease, release)) _writeRelease = null;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCount++;
    values.remove(key);
  }
}
