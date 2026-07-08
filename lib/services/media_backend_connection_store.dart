import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';

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
    final connections = _readConnections(targetPrefs);
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

    await targetPrefs.setString(activeKindKey, connection.kind.name);
    await targetPrefs.setString(
      connectionsKey,
      jsonEncode(
        connections.map((item) => item.toJson()).toList(growable: false),
      ),
    );
  }

  static Future<void> saveConnection(
    MediaBackendConnection connection, {
    SharedPreferences? prefs,
  }) async {
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    final connections = await _connectionsWith(connection, prefs: targetPrefs);
    await targetPrefs.setString(
      connectionsKey,
      jsonEncode(
        connections.map((item) => item.toJson()).toList(growable: false),
      ),
    );
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

  static List<MediaBackendConnection> _readConnections(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(connectionsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map<MediaBackendConnection?>(
            (item) => MediaBackendConnection.tryFromJson(
              Map<String, Object?>.from(item),
            ),
          )
          .whereType<MediaBackendConnection>()
          .toList(growable: false);
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
}
