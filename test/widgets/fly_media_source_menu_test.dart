import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/widgets/fly_media_source_menu.dart';

FlyDataSession _session(String user) => FlyDataSession(
  serverUrl: 'https://fly.example',
  userId: user,
  username: user,
  deviceId: 'device',
  deviceName: 'test',
  token: 'test',
  installationId: 'test',
  serviceInstanceId: 'fly',
);

class _MenuAccount extends FlyAccountController {
  _MenuAccount()
    : super(
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        service: FlyDataService(
          database: SqflitePlayStatsDatabase(),
          drainWrites: () async {},
        ),
        autoLoad: false,
      ) {
    service.session = _session('alice');
    activeBindingId = 'feiniu';
    bindings = [
      for (final kind in ['feiniu', 'emby'])
        {
          'id': kind,
          'label': kind == 'feiniu' ? '家里的飞牛' : '我的 Emby',
          'status': 'active',
          'revision': 1,
          'remote_username': 'media-user',
          'server': {
            'kind': kind,
            'addresses': [
              {
                'purpose': 'client_lan',
                'base_url': 'http://media.example/$kind',
              },
            ],
          },
        },
    ];
  }
  final activations = <String>[];
  bool fail = false;
  @override
  Future<void> activate(Map<String, dynamic> binding, {String? address}) async {
    activations.add(binding['id'] as String);
    if (fail) throw StateError('媒体服务器暂时无法连接');
    activeBindingId = binding['id'] as String;
    notifyListeners();
  }

  void switchUser() {
    service.session = _session('bob');
    notifyListeners();
  }

  @override
  void dispose() {
    nas.dispose();
    backendSession.dispose();
    super.dispose();
  }
}

void main() {
  late _MenuAccount account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    account = _MenuAccount();
  });
  tearDown(() {
    account.dispose();
    SecureCredentialStore.resetBackendForTesting();
  });
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    ChangeNotifierProvider<FlyAccountController>.value(
      value: account,
      child: const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: Align(
            alignment: Alignment.topLeft,
            child: FlyMediaSourceMenu(),
          ),
        ),
      ),
    ),
  );

  testWidgets('home source menu changes source without another login or page', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('家里的飞牛'), findsOneWidget);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的 Emby'));
    await tester.pumpAndSettle();
    expect(account.activations, ['emby']);
    expect(find.text('我的 Emby'), findsOneWidget);
    expect(find.byType(FlyMediaSourceMenu), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed source change retains the current home and reports the error',
    (tester) async {
      account.fail = true;
      await mount(tester);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的 Emby'));
      await tester.pumpAndSettle();
      expect(account.activeBindingId, 'feiniu');
      expect(find.text('家里的飞牛'), findsOneWidget);
      expect(find.textContaining('媒体服务器暂时无法连接'), findsOneWidget);
    },
  );

  testWidgets(
    'an open menu cannot activate a binding after the Fly account changes',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      account.switchUser();
      await tester.pump();
      await tester.tap(find.text('我的 Emby'));
      await tester.pumpAndSettle();
      expect(account.activations, isEmpty);
    },
  );

  testWidgets('long source names remain usable on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    account.bindings[0]['label'] = '家里的飞牛影视与动画媒体库非常长的名字';
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.text('账号与媒体来源'), findsOneWidget);
    expect(find.text('已同步节目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
