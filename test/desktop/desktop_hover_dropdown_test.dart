import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_hover_dropdown.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';
import 'package:fly_player/widgets/detail/detail_selector_row.dart';

void main() {
  Future<void> wheel(WidgetTester tester, Offset position, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: Offset(0, dy)),
    );
    await tester.pump();
  }

  Future<TestGesture> hoverPointer(WidgetTester tester, Offset location) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await gesture.addPointer(location: location);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> pumpScaffold(
    WidgetTester tester, {
    DesktopHoverDropdownSpec? spec,
    ValueChanged<bool>? onOpenChanged,
    ScrollController? scrollController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.latte),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: 1200,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DesktopHoverDropdown(
                    spec: spec,
                    onOpenChanged: onOpenChanged,
                    child: const SizedBox(
                      width: 120,
                      height: 24,
                      child: Text('触发件'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  DesktopHoverDropdownSpec buildSpec({
    ValueChanged<String>? onSelected,
    double maxHeight = 380,
  }) {
    return DesktopHoverDropdownSpec.single(
      title: '选择字幕',
      maxHeight: maxHeight,
      selectedId: 'sub-1',
      onSelected: onSelected ?? (_) {},
      items: const [
        TrackOptionSheetItem(id: 'sub-1', title: '法语-默认', subtitle: 'SUP'),
        TrackOptionSheetItem(id: 'sub-2', title: '日语', subtitle: 'SRT 1'),
      ],
    );
  }

  testWidgets('详情字幕与音轨共用浮层并连续移动，快速折返不重复入场', (tester) async {
    final selected = <String>[];
    final subtitleOpen = <bool>[];
    final audioOpen = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: DetailSelectorRow(
              subtitleLabel: '字幕入口',
              audioLabel: '音轨入口',
              capabilityLabels: const ['1080'],
              onSubtitleOpenChanged: subtitleOpen.add,
              onAudioOpenChanged: audioOpen.add,
              subtitleHoverPopup: buildSpec(),
              audioHoverPopup: DesktopHoverDropdownSpec.single(
                title: '选择音频',
                items: const [TrackOptionSheetItem(id: 'audio', title: '测试音轨')],
                selectedId: 'audio',
                onSelected: selected.add,
              ),
            ),
          ),
        ),
      ),
    );
    final pointer = await hoverPointer(
      tester,
      tester.getCenter(find.text('字幕入口')),
    );
    await tester.pumpAndSettle();
    final panelFinder = find.byType(DesktopFloatingPanel);
    final panel = tester.element(panelFinder);
    final start = tester.getRect(panelFinder);

    await pointer.moveTo(tester.getCenter(find.text('音轨入口')));
    await tester.pump();
    expect(panelFinder, findsOneWidget);
    expect(tester.element(panelFinder), same(panel));
    expect(tester.getRect(panelFinder), start);
    expect(find.text('选择字幕'), findsNothing);
    expect(find.text('选择音频'), findsOneWidget);
    expect(subtitleOpen, [true, false]);
    expect(audioOpen, [true]);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(of: panelFinder, matching: find.byType(Opacity))
                .first,
          )
          .opacity,
      1,
    );
    await tester.pump(const Duration(milliseconds: 80));
    final middle = tester.getRect(panelFinder);
    expect(middle.left, greaterThan(start.left));
    expect(middle.height, lessThan(start.height));

    await pointer.moveTo(tester.getCenter(find.text('字幕入口')));
    await tester.pump();
    expect(tester.element(panelFinder), same(panel));
    expect(tester.getRect(panelFinder), middle);
    await tester.pumpAndSettle();
    expect(tester.getRect(panelFinder), start);

    await pointer.moveTo(tester.getCenter(find.text('音轨入口')));
    await tester.pumpAndSettle();
    expect(tester.getRect(panelFinder).left, greaterThan(middle.left));
    await tester.tap(find.text('测试音轨'));
    await tester.pumpAndSettle();
    expect(selected, ['audio']);
    expect(panelFinder, findsNothing);
    expect(subtitleOpen, [true, false, true, false]);
    expect(audioOpen, [true, false, true, false]);
  });

  testWidgets('悬停触发件弹出选项面板并高亮选中项', (tester) async {
    await pumpScaffold(tester, spec: buildSpec());
    expect(find.text('选择字幕'), findsNothing);

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();

    expect(find.text('选择字幕'), findsOneWidget);
    expect(find.text('法语-默认'), findsOneWidget);
    expect(find.text('日语'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('日语')).style!.color,
      tester.element(find.text('日语')).appColors.textPrimary,
    );

    // 回归锁定：弹层子树承载 tight 全屏约束，面板必须收缩到 spec 宽度，
    // 否则命中测试区铺满全屏、移出收起失效。
    final panelRect = tester.getRect(find.byType(DesktopFloatingPanel));
    expect(panelRect.width, 280.0);
    expect(panelRect.height, lessThan(600.0));

    // 面板应出现在触发件下方（贴近图 2 的下拉形态）。
    final triggerTop = tester.getTopLeft(find.text('触发件')).dy;
    final panelTop = tester.getTopLeft(find.text('选择字幕')).dy;
    expect(panelTop, greaterThan(triggerTop));

    await gesture.removePointer();
  });

  testWidgets('点选条目上抛 id 并收起面板', (tester) async {
    final selected = <String>[];
    await pumpScaffold(tester, spec: buildSpec(onSelected: selected.add));

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕'), findsOneWidget);

    await tester.tap(find.text('日语'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, ['sub-2']);
    // 点选后面板卸载，标题不再存在。
    expect(find.text('选择字幕'), findsNothing);

    await gesture.removePointer();
  });

  testWidgets('悬停短菜单不阻断页面滚轮，长菜单优先滚动选项', (tester) async {
    final page = ScrollController();
    addTearDown(page.dispose);
    await pumpScaffold(tester, spec: buildSpec(), scrollController: page);
    await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();

    await wheel(tester, const Offset(600, 300), 10);
    expect(page.offset, 10);
    await wheel(tester, tester.getCenter(find.text('日语')), 10);
    expect(page.offset, 20);
    await wheel(tester, tester.getCenter(find.text('日语')), -10);
    expect(page.offset, 10);

    page.jumpTo(0);
    await pumpScaffold(
      tester,
      scrollController: page,
      spec: buildSpec(maxHeight: 50),
    );
    await tester.pumpAndSettle();
    final options = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(DesktopFloatingPanel),
        matching: find.byType(Scrollable),
      ),
    );
    await wheel(tester, tester.getCenter(find.text('法语-默认')), 30);
    expect(options.position.pixels, 30);
    expect(page.offset, 0);
  });

  testWidgets('指针移出触发件（未进入面板）后自动收起', (tester) async {
    await pumpScaffold(tester, spec: buildSpec());

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕'), findsOneWidget);

    await gesture.moveTo(const Offset(400, 500));
    // ignore: avoid_print
    print('TEST after moveTo');
    await tester.pump();
    // ignore: avoid_print
    print('TEST after pump()');
    await tester.pump(const Duration(milliseconds: 200));
    // ignore: avoid_print
    print('TEST after pump(200)');
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('TEST after settle');
    expect(find.text('选择字幕'), findsNothing);

    await gesture.removePointer();
  });

  testWidgets('spec 为空时不响应悬停', (tester) async {
    await pumpScaffold(tester, spec: null);

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕'), findsNothing);

    await gesture.removePointer();
  });

  testWidgets('展开态经 onOpenChanged 上抛', (tester) async {
    final opens = <bool>[];
    await pumpScaffold(tester, spec: buildSpec(), onOpenChanged: opens.add);

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();
    expect(opens, [true]);

    await gesture.moveTo(const Offset(400, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(opens, [true, false]);

    await gesture.removePointer();
  });
  testWidgets('点击模式：触发件开合、点选外部关闭、点选条目上抛', (tester) async {
    final dropdownKey = GlobalKey<DesktopHoverDropdownState>();
    final selected = <String>[];
    final page = ScrollController();
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DesktopHoverDropdown(
                    key: dropdownKey,
                    activation: DesktopDropdownActivation.tap,
                    spec: buildSpec(onSelected: selected.add),
                    pageScrollController: page,
                    child: GestureDetector(
                      onTap: () => dropdownKey.currentState?.toggle(),
                      child: const SizedBox(
                        width: 120,
                        height: 24,
                        child: Text('触发件'),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: page,
                  children: const [SizedBox(height: 1200)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // 点击模式下悬停不展开。
    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();
    expect(find.text('法语-默认'), findsNothing);

    // 点击展开（buildSpec 带 title,标题正常渲染）。
    await tester.tap(find.text('触发件'));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕'), findsOneWidget);
    expect(find.text('法语-默认'), findsOneWidget);

    await wheel(tester, const Offset(600, 300), 10);
    expect(page.offset, 10);

    await wheel(tester, tester.getCenter(find.text('日语')), 10);
    expect(page.offset, 20);

    // 点击面板外关闭。
    await tester.tapAt(const Offset(600, 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('法语-默认'), findsNothing);

    // 再次点击展开并点选条目。
    await tester.tap(find.text('触发件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日语'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, ['sub-2']);
    expect(find.text('法语-默认'), findsNothing);

    await gesture.removePointer();
  });
}
