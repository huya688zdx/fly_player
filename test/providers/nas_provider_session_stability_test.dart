import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}

class _SwitchableCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;

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
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
