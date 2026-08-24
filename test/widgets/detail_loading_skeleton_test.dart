import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/widgets/detail/detail_loading_skeleton.dart';
import 'package:fly_player/ui/detail_presentation.dart';

void main() {
  testWidgets('详情加载骨架在真机横屏高度不发生纵向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 384));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(853, 384)),
        child: MaterialApp(home: DetailLoadingSkeleton()),
      ),
    );

    expect(tester.takeException(), isNull);
    final hero = tester.getSize(
      find.byKey(const ValueKey('detail-skeleton-hero')),
    );
    expect(hero.height, lessThanOrEqualTo(254));
  });

  testWidgets('详情加载骨架在 701×331 超矮横屏下不发生纵向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(701, 331));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(701, 331),
          padding: EdgeInsets.only(top: 24),
        ),
        child: MaterialApp(home: DetailLoadingSkeleton()),
      ),
    );

    expect(tester.takeException(), isNull);
    final hero = tester.getSize(
      find.byKey(const ValueKey('detail-skeleton-hero')),
    );
    expect(hero.height, lessThanOrEqualTo(201));
  });

  testWidgets('详情加载骨架在嵌入窗格及极短高度不发生纵向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(853, 320)),
        child: MaterialApp(
          home: DetailLoadingSkeleton(presentation: DetailPresentation.pane),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('详情加载骨架在普通高度保持原有 hero 最小高度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DetailLoadingSkeleton()));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-skeleton-hero'))).height,
      greaterThanOrEqualTo(300),
    );
  });

  testWidgets('详情加载骨架在 hero 内容净高临界区隐藏内容', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 270));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DetailLoadingSkeleton()));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('detail-skeleton-hero-content')),
      findsNothing,
    );
  });

  testWidgets('详情加载骨架在 page body 预算不足时不渲染完整 body', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DetailLoadingSkeleton()));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('detail-skeleton-body-content')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-skeleton-hero'))).height,
      greaterThanOrEqualTo(0),
    );
  });

  testWidgets('详情加载骨架在 pane hero 内容净高临界区隐藏内容', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 245));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: DetailLoadingSkeleton(presentation: DetailPresentation.pane),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('detail-skeleton-hero-content')),
      findsNothing,
    );
  });

  testWidgets('详情加载骨架在键盘压缩高度临界区无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 272));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DetailLoadingSkeleton()));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-skeleton-hero'))).height,
      greaterThanOrEqualTo(0),
    );

    await tester.binding.setSurfaceSize(const Size(853, 285));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情加载骨架在 pane body 预算不足时不渲染完整 body', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: DetailLoadingSkeleton(presentation: DetailPresentation.pane),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('detail-skeleton-body-content')),
      findsNothing,
    );
  });
}
