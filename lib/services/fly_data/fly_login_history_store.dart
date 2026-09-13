import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../secure_credential_store.dart';
import 'fly_data_api.dart';

class FlyLoginHistoryEntry {
  const FlyLoginHistoryEntry({
    required this.serverUrl,
    required this.username,
    required this.deviceName,
    this.serviceInstanceId = '',
    required this.updatedAtMillis,
    required this.rememberPassword,
    this.password = '',
  });

  final String serverUrl, username, deviceName, serviceInstanceId, password;
  final int updatedAtMillis;
  final bool rememberPassword;
  String get id => jsonEncode([
    serviceInstanceId.isEmpty ? 'url' : 'instance',
    serviceInstanceId.isEmpty
        ? normalizeServerUrl(serverUrl)
        : serviceInstanceId,
    username.trim(),
  ]);

  Map<String, Object> _metadata() => {
    'server_url': serverUrl,
    'username': username,
    'device_name': deviceName,
    'service_instance_id': serviceInstanceId,
    'updated_at_ms': updatedAtMillis,
    'remember_password': rememberPassword,
  };

  FlyLoginHistoryEntry _withPassword(String value, {bool? remember}) =>
      FlyLoginHistoryEntry(
        serverUrl: normalizeServerUrl(serverUrl),
        username: username.trim(),
        deviceName: deviceName.trim(),
        serviceInstanceId: serviceInstanceId,
        updatedAtMillis: updatedAtMillis,
        rememberPassword: remember ?? rememberPassword,
        password: value,
      );
}

/// Successful Fly logins only. Metadata contains no credentials; passwords are
/// bound to both the account identity and exact URL in the platform secure store.
class FlyLoginHistoryStore {
  static const _key = 'fly_login_history_v1';
  static const _maxEntries = 10;
  static Future<void> _pending = Future<void>.value();

  /// Use only after the previous widget test clock has ended and the test
  /// backend is reset. This does not cancel I/O or clear persisted records.
  @visibleForTesting
  static void resetPendingForTesting() {
    _pending = Future<void>.value();
  }

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static String _passwordKey(FlyLoginHistoryEntry entry) {
    final identity = jsonEncode([
      entry.id,
      normalizeServerUrl(entry.serverUrl),
    ]);
    return 'fly_login_history.password.${sha256.convert(utf8.encode(identity))}';
  }

  static Future<List<FlyLoginHistoryEntry>> _metadata() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((value) {
      final row = value as Map;
      return FlyLoginHistoryEntry(
        serverUrl: normalizeServerUrl(row['server_url'] as String),
        username: (row['username'] as String).trim(),
        deviceName: row['device_name'] as String,
        serviceInstanceId: row['service_instance_id'] as String? ?? '',
        updatedAtMillis: row['updated_at_ms'] as int,
        rememberPassword: row['remember_password'] as bool,
      );
    }).toList();
  }

  static Future<void> _persist(List<FlyLoginHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key,
      jsonEncode(entries.map((entry) => entry._metadata()).toList()),
    )) {
      throw StateError('无法保存飞翔登录记录。');
    }
  }

  static Future<List<FlyLoginHistoryEntry>> load() => _serialized(() async {
    final entries = await _metadata();
    final restored = <FlyLoginHistoryEntry>[];
    for (final entry in entries) {
      final credential = entry.rememberPassword
          ? await SecureCredentialStore.read(_passwordKey(entry))
          : const SecureCredentialReadResult.missing();
      // A temporarily unavailable secure store never changes saved metadata.
      restored.add(entry._withPassword(credential.value));
    }
    return List.unmodifiable(restored);
  });

  static Future<void> save(FlyLoginHistoryEntry entry) => _serialized(() async {
    final normalized = entry._withPassword(
      entry.rememberPassword ? entry.password : '',
    );
    final previous = await _metadata();
    final next = [
      normalized,
      ...previous.where((row) => row.id != normalized.id),
    ]..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final kept = next.take(_maxEntries).toList();
    final keptKeys = kept.map(_passwordKey).toSet();
    // Remove the old account/address secret before publishing new metadata.
    // If a later write fails, neither an orphan nor an old password can be
    // mistaken for the newly remembered password.
    final removed = {
      _passwordKey(normalized),
      for (final row in previous)
        if (row.id == normalized.id || !keptKeys.contains(_passwordKey(row)))
          _passwordKey(row),
    };
    for (final key in removed) {
      await SecureCredentialStore.delete(key);
    }
    await _persist(kept);
    if (kept.contains(normalized) && normalized.password.isNotEmpty) {
      await SecureCredentialStore.write(
        _passwordKey(normalized),
        normalized.password,
      );
    }
  });

  static Future<void> clear() => _serialized(() async {
    for (final entry in await _metadata()) {
      await SecureCredentialStore.delete(_passwordKey(entry));
    }
    await _persist([]);
  });

  static Future<void> updateAddress(
    FlyLoginHistoryEntry previous,
    FlyLoginHistoryEntry next,
  ) => _serialized(() async {
    final entries = await _metadata();
    final index = entries.indexWhere(
      (entry) =>
          entry.id == previous.id &&
          entry.serverUrl == normalizeServerUrl(previous.serverUrl),
    );
    // Clearing history or signing in again wins over a late address callback.
    if (index < 0) return;
    if (previous.username.trim() != next.username.trim() ||
        (previous.serviceInstanceId.isNotEmpty &&
            previous.serviceInstanceId != next.serviceInstanceId) ||
        (previous.serviceInstanceId.isEmpty &&
            normalizeServerUrl(previous.serverUrl) !=
                normalizeServerUrl(next.serverUrl))) {
      throw ArgumentError('An address update must keep the verified account.');
    }
    if (previous.id != next.id && entries.any((entry) => entry.id == next.id)) {
      return;
    }
    await SecureCredentialStore.delete(_passwordKey(entries[index]));
    await SecureCredentialStore.delete(_passwordKey(next));
    entries[index] = FlyLoginHistoryEntry(
      serverUrl: normalizeServerUrl(next.serverUrl),
      username: next.username.trim(),
      deviceName: next.deviceName.trim(),
      serviceInstanceId: next.serviceInstanceId,
      updatedAtMillis: entries[index].updatedAtMillis,
      rememberPassword: false,
    );
    await _persist(entries);
  });

  static Future<void> forgetPassword(FlyLoginHistoryEntry entry) =>
      _serialized(() async {
        final entries = await _metadata();
        final next = <FlyLoginHistoryEntry>[];
        for (final current in entries) {
          if (current.id == entry.id) {
            await SecureCredentialStore.delete(_passwordKey(current));
            next.add(current._withPassword('', remember: false));
          } else {
            next.add(current);
          }
        }
        await _persist(next);
      });
}
