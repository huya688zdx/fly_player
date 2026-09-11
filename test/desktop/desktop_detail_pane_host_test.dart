import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/app_transitions.dart';
import 'package:fly_player/ui/player_pane_host_scope.dart';
import 'package:fly_player/utils/app_exception.dart';
import 'package:fly_player/widgets/common/app_error_state.dart';
import 'package:fly_player/widgets/detail/detail_loading_skeleton.dart';
import 'package:fly_player/widgets/detail/detail_status_page.dart';

/// 测试用极简路由映射：按 URI path 分发到便携页面。
Route<dynamic> _testRouteFactory(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '') ?? Uri();
  switch (uri.path) {
    case '/screen/search':
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            const Scaffold(body: Center(child: Text('SEARCH_PAGE'))),
      );
    case '/detail/item':
      final itemGuid = uri.queryParameters['itemGuid'] ?? '';
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Center(child: Text('ITEM:$itemGuid'))),
      );
    default:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Center(child: Text('UNKNOWN'))),
      );
  }
}

Future<DesktopDetailPaneHostState> _pumpHost(
  WidgetTester tester, {
  required DesktopSplitController controller,
  double width = 900,
  RouteFactory? onGenerateRoute = _testRouteFactory,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 600,
            child: DesktopDetailPaneHost(
              splitController: controller,
              onGenerateRoute: onGenerateRoute,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<DesktopDetailPaneHostState>(
    find.byType(DesktopDetailPaneHost),
  );
}

/// 推进假时钟走完挂起定时器：openRoute 的 AsyncActionGuard 320ms settle 与
/// 轻提示 1300ms 自动消失都靠 Timer 驱动，不显式走完会触发
/// 「A Timer is still pending」测试失败。
Future<void> _flushTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

void main() {
  testWidgets('详情分屏失败可返回，重试等待时也能关闭', (tester) async {
    final controller = DesktopSplitController(enabled: true);
    addTearDown(controller.dispose);
    var retries = 0;
    final state = await _pumpHost(
      tester,
      controller: controller,
      locale: const Locale('zh', 'CN'),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => StatefulBuilder(
          builder: (context, setState) => retries > 0
              ? const DetailLoadingSkeleton()
              : DetailStatusPage(
                  child: AppErrorState(
                    error: const AppException(
                      kind: AppExceptionKind.transient,
                      action: '详情加载',
                      message: '暂时不可用',
                    ),
                    onRetry: () => setState(() => retries++),
                  ),
                ),
        ),
      ),
    );
    await state.openRoute('/detail/item?itemGuid=unavailable');
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-status-back')));
    await tester.pumpAndSettle();
    expect(controller.paneVisible, isFalse);
    await _flushTimers(tester);

    await state.openRoute('/detail/item?itemGuid=unavailable');
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新重试'));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(DetailLoadingSkeleton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-status-back')));
    await tester.pumpAndSettle();
    expect(controller.paneVisible, isFalse);
    expect(state.currentRouteName, isNull);
    expect(tester.takeException(), isNull);
    await _flushTimers(tester);
  });

  testWidgets('桌面详情原位淡入 200ms，返回原位淡出 180ms', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('首页')),
    );
    final route = AppTransitions.leftToRightPageTurnRoute<void>(
      const Text('详情'),
    );
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final detail = find.text('详情');
    final position = tester.getTopLeft(detail);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: detail, matching: find.byType(Opacity)).first,
          )
          .opacity,
      closeTo(0.5, 0.01),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(detail), position);
    expect((route as PageRoute<void>).animation!.value, 1);
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(detail), position);
    final opacity = tester
        .widget<Opacity>(
          find.ancestor(of: detail, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity, closeTo(0.5, 0.01));
    await tester.pump(const Duration(milliseconds: 90));
    expect(route.animation!.value, closeTo(0.0, 0.0001));
    await tester.pump(const Duration(milliseconds: 16));
    expect(detail, findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  group('DesktopDetailPaneHost', () {
    testWidgets('openRoute 在 pane 内打开目标页并返回 true，scope 暴露同一控制器', (
      tester,
    ) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);
      expect(find.text('SEARCH_PAGE'), findsNothing);

      final handled = await state.openRoute('/screen/search');
      expect(handled, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('SEARCH_PAGE'), findsOneWidget);
      // 宿主不再重复显示工具条和路由名。
      expect(find.text('search'), findsNothing);

      final scope = tester.widget<PlayerPaneHostScope>(
        find.byType(PlayerPaneHostScope),
      );
      expect(scope.controller, same(state));
      await _flushTimers(tester);
    });

    testWidgets('打开详情后 backInPane 退回上一页', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      expect(await state.openRoute('/screen/search'), isTrue);
      await tester.pumpAndSettle();
      expect(await state.openRoute('/detail/item?itemGuid=x1'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ITEM:x1'), findsOneWidget);

      expect(await state.backInPane(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('SEARCH_PAGE'), findsOneWidget);
      expect(find.text('ITEM:x1'), findsNothing);
      await _flushTimers(tester);
    });

    testWidgets('同一详情目标重复 openRoute 防抖不重复压栈，退回即到栈底', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      expect(await state.openRoute('/detail/item?itemGuid=dup'), isTrue);
      await tester.pumpAndSettle();
      expect(await state.openRoute('/detail/item?itemGuid=dup'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ITEM:dup'), findsOneWidget);

      // 只压过一层：退一次即到栈底占位。
      expect(await state.backInPane(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ITEM:dup'), findsNothing);
      expect(find.text('选择内容查看详情'), findsOneWidget);
      await _flushTimers(tester);
    });

    testWidgets('同路径不同目标替换栈顶（详情 A → 详情 B 不加深栈）', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      expect(await state.openRoute('/detail/item?itemGuid=A'), isTrue);
      await tester.pumpAndSettle();
      expect(await state.openRoute('/detail/item?itemGuid=B'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ITEM:B'), findsOneWidget);
      expect(find.text('ITEM:A'), findsNothing);

      // 替换栈顶后退一次应直接回到栈底，而不是回到详情 A。
      expect(await state.backInPane(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ITEM:B'), findsNothing);
      expect(find.text('选择内容查看详情'), findsOneWidget);
      await _flushTimers(tester);
    });

    testWidgets('栈底 backInPane 返回 false 且不关闭面板', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      expect(await state.backInPane(), isFalse);
      expect(controller.enabled, isTrue);
    });

    testWidgets('closePane 清空路由栈并收起副屏，保留全局开关', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      expect(await state.openRoute('/screen/search'), isTrue);
      await tester.pumpAndSettle();
      expect(await state.closePane(), isTrue);
      await tester.pumpAndSettle();
      expect(controller.enabled, isTrue);
      expect(controller.paneVisible, isFalse);
      expect(find.text('SEARCH_PAGE'), findsNothing);
      expect(await state.backInPane(), isFalse);
      await _flushTimers(tester);
    });

    testWidgets('replacePlayerSource 桌面未承载播放恒返回 false', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(tester, controller: controller);

      final handled = await state.replacePlayerSource(
        title: 't',
        source: const MpvMediaSource(
          itemGuid: 'i1',
          mediaGuid: 'm1',
          videoGuid: 'v1',
          url: 'http://127.0.0.1/video.mp4',
          headers: <String, String>{},
          title: 't',
        ),
      );
      expect(handled, isFalse);
    });

    testWidgets('未注入 onGenerateRoute 时走统一映射（无效详情路由显示路由错误页）', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      final state = await _pumpHost(
        tester,
        controller: controller,
        onGenerateRoute: null,
        locale: const Locale('zh'),
      );

      expect(await state.openRoute('/detail/item'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('缺少详情参数'), findsOneWidget);
      await _flushTimers(tester);
    });

    testWidgets('paneHostBuilder 接线方式可用', (tester) async {
      final controller = DesktopSplitController(enabled: true);
      controller.paneHostBuilder = (context) =>
          DesktopDetailPaneHost(splitController: controller);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 600,
                child: Builder(
                  builder: (context) {
                    final hostBuilder = controller.paneHostBuilder;
                    return hostBuilder == null
                        ? const SizedBox.shrink()
                        : hostBuilder(context);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopDetailPaneHost), findsOneWidget);
      final state = tester.state<DesktopDetailPaneHostState>(
        find.byType(DesktopDetailPaneHost),
      );
      // 接线后 scope 暴露宿主自身，栈底占位可见，backInPane 交还外层。
      final scope = tester.widget<PlayerPaneHostScope>(
        find.byType(PlayerPaneHostScope),
      );
      expect(scope.controller, same(state));
      expect(find.text('选择内容查看详情'), findsOneWidget);
      expect(await state.backInPane(), isFalse);
      expect(await state.closePane(), isTrue);
      expect(controller.enabled, isTrue);
      expect(controller.paneVisible, isFalse);
    });
  });
}
