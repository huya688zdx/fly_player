import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
