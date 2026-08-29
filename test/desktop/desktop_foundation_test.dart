import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  group('DesktopEnvironment', () {
    test('平台判定与 dart:io 一致', () {
      expect(
        DesktopEnvironment.isDesktopPlatform,
        Platform.isWindows || Platform.isMacOS || Platform.isLinux,
      );
      expect(DesktopEnvironment.isWindows, Platform.isWindows);
    });
  });

  group('DesktopBreakpoints', () {
    test('断点单调递增且分屏最小宽度包含侧栏场景', () {
      expect(
        DesktopBreakpoints.sidebarMinWidth,
        lessThan(DesktopBreakpoints.splitMinWidth),
      );
      expect(
        DesktopBreakpoints.splitMinWidth,
        lessThan(DesktopBreakpoints.wideContentWidth),
      );
      expect(DesktopBreakpoints.paneMinWidth, greaterThan(0));
    });
  });

  group('DesktopSplitController', () {
    test('默认关闭、比例 50/50，开启时通知一次', () {
      final controller = DesktopSplitController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      expect(controller.enabled, isFalse);
      expect(
        controller.paneFraction,
        DesktopSplitController.defaultPaneFraction,
      );

      controller.enabled = true;
      controller.enabled = true; // 重复赋值不通知
      expect(controller.enabled, isTrue);
      expect(notifications, 1);
    });

    test('比例预设对齐分屏设置页且写入时夹取范围', () {
      expect(DesktopSplitController.paneFractionPresets, [0.42, 0.50, 0.65]);
      final controller = DesktopSplitController();
      controller.setPaneFraction(0.65);
      expect(controller.paneFraction, 0.65);
      controller.setPaneFraction(0.9);
      expect(controller.paneFraction, 0.70); // 夹取上限
      controller.setPaneFraction(0.1);
      expect(controller.paneFraction, 0.30); // 夹取下限
    });

    test('paneHostBuilder 未接线时为 null（Shell 渲染占位不崩溃）', () {
      expect(DesktopSplitController().paneHostBuilder, isNull);
    });
  });

  group('HoverLift', () {
    Widget host({ThemeData? theme, bool enabled = true}) {
      Widget child = HoverLift(
        enabled: enabled,
        child: const SizedBox(width: 40, height: 60),
      );
      if (theme != null) child = Theme(data: theme, child: child);
      return MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      );
    }

    testWidgets('悬停放大到桌面档位，移出复原', (tester) async {
      await tester.pumpWidget(
        host(theme: AppThemeBuilder.build(AppThemePreset.midnight)),
      );
      final center = tester.getCenter(find.byType(HoverLift));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();
      final scale = tester
          .widget<AnimatedScale>(
            find.descendant(
              of: find.byType(HoverLift),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;
      expect(scale, DesktopTokens.hoverLiftScale);
      await gesture.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      final scaleAfter = tester
          .widget<AnimatedScale>(
            find.descendant(
              of: find.byType(HoverLift),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;
      expect(scaleAfter, 1.0);
    });

    testWidgets('enabled=false 时直通不包裹手势（触屏布局零开销）', (tester) async {
      await tester.pumpWidget(host(enabled: false));
      expect(
        find.descendant(
          of: find.byType(HoverLift),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
      );
    });

    testWidgets('主题扩展缺失时退化为仅缩放不抛错', (tester) async {
      await tester.pumpWidget(host());
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
        location: tester.getCenter(find.byType(HoverLift)),
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HoverLift)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('showDesktopContextMenu', () {
    testWidgets('弹出菜单并回调所选项，点击外部关闭', (tester) async {
      var selected = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDesktopContextMenu(
                    context,
                    position: const Offset(120, 120),
                    entries: [
                      DesktopContextMenuEntry(
                        label: '播放',
                        icon: Icons.play_arrow_rounded,
                        onSelected: () => selected = 'play',
                      ),
                      const DesktopContextMenuEntry(
                        label: '下载',
                        icon: Icons.download_rounded,
                      ),
                    ],
                  ),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);

      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      expect(selected, 'play');
      expect(find.text('下载'), findsNothing);
    });
  });
}
