import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
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
  test('飞牛访问码只写安全存储且加载时回填', () async {
    final backend = _RecordingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://nas.example.test',
        userName: 'alice',
        password: 'secret-password',
        accessCode: 'secret-access-code',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('login_history_v1')!.single;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final loaded = await LoginHistoryStore.load();

    expect(json.containsKey('accessCode'), isFalse);
    expect(raw, isNot(contains('secret-access-code')));
    expect(
      backend.values.entries
          .singleWhere(
            (item) => item.key.startsWith('login_history.access_code.'),
          )
          .value,
      'secret-access-code',
    );
    expect(loaded.single.accessCode, 'secret-access-code');
  });

  test('加载旧 JSON 时会移除其中的访问码字段且不从明文回填', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'https://legacy-nas.example.test',
          'userName': 'alice',
          'accessCode': 'legacy-plain-access-code',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _RecordingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    final loaded = await LoginHistoryStore.load();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('login_history_v1')!.single;

    expect(loaded.single.accessCode, isEmpty);
    expect(raw, isNot(contains('accessCode')));
    expect(raw, isNot(contains('legacy-plain-access-code')));
  });

  test('截断、删除与清空会对称清理密码和访问码安全键', () async {
    final backend = _RecordingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    for (var index = 0; index < 11; index++) {
      await LoginHistoryStore.save(
        LoginHistoryEntry(
          baseUrl: 'https://nas-$index.example.test',
          userName: 'user-$index',
          password: 'password-$index',
          accessCode: 'access-$index',
          rememberPassword: true,
          updatedAtMillis: index,
        ),
      );
    }

    expect(backend.values.values, isNot(contains('password-0')));
    expect(backend.values.values, isNot(contains('access-0')));
    expect(backend.values, hasLength(20));

    final entries = await LoginHistoryStore.load();
    await LoginHistoryStore.remove(entries.first);
    expect(backend.values.values, isNot(contains('password-10')));
    expect(backend.values.values, isNot(contains('access-10')));
    expect(backend.values, hasLength(18));

    await LoginHistoryStore.clear();
    expect(backend.values, isEmpty);
  });

  test('非飞牛条目不读写访问码且未记住的飞牛条目不持久化访问码', () async {
    final backend = _RecordingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        kind: MediaBackendKind.emby,
        baseUrl: 'https://emby.example.test',
        userName: 'alice',
        password: 'emby-password',
        accessCode: 'must-not-persist',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );
    expect(
      backend.touchedKeys.where(
        (key) => key.startsWith('login_history.access_code.'),
      ),
      isEmpty,
    );
    expect((await LoginHistoryStore.load()).single.accessCode, isEmpty);

    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://nas.example.test',
        userName: 'bob',
        password: 'runtime-password',
        accessCode: 'runtime-access-code',
        rememberPassword: false,
        updatedAtMillis: 2,
      ),
    );
    final loaded = await LoginHistoryStore.load();
    expect(
      loaded.singleWhere((entry) => entry.userName == 'bob').accessCode,
      isEmpty,
    );
    expect(backend.values.values, isNot(contains('runtime-access-code')));
  });

  test('访问码安全键暂不可用时后续保存不会误删该键', () async {
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
    final backend = _SelectiveUnavailableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://new-nas.example.test',
        userName: 'bob',
        password: 'new-password',
        accessCode: 'new-access-code',
        rememberPassword: true,
        updatedAtMillis: 2,
      ),
    );

    expect(backend.unavailableAccessCodeKey, isNotNull);
    expect(
      backend.deletedKeys,
      isNot(contains(backend.unavailableAccessCodeKey)),
    );
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

class _RecordingCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  final Set<String> touchedKeys = <String>{};

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    touchedKeys.add(key);
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    touchedKeys.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    touchedKeys.add(key);
    values.remove(key);
  }
}

class _SelectiveUnavailableCredentialBackend
    implements SecureCredentialBackend {
  final List<String> deletedKeys = <String>[];
  String? unavailableAccessCodeKey;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (key.startsWith('login_history.access_code.')) {
      unavailableAccessCodeKey = key;
      return const SecureCredentialReadResult.unavailable();
    }
    return const SecureCredentialReadResult.missing();
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
  }
}
