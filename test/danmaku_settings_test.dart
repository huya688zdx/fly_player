import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/danmaku/models/danmaku_settings.dart';

void main() {
  group('DanmakuSettings native player defaults', () {
    test('默认开启弹幕以便进入播放器时自动预取', () {
      expect(DanmakuSettings.defaults.enabled, isTrue);
    });

    test('旧设置缺少 enabled 时沿用当前默认值', () {
      final settings = DanmakuSettings.fromJson(const <String, dynamic>{});

      expect(settings.enabled, DanmakuSettings.defaults.enabled);
    });

    test('用户明确关闭弹幕时保留关闭状态', () {
      final settings = DanmakuSettings.fromJson(const <String, dynamic>{
        'enabled': false,
      });

      expect(settings.enabled, isFalse);
    });

    test('defaults to the native player shell', () {
      expect(DanmakuSettings.defaults.useNativeRenderer, isTrue);
    });

    test('uses native player shell when legacy settings omit the flag', () {
      final settings = DanmakuSettings.fromJson(const <String, dynamic>{
        'enabled': true,
      });

      expect(settings.useNativeRenderer, isTrue);
    });
  });
}
