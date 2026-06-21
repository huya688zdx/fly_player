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
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
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
    final snapshot = await load(prefs: targetPrefs);
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

    await targetPrefs.setString(activeKindKey, connection.kind.name);
    await targetPrefs.setString(
      connectionsKey,
      jsonEncode(
        connections.map((item) => item.toJson()).toList(growable: false),
      ),
    );
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
          .map(
            (item) => MediaBackendConnection.fromJson(
              Map<String, Object?>.from(item),
            ),
          )
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
