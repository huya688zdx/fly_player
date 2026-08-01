import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/dynamic_theme_seed_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/theme_sampler');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await DynamicThemeSeedExtractor.clearCache();
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await DynamicThemeSeedExtractor.clearCache();
  });

  test('Android 原生取色通道接收完整图片请求头', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, Object>{
        'pixels': Int32List.fromList(<int>[
          0xFFFF0000,
          0xFF00FF00,
          0xFF0000FF,
          0xFFFFFFFF,
        ]),
      };
    });
    const headers = <String, String>{
      'Authorization': 'NAS_TOKEN',
      'Trim-MC-token': 'NAS_TOKEN',
      'x-access-code': 'BASE64_ACCESS_CODE',
      'x-access-source': 'app',
    };

    final seed = await DynamicThemeSeedExtractor.extract(
      imageUrl: 'https://nas.example/image-theme-test.jpg',
      imageHeaders: headers,
    );

    expect(seed, isNotNull);
    expect(capturedCall?.method, 'sampleImagePixels');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['imageUrl'], 'https://nas.example/image-theme-test.jpg');
    expect(arguments['headers'], headers);
    expect(arguments, isNot(contains('token')));
  });
}
