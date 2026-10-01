import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/ui/route_transition_gate.dart';

/// RouteGateAnchor 锚点化行为测试（§5.2 测试 1/2，docs/plans/route-gate-popup-jank-fix.md）。
///
/// 黄金断言：弹窗（PopupRoute）push/pop 翻转 `_ModalScopeStatus` 时，通知只落在
/// `RouteGateAnchor` 这个叶子 element 上（锚点 build 原样返回同一 child 实例，
/// identical 短路），页面根 State 不重建。
///
/// harness 对齐生产形态：
/// - `navigatorObservers` 挂 `RouteTransitionGate.observer`（对齐 main.dart:459-461）；
/// - 埋点页面根 State 经 `RouteGateAnchor(key: gateKey, child: 页面根)` 包根
///   （§3.4 接入范式），gate 依赖经锚点 build 内的 `ModalRoute.of` 注册。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // §5.2 测试 2：锚点重建计数在用例间清零（对齐 debugResetTransitionOverride
  // 的 tearDown 隔离约定；计数在锚点 build 的 assert 内自增，widget 测试下断言
  // 开启生效）。
  setUp(() {
    RouteGateAnchorState.debugRebuildCount = 0;
  });

  testWidgets(
      '弹窗 push/pop 期间页面根 build 计数不变（showModalBottomSheet 与 showDialog 各一轮）',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey));
    // 等首页自身进场转场结束：此后每一帧的转场信号只来自弹窗开/关。
    await tester.pumpAndSettle();
    final page =
        tester.state<_InstrumentedPageState>(find.byType(_InstrumentedPage));
    final baseline = page.rootBuildCount;

    // —— 第一轮：showModalBottomSheet（进场 250ms，小步 pump 落在转场中途）——
    await tester.tap(find.text('打开底部弹窗'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteTransitionGate.anyRouteTransitioning,
      isTrue,
      reason: 'observer 已挂（对齐 main.dart:461），弹窗进场中应处于转场',
    );
    expect(
      page.rootBuildCount,
      baseline,
      reason: '弹窗 push 翻转 _ModalScopeStatus 只允许重建锚点叶子，页根不得重建',
    );
    await tester.pumpAndSettle();
    expect(
      page.rootBuildCount,
      baseline,
      reason: '弹窗打开完成后页根仍不得重建',
    );

    navKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      page.rootBuildCount,
      baseline,
      reason: 'pop 翻转 _ModalScopeStatus 同样不得触发页根重建',
    );
    await tester.pumpAndSettle();
    expect(
      page.rootBuildCount,
      baseline,
      reason: '弹窗关闭完成后页根仍不得重建',
    );
    expect(RouteTransitionGate.anyRouteTransitioning, isFalse);

    // —— 第二轮：showDialog（进场 150ms，同款小步 pump）——
    await tester.tap(find.text('打开对话框'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      page.rootBuildCount,
      baseline,
      reason: '对话框 push 中途页根不得重建',
    );
    await tester.pumpAndSettle();
    expect(
      page.rootBuildCount,
      baseline,
      reason: '对话框打开完成后页根不得重建',
    );

    navKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      page.rootBuildCount,
      baseline,
      reason: '对话框 pop 中途页根不得重建',
    );
    await tester.pumpAndSettle();
    expect(
      page.rootBuildCount,
      baseline,
      reason: '对话框关闭完成后页根不得重建',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('锚点承接通知：debugRebuildCount 每轮 push/pop 必增且页根计数不动',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey));
    // 等首页自身进场转场结束，锚点/页根计数基线此后不再受初始动画影响。
    await tester.pumpAndSettle();
    final page =
        tester.state<_InstrumentedPageState>(find.byType(_InstrumentedPage));
    final rootBaseline = page.rootBuildCount;

    final anchorAtStart = RouteGateAnchorState.debugRebuildCount;
    expect(
      anchorAtStart,
      greaterThanOrEqualTo(1),
      reason: '初始 build 已在锚点内自增一次（setUp 清零之后）',
    );

    // —— 第一轮：showModalBottomSheet ——
    await tester.tap(find.text('打开底部弹窗'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteGateAnchorState.debugRebuildCount,
      greaterThan(anchorAtStart),
      reason: 'push 翻转 _ModalScopeStatus 后锚点必须收到重建通知',
    );
    final afterSheetPush = RouteGateAnchorState.debugRebuildCount;
    await tester.pumpAndSettle();

    navKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteGateAnchorState.debugRebuildCount,
      greaterThan(afterSheetPush),
      reason: 'pop 翻转后锚点必须再次收到重建通知',
    );
    final afterSheetPop = RouteGateAnchorState.debugRebuildCount;
    await tester.pumpAndSettle();
    expect(
      page.rootBuildCount,
      rootBaseline,
      reason: '通知只落在锚点叶子，页根 build 计数不动',
    );

    // —— 第二轮：showDialog ——
    await tester.tap(find.text('打开对话框'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteGateAnchorState.debugRebuildCount,
      greaterThan(afterSheetPop),
      reason: '对话框 push 后锚点再次收到通知',
    );
    final afterDialogPush = RouteGateAnchorState.debugRebuildCount;
    await tester.pumpAndSettle();

    navKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      RouteGateAnchorState.debugRebuildCount,
      greaterThan(afterDialogPush),
      reason: '对话框 pop 后锚点再次收到通知',
    );
    await tester.pumpAndSettle();

    // 2 轮 ×（push + pop）各至少一次重建通知。
    expect(
      RouteGateAnchorState.debugRebuildCount,
      greaterThanOrEqualTo(anchorAtStart + 4),
    );
    expect(
      page.rootBuildCount,
      rootBaseline,
      reason: '两轮弹窗开关后页根 build 计数全程不变',
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(GlobalKey<NavigatorState> navKey) => MaterialApp(
      navigatorKey: navKey,
      // 对齐生产：main.dart:459-461 的 _appNavigatorObservers 首项。
      navigatorObservers: <NavigatorObserver>[RouteTransitionGate.observer],
      home: const _InstrumentedPage(),
    );

/// 埋点页面：根 build 计数自增；build 根包 [RouteGateAnchor]（§3.4 范式）。
class _InstrumentedPage extends StatefulWidget {
  const _InstrumentedPage();

  @override
  State<_InstrumentedPage> createState() => _InstrumentedPageState();
}

class _InstrumentedPageState extends State<_InstrumentedPage> {
  /// 黄金观测量：页面根 State 的 build 执行次数。
  int rootBuildCount = 0;

  /// §3.4：锚点句柄存 final 字段，setState 重建与热重载都保留锚点 State。
  final GlobalKey<RouteGateAnchorState> gateKey =
      GlobalKey<RouteGateAnchorState>();

  void _openBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(
        height: 48,
        child: Center(child: Text('底部弹窗')),
      ),
    );
  }

  void _openDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('对话框')),
    );
  }

  @override
  Widget build(BuildContext context) {
    rootBuildCount++;
    return RouteGateAnchor(
      key: gateKey,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton(
                onPressed: () => _openBottomSheet(context),
                child: const Text('打开底部弹窗'),
              ),
              TextButton(
                onPressed: () => _openDialog(context),
                child: const Text('打开对话框'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
