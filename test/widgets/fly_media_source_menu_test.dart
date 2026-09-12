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
import 'package:fly_player/widgets/common/app_option_list.dart';

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

  void setBusy(bool value) {
    busy = value;
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
      final staleSelection = tester
          .widgetList<AppOptionListTile>(find.byType(AppOptionListTile))
          .firstWhere((tile) => tile.title == '我的 Emby')
          .onTap;
      account.switchUser();
      await tester.pump();
      // A callback captured before the account changed can still finish late.
      staleSelection();
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

  testWidgets('source menu uses the original option panel and brand assets', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      findsNothing,
    );
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.byType(AppOptionSheetPanel), findsOneWidget);
    final tiles = tester
        .widgetList<AppOptionListTile>(find.byType(AppOptionListTile))
        .toList();
    expect(tiles.where((tile) => tile.selected).single.title, '家里的飞牛');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((asset) => asset.assetName)
        .toList();
    expect(
      assets,
      containsAll(['lib/img/feiniu_Logo.png', 'lib/img/Emby_logo.png']),
    );
    expect(find.text('账号与媒体来源'), findsOneWidget);
    expect(find.text('已同步节目'), findsOneWidget);
    expect(find.text('观看统计'), findsOneWidget);
  });

  testWidgets('busy and reauthorization entries remain disabled', (
    tester,
  ) async {
    account.bindings[1]['status'] = 'reauth_required';
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.text('需要重新授权'), findsOneWidget);
    await tester.tap(find.text('我的 Emby'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(account.activations, isEmpty);
    expect(find.byType(AppOptionSheetPanel), findsOneWidget);
    account.setBusy(true);
    await tester.pump();
    await tester.tap(find.text('账号与媒体来源'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppOptionSheetPanel), findsOneWidget);
    account.setBusy(false);
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('busy title cannot open another source selector', (tester) async {
    account.setBusy(true);
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppOptionSheetPanel), findsNothing);
    expect(account.activations, isEmpty);
  });

  testWidgets(
    'many long sources stay scrollable inside a bounded narrow sheet',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      account.bindings.addAll(
        List.generate(
          24,
          (index) => {
            'id': 'extra-$index',
            'label': '家里的第 $index 个影视与动画媒体库非常长的名称',
            'status': 'active',
            'server': {'kind': 'jellyfin'},
          },
        ),
      );
      await mount(tester);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      final panel = find.byType(AppOptionSheetPanel);
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel).height, lessThan(640 * .82));
      final scrollable = find.descendant(
        of: panel,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('观看统计'),
        300,
        scrollable: scrollable,
      );
      expect(find.text('观看统计').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('landscape uses the original floating option surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    final panel = tester.widget<AppOptionSheetPanel>(
      find.byType(AppOptionSheetPanel),
    );
    expect(panel.floating, isTrue);
    expect(
      tester.getSize(find.byType(AppOptionSheetPanel)).width,
      lessThan(900),
    );
    expect(
      tester.getSize(find.byType(AppOptionSheetPanel)).height,
      lessThan(480),
    );
    expect(tester.takeException(), isNull);
  });
}
