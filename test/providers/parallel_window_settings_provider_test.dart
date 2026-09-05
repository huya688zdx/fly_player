import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/providers/parallel_window_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/embedding');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
