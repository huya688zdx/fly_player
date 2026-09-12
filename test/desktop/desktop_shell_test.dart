import 'dart:async';

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
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
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
    for (final initialKind in [
      MediaBackendKind.feiniu,
      MediaBackendKind.emby,
    ]) {
      testWidgets('侧栏切换 ${initialKind.name} 到另一绑定后清空旧库并刷新计数', (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final session = _SidebarSession(initialKind);
        final oldBackend = _SidebarBackend()..complete('old-library', 35, 46);
        final nextBackend = _SidebarBackend();
        await tester.pumpWidget(
          _desktopApp(
            pages: const [Text('影视内容页'), Text('设置内容页')],
            backendSession: session,
            createBackendProvider: (nas, session) => _SidebarBackendProvider(
              nas,
              session,
              {'old': oldBackend, 'next': nextBackend},
            ),
          ),
        );
        await tester.pumpAndSettle();
        DesktopSideBar sidebar() => tester.widget(find.byType(DesktopSideBar));
        expect(sidebar().catalogs.single.id, 'old-library');
        expect(sidebar().movieCount, 35);
        expect(sidebar().tvCount, 46);

        session.select('next', MediaBackendKind.emby);
        await tester.pump();
        expect(sidebar().catalogs, isEmpty);
        expect(sidebar().movieCount, 0);
        expect(sidebar().tvCount, 0);
        expect(nextBackend.catalogRequests, 1);

        nextBackend.complete('next-library', 3, 7);
        await tester.pumpAndSettle();
        expect(sidebar().catalogs.single.id, 'next-library');
        expect(sidebar().movieCount, 3);
        expect(sidebar().tvCount, 7);
        expect(sidebar().totalItems, 10);
        await tester.tap(find.text('next-library'));
        await tester.pumpAndSettle();
        final route = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data ?? '')
            .singleWhere((text) => text.startsWith('content:/screen/category'));
        expect(Uri.decodeComponent(route), contains('next-library'));
        expect(Uri.decodeComponent(route), isNot(contains('old-library')));
      });
    }

    testWidgets('侧栏切换绑定后旧会话迟到响应不能覆盖当前库', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = _SidebarSession(MediaBackendKind.feiniu);
      final oldBackend = _SidebarBackend();
      final nextBackend = _SidebarBackend()..complete('next-library', 3, 7);
      await tester.pumpWidget(
        _desktopApp(
          pages: const [Text('影视内容页'), Text('设置内容页')],
          backendSession: session,
          createBackendProvider: (nas, session) => _SidebarBackendProvider(
            nas,
            session,
            {'old': oldBackend, 'next': nextBackend},
          ),
        ),
      );
      await tester.pump();
      expect(oldBackend.catalogRequests, 1);
      session.select('next', MediaBackendKind.emby);
      await tester.pumpAndSettle();
      DesktopSideBar sidebar() => tester.widget(find.byType(DesktopSideBar));
      expect(sidebar().catalogs.map((catalog) => catalog.id), ['next-library']);

      oldBackend.complete('old-library', 35, 46);
      await tester.pumpAndSettle();
      expect(sidebar().catalogs.map((catalog) => catalog.id), ['next-library']);
      expect(sidebar().movieCount, 3);
      expect(sidebar().tvCount, 7);
    });

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
      void expectSelected(String label) {
        for (final item in ['影视', '收藏', '下载列表', '设置']) {
          expect(
            tester.widget<Text>(find.text(item)).style?.fontWeight,
            item == label ? FontWeight.w600 : FontWeight.w500,
            reason: '$label 页面下 $item 的选中状态',
          );
        }
      }

      expect(indexedStackOf().index, 0);
      expectSelected('影视');

      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(indexedStackOf().index, 1);
      expectSelected('设置');

      await tester.tap(find.text('影视'));
      await tester.pump();
      expect(indexedStackOf().index, 0);

      // 侧栏收藏：在影视内容区内嵌导航打开，侧栏常驻、不推 root 全屏。
      // （搜索已移至内容区右上角弹窗、大屏浏览移至首页 AppBar，均不在侧栏。）
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(observer.pushedNames, isNot(contains('/screen/favorites')));
      expect(find.text('content:/screen/favorites'), findsOneWidget);
      expectSelected('收藏');

      await tester.tap(find.text('下载列表'));
      await tester.pumpAndSettle();
      expect(find.text('content:/screen/downloads'), findsOneWidget);
      expectSelected('下载列表');

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expectSelected('设置');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expectSelected('下载列表');

      Navigator.of(
        tester.element(find.text('content:/screen/downloads')),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.text('影视内容页'), findsOneWidget);
      expectSelected('影视');

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      // 即使影视页签已选中，再点一次仍应清空内容区栈、直达首页。
      await tester.tap(find.text('影视'));
      await tester.pumpAndSettle();
      expect(find.text('影视内容页'), findsOneWidget);
      expect(find.text('content:/screen/favorites'), findsNothing);
      expectSelected('影视');
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
      await tester.pumpAndSettle();

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

    testWidgets('分屏按设置展开与换边，返回保留开关和主屏状态', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _desktopApp(pages: const <Widget>[Text('影视内容页'), Text('设置内容页')]),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DesktopSideBar));
      final provider = context.read<ParallelWindowSettingsProvider>();
      final proxy = PlayerPaneHostScope.maybeOf(context)!;
      final homeElement = tester.element(find.text('影视内容页'));
      await provider.setEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopDetailPaneHost), findsNothing);

      final browse = find.byType(IndexedStack);
      final fullWidth = tester.getSize(browse).width;
      await proxy.openRoute('/detail/item?itemGuid=a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final openingWidth = tester.getRect(browse).width;
      final openingLayoutWidth = tester.getSize(browse).width;
      expect(openingWidth, lessThan(fullWidth));
      // 转场只混合旧画面，真实内容不允许被横向拉伸。
      expect(openingWidth, openingLayoutWidth);
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(browse).width, openingLayoutWidth);
      await tester.pumpAndSettle();
      expect(openingWidth, tester.getSize(browse).width);
      expect(find.byType(RawImage), findsNothing);
      final pane = find.byType(DesktopDetailPaneHost);
      final controller = tester.element(pane).read<DesktopSplitController>();
      expect(controller.paneFraction, 0.58);
      expect(find.text('item'), findsNothing);
      expect(find.text('50%'), findsNothing);
      expect(
        tester.getTopLeft(pane).dx,
        greaterThan(tester.getTopLeft(find.text('影视内容页')).dx),
      );
      final state = tester.state<DesktopDetailPaneHostState>(pane);
      final paneWidth = tester.getSize(pane).width;
      final pageContext = tester.element(
        find.text('pane:/detail/item?itemGuid=a'),
      );
      expect(MediaQuery.sizeOf(pageContext).width, paneWidth);

      await provider.setPreferredPrimaryPaneSide('right');
      await provider.setSplitRatioPreset('focus_detail');
      await tester.pumpAndSettle();
      expect(controller.paneFraction, 0.65);
      expect(tester.state(pane), same(state));
      expect(
        tester.getTopLeft(pane).dx,
        lessThan(tester.getTopLeft(find.text('影视内容页')).dx),
      );

      final splitWidth = tester.getSize(browse).width;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final closingWidth = tester.getRect(browse).width;
      expect(tester.getSize(browse).width, fullWidth);
      expect(closingWidth, greaterThan(splitWidth));
      expect(closingWidth, fullWidth);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
      expect(provider.enabled, isTrue);
      expect(tester.element(find.text('影视内容页')), same(homeElement));
      await proxy.openRoute('/detail/item?itemGuid=b');
      await tester.pumpAndSettle();
      expect(find.text('pane:/detail/item?itemGuid=b'), findsOneWidget);
      // 窗口缩窄时保留当前详情，返回后新详情在主屏打开。
      tester.view.physicalSize = const Size(1100, 900);
      await tester.pumpAndSettle();
      expect(find.text('影视内容页'), findsNothing);
      expect(find.text('pane:/detail/item?itemGuid=b'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final detailContext = tester.element(
        find.text('pane:/detail/item?itemGuid=b'),
      );
      Navigator.of(detailContext).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopDetailPaneHost), findsNothing);
      await proxy.openRoute('/detail/item?itemGuid=c');
      await tester.pumpAndSettle();
      expect(find.text('content:/detail/item?itemGuid=c'), findsOneWidget);
      await proxy.closePane();
      await tester.pumpAndSettle();
      expect(provider.enabled, isTrue);
      expect(controller.paneVisible, isFalse);
      await tester.pump(const Duration(seconds: 2));
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
      // Ctrl+K 展开搜索框：未输入时不提前显示结果小窗，也不推整页路由。
      expect(observer.pushedNames, isNot(contains('/screen/search')));
      expect(find.text('全部'), findsNothing);
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
      // Ctrl+K 不受文本焦点影响：展开搜索框（叠加替身页自带的输入框）。
      expect(find.text('全部'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });
}

Widget _desktopApp({
  NavigatorObserver? observer,
  List<Widget>? pages,
  AppThemePreset themePreset = AppThemePreset.midnight,
  BackendSessionProvider? backendSession,
  MediaBackendProvider Function(NasProvider, BackendSessionProvider)?
  createBackendProvider,
}) {
  return MultiProvider(
    providers: [
      // 搜索弹窗构建时读取 NAS / 后端能力，与 _mainNavigationApp 同栈注入。
      ChangeNotifierProvider<NasProvider>(create: (_) => NasProvider()),
      ChangeNotifierProvider<BackendSessionProvider>(
        create: (_) => backendSession ?? BackendSessionProvider(),
      ),
      ChangeNotifierProxyProvider2<
        NasProvider,
        BackendSessionProvider,
        MediaBackendProvider
      >(
        create: (context) =>
            (createBackendProvider ?? MediaBackendProvider.new)(
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

class _SidebarSession extends BackendSessionProvider {
  _SidebarSession(MediaBackendKind kind) : super(autoLoad: false) {
    select('old', kind);
  }

  MediaBackendConnection? _connection;

  @override
  MediaBackendConnection? get currentConnection => _connection;

  @override
  MediaBackendKind get currentKind => _connection!.kind;

  void select(String bindingId, MediaBackendKind kind) {
    _connection = MediaBackendConnection(
      kind: kind,
      accountKey: 'test-account',
      bindingId: bindingId,
      serverUrl: 'https://$bindingId.invalid',
      accessToken: 'test-token-$bindingId',
    );
    notifyListeners();
  }
}

class _SidebarBackendProvider extends MediaBackendProvider {
  _SidebarBackendProvider(
    super.nasProvider,
    super.sessionProvider,
    this.backends,
  );

  final Map<String, MediaBackend> backends;

  @override
  MediaBackend get backend =>
      backends[sessionProvider!.currentConnection!.bindingId]!;
}

class _SidebarBackend extends Fake implements MediaBackend {
  final _catalogs = Completer<List<MediaCatalog>>();
  final _summary = Completer<Map<String, dynamic>>();
  int catalogRequests = 0;

  @override
  Future<List<MediaCatalog>> getCatalogs() {
    catalogRequests++;
    return _catalogs.future;
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() => _summary.future;

  void complete(String library, int movies, int series) {
    _catalogs.complete([
      MediaCatalog(
        id: library,
        title: library,
        type: '',
        primaryImage: MediaImageRef.empty,
      ),
    ]);
    _summary.complete({
      'movie': movies,
      'tv': series,
      'total': movies + series,
    });
  }
}
