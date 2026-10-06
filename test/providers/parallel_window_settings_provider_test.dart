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

  test('桌面无原生通道时，重新加载保留分屏方向、比例与悬浮小窗开关（二选一）', () async {
    DesktopEnvironment.debugOverridePlatform = true;
    SharedPreferences.setMockInitialValues({});
    final provider = ParallelWindowSettingsProvider(autoLoad: false);
    await provider.load();
    expect(provider.enabled, isFalse);
    await provider.setEnabled(true);
    await provider.setPreferredPrimaryPaneSide('right');
    await provider.setSplitRatioPreset('focus_detail');
    // 二选一：开启悬浮小窗自动关闭平行窗口。
    await provider.setFloatingMiniPlayerEnabled(true);
    final restored = ParallelWindowSettingsProvider(autoLoad: false);
    await restored.load();
    expect(restored.enabled, isFalse);
    expect(restored.primaryOnLeft, isFalse);
    expect(restored.splitRatioPreset, 'focus_detail');
    expect(restored.floatingMiniPlayerEnabled, isTrue);
    provider.dispose();
    restored.dispose();
  });

  test('悬浮小窗与平行窗口二选一：开启一侧自动关闭另一侧，关闭不反向联动', () async {
    DesktopEnvironment.debugOverridePlatform = true;
    SharedPreferences.setMockInitialValues({});
    final provider = ParallelWindowSettingsProvider(autoLoad: false);
    await provider.load();

    await provider.setEnabled(true);
    await provider.setFloatingMiniPlayerEnabled(true);
    expect(provider.floatingMiniPlayerEnabled, isTrue);
    expect(provider.enabled, isFalse);

    await provider.setEnabled(true);
    expect(provider.enabled, isTrue);
    expect(provider.floatingMiniPlayerEnabled, isFalse);

    // 关闭平行窗口不悄悄替用户打开悬浮小窗。
    await provider.setEnabled(false);
    expect(provider.floatingMiniPlayerEnabled, isFalse);
    provider.dispose();
  });

  test('悬浮小窗开关经保存通道下发宿主并回读', () async {
    Object? savedFloatingFlag;
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
                'floatingMiniPlayerEnabled': savedFloatingFlag == true,
              };
            case 'updateParallelWindowSettings':
              savedFloatingFlag = call.arguments['floatingMiniPlayerEnabled'];
              return <String, Object?>{
                'enabled': call.arguments['enabled'],
                'preferredPrimaryPaneSide':
                    call.arguments['preferredPrimaryPaneSide'],
                'preferredPlaybackPrimaryPaneSide':
                    call.arguments['preferredPlaybackPrimaryPaneSide'],
                'splitRatioPreset': call.arguments['splitRatioPreset'],
                'defaultPlaybackFullscreen':
                    call.arguments['defaultPlaybackFullscreen'],
                'immersiveStatusBar': call.arguments['immersiveStatusBar'],
                'floatingMiniPlayerEnabled': savedFloatingFlag,
              };
          }
          return null;
        });

    final provider = ParallelWindowSettingsProvider(autoLoad: false);
    await provider.load();
    // 默认关：宿主未下发该键时不得误开（入口让位序的保守口径）。
    expect(provider.floatingMiniPlayerEnabled, isFalse);

    await provider.setFloatingMiniPlayerEnabled(true);
    expect(savedFloatingFlag, isTrue);
    expect(provider.floatingMiniPlayerEnabled, isTrue);

    await provider.setFloatingMiniPlayerEnabled(false);
    expect(savedFloatingFlag, isFalse);
    expect(provider.floatingMiniPlayerEnabled, isFalse);
    provider.dispose();
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
