import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/api/dandanplay_config.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fly_player/secret_store');
  const appId = String.fromEnvironment('DANDANPLAY_APP_ID');
  const secret = String.fromEnvironment('DANDANPLAY_APP_SECRET');
  const fallback = String.fromEnvironment('DANDANPLAY_APP_SECRET_FALLBACK');

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform loads only build credentials without an Android channel',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <String>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call.method);
          throw MissingPluginException();
        });
        addTearDown(() async {
          await DanDanPlayConfig.clearCachedConfig();
          debugDefaultTargetPlatformOverride = null;
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });
        await DanDanPlayConfig.clearCachedConfig();
        final config = await DanDanPlayConfig.ensureLoaded(forceRefresh: true);
        final secrets = {secret.trim(), fallback.trim()}..remove('');
        final configured = appId.trim().isNotEmpty && secrets.isNotEmpty;
        expect(config.configured, configured);
        expect(config.appId, configured ? appId.trim() : '');
        expect(config.appSecrets, configured ? secrets.toList() : isEmpty);
        expect(
          config.statusMessage,
          configured ? '' : DanDanPlayConfig.defaultUnavailableMessage,
        );
        expect(await DanDanPlayConfig.ensureLoaded(), same(config));
        expect(calls, isEmpty);
      },
    );
  }
}
