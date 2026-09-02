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
}
