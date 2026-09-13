import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_oped_settings.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';

FlyDataSession fixtureSession({String token = 'fixture-token', String user = 'alice'}) =>
    FlyDataSession(serverUrl: 'http://service.invalid', userId: user,
      username: user, deviceId: 'device', deviceName: 'fixture', token: token,
      installationId: 'installation', serviceInstanceId: 'instance');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verified OPED preference persists independently of chapter skipping', () async {
    SharedPreferences.setMockInitialValues({'player_intro_outro_enabled': false});
    expect(await FlyOpedSettings.load(), isTrue);
    await FlyOpedSettings.save(false);
    expect(await FlyOpedSettings.load(), isFalse);
    await FlyOpedSettings.save(true);
    expect(await FlyOpedSettings.load(), isTrue);
    expect((await SharedPreferences.getInstance()).getBool('player_intro_outro_enabled'), isFalse);
  });

  test('login, account switch and logout notify UI without exposing credentials', () {
    final service = FlyDataService(database: SqflitePlayStatsDatabase(), drainWrites: () async {});
    final states = <String>[];
    service.accountChanges.addListener(() => states.add(service.accountChanges.value));
    service.session = fixtureSession();
    service.session = fixtureSession(token: 'refreshed-fixture-token');
    expect(states, hasLength(1), reason: 'A token refresh must not reset an active seek');
    service.session = fixtureSession(user: 'bob');
    service.session = null;
    expect(states, hasLength(3));
    expect(states.last, isEmpty);
    expect(states.join(), isNot(contains('fixture-token')));
    expect(service.session, isNull);
    service.accountChanges.dispose();
  });
}
