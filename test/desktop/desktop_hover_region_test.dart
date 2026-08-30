import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';

void main() {
  setUp(() {
    DesktopPointerPosition.debugResetForTest();
  });

  // 基础宿主：行固定在左上 (0..200, 48..98)。点 shift 按钮在行上方插入
  // 100px 占位，把行从静止指针下方挪走（模拟数据加载挤位 / 内容位移）。
  Widget harness() {
    final inserted = ValueNotifier<bool>(false);
    return MaterialApp(
      home: DesktopPointerPositionTracker(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<bool>(
              valueListenable: inserted,
              builder: (context, value, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ElevatedButton(
                      key: const ValueKey<String>('shift'),
                      onPressed: () => inserted.value = !inserted.value,
                      child: const SizedBox(width: 40, height: 36),
                    ),
                    if (value) const SizedBox(height: 100),
                    DesktopHoverRegion(
                      builder: (context, hovering) => ColoredBox(
                        key: const ValueKey<String>('row'),
                        color: hovering ? Colors.red : Colors.blue,
                        child: const SizedBox(width: 200, height: 50),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Color rowColor(WidgetTester tester) => tester
      .widget<ColoredBox>(find.byKey(const ValueKey<String>('row')))
      .color;

  // 外扩宿主：行 200x50 位于 (100..300, 50..100)，校验边界左右各外扩
  // [insets]；指针在行外左侧但外扩区内时悬停应维持（贴边滚动按钮伸出
  // 页面留白、悬停须维持的场景）。
  Widget insetHarness(double insets) {
    return MaterialApp(
      home: DesktopPointerPositionTracker(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 100, top: 50),
              child: DesktopHoverRegion(
                hoverBoundsInsets: EdgeInsets.symmetric(horizontal: insets),
                builder: (context, hovering) => ColoredBox(
                  key: const ValueKey<String>('inset-row'),
                  color: hovering ? Colors.red : Colors.blue,
                  child: const SizedBox(width: 200, height: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color insetRowColor(WidgetTester tester) => tester
      .widget<ColoredBox>(find.byKey(const ValueKey<String>('inset-row')))
      .color;

  testWidgets('指针事件移入点亮、移出熄灭', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 20));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(100, 75));
    await tester.pump();

    expect(rowColor(tester), Colors.red);

    await gesture.moveTo(const Offset(400, 300));
    await tester.pump();

    expect(rowColor(tester), Colors.blue);
  });

  testWidgets('指针静止、内容位移把行挪走后悬停自愈（帧回调触发）', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 20));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(100, 75));
    await tester.pump();
    expect(rowColor(tester), Colors.red);

    // 不动指针：点击按钮在行上方插入 100px，行被挪出指针范围。
    await tester.tap(find.byKey(const ValueKey<String>('shift')));
    await tester.pumpAndSettle();

    expect(rowColor(tester), Colors.blue);
  });

  testWidgets('滚轮滚动触发重校验（PointerScrollEvent 信号）', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 20));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(100, 75));
    await tester.pump();
    expect(rowColor(tester), Colors.red);

    // 插入占位把行挪走；指针不动，滚轮事件也应驱动重校验。
    await tester.tap(find.byKey(const ValueKey<String>('shift')));
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 75),
        scrollDelta: Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();

    expect(rowColor(tester), Colors.blue);
  });

  testWidgets('外扩边界：指针在行外但外扩区内时悬停点亮并维持（按钮伸出区）', (tester) async {
    await tester.pumpWidget(insetHarness(40));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(80, 20));
    addTearDown(gesture.removePointer);
    // 行左缘在 x=100；指针在 x=80 —— 行外、MouseRegion 外，但外扩 40px 内。
    // 悬停经指针位置校验点亮（对应「从页面留白直接挪到贴边按钮上」）。
    await gesture.moveTo(const Offset(80, 75));
    await tester.pumpAndSettle();

    expect(insetRowColor(tester), Colors.red);

    // 移出外扩区：熄灭。
    await gesture.moveTo(const Offset(20, 75));
    await tester.pump();

    expect(insetRowColor(tester), Colors.blue);
  });

  testWidgets('零外扩维持旧行为：行外即熄灭（自愈不回归）', (tester) async {
    await tester.pumpWidget(insetHarness(0));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(80, 20));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(80, 75));
    await tester.pump();

    // 指针在行左侧 20px（行外）：悬停不亮。
    expect(insetRowColor(tester), Colors.blue);
  });
}
