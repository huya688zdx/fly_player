import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/playlist_view_preference_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('readViewType returns null when no cache exists', () async {
    const store = PlaylistViewPreferenceStore();
    expect(await store.readViewType(), isNull);
  });

  test(
    'writeViewType then readViewType round trips through shared_preferences key',
    () async {
      const store = PlaylistViewPreferenceStore();
      await store.writeViewType('card');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('playlist_view_type'), 'card');
      expect(await store.readViewType(), 'card');
    },
  );

  test('readViewType ignores invalid cached value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playlist_view_type': 'not-a-valid-mode',
    });
    const store = PlaylistViewPreferenceStore();
    expect(await store.readViewType(), isNull);
  });
}
