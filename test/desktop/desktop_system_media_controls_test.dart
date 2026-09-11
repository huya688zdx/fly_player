import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_system_media_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('系统会话同步影片和状态，响应控制并在退出时清除', () async {
    const channel = MethodChannel('fly_player/system_media_controls');
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    final playing = <bool>[];
    Duration? sought;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => calls.add(call),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controls = DesktopSystemMediaControls(
      onPlaying: (value) async => playing.add(value),
      onSeek: (value) async => sought = value,
    );
    await controls.setMetadata(title: '验收影片', subtitle: '第 1 集');
    await controls.update(
      status: 'playing',
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 2),
      rate: 1,
    );
    await controls.update(
      status: 'paused',
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 2),
      rate: 1,
    );
    expect(calls.first.arguments, {'title': '验收影片', 'subtitle': '第 1 集'});
    expect(calls.last.arguments, {
      'status': 'paused',
      'position': 12000,
      'duration': 120000,
      'rate': 1.0,
    });
    for (final call in const [
      MethodCall('pause'),
      MethodCall('play'),
      MethodCall('seek', 30000),
    ]) {
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(call),
        (_) {},
      );
    }
    expect(playing, [false, true]);
    expect(sought, const Duration(seconds: 30));
    await controls.dispose();
    expect(calls.last.method, 'clear');
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('play')),
      (_) {},
    );
    expect(playing, [false, true]);
  });
}
