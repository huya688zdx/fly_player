import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/services/native_player_bridge.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_oped_settings.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native OPED settings use current login and scope, never a supplied login flag', () async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('fly_player/native_player');
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final stats = PlayStatsService.instance;
    final service = FlyDataService.instance;
    final scope = PlayStatsService.scopeForBinding('http://service.invalid|alice', 'fixture-binding');
    await stats.bindOwnerScope(scope);
    (stats.database as SqflitePlayStatsDatabase).bindingReference = {'binding_id': 'fixture-binding'};
    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback: (_, {qualityIndex, qualityMediaGuid, startPositionMs,
        subtitleGuid, audioGuid, audioTrackIndex, subtitleTrackIndex, preferredQualityResolution}) async => null,
      onRecordProgress: (_) async {},
    );
    Future<dynamic> send(String method, [Map<String, Object?> args = const {}]) async {
      dynamic result;
      await messenger.handlePlatformMessage(channel.name,
        codec.encodeMethodCall(MethodCall(method, args)),
        (bytes) => result = codec.decodeEnvelope(bytes!));
      return result;
    }
    try {
      expect((await send('getFlyAccountState'))['signedIn'], isFalse);
      expect(await send('loadNasDanmakuSource', {'statsScope': scope,
        'itemGuid': 'item', 'signedIn': true}), {'status': 'unavailable'});
      expect(await send('persistFlyOpedSettings', {'enabled': false,
        'statsScope': scope, 'signedIn': true}), isFalse);
      expect(await FlyOpedSettings.load(), isTrue);
      service.session = FlyDataSession(serverUrl: 'http://service.invalid', userId: 'alice',
        username: 'alice', deviceId: 'device', deviceName: 'fixture',
        token: 'fixture-private-token', installationId: 'installation');
      final state = await send('getFlyAccountState');
      expect(state['signedIn'], isTrue);
      expect(await send('loadNasDanmakuSource', {'statsScope': 'old-source',
        'itemGuid': 'item'}), {'status': 'unavailable'});
      expect(await send('loadNasDanmakuSource', {'statsScope': scope,
        'itemGuid': ''}), {'status': 'missing'});
      expect(state.toString(), isNot(contains('fixture-private-token')));
      expect(await send('persistFlyOpedSettings', {'enabled': false, 'statsScope': 'old-source'}), isFalse);
      expect(await send('persistFlyOpedSettings', {'enabled': false, 'statsScope': scope}), isTrue);
      expect(await FlyOpedSettings.load(), isFalse);
      expect(await send('resolveFlyOped', {'statsScope': scope, 'itemGuid': 'item',
        'playback_context_id': 'fixture-context', 'generation': 0}), isNull);
      // Legacy login keeps the saved Fly account, but clears its active binding.
      await stats.bindOwnerScope('');
      expect(service.session, isNotNull);
      expect(await send('loadNasDanmakuSource', {'statsScope': scope,
        'itemGuid': 'item', 'signedIn': true}), {'status': 'unavailable'});
      expect((await send('getFlyAccountState'))['signedIn'], isFalse);
      expect(await send('persistFlyOpedSettings', {'enabled': true, 'statsScope': scope}), isFalse);
      service.session = null;
      expect((await send('getFlyAccountState'))['signedIn'], isFalse);
    } finally {
      service.session = null;
      NativePlayerBridge.unbindReentry(token);
      messenger.setMockMethodCallHandler(channel, null);
      await stats.bindOwnerScope('');
    }
  });
}
