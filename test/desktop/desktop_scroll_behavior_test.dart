import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_scroll_behavior.dart';

void main() {
  testWidgets('桌面滚轮优先滚动横向列表，到边界后交给纵向页面', (tester) async {
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
    expect(horizontal.offset, 120);
    expect(vertical.offset, 0);
    await wheel(const Offset(60, 0));
    expect(horizontal.offset, 180);
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    await wheel(const Offset(0, 120));
    expect(vertical.offset, 120);
    vertical.jumpTo(0);
    await tester.pump();
    await wheel(const Offset(0, -120));
    expect(horizontal.offset, horizontal.position.maxScrollExtent - 120);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await wheel(const Offset(0, 120));
    expect(vertical.offset, 120);
    expect(horizontal.offset, horizontal.position.maxScrollExtent - 120);
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
