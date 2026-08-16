import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/home/widgets/home_adaptive_pager.dart';

void main() {
  Widget buildPager({required double width, List<int>? items}) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: HomeAdaptivePager<int>(
              items: items ?? List<int>.generate(8, (index) => index),
              itemId: (item) => '$item',
              idealItemWidth: 190,
              itemAspectRatio: 16 / 10,
              itemBuilder: (context, item, width) =>
                  SizedBox(key: ValueKey<int>(item), width: width),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('分页器按约束宽度改变列数且不裁半张卡', (tester) async {
    await tester.pumpWidget(buildPager(width: 336));

    expect(
      tester.getSize(find.byKey(const ValueKey<int>(0))).width,
      closeTo(163, .01),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<int>(1))).width,
      closeTo(163, .01),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(buildPager(width: 570));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey<int>(0))).width,
      closeTo(183.33, .02),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<int>(2))).width,
      closeTo(183.33, .02),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('多页时显示当前页语义，单页时隐藏指示器', (tester) async {
    await tester.pumpWidget(buildPager(width: 336));

    expect(find.bySemanticsLabel('第 1 页，共 4 页'), findsOneWidget);

    await tester.pumpWidget(buildPager(width: 336, items: <int>[0, 1]));
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('第 .* 页')), findsNothing);
  });

  testWidgets('数据变化后以原首项或最接近索引恢复页码', (tester) async {
    final visibleIds = <String>[];
    Widget pager(List<int> items) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 336,
          child: HomeAdaptivePager<int>(
            items: items,
            itemId: (item) => '$item',
            idealItemWidth: 190,
            itemAspectRatio: 16 / 10,
            itemBuilder: (context, item, width) =>
                SizedBox(key: ValueKey<int>(item), width: width),
            onFirstVisibleItemIdChanged: visibleIds.add,
          ),
        ),
      ),
    );

    await tester.pumpWidget(pager(<int>[0, 1, 2, 3, 4, 5]));
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(visibleIds.last, '2');

    await tester.pumpWidget(pager(<int>[0, 1, 2, 3, 4]));
    await tester.pump();
    expect(find.bySemanticsLabel('第 2 页，共 3 页'), findsOneWidget);

    await tester.pumpWidget(pager(<int>[0, 1, 3, 4]));
    await tester.pump();
    expect(find.bySemanticsLabel('第 2 页，共 2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
