import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/main_host_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/main_host');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('宿主未实现通道（如 Windows）时 openPrimarySettings 返回 false 而不抛异常', () async {
    // 不注册 mock handler：invokeMethod 抛 MissingPluginException，桥接层需兜底。
    final handled = await MainHostBridge.openPrimarySettings(
      destinationRoute: '/screen/settings/theme',
    );
    expect(handled, isFalse);
  });

  test('宿主未实现通道时 switchPrimaryTab 返回 false 而不抛异常', () async {
    final handled = await MainHostBridge.switchPrimaryTab('home');
    expect(handled, isFalse);
  });

  test('宿主返回 true 时 openPrimarySettings 透传结果', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    final handled = await MainHostBridge.openPrimarySettings();
    expect(handled, isTrue);
  });
}
