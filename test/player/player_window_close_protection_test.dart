import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/playback/player_window_close_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '$platform player lock and cleanup do not call desktop plugins',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          debugDefaultTargetPlatformOverride = null;
        });

        await setPlayerWindowPreventClose(true);
        await setPlayerWindowPreventClose(false);

        expect(calls, isEmpty);
      },
    );
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    test(
      '$platform player lock sets and clears window close protection',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          debugDefaultTargetPlatformOverride = null;
        });

        await setPlayerWindowPreventClose(true);
        await setPlayerWindowPreventClose(false);

        expect(calls.map((call) => call.method), [
          'setPreventClose',
          'setPreventClose',
        ]);
        expect(calls.map((call) => call.arguments), [
          {'isPreventClose': true},
          {'isPreventClose': false},
        ]);
      },
    );
  }
}
