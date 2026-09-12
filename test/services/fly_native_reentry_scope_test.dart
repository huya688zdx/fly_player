import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/native_player_bridge.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native resolve and reload preserve launch scope and reject a previous binding callback',
    () async {
      const channel = MethodChannel('fly_player/native_player'),
          codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final stats = PlayStatsService.instance;
      var calls = 0;
      Object bind() => NativePlayerBridge.bindReentry(
        onResolvePlayback:
            (
              _, {
              qualityIndex,
              qualityMediaGuid,
              startPositionMs,
              subtitleGuid,
              audioGuid,
              audioTrackIndex,
              subtitleTrackIndex,
              preferredQualityResolution,
            }) async {
              calls++;
              return {
                'loadArgs': jsonEncode({'itemGuid': 'same'}),
              };
            },
        onReloadServerSession: (_, _) async {
          calls++;
          return {
            'loadArgs': jsonEncode({'itemGuid': 'same'}),
          };
        },
        onRecordProgress: (_) async {},
      );
      Future<Object?> send(String method, String scope) async {
        Object? result;
        await messenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            MethodCall(
              method,
              method == 'resolvePlayback'
                  ? {'itemGuid': 'same', 'statsScope': scope}
                  : {
                      'loadArgs': jsonEncode({
                        'itemGuid': 'same',
                        'statsScope': scope,
                      }),
                    },
            ),
          ),
          (bytes) {
            result = codec.decodeEnvelope(bytes!);
          },
        );
        return result;
      }

      await stats.bindOwnerScope('scope-a');
      var token = bind();
      try {
        final resolved = await send('resolvePlayback', 'scope-a') as Map;
        expect(
          jsonDecode(resolved['loadArgs'] as String)['statsScope'],
          'scope-a',
        );
        await stats.bindOwnerScope('scope-b');
        expect(await send('resolvePlayback', 'scope-a'), isNull);
        expect(calls, 1);
        token = bind();
        expect(await send('resolvePlayback', 'scope-a'), isNull);
        expect(await send('reloadServerSession', 'scope-a'), isNull);
        expect(calls, 1);
        final reload = await send('reloadServerSession', 'scope-b') as Map;
        expect(
          jsonDecode(reload['loadArgs'] as String)['statsScope'],
          'scope-b',
        );
        expect(calls, 2);
      } finally {
        NativePlayerBridge.unbindReentry(token);
        messenger.setMockMethodCallHandler(channel, null);
        await stats.bindOwnerScope('');
      }
    },
  );
}
