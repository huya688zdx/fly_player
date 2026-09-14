import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/services/secure_credential_store_linux.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const linuxChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const linuxBackend = LinuxSecureCredentialBackend();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(linuxChannel, null));

  test('Linux 凭据通过密钥环读写，写空值删除', () async {
    final values = <String, String>{};
    messenger.setMockMethodCallHandler(linuxChannel, (call) async {
      final key = call.arguments['key'] as String;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          values[key] = call.arguments['value'] as String;
        case 'delete':
          values.remove(key);
      }
      return null;
    });
    await linuxBackend.write(' session.token ', 'linux-token');
    expect(values['session.token'], 'linux-token');
    expect((await linuxBackend.read('session.token')).value, 'linux-token');
    await linuxBackend.write('session.token', '');
    expect(
      (await linuxBackend.read('session.token')).status,
      SecureCredentialReadStatus.missing,
    );
  });

  test('Linux 密钥环锁定不丢失凭据，解锁后重新读取', () async {
    var locked = true;
    messenger.setMockMethodCallHandler(linuxChannel, (call) async {
      if (locked) throw PlatformException(code: 'KeyringLocked');
      return 'restored-token';
    });
    expect(
      (await linuxBackend.read('session.token')).status,
      SecureCredentialReadStatus.unavailable,
    );
    await expectLater(
      linuxBackend.write('session.token', 'secret-value'),
      throwsA(isA<SecureCredentialOperationException>()),
    );
    locked = false;
    expect((await linuxBackend.read('session.token')).value, 'restored-token');
  });

  test('平台读取失败返回 unavailable 且下一次仍会重试平台通道', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          (call) async {
            if (call.method != 'readCredential') return null;
            calls += 1;
            if (calls == 1) {
              throw PlatformException(code: 'temporary_failure');
            }
            return <String, Object?>{
              'status': 'value',
              'value': 'restored-token',
            };
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('fly_player/secret_store'),
            null,
          );
      SecureCredentialStore.resetBackendForTesting();
    });
    SecureCredentialStore.setBackendForTesting(
      MethodChannelSecureCredentialBackend(forcePlatformChannel: true),
    );

    final first = await SecureCredentialStore.read('session.token');
    final second = await SecureCredentialStore.read('session.token');

    expect(first.status, SecureCredentialReadStatus.unavailable);
    expect(second.status, SecureCredentialReadStatus.value);
    expect(second.value, 'restored-token');
    expect(calls, 2);
  });

  test('平台写入返回 false 时不会假成功', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          (call) async => call.method == 'writeCredential' ? false : null,
        );
    _resetSecretStoreAfterTest();
    SecureCredentialStore.setBackendForTesting(
      MethodChannelSecureCredentialBackend(forcePlatformChannel: true),
    );

    await expectLater(
      SecureCredentialStore.write('session.token', 'secret-value'),
      throwsA(
        predicate<Object>(
          (error) => !error.toString().contains('secret-value'),
        ),
      ),
    );
  });

  test('平台删除返回 false 时不会假成功', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          (call) async => call.method == 'deleteCredential' ? false : null,
        );
    _resetSecretStoreAfterTest();
    SecureCredentialStore.setBackendForTesting(
      MethodChannelSecureCredentialBackend(forcePlatformChannel: true),
    );

    await expectLater(
      SecureCredentialStore.delete('session.token'),
      throwsA(isA<Exception>()),
    );
  });
}

void _resetSecretStoreAfterTest() {
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          null,
        );
    SecureCredentialStore.resetBackendForTesting();
  });
}
