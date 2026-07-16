import 'package:flutter/services.dart';

enum SecureCredentialReadStatus { value, missing, unavailable }

class SecureCredentialReadResult {
  final SecureCredentialReadStatus status;
  final String value;

  const SecureCredentialReadResult._(this.status, this.value);

  const SecureCredentialReadResult.missing()
    : this._(SecureCredentialReadStatus.missing, '');

  const SecureCredentialReadResult.unavailable()
    : this._(SecureCredentialReadStatus.unavailable, '');

  factory SecureCredentialReadResult.found(String value) =>
      SecureCredentialReadResult._(SecureCredentialReadStatus.value, value);

  bool get isUnavailable => status == SecureCredentialReadStatus.unavailable;
}

class SecureCredentialUnavailableException implements Exception {
  final String key;

  const SecureCredentialUnavailableException(this.key);

  @override
  String toString() => 'Secure credential is temporarily unavailable: $key';
}

class SecureCredentialOperationException implements Exception {
  final String operation;
  final String key;

  const SecureCredentialOperationException(this.operation, this.key);

  @override
  String toString() => 'Secure credential $operation failed: $key';
}

abstract class SecureCredentialBackend {
  Future<SecureCredentialReadResult> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MethodChannelSecureCredentialBackend implements SecureCredentialBackend {
  MethodChannelSecureCredentialBackend({this.forcePlatformChannel = false});

  static const MethodChannel _channel = MethodChannel(
    'fly_player/secret_store',
  );

  final bool forcePlatformChannel;
  final Map<String, String> _testValues = <String, String>{};

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) {
      return const SecureCredentialReadResult.missing();
    }
    if (_usesTestMemoryBackend) {
      return _resultForValue(_testValues[normalized]);
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'readCredential',
        <String, String>{'key': normalized},
      );
      return switch (raw?['status']) {
        'value' => SecureCredentialReadResult.found(
          (raw?['value'] ?? '').toString(),
        ),
        'missing' => const SecureCredentialReadResult.missing(),
        _ => const SecureCredentialReadResult.unavailable(),
      };
    } on MissingPluginException {
      return const SecureCredentialReadResult.unavailable();
    } on PlatformException {
      return const SecureCredentialReadResult.unavailable();
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    if (value.isEmpty) {
      await delete(normalized);
      return;
    }
    if (_usesTestMemoryBackend) {
      _testValues[normalized] = value;
      return;
    }
    final succeeded = await _channel.invokeMethod<bool>('writeCredential', {
      'key': normalized,
      'value': value,
    });
    if (succeeded != true) {
      throw SecureCredentialOperationException('write', normalized);
    }
  }

  @override
  Future<void> delete(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    if (_usesTestMemoryBackend) {
      _testValues.remove(normalized);
      return;
    }
    final succeeded = await _channel.invokeMethod<bool>('deleteCredential', {
      'key': normalized,
    });
    if (succeeded != true) {
      throw SecureCredentialOperationException('delete', normalized);
    }
  }

  bool get _usesTestMemoryBackend =>
      !forcePlatformChannel && _usesTestMessenger();

  bool _usesTestMessenger() {
    try {
      return ServicesBinding.instance.defaultBinaryMessenger.runtimeType
          .toString()
          .contains('Test');
    } catch (_) {
      return true;
    }
  }
}

class MemorySecureCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<SecureCredentialReadResult> read(String key) async =>
      _resultForValue(_values[_normalizeKey(key)]);

  @override
  Future<void> write(String key, String value) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    if (value.isEmpty) {
      _values.remove(normalized);
    } else {
      _values[normalized] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(_normalizeKey(key));
  }
}

class SecureCredentialStore {
  static SecureCredentialBackend _backend =
      MethodChannelSecureCredentialBackend();

  const SecureCredentialStore._();

  static Future<SecureCredentialReadResult> read(String key) =>
      _backend.read(key);

  static Future<void> write(String key, String value) =>
      _backend.write(key, value);

  static Future<void> delete(String key) => _backend.delete(key);

  static void setBackendForTesting(SecureCredentialBackend backend) {
    _backend = backend;
  }

  static void resetBackendForTesting() {
    _backend = MethodChannelSecureCredentialBackend();
  }
}

SecureCredentialReadResult _resultForValue(String? value) {
  if (value == null || value.isEmpty) {
    return const SecureCredentialReadResult.missing();
  }
  return SecureCredentialReadResult.found(value);
}

String _normalizeKey(String key) => key.trim();
