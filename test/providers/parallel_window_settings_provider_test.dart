import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/desktop/desktop_environment.dart';

import 'package:fly_player/providers/parallel_window_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/embedding');

  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('桌面无原生通道时，重新加载保留分屏开关、方向和比例', () async {
    DesktopEnvironment.debugOverridePlatform = true;
    SharedPreferences.setMockInitialValues({});
    final provider = ParallelWindowSettingsProvider(autoLoad: false);
    await provider.load();
    expect(provider.enabled, isFalse);
    await provider.setEnabled(true);
    await provider.setPreferredPrimaryPaneSide('right');
    await provider.setSplitRatioPreset('focus_detail');
    final restored = ParallelWindowSettingsProvider(autoLoad: false);
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.primaryOnLeft, isFalse);
    expect(restored.splitRatioPreset, 'focus_detail');
    provider.dispose();
    restored.dispose();
  });

  test('保存失败时恢复更新前的并行窗口设置', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getParallelWindowSettings':
              return <String, Object?>{
                'enabled': true,
                'preferredPrimaryPaneSide': 'left',
                'preferredPlaybackPrimaryPaneSide': 'right',
                'splitRatioPreset': 'balanced',
                'defaultPlaybackFullscreen': true,
                'immersiveStatusBar': true,
              };
            case 'updateParallelWindowSettings':
              return null;
          }
          return null;
        });

    final provider = ParallelWindowSettingsProvider(
      autoLoad: false,
      saveSettings: (_) async => throw StateError('save failed'),
    );
    await provider.load();

    await expectLater(provider.setEnabled(false), throwsStateError);
    expect(provider.enabled, isTrue);
  });
}
