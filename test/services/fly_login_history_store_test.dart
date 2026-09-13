import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Secure extends MemorySecureCredentialBackend {
  final values = <String, String>{};
  bool unavailable = false;
  bool failDelete = false;

  @override
  Future<SecureCredentialReadResult> read(String key) async => unavailable
      ? const SecureCredentialReadResult.unavailable()
      : super.read(key);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('test secure deletion unavailable');
    values.remove(key);
    await super.delete(key);
  }
}

FlyLoginHistoryEntry _entry({
  String url = 'https://example.test:8787',
  String instance = 'test-instance',
  String user = 'alice',
  int time = 10,
  bool remember = true,
  String password = 'synthetic-history-password',
}) => FlyLoginHistoryEntry(
  serverUrl: url,
  username: user,
  deviceName: 'Test device',
  serviceInstanceId: instance,
  updatedAtMillis: time,
  rememberPassword: remember,
  password: password,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Secure secure;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = _Secure();
    SecureCredentialStore.setBackendForTesting(secure);
  });
  tearDown(SecureCredentialStore.resetBackendForTesting);

  test(
    'persists metadata and reloads password only from secure storage',
    () async {
      await FlyLoginHistoryStore.save(_entry());
      final prefs = await SharedPreferences.getInstance();
      final persisted = {
        for (final key in prefs.getKeys()) key: prefs.get(key)!,
      };
      expect(
        jsonEncode(persisted),
        isNot(contains('synthetic-history-password')),
      );
      expect(secure.values.values, ['synthetic-history-password']);
      // Recreate the preferences cache, as a new process would read persisted data.
      SharedPreferences.setMockInitialValues(persisted);
      final loaded = (await FlyLoginHistoryStore.load()).single;
      expect(loaded.serverUrl, 'https://example.test:8787');
      expect(loaded.username, 'alice');
      expect(loaded.deviceName, 'Test device');
      expect(loaded.serviceInstanceId, 'test-instance');
      expect(loaded.updatedAtMillis, 10);
      expect(loaded.rememberPassword, isTrue);
      expect(loaded.password, 'synthetic-history-password');
    },
  );

  test(
    'service aliases deduplicate but accounts and instances remain separate',
    () async {
      await FlyLoginHistoryStore.save(_entry());
      await FlyLoginHistoryStore.save(
        _entry(url: 'http://alias.test:8787', time: 20),
      );
      await FlyLoginHistoryStore.save(_entry(user: 'bob', time: 30));
      await FlyLoginHistoryStore.save(
        _entry(instance: 'other-instance', time: 40),
      );
      final rows = await FlyLoginHistoryStore.load();
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.updatedAtMillis), [40, 30, 20]);
      expect(rows.last.serverUrl, 'http://alias.test:8787');
      expect(secure.values, hasLength(3));
    },
  );

  test('fallback ID includes scheme port and case-sensitive username', () {
    final ids = [
      _entry(instance: ''),
      _entry(instance: '', url: 'http://example.test:8787'),
      _entry(instance: '', url: 'https://example.test:8788'),
      _entry(instance: '', user: 'Alice'),
      _entry(instance: 'https://example.test:8787'),
    ].map((entry) => entry.id).toSet();
    expect(ids, hasLength(5));
    expect(
      _entry(instance: '', url: 'https://example.test:8787/').id,
      _entry(instance: '').id,
    );
    expect(
      _entry(instance: 'a|b', user: 'c').id,
      isNot(_entry(instance: 'a', user: 'b|c').id),
    );
  });

  test('unchecking remember deletes the previously saved password', () async {
    await FlyLoginHistoryStore.save(_entry());
    await FlyLoginHistoryStore.save(_entry(remember: false, time: 20));
    final row = (await FlyLoginHistoryStore.load()).single;
    expect(row.rememberPassword, isFalse);
    expect(row.password, isEmpty);
    expect(secure.values, isEmpty);
  });

  test(
    'changing address without a password cannot reuse the old secret',
    () async {
      await FlyLoginHistoryStore.save(_entry());
      await FlyLoginHistoryStore.save(
        _entry(url: 'https://alias.test', password: ''),
      );
      expect((await FlyLoginHistoryStore.load()).single.password, isEmpty);
      expect(secure.values, isEmpty);
    },
  );

  test(
    'modified plain metadata cannot borrow another address password',
    () async {
      await FlyLoginHistoryStore.save(_entry());
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().single;
      final data = jsonDecode(prefs.getString(key)!) as List;
      (data.single as Map)['server_url'] = 'https://different-address.test';
      await prefs.setString(key, jsonEncode(data));
      expect((await FlyLoginHistoryStore.load()).single.password, isEmpty);
    },
  );

  test('forget password keeps the latest entry URL and recency', () async {
    final old = _entry();
    await FlyLoginHistoryStore.save(old);
    await FlyLoginHistoryStore.save(
      _entry(url: 'https://alias.test', time: 20),
    );
    await FlyLoginHistoryStore.forgetPassword(old);
    final row = (await FlyLoginHistoryStore.load()).single;
    expect(row.serverUrl, 'https://alias.test');
    expect(row.updatedAtMillis, 20);
    expect(row.rememberPassword, isFalse);
    expect(row.password, isEmpty);
    expect(secure.values, isEmpty);
  });

  test(
    'keeps newest ten entries and deletes evicted secure credentials',
    () async {
      for (var i = 0; i < 11; i++) {
        await FlyLoginHistoryStore.save(_entry(user: 'user$i', time: i));
      }
      final rows = await FlyLoginHistoryStore.load();
      expect(rows, hasLength(10));
      expect(rows.first.username, 'user10');
      expect(rows.last.username, 'user1');
      expect(secure.values, hasLength(10));
      await FlyLoginHistoryStore.clear();
      expect(await FlyLoginHistoryStore.load(), isEmpty);
      expect(secure.values, isEmpty);
    },
  );

  test('concurrent saves retain all accounts', () async {
    await Future.wait(
      List.generate(
        4,
        (i) => FlyLoginHistoryStore.save(_entry(user: 'user$i', time: i)),
      ),
    );
    expect(await FlyLoginHistoryStore.load(), hasLength(4));
  });

  test(
    'temporary secure read failure does not erase a remembered password',
    () async {
      await FlyLoginHistoryStore.save(_entry());
      secure.unavailable = true;
      expect((await FlyLoginHistoryStore.load()).single.password, isEmpty);
      secure.unavailable = false;
      expect(
        (await FlyLoginHistoryStore.load()).single.password,
        'synthetic-history-password',
      );
    },
  );

  test('failed secure deletion is reported and can be retried', () async {
    await FlyLoginHistoryStore.save(_entry());
    secure.failDelete = true;
    await expectLater(
      FlyLoginHistoryStore.forgetPassword(_entry()),
      throwsStateError,
    );
    secure.failDelete = false;
    await FlyLoginHistoryStore.forgetPassword(_entry());
    expect((await FlyLoginHistoryStore.load()).single.password, isEmpty);
  });

  test(
    'address update clears secret and cannot resurrect cleared histories',
    () async {
      final previous = _entry();
      final next = _entry(url: 'https://alias.test', time: 20);
      await FlyLoginHistoryStore.save(previous);
      await FlyLoginHistoryStore.updateAddress(previous, next);
      final row = (await FlyLoginHistoryStore.load()).single;
      expect(row.serverUrl, next.serverUrl);
      expect(row.rememberPassword, isFalse);
      expect(row.password, isEmpty);
      expect(secure.values, isEmpty);
      await FlyLoginHistoryStore.clear();
      await FlyLoginHistoryStore.updateAddress(next, previous);
      expect(await FlyLoginHistoryStore.load(), isEmpty);
    },
  );

  test(
    'late address callback cannot replace a more recent login address',
    () async {
      final previous = _entry();
      final signedIn = _entry(url: 'https://new-login.test', time: 30);
      await FlyLoginHistoryStore.save(previous);
      await FlyLoginHistoryStore.save(signedIn);
      await FlyLoginHistoryStore.updateAddress(
        previous,
        _entry(url: 'https://alias.test'),
      );
      final row = (await FlyLoginHistoryStore.load()).single;
      expect(row.serverUrl, signedIn.serverUrl);
      expect(row.updatedAtMillis, 30);
      expect(row.password, signedIn.password);
    },
  );
}
