import 'package:flutter/gestures.dart';
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
import 'package:fly_player/ui/player_pane_host_scope.dart';

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
    testWidgets('1400px：侧栏可见、tab 可切换、收藏在内容区打开（侧栏常驻）', (tester) async {
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
      // 分屏默认关闭（测试设置 enabled=false）：右栏宿主不出现。
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
      IndexedStack indexedStackOf() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(indexedStackOf().index, 0);

      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(indexedStackOf().index, 1);

      await tester.tap(find.text('影视'));
      await tester.pump();
      expect(indexedStackOf().index, 0);

      // 侧栏收藏：在影视内容区内嵌导航打开，侧栏常驻、不推 root 全屏。
      // （搜索已移至内容区右上角弹窗、大屏浏览移至首页 AppBar，均不在侧栏。）
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(observer.pushedNames, isNot(contains('/screen/favorites')));
      expect(find.text('content:/screen/favorites'), findsOneWidget);

      // 即使影视页签已选中，再点一次仍应清空内容区栈、直达首页。
      await tester.tap(find.text('影视'));
      await tester.pumpAndSettle();
      expect(find.text('影视内容页'), findsOneWidget);
      expect(find.text('content:/screen/favorites'), findsNothing);
    });

    testWidgets('浅色主题侧栏快速掠过时仅当前项显示半透明强调色', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _desktopApp(
          themePreset: AppThemePreset.latte,
          pages: const <Widget>[Text('影视内容页'), Text('设置内容页')],
        ),
      );
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 400));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('下载列表')));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('收藏')));
      await tester.pump();

      Color rowColor(String label) {
        final row = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (row.decoration! as BoxDecoration).color!;
      }

      expect(rowColor('下载列表'), Colors.transparent);
      final colors = tester.element(find.text('收藏')).appColors;
      expect(rowColor('收藏'), colors.selection.withValues(alpha: 0.08));
    });

    testWidgets('分屏关闭：pane 代理把路由回退到内容区导航器（不整窗覆盖）', (tester) async {
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

      // 分屏关闭时全局代理仍可达（首页 / 媒体库条目点击的入口）。
      final proxy = PlayerPaneHostScope.maybeOf(
        tester.element(find.byType(DesktopSideBar)),
      );
      expect(proxy, isNotNull);

      // 详情 / 二级页路由：推进内容区内嵌导航器，root 不推全屏。
      await proxy!.openRoute('/screen/favorites');
      await tester.pumpAndSettle();
      expect(find.text('content:/screen/favorites'), findsOneWidget);
      expect(observer.pushedNames, isNot(contains('/screen/favorites')));

      // 设置类路由：切到设置页签，不往内容区塞整套 MainNavigation。
      await proxy.openRoute('/screen/settings/appearance');
      await tester.pump();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
      expect(find.text('content:/screen/settings/appearance'), findsNothing);
    });

    testWidgets('分屏开关在设置：provider 开 → 右栏宿主出现，比例可调，关 → 恢复', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _desktopApp(pages: const <Widget>[Text('影视内容页'), Text('设置内容页')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 分屏默认关闭（测试设置 enabled=false）：无右栏宿主、侧栏也无开关。
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
      final context = tester.element(find.byType(DesktopSideBar));
      final provider = context.read<ParallelWindowSettingsProvider>();
      expect(provider.enabled, isFalse);

      // 经设置（provider）开启分屏：右栏宿主出现。
      await provider.setEnabled(true);
      await tester.pumpAndSettle();
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

      // 右栏关闭按钮：经控制器回写 provider，设置与分屏状态一致。
      await tester.tap(
        find.byKey(const ValueKey<String>('desktop_pane_close')),
      );
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      expect(provider.enabled, isFalse);
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
    });

    testWidgets('快捷键：数字 1/2 切 tab，Ctrl+K 打开搜索弹窗', (tester) async {
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
      // Ctrl+K 打开桌面搜索弹窗：内容区导航上的浮层，不推整页路由。
      expect(observer.pushedNames, isNot(contains('/screen/search')));
      expect(find.text('全部'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Esc 关闭弹窗，回到内容区首页。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
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
      // Ctrl+K 不受文本焦点影响：弹出桌面搜索弹窗（叠加替身页自带的输入框）。
      expect(find.text('全部'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });
}

Widget _desktopApp({
  NavigatorObserver? observer,
  List<Widget>? pages,
  AppThemePreset themePreset = AppThemePreset.midnight,
}) {
  return MultiProvider(
    providers: [
      // 搜索弹窗构建时读取 NAS / 后端能力，与 _mainNavigationApp 同栈注入。
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
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(themePreset),
      navigatorObservers: <NavigatorObserver>[if (observer != null) observer],
      routes: <String, WidgetBuilder>{
        '/screen/poster-browse': (_) =>
            const Scaffold(body: Center(child: Text('大屏浏览页'))),
        '/screen/search': (_) =>
            const Scaffold(body: Center(child: Text('搜索页'))),
        '/screen/favorites': (_) =>
            const Scaffold(body: Center(child: Text('收藏页'))),
        '/screen/downloads': (_) =>
            const Scaffold(body: Center(child: Text('下载页'))),
      },
      home: DesktopShell(
        pages: pages,
        // 分屏右栏 / 内容区均注入轻量替身路由，避免构建真实二级页
        // （需完整 provider 栈）。
        paneRouteFactory: (settings) => _stubPaneRoute(settings, 'pane'),
        contentRouteFactory: (settings) => _stubPaneRoute(settings, 'content'),
      ),
    ),
  );
}

PageRouteBuilder<void> _stubPaneRoute(RouteSettings settings, String prefix) {
  return PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) =>
        Scaffold(body: Center(child: Text('$prefix:${settings.name}'))),
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
