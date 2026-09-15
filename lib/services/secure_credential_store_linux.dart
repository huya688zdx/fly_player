import 'package:flutter/services.dart';

import 'secure_credential_store.dart';

/// Linux 凭据交给桌面 Secret Service 密钥环，不在普通配置中保存明文。
final class LinuxSecureCredentialBackend implements SecureCredentialBackend {
  const LinuxSecureCredentialBackend();

  // flutter_secure_storage_linux 仅提供原生插件，通过它的通道访问 libsecret。
  static const _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return const SecureCredentialReadResult.missing();
    try {
      final value = await _channel.invokeMethod<String>('read', {
        'key': normalized,
      });
      return value == null || value.isEmpty
          ? const SecureCredentialReadResult.missing()
          : SecureCredentialReadResult.found(value);
    } on PlatformException {
      // 密钥环锁定或服务不可达时不能当作凭据缺失，也不缓存失败结果。
      return const SecureCredentialReadResult.unavailable();
    } on MissingPluginException {
      return const SecureCredentialReadResult.unavailable();
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    if (value.isEmpty) return delete(normalized);
    try {
      await _channel.invokeMethod<void>('write', {
        'key': normalized,
        'value': value,
      });
    } on PlatformException {
      throw SecureCredentialOperationException('write', normalized);
    } on MissingPluginException {
      throw SecureCredentialOperationException('write', normalized);
    }
  }

  @override
  Future<void> delete(String key) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('delete', {'key': normalized});
    } on PlatformException {
      throw SecureCredentialOperationException('delete', normalized);
    } on MissingPluginException {
      throw SecureCredentialOperationException('delete', normalized);
    }
  }
}
