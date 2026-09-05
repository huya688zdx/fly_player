import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  testWidgets('通用悬浮小窗在浅色主题下使用浅色背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.latte),
        home: const Scaffold(
          body: DesktopFloatingPanel(child: SizedBox(width: 240, height: 180)),
        ),
      ),
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(DesktopFloatingPanel),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;

    expect(decoration.color!.computeLuminance(), greaterThan(0.7));
  });

  // 模拟播放器画面层：背景手势是弹窗的祖先（与真实控件层拓扑一致）。
  Future<void> pumpPanel(
    WidgetTester tester, {
    required VoidCallback onBackgroundTap,
    required VoidCallback onBackgroundDoubleTap,
    Widget? panelChild,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBackgroundTap,
            onDoubleTap: onBackgroundDoubleTap,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DesktopFloatingPanel(
                  child: panelChild ?? const SizedBox(width: 160, height: 72),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('外壳空白处单击/双击不穿透背景', (tester) async {
    var backgroundTaps = 0;
    var backgroundDoubleTaps = 0;
    await pumpPanel(
      tester,
      onBackgroundTap: () => backgroundTaps++,
      onBackgroundDoubleTap: () => backgroundDoubleTaps++,
    );
    await tester.tapAt(const Offset(80, 60));
    await tester.tapAt(const Offset(80, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(backgroundTaps, 0);
    expect(backgroundDoubleTaps, 0);
  });

  testWidgets('玻璃圆角外的四角死区同样不穿透', (tester) async {
    var backgroundTaps = 0;
    await pumpPanel(
      tester,
      onBackgroundTap: () => backgroundTaps++,
      onBackgroundDoubleTap: () {},
    );
    // 面板左上角在 (24, 24)，该点距角 2px：在矩形内、圆角外。
    await tester.tapAt(const Offset(26, 26));
    await tester.pump(const Duration(milliseconds: 400));
    expect(backgroundTaps, 0);
  });

  testWidgets('外壳内部按钮仍可点击', (tester) async {
    var pressed = 0;
    await pumpPanel(
      tester,
      onBackgroundTap: () {},
      onBackgroundDoubleTap: () {},
      panelChild: TextButton(
        onPressed: () => pressed++,
        child: const Text('从头播放'),
      ),
    );
    await tester.tap(find.text('从头播放'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pressed, 1);
  });
}
