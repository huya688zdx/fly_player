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
import 'package:fly_player/screens/theme_settings_screen.dart';

void main() {
  const embeddingChannel = MethodChannel('fly_player/embedding');
  const mainHostChannel = MethodChannel('fly_player/main_host');
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
    // 模拟 Windows 无宿主实现：invokeMethod 抛 MissingPluginException
    // （testWidgets 中未 mock 的通道会挂起而非抛错，必须显式 mock）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mainHostChannel, (call) async {
          throw MissingPluginException(
            'No implementation found for method ${call.method}',
          );
        });
  });

  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mainHostChannel, null);
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

  testWidgets('桌面端宽视口显示分组卡片网格：四个分组与全部条目可见', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await pumpSettings(tester, size: const Size(1400, 900));

    // 设置区独立导航出现，分组标题齐全。
    expect(
      find.byKey(const ValueKey<String>('desktop_settings_area')),
      findsOneWidget,
    );
    expect(find.text('通用'), findsOneWidget);
    expect(find.text('外观与播放'), findsOneWidget);
    expect(find.text('数据与下载'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);

    // 分组条目复用移动端组件，全部同屏渲染。
    expect(find.text('应用语言'), findsOneWidget);
    expect(find.text('启动直达海报首页'), findsOneWidget);
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('MPV播放器设置'), findsOneWidget);
    expect(find.text('储存管理'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('全局播放数据统计'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('日志信息'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);

    // 旧双栏左栏 / 单栏混排的痕迹不再出现。
    expect(find.text('常用入口'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  testWidgets('桌面端点击条目在右侧子页列打开三级页，网格保持可见', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await pumpSettings(tester, size: const Size(1400, 900));

    await tester.tap(find.text('主题设置'));
    await tester.pumpAndSettle();

    // 三栏形态：子页（ThemeSettingsScreen）在右栏打开，
    // 中间网格（通用分组）保持可见。
    expect(find.byType(ThemeSettingsScreen), findsOneWidget);
    expect(find.text('通用'), findsOneWidget);

    // 右栏返回后子页列收起，网格不受影响。
    tester
        .state<NavigatorState>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('desktop_settings_navigator'),
            ),
            matching: find.byType(Navigator),
          ),
        )
        .pop();
    await tester.pumpAndSettle();
    expect(find.byType(ThemeSettingsScreen), findsNothing);
    expect(find.text('通用'), findsOneWidget);
  });

  testWidgets('窄视口回落既有单栏列表：无分组网格', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    await pumpSettings(tester);

    expect(
      find.byKey(const ValueKey<String>('desktop_settings_area')),
      findsNothing,
    );
    expect(find.text('通用'), findsNothing);

    // 既有单栏列表完整保留。
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('应用语言'), findsOneWidget);
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.text('日志信息'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  testWidgets('非桌面平台宽视口保持既有单栏列表', (tester) async {
    DesktopEnvironment.debugOverridePlatform = false;
    await pumpSettings(tester, size: const Size(1400, 900));

    expect(
      find.byKey(const ValueKey<String>('desktop_settings_area')),
      findsNothing,
    );
    expect(find.text('通用'), findsNothing);
    expect(find.byKey(startupSwitchKey), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
  });
}
