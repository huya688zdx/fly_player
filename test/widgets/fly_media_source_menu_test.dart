import 'package:flutter/material.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:flutter/services.dart';
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
import 'package:fly_player/utils/app_top_tip.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_hover_dropdown.dart';

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
  final activationAddresses = <String?>[];
  bool fail = false;
  @override
  Future<void> activate(
    Map<String, dynamic> binding, {
    String? address,
    String fnEntryToken = '',
  }) async {
    activations.add(binding['id'] as String);
    activationAddresses.add(address);
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
    DesktopEnvironment.debugOverridePlatform = false;
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    account = _MenuAccount();
  });
  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    AppTopTip().dispose();
    account.dispose();
    SecureCredentialStore.resetBackendForTesting();
  });
  Future<void> mount(
    WidgetTester tester, {
    AppThemeColors? pageColors,
    Locale locale = const Locale('zh', 'CN'),
  }) => tester.pumpWidget(
    ChangeNotifierProvider<FlyAccountController>.value(
      value: account,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppRuntimeColorScope(
          colors: pageColors,
          hasRuntimeColors: pageColors != null,
          child: const Scaffold(
            appBar: null,
            body: Align(
              alignment: Alignment.topLeft,
              child: FlyMediaSourceMenu(),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'source menu follows locale changes and preserves source labels',
    (tester) async {
      await mount(tester, locale: const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.text('家里的飞牛'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch media source'));
      await tester.pumpAndSettle();
      expect(find.text('Media sources'), findsOneWidget);
      expect(find.text('Account and media sources'), findsOneWidget);
      expect(find.text('Synced titles'), findsNothing);
      expect(find.text('Watch statistics'), findsNothing);
      await tester.tap(find.text('我的 Emby'));
      await tester.pumpAndSettle();
      expect(account.activations, ['emby']);

      await mount(tester, locale: const Locale('ja'));
      await tester.pumpAndSettle();
      expect(find.text('我的 Emby'), findsOneWidget);
      await tester.tap(find.byTooltip('メディアソースを切り替え'));
      await tester.pumpAndSettle();
      expect(find.text('メディアソース'), findsOneWidget);
      expect(find.text('同期済みの作品'), findsNothing);
      expect(find.text('視聴統計'), findsNothing);
      expect(find.text('切换媒体来源'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1200.0, 320.0, 240.0]) {
    testWidgets('PC source menu keeps the desktop panel at width $width', (
      tester,
    ) async {
      DesktopEnvironment.debugOverridePlatform = true;
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopHoverDropdown), findsOneWidget);
      final panel = find.byType(DesktopFloatingPanel);
      expect(panel, findsOneWidget);
      expect(find.byType(AppOptionSheetPanel), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      final rect = tester.getRect(panel);
      expect(rect.left, greaterThanOrEqualTo(12));
      expect(rect.right, lessThanOrEqualTo(width - 12));
      expect(find.text('账号与媒体来源'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的 Emby'));
      await tester.pumpAndSettle();
      expect(account.activations, ['emby']);
      expect(account.activationAddresses, [null]);
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      expect(find.text('我的 Emby'), findsOneWidget);
    });
  }

  testWidgets('PC source menu closes with Escape or an outside click', (
    tester,
  ) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(600, 500));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    expect(account.activations, isEmpty);
  });

  testWidgets('同名媒体账号通过服务器显示名和用户名区分', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    for (var i = 0; i < account.bindings.length; i++) {
      account.bindings[i]['label'] = '我的媒体账号';
      (account.bindings[i]['server'] as Map)['name'] = '家庭服务器 ${i + 1}';
    }
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(find.text('飞牛影视 · 家庭服务器 1 · media-user'), findsOneWidget);
    expect(find.text('Emby · 家庭服务器 2 · media-user'), findsOneWidget);
    await tester.tap(find.text('Emby · 家庭服务器 2 · media-user'));
    await tester.pumpAndSettle();
    expect(account.activations, ['emby']);
    expect(find.byType(DesktopFloatingPanel), findsNothing);
  });

  testWidgets('PC menu preserves brand assets, selection and page colors', (
    tester,
  ) async {
    DesktopEnvironment.debugOverridePlatform = true;
    final colors = AppThemeBuilder.build(
      AppThemePreset.forest,
    ).extension<AppThemeColors>()!;
    await mount(tester, pageColors: colors);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<DesktopDropdownOptionRow>(
      find.byType(DesktopDropdownOptionRow),
    );
    expect(rows.where((row) => row.selected).single.item.id, 'feiniu');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((asset) => asset.assetName);
    expect(
      assets,
      containsAll(['lib/img/feiniu_Logo.png', 'lib/img/Emby_logo.png']),
    );
    expect(tester.element(find.byType(DesktopFloatingPanel)).appColors, colors);
    final title = tester.widget<Text>(find.text('我的 Emby'));
    expect(title.style?.fontSize, 13);
    expect(find.text('已同步节目'), findsNothing);
    expect(find.text('观看统计'), findsNothing);
  });

  testWidgets('PC menu disables reauthorization and busy actions live', (
    tester,
  ) async {
    DesktopEnvironment.debugOverridePlatform = true;
    account.bindings[1]['status'] = 'reauth_required';
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    DesktopDropdownOptionRow row(String id) => tester
        .widgetList<DesktopDropdownOptionRow>(
          find.byType(DesktopDropdownOptionRow),
        )
        .singleWhere((row) => row.item.id == id);
    expect(row('emby').enabled, isFalse);
    expect(find.text('需要重新授权'), findsOneWidget);
    await tester.tap(find.text('我的 Emby'));
    expect(account.activations, isEmpty);
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    final staleAction = row('account').onTap;
    account.setBusy(true);
    await tester.pump();
    expect(row('account').enabled, isFalse);
    staleAction();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    expect(account.activations, isEmpty);
    account.setBusy(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'PC old callbacks reject changed accounts and a fresh menu works',
    (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      await mount(tester);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      final stale = tester
          .widgetList<DesktopDropdownOptionRow>(
            find.byType(DesktopDropdownOptionRow),
          )
          .singleWhere((row) => row.item.id == 'emby')
          .onTap;
      account.switchUser();
      await tester.pump();
      stale();
      await tester.pumpAndSettle();
      expect(account.activations, isEmpty);
      expect(
        tester
            .widgetList<DesktopDropdownOptionRow>(
              find.byType(DesktopDropdownOptionRow),
            )
            .every((row) => !row.enabled),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      // Even after a fresh menu opens, an old account's callback is rejected.
      stale();
      await tester.pumpAndSettle();
      expect(account.activations, isEmpty);
      await tester.tap(find.byTooltip('切换媒体来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的 Emby'));
      await tester.pumpAndSettle();
      expect(account.activations, ['emby']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PC failed switch keeps the current source and page', (
    tester,
  ) async {
    DesktopEnvironment.debugOverridePlatform = true;
    account.fail = true;
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的 Emby'));
    await tester.pumpAndSettle();
    expect(account.activeBindingId, 'feiniu');
    expect(find.byType(FlyMediaSourceMenu), findsOneWidget);
    expect(find.textContaining('媒体服务器暂时无法连接'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('PC busy trigger cannot open a menu', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    account.setBusy(true);
    await mount(tester);
    await tester.tap(find.byTooltip('切换媒体来源'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    expect(account.activations, isEmpty);
  });

  testWidgets('landscape source menu keeps the calling page colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final colors = AppThemeBuilder.build(
      AppThemePreset.forest,
    ).extension<AppThemeColors>()!;
    await mount(tester, pageColors: colors);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byKey(const ValueKey('media-source-emby'))).appColors,
      colors,
    );
  });

  testWidgets('home source menu changes source without another login or page', (
    tester,
  ) async {
    final server = account.bindings[1]['server'] as Map;
    (server['addresses'] as List).add({
      'purpose': 'client_remote',
      'base_url': 'https://remote.example/emby',
    });
    await mount(tester);
    expect(find.text('家里的飞牛'), findsOneWidget);
    await tester.tap(find.byTooltip('切换媒体来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的 Emby'));
    await tester.pumpAndSettle();
    expect(account.activations, ['emby']);
    expect(account.activationAddresses, [null]);
    expect(find.text('选择播放连接'), findsNothing);
    expect(find.text('连接设置'), findsNothing);
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
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('媒体服务器暂时无法连接'), findsNothing);
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
    expect(find.text('已同步节目'), findsNothing);
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
    expect(find.text('已同步节目'), findsNothing);
    expect(find.text('观看统计'), findsNothing);
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
        find.text('账号与媒体来源'),
        300,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('账号与媒体来源').hitTestable(), findsOneWidget);
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
