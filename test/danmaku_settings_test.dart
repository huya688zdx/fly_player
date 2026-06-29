import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/danmaku/models/danmaku_settings.dart';

void main() {
  group('DanmakuSettings native player defaults', () {
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
