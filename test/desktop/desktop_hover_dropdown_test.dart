import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_hover_dropdown.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

void main() {
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
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
    );
    await tester.pump();
  }

  DesktopHoverDropdownSpec buildSpec({ValueChanged<String>? onSelected}) {
    return DesktopHoverDropdownSpec(
      title: '选择字幕',
      selectedId: 'sub-1',
      onSelected: onSelected ?? (_) {},
      items: const [
        TrackOptionSheetItem(id: 'sub-1', title: '法语-默认', subtitle: 'SUP'),
        TrackOptionSheetItem(id: 'sub-2', title: '日语', subtitle: 'SRT 1'),
      ],
    );
  }

  testWidgets('悬停触发件弹出选项面板并高亮选中项', (tester) async {
    await pumpScaffold(tester, spec: buildSpec());
    expect(find.text('选择字幕'), findsNothing);

    final gesture = await hoverPointer(tester, const Offset(60, 36));
    await tester.pumpAndSettle();

    expect(find.text('选择字幕'), findsOneWidget);
    expect(find.text('法语-默认'), findsOneWidget);
    expect(find.text('日语'), findsOneWidget);

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
}
