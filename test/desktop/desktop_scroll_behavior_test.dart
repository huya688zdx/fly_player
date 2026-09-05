import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_scroll_behavior.dart';

void main() {
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
