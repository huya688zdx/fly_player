import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/login_history_store.dart';

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
}
