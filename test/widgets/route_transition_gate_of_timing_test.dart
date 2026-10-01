import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/ui/route_transition_gate.dart';

/// RouteTransitionGate 等待时序测试（§5.2 测试 3/4/5，docs/plans/route-gate-popup-jank-fix.md）。
///
/// 测试 3 的同一组时序断言对三条 API 路径各跑一遍（三者同走核心，等价性回归
/// 保护）：`RouteTransitionGate.of(context)` / `RouteGateAnchorState.waitTransition()`
/// / `RouteTransitionGate.waitForRoute(route)`。
///
/// 假时钟时序：页面转场统一用 400ms 的 [PageRouteBuilder]（自定时长，不依赖
/// SDK 默认值）；"未完成"断言前先 [WidgetTester.idle] 排空微任务，给错误的
/// 立即 resolve 一个暴露机会。观测 gate future 一律用 flag + `then()`、**绝不
/// await**：`await showDialog(...)` 这类"路由被 pop 才完成"的 future 会把测试
/// 体挂死（pop 代码在 await 之后，构成死锁，测试只能等 10 分钟超时）。
///
/// 路由组合约束（SDK 真值：widgets/pages.dart 与 material/page.dart 亲读 +
/// 本文件实测核验）：底层页的 secondaryAnimation 只在上层路由与其转场兼容时
/// 才被驱动——`PageRoute.canTransitionTo` 只认 `nextRoute is PageRoute`，
/// `MaterialRouteTransitionMixin.canTransitionTo` 只认同 mixin 的路由。因此
/// DialogRoute / ModalBottomSheetRoute 等 PopupRoute 压在页面上时，底层页
/// secondary 恒为 dismissed：页面级闸门只看本路由的 primary+secondary 两条
/// 动画，此时依语义立即放行（弹窗不挂起页面闸门，这是 SDK 既有行为而非闸门
/// 缺陷）。故"仅 secondary 在动"的场景统一用页面压页面（PageRouteBuilder 压
/// PageRouteBuilder）构造；需要"真实转场中的首页"时用 MaterialPageRoute 压
/// home（同 mixin，secondary 跟随进场动画）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // 对齐 dynamic_page_theme_scope_headers_race_test.dart 的隔离约定。
    RouteTransitionGate.debugResetTransitionOverride();
  });

  for (final api in _GateApi.values) {
    testWidgets('gate 等待时序：primary+secondary 全部稳定才放行（api: ${api.name}）', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      final homeProbe = _GateProbe();
      await tester.pumpWidget(_app(navKey, homeProbe));
      // 等首页自身进场转场结束（若有），后续小步 pump 的时序断言从稳定基线起跑。
      await tester.pumpAndSettle();
      final nav = navKey.currentState!;

      // ① 二级页 primary 动画：转场中途取 future，假时钟下不完成，settle 后完成。
      final primaryProbe = _GateProbe();
      nav.push(_pageRoute(primaryProbe));
      await tester.pump(const Duration(milliseconds: 10)); // 400ms 转场的中途
      var primaryResolved = false;
      _gateFuture(api, primaryProbe).then((_) => primaryResolved = true);
      await tester.idle();
      expect(
        primaryResolved,
        isFalse,
        reason: '[${api.name}] 转场中途取到的 future 不得立即 resolve',
      );
      await tester.pumpAndSettle();
      await tester.idle();
      expect(primaryResolved, isTrue, reason: '[${api.name}] 转场结束后必须 resolve');
      nav.pop();
      await tester.pumpAndSettle();

      // ② 底层页被上层页面压住（仅 secondaryAnimation 在动）同样要等转场结束。
      //    上层若是弹窗类 PopupRoute 则底层页 secondary 恒 dismissed（见文件头
      //    "路由组合约束"），故用页面压页面构造该场景。
      final belowProbe = _GateProbe();
      nav.push(_pageRoute(belowProbe)); // A 起步
      await tester.pumpAndSettle(); // A 稳定：primary completed，此后只看 secondary
      nav.push(_pageRoute(null)); // B 压上，A 的 secondary 随 B 进场启动
      await tester.pump(const Duration(milliseconds: 10)); // B 进场中途
      var secondaryResolved = false;
      _gateFuture(api, belowProbe).then((_) => secondaryResolved = true);
      await tester.idle();
      expect(
        secondaryResolved,
        isFalse,
        reason: '[${api.name}] 上层转场中，仅 secondary 在动的底层页 future 不得 resolve',
      );
      await tester.pumpAndSettle();
      await tester.idle();
      expect(
        secondaryResolved,
        isTrue,
        reason: '[${api.name}] 上层转场结束后底层页 future 必须放行',
      );
      nav.pop(); // 收走 B
      await tester.pumpAndSettle();
      nav.pop(); // 收走 A，回到稳定首页，③ 从干净栈起步
      await tester.pumpAndSettle();

      // ③ 快速连续 push 两页：A 的 primary（A 进场）刚 completed 时 A 的
      //    secondary（B 压上进场）仍在动，必须重查两条、都 completed 才放行。
      final sandwichProbe = _GateProbe();
      nav.push(_pageRoute(sandwichProbe)); // A 在 t=T 起步（400ms）
      await tester.pump(const Duration(milliseconds: 10)); // t=T+10：A 已建、转场中途
      var sandwichResolved = false;
      _gateFuture(api, sandwichProbe).then((_) => sandwichResolved = true);
      nav.push(_pageRoute(null)); // B 在 t=T+10 起步，A 的 secondary 随 B 进场启动
      await tester.pump(
        const Duration(milliseconds: 395),
      ); // t=T+405：A.primary 刚 completed、B 仍 forward
      await tester.idle();
      expect(
        sandwichResolved,
        isFalse,
        reason:
            '[${api.name}] primary 刚 completed 而 secondary 仍在动时不得放行'
            '（任一动画状态变化后重查两条）',
      );
      await tester.pumpAndSettle();
      await tester.idle();
      expect(
        sandwichResolved,
        isTrue,
        reason: '[${api.name}] 两条动画都 completed 后必须放行',
      );
      nav.pop();
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('无 ModalRoute 的 context 立即放行且 isTransitioning 为 false', (
    tester,
  ) async {
    BuildContext? aboveNavigatorContext;
    final floatingAnchorKey = GlobalKey<RouteGateAnchorState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Column(
          children: <Widget>[
            Builder(
              builder: (context) {
                aboveNavigatorContext =
                    context; // Navigator 之上：ModalRoute.of 返回 null
                return const SizedBox(height: 1);
              },
            ),
            RouteGateAnchor(
              key: floatingAnchorKey,
              child: const SizedBox(height: 1),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    expect(floatingAnchorKey.currentState, isNotNull);
    expect(
      floatingAnchorKey.currentState!.route,
      isNull,
      reason: '锚点不在任何 ModalRoute 下时 route 解析为 null',
    );
    expect(
      floatingAnchorKey.currentState!.isTransitioning,
      isFalse,
      reason: '无路由时 isTransitioning 退化为 false',
    );

    var ofResolved = false;
    RouteTransitionGate.of(
      aboveNavigatorContext!,
    ).then((_) => ofResolved = true);
    var anchorResolved = false;
    floatingAnchorKey.currentState!.waitTransition().then(
      (_) => anchorResolved = true,
    );
    await tester.pump(); // 下一次 pump 即完成：不挂起
    expect(ofResolved, isTrue, reason: '无 ModalRoute 的 of() 不得挂起');
    expect(anchorResolved, isTrue, reason: '锚点 route==null 退化路径同样立即放行');
    expect(
      RouteTransitionGate.isTransitioning(aboveNavigatorContext!),
      isFalse,
      reason: '无 ModalRoute 的 isTransitioning 为 false',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('debugOverrideTransition 短路优先于真实转场：强制关闭时立即放行', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final homeProbe = _GateProbe();
    await tester.pumpWidget(_app(navKey, homeProbe));
    await tester.pumpAndSettle();

    // 真实转场：Material 路由压 Material 路由，home 的 secondary 随上层页进场
    // （PageRouteBuilder 压 home 时 secondary 恒 dismissed，见文件头说明）。
    navKey.currentState!.push(_homeCompatiblePageRoute());
    await tester.pump(const Duration(milliseconds: 10)); // 真实转场进行中
    expect(
      homeProbe.anchorKey.currentState!.isTransitioning,
      isTrue,
      reason: '前置确认：override 未设置时锚点真实读数为转场中',
    );

    RouteTransitionGate.debugOverrideTransition(
      isTransitioning: false,
      wait: Future<void>.value(), // 已完成 future
    );
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isFalse,
      reason: 'override 短路必须压过真实转场中的路由',
    );
    expect(
      homeProbe.anchorKey.currentState!.isTransitioning,
      isFalse,
      reason: '锚点路径同样先查 override',
    );

    var ofResolved = false;
    RouteTransitionGate.of(
      homeProbe.innerContext!,
    ).then((_) => ofResolved = true);
    var coreResolved = false;
    RouteTransitionGate.waitForRoute(
      ModalRoute.of(homeProbe.innerContext!),
    ).then((_) => coreResolved = true);
    await tester.pump();
    await tester.idle();
    expect(ofResolved, isTrue, reason: '短路 wait 为已完成 future 时 of() 立即 resolve');
    expect(coreResolved, isTrue, reason: '核心 waitForRoute 同样被短路');

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('debugOverrideTransition 在稳定路由上强制挂起直至 override future 完成', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    final homeProbe = _GateProbe();
    await tester.pumpWidget(_app(navKey, homeProbe));
    await tester.pumpAndSettle(); // 无任何转场，路由稳定

    final pending = Completer<void>();
    RouteTransitionGate.debugOverrideTransition(
      isTransitioning: true,
      wait: pending.future, // 未完成 Completer
    );
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isTrue,
      reason: '稳定路由被 override 强制为转场中',
    );

    var ofResolved = false;
    RouteTransitionGate.of(
      homeProbe.innerContext!,
    ).then((_) => ofResolved = true);
    var anchorResolved = false;
    homeProbe.anchorKey.currentState!.waitTransition().then(
      (_) => anchorResolved = true,
    );
    await tester.pumpAndSettle();
    await tester.idle();
    expect(ofResolved, isFalse, reason: 'override future 未完成时 of() 必须挂起');
    expect(
      anchorResolved,
      isFalse,
      reason: '锚点 waitTransition() 同样被 override 挂起',
    );

    pending.complete();
    await tester.pump();
    await tester.idle();
    expect(ofResolved, isTrue, reason: 'override future 完成后 of() 放行');
    expect(anchorResolved, isTrue, reason: 'override future 完成后锚点路径放行');
  });

  testWidgets('debugResetTransitionOverride 后恢复读取真实路由状态', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final homeProbe = _GateProbe();
    await tester.pumpWidget(_app(navKey, homeProbe));
    await tester.pumpAndSettle(); // 稳定基线：reset 后的 false 断言才有意义

    RouteTransitionGate.debugOverrideTransition(
      isTransitioning: true,
      wait: Completer<void>().future,
    );
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isTrue,
      reason: 'override 生效中：稳定路由被强制为转场中',
    );

    RouteTransitionGate.debugResetTransitionOverride();
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isFalse,
      reason: 'reset 后稳定路由恢复真实读数 false',
    );

    var resolved = false;
    RouteTransitionGate.of(
      homeProbe.innerContext!,
    ).then((_) => resolved = true);
    await tester.pump();
    await tester.idle();
    expect(resolved, isTrue, reason: 'reset 后稳定路由 of() 恢复立即 resolve');

    // 真实转场读数恢复：Material 路由压 Material 路由使 home 的 secondary 随
    // 上层页进场（见文件头说明），push 后转场中识别为 true，settle 后 false。
    navKey.currentState!.push(_homeCompatiblePageRoute());
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isTrue,
      reason: 'reset 后真实转场恢复被识别',
    );
    await tester.pumpAndSettle();
    expect(
      RouteTransitionGate.isTransitioning(homeProbe.innerContext!),
      isFalse,
      reason: '转场结束后恢复 false',
    );

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
  });
}

enum _GateApi { of, waitTransition, waitForRoute }

/// 页面探针：锚点句柄 + 页内 context 捕获（of / waitForRoute 取路由用）。
class _GateProbe {
  final GlobalKey<RouteGateAnchorState> anchorKey =
      GlobalKey<RouteGateAnchorState>();
  BuildContext? innerContext;
}

Widget _app(GlobalKey<NavigatorState> navKey, _GateProbe homeProbe) =>
    MaterialApp(navigatorKey: navKey, home: _ProbedPage(homeProbe));

/// 探针页面：build 根包 [RouteGateAnchor]（§3.4 范式），页内 Builder 捕获 context。
class _ProbedPage extends StatelessWidget {
  const _ProbedPage(this.probe);

  final _GateProbe probe;

  @override
  Widget build(BuildContext context) {
    return RouteGateAnchor(
      key: probe.anchorKey,
      child: Scaffold(
        body: Builder(
          builder: (context) {
            probe.innerContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }
}

const Duration _transitionDuration = Duration(milliseconds: 400);

PageRouteBuilder<void> _pageRoute(_GateProbe? probe) => PageRouteBuilder<void>(
  transitionDuration: _transitionDuration,
  reverseTransitionDuration: _transitionDuration,
  pageBuilder: (_, __, ___) => probe == null
      ? const Scaffold(body: SizedBox.expand())
      : _ProbedPage(probe),
);

/// 与 `MaterialApp.home`（MaterialPageRoute）转场兼容的上层页路由。
///
/// SDK `MaterialRouteTransitionMixin.canTransitionTo` 只认同 mixin 的路由
/// （material/page.dart），`PageRouteBuilder`/`DialogRoute` 压 MaterialPageRoute
/// 时底层页 secondaryAnimation 恒为 dismissed。需要"真实转场中的 home"作为
/// override 短路的对照时，必须用 MaterialPageRoute 压 home。
MaterialPageRoute<void> _homeCompatiblePageRoute() => MaterialPageRoute<void>(
  builder: (_) => const Scaffold(body: SizedBox.expand()),
);

/// 三条 API 路径取同一个 gate future（三者同走核心，等价性回归保护）。
Future<void> _gateFuture(_GateApi api, _GateProbe probe) {
  switch (api) {
    case _GateApi.of:
      // 旧式薄封装：先查 override、再 ModalRoute.of。时序测试不观测量重建，
      // 只验证等待语义与核心等价。
      return RouteTransitionGate.of(probe.innerContext!);
    case _GateApi.waitTransition:
      return probe.anchorKey.currentState!.waitTransition();
    case _GateApi.waitForRoute:
      return RouteTransitionGate.waitForRoute(
        ModalRoute.of(probe.innerContext!),
      );
  }
}
