import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/theme/app_theme.dart';

double _opacityOf(WidgetTester tester, IconData icon) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Future<void> _hoverAt(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: tester.getCenter(finder));
  addTearDown(gesture.removePointer);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('悬浮箭头：溢出时悬停出现，点击按 0.8 视口翻页，边界自动隐藏', (tester) async {
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 120,
              width: 800,
              child: HoverScrollArrows(
                scrollController: controller,
                child: ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  itemCount: 40,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => SizedBox(
                    width: 100,
                    child: Center(child: Text('卡 $index')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 未悬停：箭头淡出；起点只能向右滚。
    expect(_opacityOf(tester, Icons.chevron_right), 0);
    expect(_opacityOf(tester, Icons.chevron_left), 0);

    await _hoverAt(tester, find.byType(ListView));
    expect(_opacityOf(tester, Icons.chevron_right), 1);
    expect(_opacityOf(tester, Icons.chevron_left), 0);

    // 点右箭头：按 0.8 视口宽度翻页，此后左右箭头都可用。
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      controller.position.pixels,
      closeTo(controller.position.viewportDimension * 0.8, .5),
    );
    expect(_opacityOf(tester, Icons.chevron_left), 1);
    expect(_opacityOf(tester, Icons.chevron_right), 1);

    // 滚到最右：右箭头隐藏。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, Icons.chevron_right), 0);
    expect(_opacityOf(tester, Icons.chevron_left), 1);
  });
}
