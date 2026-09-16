import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_scroll_behavior.dart';

void main() {
  testWidgets('卡片上普通滚轮上下滚动页面，横向输入和 Shift 滚轮横移', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final horizontal = ScrollController();
    final vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DesktopScrollBehavior(),
        home: Scaffold(
          body: ListView(
            controller: vertical,
            children: [
              SizedBox(
                height: 200,
                child: ListView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  children: const [SizedBox(width: 2400)],
                ),
              ),
              const SizedBox(height: 1800),
            ],
          ),
        ),
      ),
    );
    Future<void> wheel(Offset delta) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(100, 100),
          scrollDelta: delta,
        ),
      );
      await tester.pump();
    }

    await wheel(const Offset(0, 120));
    expect(horizontal.offset, 0);
    expect(vertical.offset, 120);
    vertical.jumpTo(0);
    await tester.pump();
    await wheel(const Offset(60, 0));
    expect(horizontal.offset, 60);
    expect(vertical.offset, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(const Offset(0, 120));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(horizontal.offset, 180);
    expect(vertical.offset, 0);
    await wheel(const Offset(0, 120));
    await wheel(const Offset(0, -60));
    expect(vertical.offset, 60);
    expect(horizontal.offset, 180);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await wheel(const Offset(0, 60));
    expect(vertical.offset, 120);
    expect(horizontal.offset, 180);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('提示浮层打开时窗口缩小出现滚动条，不重挂载页面', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DesktopScrollBehavior(),
        home: Scaffold(
          body: ListView(
            children: [
              Tooltip(
                message: '媒体来源说明',
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.info_outline),
                ),
              ),
              const SizedBox(height: 300),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<TooltipState>(find.byType(Tooltip).first)
        .ensureTooltipVisible();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(800, 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(800, 190));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(IconButton), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('controller 首帧尚未建立内容尺寸时不会抛错', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DesktopScrollBehavior(),
        home: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: controller,
            itemCount: 30,
            itemBuilder: (_, index) => Text('item $index'),
          ),
        ),
      ),
    );

    expect(errors, isEmpty);
  });

  testWidgets('视图切换过渡期 controller 多重挂载时不会抛错', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DesktopScrollBehavior(),
        home: Row(
          children: <Widget>[
            for (var column = 0; column < 2; column++)
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (_, index) => Text('$column-$index'),
                ),
              ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
