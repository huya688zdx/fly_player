import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('保存登录历史时不把密码写入 SharedPreferences 明文 JSON', () async {
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://nas.example.test',
        userName: 'alice',
        password: 'secret-password',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('login_history_v1')!;
    final json = jsonDecode(raw.single) as Map<String, dynamic>;

    expect(json.containsKey('password'), isFalse);
    expect(raw.single, isNot(contains('secret-password')));
  });

  test('未记住密码时会清理旧明文密码', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://nas.example.test',
          'userName': 'alice',
          'password': 'old-password',
          'rememberPassword': false,
          'updatedAtMillis': 1,
        }),
      ],
    });

    final entries = await LoginHistoryStore.load();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('login_history_v1')!;

    expect(entries.single.password, isEmpty);
    expect(raw.single, isNot(contains('old-password')));
  });

  test('安全凭据暂不可用时保留记住密码状态且不删除凭据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://nas.example.test',
          'userName': 'alice',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _UnavailableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    final entries = await LoginHistoryStore.load();

    expect(entries.single.password, isEmpty);
    expect(entries.single.rememberPassword, isTrue);
    expect(backend.deletedKeys, isEmpty);
  });

  test('保存另一条历史时不会删除暂不可用条目的既有凭据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://old-nas.example.test',
          'userName': 'alice',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _UnavailableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await LoginHistoryStore.load();
    final unavailableKey = backend.lastReadKey;
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://new-nas.example.test',
        userName: 'bob',
        password: 'new-password',
        rememberPassword: true,
        updatedAtMillis: 2,
      ),
    );

    expect(unavailableKey, isNotNull);
    expect(backend.deletedKeys, isNot(contains(unavailableKey)));
  });

  test('同一条暂不可用历史以空密码保存时保留既有凭据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://nas.example.test',
          'userName': 'alice',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _UnavailableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await LoginHistoryStore.load();
    final unavailableKey = backend.lastReadKey;
    final entries = await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://nas.example.test',
        userName: 'alice',
        password: '',
        rememberPassword: true,
        updatedAtMillis: 2,
      ),
    );

    expect(entries.single.rememberPassword, isTrue);
    expect(unavailableKey, isNotNull);
    expect(backend.deletedKeys, isNot(contains(unavailableKey)));
  });

  test('迁移旧密码时安全写入失败会向调用方抛出', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://nas.example.test',
          'userName': 'alice',
          'password': 'legacy-password',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    SecureCredentialStore.setBackendForTesting(
      const _FailingCredentialBackend(failWrite: true),
    );
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await expectLater(LoginHistoryStore.load(), throwsStateError);
  });

  test('清理未记住的旧密码时安全删除失败会向调用方抛出', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://nas.example.test',
          'userName': 'alice',
          'rememberPassword': false,
          'updatedAtMillis': 1,
        }),
      ],
    });
    SecureCredentialStore.setBackendForTesting(
      const _FailingCredentialBackend(failDelete: true),
    );
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await expectLater(LoginHistoryStore.load(), throwsStateError);
  });
}

class _UnavailableCredentialBackend implements SecureCredentialBackend {
  final List<String> deletedKeys = <String>[];
  String? lastReadKey;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    lastReadKey = key;
    return const SecureCredentialReadResult.unavailable();
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
  }
}

class _FailingCredentialBackend implements SecureCredentialBackend {
  const _FailingCredentialBackend({
    this.failWrite = false,
    this.failDelete = false,
  });

  final bool failWrite;
  final bool failDelete;

  @override
  Future<SecureCredentialReadResult> read(String key) async =>
      const SecureCredentialReadResult.missing();

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('secure write failed');
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('secure delete failed');
  }
}
