import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/danmaku/settings/danmaku_settings_store.dart';
import 'package:fly_player/desktop/desktop_detail_pane_host.dart';
import 'package:fly_player/desktop/desktop_split_controller.dart';
import 'package:fly_player/desktop/playback/external_player_settings.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/external_player_settings_screen.dart';
import 'package:fly_player/screens/settings_destination_routes.dart';
import 'package:fly_player/theme/app_theme.dart';

Route<void> _route(RouteSettings settings) => MaterialPageRoute<void>(
  settings: settings,
  builder: (_) => settings.name == SettingsDestinationRoutes.externalPlayer
      ? const ExternalPlayerSettingsScreen()
      : const Scaffold(body: Center(child: Text('DANMAKU_PAGE'))),
);

Future<void> _pump(WidgetTester tester, {DesktopSplitController? split}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(split == null ? 440 : 1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      onGenerateRoute: _route,
      home: split == null
          ? const ExternalPlayerSettingsScreen()
          : DesktopDetailPaneHost(
              splitController: split,
              onGenerateRoute: _route,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  test('旧外部播放器配置沿用 PotPlayer，保存后记录播放器类型', () async {
    SharedPreferences.setMockInitialValues({
      'desktop_external_player_v1': jsonEncode({
        'enabled': false,
        'executablePath': r'D:\PotPlayer\PotPlayerMini64.exe',
      }),
    });
    final settings = await ExternalPlayerSettings.load();
    expect(settings.playerId, 'potplayer');
    expect(settings.adapter.displayName, 'PotPlayer');
    await settings.save();
    final saved = await ExternalPlayerSettings.load();
    expect(saved.playerId, settings.playerId);
    expect(saved.executablePath, settings.executablePath);
    final preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        preferences.getString('desktop_external_player_v1')!,
      )['playerId'],
      'potplayer',
    );
  });

  test('未知播放器类型不能被静默替换或保存', () async {
    SharedPreferences.setMockInitialValues({
      'desktop_external_player_v1': jsonEncode({'playerId': 'unknown-player'}),
    });
    await expectLater(ExternalPlayerSettings.load(), throwsStateError);
    await expectLater(
      const ExternalPlayerSettings(playerId: 'unknown-player').save(),
      throwsStateError,
    );
  });

  testWidgets('子页直接 push 后宿主记录真实栈，重开外部设置、返回和关闭一致', (tester) async {
    final split = DesktopSplitController(enabled: true);
    addTearDown(split.dispose);
    await _pump(tester, split: split);
    final host = tester.state<DesktopDetailPaneHostState>(
      find.byType(DesktopDetailPaneHost),
    );
    await host.openRoute(SettingsDestinationRoutes.externalPlayer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('弹幕设置'));
    await tester.pumpAndSettle();
    expect(find.text('DANMAKU_PAGE'), findsOneWidget);
    expect(host.currentRouteName, SettingsDestinationRoutes.danmaku);
    await tester.pump(const Duration(seconds: 1));
    expect(
      await host.openRoute(SettingsDestinationRoutes.externalPlayer),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExternalPlayerSettingsScreen), findsOneWidget);
    expect(host.currentRouteName, SettingsDestinationRoutes.externalPlayer);
    expect(
      await host.openRoute(SettingsDestinationRoutes.externalPlayer),
      isTrue,
    );
    expect(await host.backInPane(), isTrue);
    await tester.pumpAndSettle();
    expect(host.currentRouteName, SettingsDestinationRoutes.danmaku);
    expect(find.text('DANMAKU_PAGE'), findsOneWidget);
    await host.closePane();
    await tester.pumpAndSettle();
    expect(host.currentRouteName, isNull);
    expect(split.paneVisible, isFalse);
    await _dispose(tester);
  });

  for (final inPane in [false, true]) {
    testWidgets('弹幕页返回后重新读取设置 (${inPane ? '宽窗分屏' : '窄窗全页'})', (tester) async {
      final split = inPane ? DesktopSplitController(enabled: true) : null;
      if (split != null) addTearDown(split.dispose);
      await _pump(tester, split: split);
      if (split != null) {
        await tester
            .state<DesktopDetailPaneHostState>(
              find.byType(DesktopDetailPaneHost),
            )
            .openRoute(SettingsDestinationRoutes.externalPlayer);
        await tester.pumpAndSettle();
      }
      const store = DanmakuSettingsStore();
      final initial = await store.load();
      await tester.ensureVisible(find.text('弹幕设置'));
      await tester.tap(find.text('弹幕设置'));
      await tester.pumpAndSettle();
      await store.save(initial.copyWith(enabled: !initial.enabled));
      Navigator.of(tester.element(find.text('DANMAKU_PAGE'))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalPlayerSettingsScreen), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text('弹幕设置'), matching: find.byType(ListTile)),
      );
      expect(
        (tile.subtitle as Text).data,
        contains(initial.enabled ? '关闭' : '开启'),
      );
      await _dispose(tester);
    });
  }
}
