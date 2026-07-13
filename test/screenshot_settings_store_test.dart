import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/playback/screenshots/screenshot_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenshotSettingsStore', () {
    const store = ScreenshotSettingsStore();

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('loads custom save path mode when persisted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ScreenshotSettingsStore.savePathModeKey:
            ScreenshotSettingsStore.customSavePathMode,
      });

      final settings = await store.load();

      expect(settings.savePathMode, ScreenshotSettingsStore.customSavePathMode);
    });

    test('persists custom save path mode', () async {
      final settings = await store.savePathMode(
        ScreenshotSettingsStore.customSavePathMode,
      );

      expect(settings.savePathMode, ScreenshotSettingsStore.customSavePathMode);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ScreenshotSettingsStore.savePathModeKey),
        ScreenshotSettingsStore.customSavePathMode,
      );
    });
  });
}
