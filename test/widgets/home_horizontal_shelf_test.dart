import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/home/widgets/home_horizontal_shelf.dart';

void main() {
  Widget buildShelf({
    required double width,
    List<int>? items,
    TextScaler textScaler = TextScaler.noScaling,
    double idealItemWidth = 320,
    double minItemWidth = 140,
    double maxItemWidth = 360,
    double textLinesHeight = 44,
    double gap = 12,
    bool includeRealText = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: HomeHorizontalShelf<int>(
                storageKey: 'test',
                items: items ?? List<int>.generate(8, (index) => index),
                idealItemWidth: idealItemWidth,
                minItemWidth: minItemWidth,
                maxItemWidth: maxItemWidth,
                itemAspectRatio: 16 / 10,
                textLinesHeight: textLinesHeight,
                gap: gap,
                itemBuilder: (context, item, cardWidth) => includeRealText
                    ? SizedBox(
                        key: ValueKey<int>(item),
                        width: cardWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: cardWidth,
                              height: cardWidth / (16 / 10),
                              child: const ColoredBox(color: Colors.blue),
                            ),
                            Text(
                              '标题',
                              key: ValueKey<String>('shelf-title-$item'),
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              '副标题',
                              key: ValueKey<String>('shelf-subtitle-$item'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        key: ValueKey<int>(item),
                        width: cardWidth,
                        color: Colors.blue,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('横向架可连续拖动并停在卡片中间', (tester) async {
    await tester.pumpWidget(buildShelf(width: 360));

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);

    final list = tester.widget<ListView>(find.byType(ListView));
    final cardWidth = tester.getSize(find.byKey(const ValueKey<int>(0))).width;
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;

    await tester.drag(find.byType(ListView), const Offset(-95, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(cardWidth));
    expect(list.physics, isA<ClampingScrollPhysics>());
    expect(list.padding, EdgeInsets.zero);
  });

  testWidgets('断点宽度下卡片遵守上下限且手机露出下一张', (tester) async {
    Future<double> cardWidth(double width) async {
      await tester.pumpWidget(buildShelf(width: width));
      await tester.pump();
      return tester.getSize(find.byKey(const ValueKey<int>(0))).width;
    }

    final phone = await cardWidth(360);
    final tablet = await cardWidth(600);
    final desktop = await cardWidth(800);

    for (final width in <double>[phone, tablet, desktop]) {
      expect(width, greaterThanOrEqualTo(140));
      expect(width, lessThanOrEqualTo(360));
    }
    expect(phone, closeTo(201.6, .01));
    expect(tablet, closeTo(240, .01));
    expect(desktop, closeTo(224, .01));
    expect(phone * 2 + 12, greaterThan(360));
    expect({phone, tablet, desktop}.length, 3);
  });

  testWidgets('大号文字会增加固定容器高度且不溢出', (tester) async {
    await tester.pumpWidget(buildShelf(width: 360));
    final normalHeight = tester.getSize(find.byType(ListView)).height;

    await tester.pumpWidget(
      buildShelf(width: 360, textScaler: const TextScaler.linear(2)),
    );
    await tester.pump();
    final largeTextHeight = tester.getSize(find.byType(ListView)).height;

    expect(largeTextHeight, greaterThan(normalHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字区高度覆盖真实标题和副标题的缩放后边界', (tester) async {
    await tester.pumpWidget(
      buildShelf(
        width: 360,
        textScaler: const TextScaler.linear(2),
        includeRealText: true,
      ),
    );

    final listBounds = tester.getRect(find.byType(ListView));
    final titleBounds = tester.getRect(
      find.byKey(const ValueKey<String>('shelf-title-0')),
    );
    final subtitleBounds = tester.getRect(
      find.byKey(const ValueKey<String>('shelf-subtitle-0')),
    );

    expect(titleBounds.bottom, lessThanOrEqualTo(listBounds.bottom + .01));
    expect(subtitleBounds.bottom, lessThanOrEqualTo(listBounds.bottom + .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('空数据和无效尺寸安全返回空布局', (tester) async {
    await tester.pumpWidget(buildShelf(width: 360, items: const <int>[]));
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(buildShelf(width: 360, idealItemWidth: double.nan));
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('零文字区高度仍渲染且容器只保留媒体区高度', (tester) async {
    await tester.pumpWidget(buildShelf(width: 360, textLinesHeight: 0));

    final cardWidth = tester.getSize(find.byKey(const ValueKey<int>(0))).width;
    expect(find.byType(ListView), findsOneWidget);
    expect(
      tester.getSize(find.byType(ListView)).height,
      closeTo(cardWidth / (16 / 10), .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('极窄约束下卡片退化为可用宽度且零间距合法', (tester) async {
    await tester.pumpWidget(buildShelf(width: 80, minItemWidth: 140, gap: 0));

    expect(find.byType(ListView), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<int>(0))).width,
      closeTo(80, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('正有限边界配置统一归一化后仍渲染并遵守卡宽', (tester) async {
    Future<double> cardWidth({
      required double width,
      required double ideal,
      required double min,
      required double max,
    }) async {
      await tester.pumpWidget(
        buildShelf(
          width: width,
          idealItemWidth: ideal,
          minItemWidth: min,
          maxItemWidth: max,
        ),
      );
      await tester.pump();
      expect(find.byType(ListView), findsOneWidget);
      return tester.getSize(find.byKey(const ValueKey<int>(0))).width;
    }

    expect(
      await cardWidth(width: 360, ideal: 320, min: 250, max: 360),
      closeTo(250, .01),
    );
    expect(
      await cardWidth(width: 600, ideal: 320, min: 140, max: 210),
      closeTo(210, .01),
    );
    expect(
      await cardWidth(width: 360, ideal: 180, min: 260, max: 360),
      closeTo(180, .01),
    );
    expect(
      await cardWidth(width: 360, ideal: 320, min: 260, max: 180),
      closeTo(180, .01),
    );
  });
}
