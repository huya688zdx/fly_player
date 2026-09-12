import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
  });
  test('service instance identity survives an address change', () {
    FlyDataSession session(String url) => FlyDataSession.fromJson({
      'server_url': url,
      'service_instance_id': 'instance',
      'user_id': 'user',
      'username': 'name',
      'device_id': 'device',
      'device_name': 'device',
      'token': 'secret',
      'installation_id': 'install',
    });
    expect(session('https://home.example').accountKey, 'instance|user');
    expect(
      session('http://10.0.0.1:8787').accountKey,
      session('https://home.example').accountKey,
    );
  });
  test(
    'same kind bindings retain distinct credentials and selected identity',
    () async {
      MediaBackendConnection connection(String id, String account) =>
          MediaBackendConnection.fromJson({
            'kind': 'emby',
            'serverUrl': 'https://$id.example',
            'accessToken': 'token-$account-$id',
            'bindingId': id,
            'accountKey': account,
          });
      await MediaBackendConnectionStore.saveActive(connection('one', 'alice'));
      await MediaBackendConnectionStore.saveActive(connection('two', 'alice'));
      await MediaBackendConnectionStore.saveConnection(
        connection('one', 'bob'),
      );
      final snapshot = await MediaBackendConnectionStore.load();
      expect(snapshot.connections, hasLength(3));
      expect(snapshot.activeConnection.accessToken, 'token-alice-two');
      expect(snapshot.connections.map((e) => e.accessToken).toSet(), {
        'token-alice-one',
        'token-alice-two',
        'token-bob-one',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(MediaBackendConnectionStore.connectionsKey),
        isNot(contains('token-')),
      );
    },
  );
}
