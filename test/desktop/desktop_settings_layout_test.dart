import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/app_locale_provider.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/screens/app_settings_screen.dart';

void main() {
  const embeddingChannel = MethodChannel('fly_player/embedding');
  const desktopPaneKey = ValueKey<String>('desktop_settings_two_pane');
  const navGeneralKey = ValueKey<String>('desktop_settings_nav_general');
  const navAppearanceKey = ValueKey<String>('desktop_settings_nav_appearance');
  const navDataKey = ValueKey<String>('desktop_settings_nav_data');
  const startupSwitchKey = ValueKey<String>('startup_poster_home_switch');

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
    DesktopEnvironment.debugOverridePlatform = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, null);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(800, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final startupPreferences = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (value) async => true,
    );
    await startupPreferences.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
          ChangeNotifierProvider(create: (_) => AppThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => ParallelWindowSettingsProvider(),
          ),
          ChangeNotifierProvider<StartupPreferencesProvider>.value(
            value: startupPreferences,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('桌面环境宽视口显示双栏：左栏分类可见，点击分类切换右栏内容', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await pumpSettings(tester, size: const Size(1400, 900));

    // 双栏容器出现，左栏 5 个分类导航全部可见。
    expect(find.byKey(desktopPaneKey), findsOneWidget);
    expect(find.text('常用入口'), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('MPV播放器设置'), findsOneWidget);
    expect(find.text('储存管理'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);

    // 默认选中第一分类：右栏展示语言 / 启动直达 / FN Connect 常驻条目。
    expect(find.text('应用语言'), findsOneWidget);
    expect(find.text('启动直达海报首页'), findsOneWidget);
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    // 其他分类内容不在右栏。
    expect(find.text('缓存、截图、日志与应用数据'), findsNothing);

    // 点击「储存管理」分类：右栏切换为储存 / 下载 / 播放统计条目，无页面转场。
    await tester.tap(find.byKey(navDataKey));
    await tester.pumpAndSettle();
    expect(find.text('缓存、截图、日志与应用数据'), findsOneWidget);
    expect(find.text('已下载与下载中内容管理'), findsOneWidget);
    expect(find.text('本地播放统计与历史记录'), findsOneWidget);
    expect(find.text('已有有效登录会话时，打开应用直接进入沉浸式海报浏览。'), findsNothing);
    expect(find.byKey(startupSwitchKey), findsNothing);

    // 点击「主题设置」分类：右栏切换为主题条目（导航项 + 条目同名）。
    await tester.tap(find.byKey(navAppearanceKey));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsNWidgets(2));
    expect(find.text('已下载与下载中内容管理'), findsNothing);

    // 切回「常用入口」分类，内容恢复。
    await tester.tap(find.byKey(navGeneralKey));
    await tester.pumpAndSettle();
    expect(find.text('已有有效登录会话时，打开应用直接进入沉浸式海报浏览。'), findsOneWidget);
    expect(find.text('缓存、截图、日志与应用数据'), findsNothing);
  });

  testWidgets('窄视口回落既有单栏列表：无左栏导航，条目结构与旧路径一致', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await pumpSettings(tester);

    // 桌面双栏不出现。
    expect(find.byKey(desktopPaneKey), findsNothing);
    expect(find.byKey(navGeneralKey), findsNothing);
    expect(find.byKey(navDataKey), findsNothing);
    expect(find.text('常用入口'), findsNothing);

    // 既有单栏列表完整保留：全部条目同屏渲染。
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('应用语言'), findsOneWidget);
    expect(find.text('启动直达海报首页'), findsOneWidget);
    expect(find.text('MPV播放器设置'), findsOneWidget);
    expect(find.text('储存管理'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('全局播放数据统计'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('日志信息'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);

    // 既有交互入口可用。
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  testWidgets('非桌面平台即使视口足够宽也保持既有单栏列表', (tester) async {
    DesktopEnvironment.debugOverridePlatform = false;
    await pumpSettings(tester, size: const Size(1400, 900));

    expect(find.byKey(desktopPaneKey), findsNothing);
    expect(find.byKey(navGeneralKey), findsNothing);
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
  });
}
