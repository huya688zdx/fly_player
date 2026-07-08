import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('defaults to Feiniu when legacy prefs exist', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://nas.example.test',
      'resolved_base_url': 'https://resolved-nas.example.test',
      'user_name': 'alice',
      'token': 'feiniu-token',
      'remember_password': true,
    });

    final snapshot = await MediaBackendConnectionStore.load();

    expect(snapshot.activeKind, MediaBackendKind.feiniu);
    expect(
      snapshot.activeConnection.serverUrl,
      'https://resolved-nas.example.test',
    );
    expect(snapshot.activeConnection.userName, 'alice');
    expect(snapshot.activeConnection.accessToken, 'feiniu-token');
    expect(snapshot.activeConnection.rememberSecret, isTrue);
  });

  test('saving Emby connection does not write legacy Feiniu keys', () async {
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Emby Home',
        userName: 'bob',
        userId: 'emby-user',
        accessToken: 'emby-token',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('base_url'), isNull);
    expect(prefs.getString('token'), isNull);

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.emby);
    expect(snapshot.activeConnection.serverUrl, 'https://emby.example.test');
    expect(snapshot.activeConnection.userId, 'emby-user');
    expect(snapshot.activeConnection.accessToken, 'emby-token');
  });

  test('saved Feiniu session does not overwrite legacy Feiniu prefs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://legacy-nas.example.test',
      'token': 'legacy-token',
    });

    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.feiniu,
        serverUrl: 'https://new-nas.example.test',
        accessToken: 'new-token',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('base_url'), 'https://legacy-nas.example.test');
    expect(prefs.getString('token'), 'legacy-token');

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.feiniu);
    expect(snapshot.activeConnection.serverUrl, 'https://new-nas.example.test');
  });

  test(
    'saving stored Emby connection can clear token without activating Emby',
    () async {
      await MediaBackendConnectionStore.saveActive(
        const MediaBackendConnection(
          kind: MediaBackendKind.emby,
          serverUrl: 'https://emby.example.test',
          displayName: 'Emby Home',
          userName: 'bob',
          userId: 'emby-user',
          accessToken: 'emby-token',
          secret: 'password',
        ),
      );
      await MediaBackendConnectionStore.saveActive(
        const MediaBackendConnection(
          kind: MediaBackendKind.feiniu,
          serverUrl: '',
        ),
      );

      await MediaBackendConnectionStore.saveConnection(
        const MediaBackendConnection(
          kind: MediaBackendKind.emby,
          serverUrl: 'https://emby.example.test',
          displayName: 'Emby Home',
          userName: 'bob',
          secret: 'password',
        ),
      );

      final snapshot = await MediaBackendConnectionStore.load();
      expect(snapshot.activeKind, MediaBackendKind.feiniu);
      final emby = snapshot.connectionFor(MediaBackendKind.emby);
      expect(emby, isNotNull);
      expect(emby!.isAuthenticated, isFalse);
      expect(emby.serverUrl, 'https://emby.example.test');
      expect(emby.userName, 'bob');
      expect(emby.secret, 'password');
      expect(emby.accessToken, isEmpty);
      expect(emby.userId, isEmpty);
    },
  );

  test('load ignores stored connections with unknown backend kind', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'jellyfin',
          'serverUrl': 'https://jellyfin.example.test',
          'accessToken': 'token',
        },
        const MediaBackendConnection(
          kind: MediaBackendKind.emby,
          serverUrl: 'https://emby.example.test',
          accessToken: 'emby-token',
        ).toJson(),
      ]),
      MediaBackendConnectionStore.activeKindKey: 'jellyfin',
    });

    final snapshot = await MediaBackendConnectionStore.load();

    expect(snapshot.activeKind, MediaBackendKind.feiniu);
    expect(snapshot.connectionFor(MediaBackendKind.emby), isNotNull);
    expect(snapshot.connections, hasLength(1));
  });
}
