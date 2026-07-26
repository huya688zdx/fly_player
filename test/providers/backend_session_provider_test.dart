import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('save barrier 后的加载不会加入保存前的阻塞代次', () async {
    _setStoredEmbyConnection();
    final backend = _ControlledCredentialBackend()
      ..values['media_backend_connection.emby.access_token'] = 'old-token'
      ..blockNextRead(SecureCredentialReadResult.found('old-token'));
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    backend.blockNextWrite();

    final save = provider.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://new-emby.example.test',
        displayName: 'New Emby',
        userId: 'new-user',
        accessToken: 'new-token',
      ),
    );
    var secondLoadCompleted = false;
    final secondLoad = provider.retryLoad()
      ..then((_) => secondLoadCompleted = true);
    var ensureReadyCompleted = false;
    final ensureReady = provider.ensureReady()
      ..then((_) => ensureReadyCompleted = true);

    backend.releaseRead();
    await backend.writeStarted.future;
    await _drainMicrotasks();

    expect(secondLoadCompleted, isFalse);
    expect(ensureReadyCompleted, isFalse);

    backend.releaseWrite();
    await Future.wait<void>(<Future<void>>[save, secondLoad, ensureReady]);

    expect(backend.readCount, 4);
    expect(
      provider.currentConnection?.serverUrl,
      'https://new-emby.example.test',
    );
    expect(provider.currentConnection?.accessToken, 'new-token');
  });

  test('阻塞加载完成后 saveActive 的新连接不会被旧快照覆盖', () async {
    _setStoredEmbyConnection();
    final backend = _ControlledCredentialBackend()
      ..values['media_backend_connection.emby.access_token'] = 'old-token'
      ..blockNextRead(SecureCredentialReadResult.found('old-token'));
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider();
    addTearDown(provider.dispose);
    await backend.readStarted.future;
    final blockedLoad = provider.retryLoad();

    final save = provider.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://new-emby.example.test',
        displayName: 'New Emby',
        userId: 'new-user',
        accessToken: 'new-token',
      ),
    );
    await _drainMicrotasks();
    final writesWhileLoadBlocked = backend.writeCount;

    backend.releaseRead();
    await Future.wait<void>(<Future<void>>[blockedLoad, save]);

    expect(writesWhileLoadBlocked, 0);
    expect(
      provider.currentConnection?.serverUrl,
      'https://new-emby.example.test',
    );
    expect(provider.currentConnection?.accessToken, 'new-token');
  });

  test('saveActive 写入期间的恢复加载等待完整 mutation', () async {
    _setStoredEmbyConnection();
    final backend = _ControlledCredentialBackend()
      ..values['media_backend_connection.emby.access_token'] = 'old-token';
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);
    await provider.load();
    backend.blockNextWrite();

    final save = provider.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://new-emby.example.test',
        displayName: 'New Emby',
        userId: 'new-user',
        accessToken: 'new-token',
      ),
    );
    await backend.writeStarted.future;
    final readsBeforeResume = backend.readCount;
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final resumedLoad = provider.retryLoad();
    await _drainMicrotasks();
    final readsDuringMutation = backend.readCount - readsBeforeResume;

    backend.releaseWrite();
    await Future.wait<void>(<Future<void>>[save, resumedLoad]);

    expect(readsDuringMutation, 0);
    expect(
      provider.currentConnection?.serverUrl,
      'https://new-emby.example.test',
    );
    expect(provider.currentConnection?.accessToken, 'new-token');
  });

  test('save mutation 失败后队列仍可继续执行', () async {
    final backend = _SwitchableCredentialBackend()..failWrite = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://emby.example.test',
      userId: 'user-id',
      accessToken: 'access-token',
    );

    await expectLater(
      provider.saveActive(connection),
      throwsA(isA<SecureCredentialOperationException>()),
    );

    backend.failWrite = false;
    await provider.saveActive(connection);

    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.accessToken, 'access-token');
  });

  test('构造、恢复、重试、公开加载和 ensureReady 复用同一次成功读取', () async {
    _setStoredEmbyConnection();
    final backend = _GatedCredentialBackend(
      SecureCredentialReadResult.found('access-token'),
    );
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider();
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
    final directLoad = provider.load();
    final ensureReady = provider.ensureReady();
    await Future<void>.delayed(Duration.zero);

    expect(backend.readCount, 1);
    expect(states, isEmpty);

    backend.release();
    await Future.wait<void>(<Future<void>>[retry, directLoad, ensureReady]);

    expect(backend.readCount, 1);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
    expect(provider.isConfigured, isTrue);
    expect(states, <({bool isReady, bool hasFailure})>[
      (isReady: true, hasFailure: false),
    ]);
  });

  test('并发会话加载失败只提交一次状态且下一代可恢复', () async {
    _setStoredEmbyConnection();
    final backend = _GatedCredentialBackend(
      const SecureCredentialReadResult.unavailable(),
    );
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider();
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
    final directLoad = provider.load();
    final ensureReadyFailure = expectLater(
      provider.ensureReady(),
      throwsA(isA<BackendSessionUnavailableException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(backend.readCount, 1);
    expect(states, isEmpty);

    backend.release();
    await Future.wait<void>(<Future<void>>[retry, directLoad]);
    await ensureReadyFailure;

    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
    expect(states.where((state) => state.hasFailure), hasLength(1));

    backend.startGeneration(SecureCredentialReadResult.found('access-token'));
    final recovery = provider.retryLoad();
    await backend.readStarted.future;
    expect(backend.readCount, 2);
    backend.release();
    await recovery;

    expect(backend.readCount, 2);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
  });

  test('loads current Emby connection from the neutral store', () async {
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Living Room',
        userName: 'alice',
        userId: 'user-id',
        accessToken: 'access-token',
      ),
    );
    final provider = BackendSessionProvider(autoLoad: false);

    await provider.load();

    expect(provider.isReady, isTrue);
    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.serverUrl, 'https://emby.example.test');
    expect(provider.isConfigured, isTrue);
  });

  test('saveActive persists and exposes the new current connection', () async {
    final provider = BackendSessionProvider(autoLoad: false);

    await provider.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Living Room',
        userName: 'alice',
        userId: 'user-id',
        accessToken: 'access-token',
      ),
    );

    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.displayName, 'Living Room');

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.emby);
    expect(snapshot.activeConnection.userId, 'user-id');
  });

  test('安全凭据暂不可用时保留已加载的后端会话', () async {
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        userId: 'user-id',
        accessToken: 'access-token',
      ),
    );
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);
    await provider.load();
    backend.unavailable = true;

    await provider.load();

    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.accessToken, 'access-token');
    expect(provider.isConfigured, isTrue);
    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('首次读取安全凭据失败时不会宣告会话已准备', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..unavailable = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await provider.load();

    expect(provider.isReady, isFalse);
    expect(provider.isConfigured, isFalse);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('首次读取安全凭据失败时 ensureReady 不会返回默认后端', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..unavailable = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    final kindAfterReady = provider.ensureReady().then(
      (_) => provider.currentKind,
    );

    await expectLater(
      kindAfterReady,
      throwsA(
        isA<BackendSessionUnavailableException>()
            .having(
              (error) => error.cause,
              'cause',
              isA<SecureCredentialUnavailableException>(),
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('media_backend_connection')),
            ),
      ),
    );
    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('ensureReady 将凭据迁移写入失败规范化为会话不可用', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'accessToken': 'legacy-access-token',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..failWrite = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await expectLater(
      provider.ensureReady(),
      throwsA(
        isA<BackendSessionUnavailableException>().having(
          (error) => error.cause,
          'cause',
          isA<SecureCredentialOperationException>(),
        ),
      ),
    );
    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('ensureReady 将凭据清理失败规范化为会话不可用', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..failDelete = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await expectLater(
      provider.ensureReady(),
      throwsA(
        isA<BackendSessionUnavailableException>().having(
          (error) => error.cause,
          'cause',
          isA<SecureCredentialOperationException>(),
        ),
      ),
    );
    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('回前台自动加载凭据写入失败不泄漏未处理异常', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'accessToken': 'legacy-access-token',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..failWrite = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final unhandledErrors = <Object>[];
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await runZonedGuarded<Future<void>>(() async {
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await backend.writeAttempt.future;
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => unhandledErrors.add(error));

    expect(unhandledErrors, isEmpty);
    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);
  });

  test('首次会话加载失败后可显式重试恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _SwitchableCredentialBackend()..unavailable = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await provider.retryLoad();
    expect(provider.isReady, isFalse);
    expect(provider.hasLoadFailure, isTrue);

    backend
      ..unavailable = false
      ..values['media_backend_connection.emby.access_token'] = 'access-token';
    await provider.retryLoad();

    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.isConfigured, isTrue);
  });

  test('通道未注册时清理凭证抛 MissingPlugin 不炸整次会话加载', () async {
    _setStoredEmbyConnection();
    // emby 连接无 secret/entryToken → 载入时会对这两个键做清理 delete；
    // 并行引擎在 secret_store 通道注册前 delete 会抛 MissingPlugin（真机分屏
    // 详情首开"加载失败"实锤）——该竞态必须不影响会话加载本身。
    final backend = _ChannelMissingDeleteBackend()
      ..values['media_backend_connection.emby.access_token'] = 'access-token';
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final provider = BackendSessionProvider(autoLoad: false);
    addTearDown(provider.dispose);

    await provider.load();

    expect(provider.isReady, isTrue);
    expect(provider.hasLoadFailure, isFalse);
    expect(provider.currentConnection?.accessToken, 'access-token');
    expect(backend.deleteAttempts, greaterThan(0));
  });
}

class _SwitchableCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;
  bool failWrite = false;
  bool failDelete = false;
  final Completer<void> writeAttempt = Completer<void>();

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
    if (!writeAttempt.isCompleted) writeAttempt.complete();
    if (failWrite) {
      throw SecureCredentialOperationException('write', key);
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) {
      throw SecureCredentialOperationException('delete', key);
    }
    values.remove(key);
  }
}

// 模拟通道未注册：delete 抛 MissingPlugin（与真机 fly_player/secret_store
// 未注册时的行为一致），读写正常。
class _ChannelMissingDeleteBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  int deleteAttempts = 0;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteAttempts++;
    throw MissingPluginException(
      'No implementation found for method deleteCredential',
    );
  }
}

void _setStoredEmbyConnection() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
      <String, Object?>{
        'kind': 'emby',
        'serverUrl': 'https://emby.example.test',
        'hasAccessToken': true,
      },
    ]),
    MediaBackendConnectionStore.activeKindKey: 'emby',
  });
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
    values.remove(key);
  }
}
