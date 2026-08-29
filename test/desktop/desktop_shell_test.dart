import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/desktop/desktop_detail_pane_host.dart';
import 'package:fly_player/desktop/desktop_side_bar.dart';
import 'package:fly_player/desktop/desktop_shell.dart';
import 'package:fly_player/desktop/desktop_split_controller.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/main.dart';
import 'package:fly_player/providers/app_locale_provider.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/services/download_task_service.dart';
import 'package:fly_player/theme/app_theme.dart';

const MethodChannel _embeddingChannel = MethodChannel('fly_player/embedding');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // MainNavigation 的 IndexedStack 会构建真实 MediaListScreen，
    // 其 initState 调 DownloadTaskService.initialize()，置为已初始化避免碰 sqflite。
    DownloadTaskService.instance.debugReplaceRecordsForTesting(const []);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_embeddingChannel, (call) async {
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
        .setMockMethodCallHandler(_embeddingChannel, null);
  });

  group('MainNavigation 桌面分支', () {
    testWidgets('窄窗口(800px)仍走底部胶囊导航路径，不进入桌面 Shell', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_mainNavigationApp());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final scaffolds = tester.widgetList<Scaffold>(
        find.descendant(
          of: find.byType(MainNavigation),
          matching: find.byType(Scaffold),
        ),
      );
      final shellScaffold = scaffolds.firstWhere(
        (scaffold) => scaffold.bottomNavigationBar != null,
      );
      expect(shellScaffold.extendBody, isTrue);
      expect(find.byType(DesktopShell), findsNothing);
      expect(find.byType(DesktopSideBar), findsNothing);
      expect(find.text('影视'), findsOneWidget);
    });
  });

  group('DesktopShell', () {
    testWidgets('1400px：侧栏可见、tab 可切换、次级入口推入 root navigator', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        _desktopApp(
          observer: observer,
          pages: const <Widget>[Text('影视内容页'), Text('设置内容页')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(DesktopSideBar), findsOneWidget);
      IndexedStack indexedStackOf() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(indexedStackOf().index, 0);

      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(indexedStackOf().index, 1);

      await tester.tap(find.text('影视'));
      await tester.pump();
      expect(indexedStackOf().index, 0);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(observer.pushedNames, contains('/screen/search'));
      expect(find.text('搜索页'), findsOneWidget);
    });

    testWidgets('分屏开关：右栏详情宿主出现、比例 chip 可调、关闭后恢复', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _desktopApp(pages: const <Widget>[Text('影视内容页'), Text('设置内容页')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 开关仅在 ≥ splitMinWidth 时显示，初始关闭。
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.text('浏览 | 详情'));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      // 分屏详情宿主已接线（feat/desktop-detail-pane）：右栏渲染真实宿主而非占位。
      expect(find.byType(DesktopDetailPaneHost), findsOneWidget);

      final controller = tester
          .element(find.text('42%'))
          .read<DesktopSplitController>();
      expect(controller.paneFraction, 0.50);

      await tester.tap(find.text('65%'));
      await tester.pump();
      expect(controller.paneFraction, 0.65);

      // 分屏后内容列与右栏按 paneFraction 弹性分配（右栏 65）。
      final flexes = tester
          .widgetList<Expanded>(find.byType(Expanded))
          .map((expanded) => expanded.flex)
          .toList();
      expect(flexes, containsAll(<int>[35, 65]));

      await tester.tap(
        find.byKey(const ValueKey<String>('desktop_pane_close')),
      );
      await tester.pump();
      expect(controller.enabled, isFalse);
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('快捷键：数字 1/2 切 tab，Ctrl+K 打开搜索', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        _desktopApp(
          observer: observer,
          pages: const <Widget>[Text('影视内容页'), Text('设置内容页')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      IndexedStack indexedStackOf() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack));

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(indexedStackOf().index, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(indexedStackOf().index, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(observer.pushedNames, contains('/screen/search'));
      expect(find.text('搜索页'), findsOneWidget);
    });

    testWidgets('文本框聚焦时数字键不劫持切 tab，Ctrl+K 仍可用', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        _desktopApp(
          observer: observer,
          pages: const <Widget>[
            Material(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 300, child: TextField()),
              ),
            ),
            Text('设置内容页'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      IndexedStack indexedStackOf() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(indexedStackOf().index, 0);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(indexedStackOf().index, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(observer.pushedNames, contains('/screen/search'));
    });
  });
}

Widget _desktopApp({NavigatorObserver? observer, List<Widget>? pages}) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppThemeBuilder.build(AppThemePreset.midnight),
    navigatorObservers: <NavigatorObserver>[if (observer != null) observer],
    routes: <String, WidgetBuilder>{
      '/screen/poster-browse': (_) =>
          const Scaffold(body: Center(child: Text('大屏浏览页'))),
      '/screen/search': (_) => const Scaffold(body: Center(child: Text('搜索页'))),
      '/screen/favorites': (_) =>
          const Scaffold(body: Center(child: Text('收藏页'))),
      '/screen/downloads': (_) =>
          const Scaffold(body: Center(child: Text('下载页'))),
    },
    home: DesktopShell(pages: pages),
  );
}

/// 复刻 FlyPlayerApp 的 provider 栈，供窄窗口路径构建真实 MainNavigation。
Widget _mainNavigationApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NasProvider>(create: (_) => NasProvider()),
      ChangeNotifierProvider<BackendSessionProvider>(
        create: (_) => BackendSessionProvider(),
      ),
      ChangeNotifierProxyProvider2<
        NasProvider,
        BackendSessionProvider,
        MediaBackendProvider
      >(
        create: (context) => MediaBackendProvider(
          context.read<NasProvider>(),
          context.read<BackendSessionProvider>(),
        ),
        update: (context, nas, session, previous) =>
            previous ?? MediaBackendProvider(nas, session),
      ),
      ChangeNotifierProvider<ParallelWindowSettingsProvider>(
        create: (_) => ParallelWindowSettingsProvider(),
      ),
      ChangeNotifierProvider<StartupPreferencesProvider>(
        create: (_) => StartupPreferencesProvider(),
      ),
      ChangeNotifierProvider<AppThemeProvider>(
        create: (_) => AppThemeProvider(),
      ),
      ChangeNotifierProvider<AppLocaleProvider>(
        create: (_) => AppLocaleProvider(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: const MainNavigation(),
    ),
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<String?> pushedNames = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedNames.add(route.settings.name);
  }
}
