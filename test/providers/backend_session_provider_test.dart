import 'dart:convert';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
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
      throwsA(isA<BackendSessionUnavailableException>()),
    );
    expect(provider.isReady, isFalse);
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
      throwsA(isA<BackendSessionUnavailableException>()),
    );
    expect(provider.isReady, isFalse);
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
      throwsA(isA<BackendSessionUnavailableException>()),
    );
    expect(provider.isReady, isFalse);
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
