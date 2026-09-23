import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/providers/app_locale_provider.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/screens/app_settings_screen.dart';
import 'package:fly_player/screens/detail_host_screen.dart';
import 'package:fly_player/screens/settings_destination_routes.dart';

void main() {
  const embeddingChannel = MethodChannel('fly_player/embedding');

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, (call) async {
          if (call.method == 'isParallelWindowSupported') return false;
          if (call.method == 'getParallelWindowSettings') {
            return <String, Object>{
              'enabled': false,
              'preferredPrimaryPaneSide': 'left',
              'preferredPlaybackPrimaryPaneSide': 'right',
              'splitRatioPreset': 'balanced',
              'defaultPlaybackFullscreen': true,
              'immersiveStatusBar': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, null);
  });

  testWidgets('设置副栏返回关闭子页，不重复显示主栏设置首页', (tester) async {
    final hostKey = GlobalKey<DetailHostScreenState>();
    await tester.pumpWidget(
      _settingsApp(
        StartupPreferencesProvider(autoLoad: false),
        child: DetailHostScreen(
          key: hostKey,
          initialRouteName: SettingsDestinationRoutes.theme,
          enablePlatformChannel: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.routeStackSnapshot, [
      SettingsDestinationRoutes.theme,
    ]);
    expect(await hostKey.currentState!.handleBack(), isFalse);

    hostKey.currentState!.openRouteInPlace(
      SettingsDestinationRoutes.themeCustomRecipe,
    );
    await tester.pumpAndSettle();
    expect(await hostKey.currentState!.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.currentRoute, SettingsDestinationRoutes.theme);
    expect(await hostKey.currentState!.handleBack(), isFalse);
  });

  testWidgets('设置首页显示启动直达海报首页开关并可立即保存', (tester) async {
    var saved = false;
    final startupPreferences = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (value) async {
        saved = value;
        return true;
      },
    );
    await startupPreferences.load();

    await tester.pumpWidget(_settingsApp(startupPreferences));
    await tester.pumpAndSettle();

    expect(find.text('启动直达海报首页'), findsOneWidget);
    expect(find.text('已有有效登录会话时，打开应用直接进入沉浸式海报浏览。'), findsOneWidget);
    final switchFinder = find.byKey(
      const ValueKey<String>('startup_poster_home_switch'),
    );
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(startupPreferences.openPosterHomeOnStartup, isTrue);
    expect(saved, isTrue);
  });

  testWidgets(
    'macOS Command K opens settings search',
    (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
      final startupPreferences = StartupPreferencesProvider(autoLoad: false);
      await tester.pumpWidget(_settingsApp(startupPreferences));
      await tester.pumpAndSettle();

      expect(find.text('⌘ K'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Apple settings search hides Android screenshot options',
    (tester) async {
      DesktopEnvironment.debugOverridePlatform = false;
      addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
      final startupPreferences = StartupPreferencesProvider(autoLoad: false);
      await tester.pumpWidget(_settingsApp(startupPreferences));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_open_full_search')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '截图');
      await tester.pumpAndSettle();
      expect(find.text('截图设置'), findsNothing);
      expect(find.text('自定义保存目录'), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );
}

Widget _settingsApp(
  StartupPreferencesProvider startupPreferences, {
  Widget child = const AppSettingsScreen(),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
      ChangeNotifierProvider(create: (_) => AppThemeProvider()),
      ChangeNotifierProvider(create: (_) => ParallelWindowSettingsProvider()),
      ChangeNotifierProvider<StartupPreferencesProvider>.value(
        value: startupPreferences,
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}
