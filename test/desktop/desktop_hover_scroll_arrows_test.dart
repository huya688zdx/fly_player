import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/screens/home/widgets/home_horizontal_shelf.dart';

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

  testWidgets('桌面媒体架缩成分屏宽度后仍可双向翻页，放大后刷新边界', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
    addTearDown(DesktopPointerPosition.debugResetForTest);
    tester.view.physicalSize = const Size(1200, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        builder: (context, child) =>
            DesktopPointerPositionTracker(child: child!),
        home: Scaffold(
          body: HomeHorizontalShelf<int>(
            storageKey: 'narrow-shelf',
            items: List.generate(8, (index) => index),
            idealItemWidth: 100,
            minItemWidth: 100,
            maxItemWidth: 100,
            itemAspectRatio: 1,
            itemBuilder: (_, item, width) => Text('番剧 $item'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(950, 50));
    await mouse.moveTo(const Offset(900, 50));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, Icons.chevron_right), 0);
    tester.view.physicalSize = const Size(500, 300);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(250, 50));
    await tester.pumpAndSettle();
    expect(find.byType(HoverScrollArrows), findsOneWidget);
    expect(_opacityOf(tester, Icons.chevron_right), 1);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    tester.view.physicalSize = const Size(1200, 300);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, Icons.chevron_right), 0);
  });

  testWidgets('浅色主题翻页按钮使用主题底色、描边和紧凑圆角', (tester) async {
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.latte),
        home: Scaffold(
          body: SizedBox(
            height: 120,
            width: 800,
            child: HoverScrollArrows(
              scrollController: controller,
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: 20,
                itemBuilder: (context, index) => const SizedBox(width: 100),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _hoverAt(tester, find.byType(ListView));

    final arrowContainer = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(AnimatedContainer),
      ),
    );
    // 圆角按钮使用主题色，命中区与可见尺寸一致。
    final decoration = arrowContainer.decoration! as BoxDecoration;
    final colors = tester.element(find.byIcon(Icons.chevron_right)).appColors;
    expect(decoration.color, colors.surfaceStrong);
    expect(decoration.border, Border.all(color: colors.borderSubtle));
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.boxShadow, isNull);
    expect(arrowContainer.foregroundDecoration, isNull);
    expect(tester.widget<Icon>(find.byIcon(Icons.chevron_right)).size, 24);
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.byIcon(Icons.chevron_right),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .height,
      48,
    );
  });
}
