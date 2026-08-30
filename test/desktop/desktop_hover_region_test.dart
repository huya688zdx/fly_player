import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';

void main() {
  // 悬停可视指示：hovering 时行变红。点按钮在行上方插入 100px 占位，
  // 把行从静止指针下方挪走（模拟数据加载挤位 / 内容位移）。
  Widget harness() {
    return MaterialApp(
      home: DesktopPointerPositionTracker(
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: <Widget>[
                  ElevatedButton(
                    key: const ValueKey<String>('shift'),
                    onPressed: () => setState(() {}),
                    child: const SizedBox(width: 10, height: 10),
                  ),
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
    );
  }

  Color rowColor(WidgetTester tester) => tester
      .widget<ColoredBox>(find.byKey(const ValueKey<String>('row')))
      .color;

  testWidgets('指针事件移出后悬停熄灭', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 75));
    addTearDown(gesture.removePointer);
    await tester.pump();

    expect(rowColor(tester), Colors.red);

    await gesture.moveTo(const Offset(400, 400));
    await tester.pump();

    expect(rowColor(tester), Colors.blue);
  });

  testWidgets('指针静止、内容位移把行挪走后悬停自愈（帧回调触发）', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // 按钮高 ~36 + 间距，行顶约在 y≈48+8=56 → 指针落在行内 (100, 75)。
    await gesture.addPointer(location: const Offset(100, 75));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(rowColor(tester), Colors.red);

    // 不动指针：点击按钮触发布局位移，行被挪到指针范围之外。
    await tester.tap(find.byKey(const ValueKey<String>('shift')));
    // 帧回调阶段完成重校验；再泵一帧让 setState 落地。
    await tester.pumpAndSettle();

    expect(rowColor(tester), Colors.blue);
  });

  testWidgets('滚轮滚动触发重校验（PointerScrollEvent 信号）', (tester) async {
    await tester.pumpWidget(harness());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 75));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(rowColor(tester), Colors.red);

    // 点击挪走行之后，滚轮事件（指针不动）也应驱动重校验。
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
}
