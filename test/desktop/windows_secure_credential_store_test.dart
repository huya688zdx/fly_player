import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/services/secure_credential_store_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsSecureCredentialBackend（真机 DPAPI）', () {
    late WindowsSecureCredentialBackend backend;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      backend = WindowsSecureCredentialBackend();
    });

    test('写读 roundtrip 与删除', () async {
      await backend.write('nas_token', 'secret-token-值');
      final read = await backend.read('nas_token');
      expect(read.status, SecureCredentialReadStatus.value);
      expect(read.value, 'secret-token-值');

      // 密文确实落了 prefs 且不是明文。
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('win_secret_dpapi_nas_token')!;
      expect(stored, isNot(contains('secret-token')));

      await backend.delete('nas_token');
      expect(
        (await backend.read('nas_token')).status,
        SecureCredentialReadStatus.missing,
      );
    });

    test('未写入的键返回 missing，空键短路', () async {
      expect(
        (await backend.read('absent')).status,
        SecureCredentialReadStatus.missing,
      );
      expect(
        (await backend.read('  ')).status,
        SecureCredentialReadStatus.missing,
      );
    });

    test('损坏密文按 missing 处理（换用户/换机器场景不抛错）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'win_secret_dpapi_bad': 'not-a-valid-dpapi-blob',
      });
      expect(
        (await backend.read('bad')).status,
        SecureCredentialReadStatus.missing,
      );
    });

    test('写空串等价删除', () async {
      await backend.write('k', 'v');
      await backend.write('k', '');
      expect(
        (await backend.read('k')).status,
        SecureCredentialReadStatus.missing,
      );
    });
  });
}
