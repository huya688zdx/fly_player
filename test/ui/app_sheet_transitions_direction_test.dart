import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/ui/app_motion.dart';
import 'package:fly_player/ui/app_sheet_transitions.dart';

/// 弹层入场方向约定：手机平台横竖屏统一从下方滑入；
/// 桌面端保持横屏从右、竖屏从下（app_motion.dart 两个 offset 的分工）。
void main() {
  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// 打开一张测试弹层，返回其入场 SlideTransition 的当前位移。
  Future<Offset> captureEnterOffset(WidgetTester tester) async {
    late final BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    final sheetFuture = AppSheetTransitions.showAdaptiveSheet<bool>(
      hostContext,
      barrierLabel: 'test-sheet',
      builder: (_) => const SizedBox(key: ValueKey('sheet-body')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('sheet-body')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    final offset = slide.position.value;
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await sheetFuture;
    return offset;
  }

  void expectFromBelow(Offset offset) {
    expect(
      offset.dx == 0 && offset.dy > 0,
      isTrue,
      reason: '应从下方滑入，实际 $offset',
    );
  }

  void expectFromRight(Offset offset) {
    expect(
      offset.dx > 0 && offset.dy == 0,
      isTrue,
      reason: '应从右侧滑入，实际 $offset',
    );
  }

  testWidgets('手机横屏：弹层仍从下方滑入（横竖屏统一）', (tester) async {
    DesktopEnvironment.debugOverridePlatform = false;
    _setView(const Size(1920, 1080));
    expectFromBelow(await captureEnterOffset(tester));
    expect(AppMotion.sheetPortraitOffset.dy > 0, isTrue);
  });

  testWidgets('桌面横屏：弹层保持从右侧滑入', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    _setView(const Size(1920, 1080));
    expectFromRight(await captureEnterOffset(tester));
  });

  testWidgets('桌面竖屏窗口：弹层从下方滑入', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    _setView(const Size(1080, 1920));
    expectFromBelow(await captureEnterOffset(tester));
  });
}

void _setView(Size logicalSize) {
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = logicalSize;
  view.devicePixelRatio = 1.0;
}
