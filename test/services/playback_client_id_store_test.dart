import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/playback_client_id_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test(
    'ensureClientId generates and persists a new id under legacy key',
    () async {
      final store = PlaybackClientIdStore();

      final value = await store.ensureClientId();
      expect(value, isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('playback_client_id'), value);
    },
  );

  test('ensureClientId reuses an existing persisted id', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playback_client_id': 'existing-id',
    });
    final store = PlaybackClientIdStore();

    expect(await store.ensureClientId(), 'existing-id');
  });

  test('ensureClientId is stable across repeated calls', () async {
    final store = PlaybackClientIdStore();

    final first = await store.ensureClientId();
    final second = await store.ensureClientId();
    expect(second, first);
  });
}
