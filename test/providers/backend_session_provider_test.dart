import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('loads current Emby connection from the neutral store', () async {
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Living Room',
        userName: 'alice',
        userId: 'user-id',
        accessToken: 'access-token',
      ),
    );
    final provider = BackendSessionProvider(autoLoad: false);

    await provider.load();

    expect(provider.isReady, isTrue);
    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.serverUrl, 'https://emby.example.test');
    expect(provider.isConfigured, isTrue);
  });

  test('saveActive persists and exposes the new current connection', () async {
    final provider = BackendSessionProvider(autoLoad: false);

    await provider.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Living Room',
        userName: 'alice',
        userId: 'user-id',
        accessToken: 'access-token',
      ),
    );

    expect(provider.currentKind, MediaBackendKind.emby);
    expect(provider.currentConnection?.displayName, 'Living Room');

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.emby);
    expect(snapshot.activeConnection.userId, 'user-id');
  });
}
