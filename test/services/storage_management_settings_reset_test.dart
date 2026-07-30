import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/services/storage_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel('fly_player/storage');
  const embeddingChannel = MethodChannel('fly_player/embedding');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      StartupPreferencesProvider.preferenceKey: true,
      'token': 'keep-login-token',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, (call) async {
          if (call.method == 'getParallelWindowSettings') {
            return <String, Object>{
              'enabled': false,
              'preferredPrimaryPaneSide': 'left',
              'preferredPlaybackPrimaryPaneSide': 'right',
              'splitRatioPreset': 'balanced',
              'defaultPlaybackFullscreen': true,
              'immersiveStatusBar': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, null);
  });

  test('重置设置会关闭启动直达海报首页但保留登录配置', () async {
    final themeProvider = AppThemeProvider();
    final parallelProvider = ParallelWindowSettingsProvider(autoLoad: false);
    final startupProvider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
    );
    await startupProvider.setOpenPosterHomeOnStartup(true);

    await StorageManagementService.instance.resetSettings(
      themeProvider: themeProvider,
      parallelWindowSettingsProvider: parallelProvider,
      startupPreferencesProvider: startupProvider,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(StartupPreferencesProvider.preferenceKey),
      isFalse,
    );
    expect(prefs.getString('token'), 'keep-login-token');
    expect(startupProvider.openPosterHomeOnStartup, isFalse);
  });
}
