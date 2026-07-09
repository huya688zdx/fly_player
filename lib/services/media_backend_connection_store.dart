import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';
import 'secure_credential_store.dart';

class MediaBackendConnectionSnapshot {
  const MediaBackendConnectionSnapshot({
    required this.activeKind,
    required this.connections,
  });

  final MediaBackendKind activeKind;
  final List<MediaBackendConnection> connections;

  MediaBackendConnection get activeConnection =>
      connectionFor(activeKind) ??
      MediaBackendConnection(kind: activeKind, serverUrl: '');

  MediaBackendConnection? connectionFor(MediaBackendKind kind) {
    for (final connection in connections) {
      if (connection.kind == kind) return connection;
    }
    return null;
  }
}

class MediaBackendConnectionStore {
  MediaBackendConnectionStore._();

  static const activeKindKey = 'media_backend_active_kind_v1';
  static const connectionsKey = 'media_backend_connections_v1';

  static const _legacyBaseUrlKey = 'base_url';
  static const _legacyResolvedBaseUrlKey = 'resolved_base_url';
  static const _legacyUserNameKey = 'user_name';
  static const _legacyTokenKey = 'token';
  static const _legacyRememberPasswordKey = 'remember_password';

  static Future<MediaBackendConnectionSnapshot> load({
    SharedPreferences? prefs,
  }) async {
    final SharedPreferences targetPrefs;
    if (prefs != null) {
      // 调用方显式传入（保存路径 / 单测）：由其掌控实例，不在此重读磁盘。
      targetPrefs = prefs;
    } else {
      targetPrefs = await SharedPreferences.getInstance();
      // 跨 isolate 同步当前后端：分屏副栏是独立 Flutter 引擎（独立 isolate），其
      // SharedPreferences 首读后会内存缓存。若副栏引擎在主引擎切换后端“之前”被预热，
      // 它缓存的是旧 activeKind/连接；主引擎随后切换只更新自己 isolate 的缓存与磁盘，
      // 副栏不会自动感知 → 副栏会用旧后端路由（如主已切回飞牛、副仍判 Emby，飞牛 item
      // 查 Emby 报 noData）。与 NasProvider._loadSettings 一致：先 reload() 从磁盘重读。
      await targetPrefs.reload();
    }
    final connections = await _readConnections(targetPrefs);
    final legacyFeiniu = _readLegacyFeiniuConnection(targetPrefs);
    final mergedConnections = _mergeLegacyFeiniu(connections, legacyFeiniu);
    final activeKind =
        _readActiveKind(targetPrefs) ??
        legacyFeiniu?.kind ??
        MediaBackendKind.feiniu;

    return MediaBackendConnectionSnapshot(
      activeKind: activeKind,
      connections: List<MediaBackendConnection>.unmodifiable(mergedConnections),
    );
  }

  static Future<void> saveActive(
    MediaBackendConnection connection, {
    SharedPreferences? prefs,
  }) async {
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    final connections = await _connectionsWith(connection, prefs: targetPrefs);
    await _persistConnectionCredentials(connection);

    await targetPrefs.setString(activeKindKey, connection.kind.name);
    await _writeConnections(targetPrefs, connections);
  }

  static Future<void> saveConnection(
    MediaBackendConnection connection, {
    SharedPreferences? prefs,
  }) async {
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    final connections = await _connectionsWith(connection, prefs: targetPrefs);
    await _persistConnectionCredentials(connection);
    await _writeConnections(targetPrefs, connections);
  }

  static Future<List<MediaBackendConnection>> _connectionsWith(
    MediaBackendConnection connection, {
    required SharedPreferences prefs,
  }) async {
    final snapshot = await load(prefs: prefs);
    final connections = <MediaBackendConnection>[];
    var replaced = false;
    for (final current in snapshot.connections) {
      if (current.kind == connection.kind) {
        connections.add(connection);
        replaced = true;
      } else {
        connections.add(current);
      }
    }
    if (!replaced) {
      connections.add(connection);
    }
    return connections;
  }

  static MediaBackendKind? _readActiveKind(SharedPreferences prefs) {
    final kindName = prefs.getString(activeKindKey)?.trim();
    if (kindName == null || kindName.isEmpty) return null;
    for (final kind in MediaBackendKind.values) {
      if (kind.name == kindName) return kind;
    }
    return null;
  }

  static Future<List<MediaBackendConnection>> _readConnections(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(connectionsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final connections = <MediaBackendConnection>[];
      var needsRewrite = false;
      for (final item in decoded.whereType<Map>()) {
        final storageJson = Map<String, Object?>.from(item);
        final connection = MediaBackendConnection.tryFromJson(storageJson);
        if (connection == null) {
          needsRewrite = true;
          continue;
        }
        final restored = await _restoreConnectionCredentials(
          connection,
          hasAccessToken:
              storageJson['hasAccessToken'] == true ||
              connection.accessToken.isNotEmpty,
          hasSecret:
              storageJson['hasSecret'] == true || connection.secret.isNotEmpty,
          hasEntryToken:
              storageJson['hasEntryToken'] == true ||
              connection.entryToken.isNotEmpty,
        );
        connections.add(restored);
        if (connection.accessToken.isNotEmpty ||
            connection.secret.isNotEmpty ||
            connection.entryToken.isNotEmpty) {
          needsRewrite = true;
        }
      }
      if (needsRewrite) {
        await _writeConnections(prefs, connections);
      }
      return connections;
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  static List<MediaBackendConnection> _mergeLegacyFeiniu(
    List<MediaBackendConnection> connections,
    MediaBackendConnection? legacyFeiniu,
  ) {
    if (legacyFeiniu == null) return connections;
    final merged = <MediaBackendConnection>[];
    var hasFeiniu = false;
    for (final connection in connections) {
      if (connection.kind == MediaBackendKind.feiniu) {
        hasFeiniu = true;
      }
      merged.add(connection);
    }
    if (!hasFeiniu) {
      merged.add(legacyFeiniu);
    }
    return merged;
  }

  static MediaBackendConnection? _readLegacyFeiniuConnection(
    SharedPreferences prefs,
  ) {
    final resolvedBaseUrl =
        prefs.getString(_legacyResolvedBaseUrlKey)?.trim() ?? '';
    final baseUrl = prefs.getString(_legacyBaseUrlKey)?.trim() ?? '';
    final serverUrl = resolvedBaseUrl.isNotEmpty ? resolvedBaseUrl : baseUrl;
    final token = prefs.getString(_legacyTokenKey)?.trim() ?? '';
    if (serverUrl.isEmpty && token.isEmpty) return null;

    return MediaBackendConnection(
      kind: MediaBackendKind.feiniu,
      serverUrl: serverUrl,
      userName: prefs.getString(_legacyUserNameKey)?.trim() ?? '',
      accessToken: token,
      rememberSecret: prefs.getBool(_legacyRememberPasswordKey) ?? true,
    );
  }

  static Future<void> _writeConnections(
    SharedPreferences prefs,
    List<MediaBackendConnection> connections,
  ) async {
    await prefs.setString(
      connectionsKey,
      jsonEncode(
        connections.map(_connectionStorageJson).toList(growable: false),
      ),
    );
  }

  static Map<String, Object?> _connectionStorageJson(
    MediaBackendConnection connection,
  ) {
    return <String, Object?>{
      'kind': connection.kind.name,
      'serverUrl': connection.serverUrl,
      'displayName': connection.displayName,
      'userName': connection.userName,
      'userId': connection.userId,
      'rememberSecret': connection.rememberSecret,
      'updatedAtMillis': connection.updatedAtMillis,
      'hasAccessToken': connection.accessToken.isNotEmpty,
      'hasSecret': connection.rememberSecret && connection.secret.isNotEmpty,
      'hasEntryToken': connection.entryToken.isNotEmpty,
    };
  }

  static Future<MediaBackendConnection> _restoreConnectionCredentials(
    MediaBackendConnection connection, {
    required bool hasAccessToken,
    required bool hasSecret,
    required bool hasEntryToken,
  }) async {
    final keys = _credentialKeys(connection.kind);
    final accessToken = await _restoreCredential(
      keys.accessToken,
      legacyValue: connection.accessToken,
      shouldKeep: hasAccessToken,
    );
    final secret = await _restoreCredential(
      keys.secret,
      legacyValue: connection.secret,
      shouldKeep: connection.rememberSecret && hasSecret,
    );
    final entryToken = await _restoreCredential(
      keys.entryToken,
      legacyValue: connection.entryToken,
      shouldKeep: hasEntryToken,
    );
    return MediaBackendConnection(
      kind: connection.kind,
      serverUrl: connection.serverUrl,
      displayName: connection.displayName,
      userName: connection.userName,
      userId: connection.userId,
      accessToken: accessToken,
      secret: secret,
      rememberSecret: connection.rememberSecret,
      updatedAtMillis: connection.updatedAtMillis,
      entryToken: entryToken,
    );
  }

  static Future<String> _restoreCredential(
    String key, {
    required String legacyValue,
    required bool shouldKeep,
  }) async {
    if (!shouldKeep) {
      await SecureCredentialStore.delete(key);
      return '';
    }
    final stored = await SecureCredentialStore.read(key);
    if (stored.isNotEmpty) return stored;
    if (legacyValue.isNotEmpty) {
      await SecureCredentialStore.write(key, legacyValue);
      return legacyValue;
    }
    return '';
  }

  static Future<void> _persistConnectionCredentials(
    MediaBackendConnection connection,
  ) async {
    final keys = _credentialKeys(connection.kind);
    await _writeOrDelete(keys.accessToken, connection.accessToken);
    await _writeOrDelete(
      keys.secret,
      connection.rememberSecret ? connection.secret : '',
    );
    await _writeOrDelete(keys.entryToken, connection.entryToken);
  }

  static Future<void> _writeOrDelete(String key, String value) async {
    if (value.isEmpty) {
      await SecureCredentialStore.delete(key);
    } else {
      await SecureCredentialStore.write(key, value);
    }
  }

  static _ConnectionCredentialKeys _credentialKeys(MediaBackendKind kind) {
    final prefix = 'media_backend_connection.${kind.name}';
    return _ConnectionCredentialKeys(
      accessToken: '$prefix.access_token',
      secret: '$prefix.secret',
      entryToken: '$prefix.entry_token',
    );
  }
}

class _ConnectionCredentialKeys {
  final String accessToken;
  final String secret;
  final String entryToken;

  const _ConnectionCredentialKeys({
    required this.accessToken,
    required this.secret,
    required this.entryToken,
  });
}
