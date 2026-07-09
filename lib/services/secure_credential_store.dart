import 'package:flutter/services.dart';

abstract class SecureCredentialBackend {
  Future<String> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MethodChannelSecureCredentialBackend implements SecureCredentialBackend {
  static const MethodChannel _channel = MethodChannel(
    'fly_player/secret_store',
  );

  final Map<String, String> _memoryFallback = <String, String>{};
  bool _useMemoryFallback = false;

  @override
  Future<String> read(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return '';
    _activateMemoryFallbackForTests();
    if (_useMemoryFallback) {
      return _memoryFallback[normalized] ?? '';
    }
    try {
      final value = await _channel.invokeMethod<String>('readCredential', {
        'key': normalized,
      });
      return value ?? '';
    } on MissingPluginException {
      _useMemoryFallback = true;
      return _memoryFallback[normalized] ?? '';
    } on PlatformException {
      _useMemoryFallback = true;
      return _memoryFallback[normalized] ?? '';
    } catch (_) {
      _useMemoryFallback = true;
      return _memoryFallback[normalized] ?? '';
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
    _activateMemoryFallbackForTests();
    if (_useMemoryFallback) {
      _memoryFallback[normalized] = value;
      return;
    }
    try {
      await _channel.invokeMethod<void>('writeCredential', {
        'key': normalized,
        'value': value,
      });
    } on MissingPluginException {
      _useMemoryFallback = true;
      _memoryFallback[normalized] = value;
    } on PlatformException {
      _useMemoryFallback = true;
      _memoryFallback[normalized] = value;
    } catch (_) {
      _useMemoryFallback = true;
      _memoryFallback[normalized] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    _memoryFallback.remove(normalized);
    _activateMemoryFallbackForTests();
    if (_useMemoryFallback) return;
    try {
      await _channel.invokeMethod<void>('deleteCredential', {
        'key': normalized,
      });
    } on MissingPluginException {
      _useMemoryFallback = true;
    } on PlatformException {
      _useMemoryFallback = true;
    } catch (_) {
      _useMemoryFallback = true;
    }
  }

  void _activateMemoryFallbackForTests() {
    if (_useMemoryFallback) return;
    try {
      final messengerType = ServicesBinding
          .instance
          .defaultBinaryMessenger
          .runtimeType
          .toString();
      if (messengerType.contains('Test')) {
        _useMemoryFallback = true;
      }
    } catch (_) {
      _useMemoryFallback = true;
    }
  }
}

class MemorySecureCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String> read(String key) async => _values[_normalizeKey(key)] ?? '';

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

  static Future<String> read(String key) => _backend.read(key);

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

String _normalizeKey(String key) => key.trim();
