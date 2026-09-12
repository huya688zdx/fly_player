import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/app_info_popover.dart';
import 'package:fly_player/utils/app_top_tip.dart';

void main() {
  testWidgets('brief tip keeps local light text contrast on a dark root', (
    tester,
  ) async {
    final colors = AppThemeBuilder.build(
      AppThemePreset.latte,
    ).extension<AppThemeColors>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: colors,
          hasRuntimeColors: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => AppTopTip().show(
                  context,
                  message: '连接未完成',
                  color: colors.surfaceStrong,
                ),
                child: const Text('显示提示'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('显示提示'));
    await tester.pumpAndSettle();
    final foreground = tester.widget<Text>(find.text('连接未完成')).style!.color;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(foreground, colors.textPrimary);
    expect(find.text('连接未完成'), findsNothing);
  });
  testWidgets('explanation overlay preserves the calling page theme', (
    tester,
  ) async {
    final colors = AppThemeBuilder.build(
      AppThemePreset.forest,
    ).extension<AppThemeColors>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: colors,
          hasRuntimeColors: true,
          child: const Scaffold(
            body: Center(
              child: AppInfoPopoverAnchor(
                title: '媒体来源说明',
                description: '已绑定来源会自动连接',
                child: Icon(Icons.info_outline, key: ValueKey('open-help')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-help')));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('已绑定来源会自动连接')).appColors, colors);
    expect(tester.takeException(), isNull);
  });
}
