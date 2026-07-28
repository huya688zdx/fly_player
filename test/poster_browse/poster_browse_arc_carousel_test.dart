import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_arc_carousel.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_card.dart';

void main() {
  group('PosterBrowseArcMath', () {
    test('realIndex 使用安全正模并处理空列表', () {
      expect(PosterBrowseArcMath.realIndex(-1, 5), 4);
      expect(PosterBrowseArcMath.realIndex(0, 5), 0);
      expect(PosterBrowseArcMath.realIndex(5, 5), 0);
      expect(PosterBrowseArcMath.realIndex(3, 0), 0);
      expect(PosterBrowseArcMath.realIndex(3, -2), 0);
    });

    test('transformFor 中心最高且两侧弧线单调并按方向旋转', () {
      final center = PosterBrowseArcMath.transformFor(0);
      final nearRight = PosterBrowseArcMath.transformFor(1);
      final farRight = PosterBrowseArcMath.transformFor(3);
      final nearLeft = PosterBrowseArcMath.transformFor(-1);
      final farLeft = PosterBrowseArcMath.transformFor(-3);
      final clamped = PosterBrowseArcMath.transformFor(99);

      expect(center.verticalOffset, 0);
      expect(center.scale, 1);
      expect(center.rotation, 0);
      expect(center.opacity, 1);
      expect(center.zIndex, greaterThan(nearRight.zIndex));

      expect(nearRight.verticalOffset, greaterThan(center.verticalOffset));
      expect(farRight.verticalOffset, greaterThan(nearRight.verticalOffset));
      expect(nearRight.scale, lessThan(center.scale));
      expect(farRight.scale, lessThan(nearRight.scale));
      expect(nearRight.opacity, lessThan(center.opacity));
      expect(farRight.opacity, lessThan(nearRight.opacity));
      expect(nearRight.rotation, greaterThan(0));
      expect(nearLeft.rotation, lessThan(0));
      expect(farLeft.rotation.abs(), greaterThan(nearLeft.rotation.abs()));
      expect(farRight.zIndex, lessThan(nearRight.zIndex));

      expect(clamped.scale, inInclusiveRange(0.68, 1.0));
      expect(clamped.opacity, inInclusiveRange(0.30, 1.0));
      expect(clamped.rotation, inInclusiveRange(-0.34, 0.34));
    });
  });

  testWidgets('三项初始居中并拖动到相邻真实项后保持中心 focused', (tester) async {
    final settled = <int>[];
    await tester.pumpWidget(
      _app(
        PosterBrowseArcCarousel(
          items: _items(3),
          initialIndex: 1,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSettled: settled.add,
          onCenteredTap: (_) {},
        ),
      ),
    );

    expect(_cardByTitle('标题1').evaluate(), hasLength(1));
    expect(
      tester.widget<PosterBrowsePosterCard>(_cardByTitle('标题1')).focused,
      isTrue,
    );

    await tester.drag(
      find.byType(PosterBrowseArcCarousel),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(settled, hasLength(1));
    expect(settled.single, 2);
    expect(
      tester.widget<PosterBrowsePosterCard>(_cardByTitle('标题2')).focused,
      isTrue,
    );
  });

  testWidgets('点击侧项只吸附 settle，点击中心才触发 centeredTap', (tester) async {
    final settled = <int>[];
    final centered = <int>[];
    await tester.pumpWidget(
      _app(
        PosterBrowseArcCarousel(
          items: _items(3),
          initialIndex: 1,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSettled: settled.add,
          onCenteredTap: centered.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('poster_browse_arc_card_2')));
    await tester.pumpAndSettle();

    expect(settled, <int>[2]);
    expect(centered, isEmpty);
    expect(
      tester.widget<PosterBrowsePosterCard>(_cardByTitle('标题2')).focused,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('poster_browse_arc_card_2')));
    await tester.pumpAndSettle();

    expect(settled, <int>[2]);
    expect(centered, <int>[2]);
  });

  testWidgets('单项拖动不切换，双项每个真实卡只绘制一次', (tester) async {
    final singleSettled = <int>[];
    await tester.pumpWidget(
      _app(
        PosterBrowseArcCarousel(
          items: _items(1),
          initialIndex: 0,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSettled: singleSettled.add,
          onCenteredTap: (_) {},
        ),
      ),
    );

    await tester.drag(
      find.byType(PosterBrowseArcCarousel),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(singleSettled, isEmpty);
    expect(find.text('标题0'), findsOneWidget);
    expect(
      tester.widget<PosterBrowsePosterCard>(_cardByTitle('标题0')).focused,
      isTrue,
    );

    await tester.pumpWidget(
      _app(
        PosterBrowseArcCarousel(
          items: _items(2),
          initialIndex: 0,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSettled: (_) {},
          onCenteredTap: (_) {},
        ),
      ),
    );

    expect(find.text('标题0'), findsOneWidget);
    expect(find.text('标题1'), findsOneWidget);
  });

  testWidgets('动画中 dispose 不抛异常', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      _app(
        PosterBrowseArcCarousel(
          items: _items(3),
          initialIndex: 0,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSettled: (_) {},
          onCenteredTap: (_) {},
        ),
      ),
    );

    await tester.drag(
      find.byType(PosterBrowseArcCarousel),
      const Offset(-260, 0),
    );
    await tester.pump();
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(errors, isEmpty);
  });
}

Finder _cardByTitle(String title) {
  return find.byWidgetPredicate(
    (widget) => widget is PosterBrowsePosterCard && widget.item.title == title,
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox.expand(child: child)),
  );
}

List<PosterBrowseDisplayItem> _items(int count) {
  return List<PosterBrowseDisplayItem>.generate(count, (index) {
    final title = '标题$index';
    return PosterBrowseDisplayItem(
      card: MediaItemCard(
        id: 'item-$index',
        title: title,
        type: 'Movie',
        primaryImage: MediaImageRef.empty,
      ),
      title: title,
      episodeTitle: '',
      type: 'Movie',
      seriesId: '',
      ratingText: '',
      releaseYear: '',
      overview: '',
      detailTargetId: 'item-$index',
      seasonNumber: 0,
      episodeNumber: 0,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      durationSeconds: 0,
      genres: const <String>[],
      resolutions: const <String>[],
      backgroundImages: const <MediaImageRef>[],
      logoImages: const <MediaImageRef>[],
      posterImages: const <MediaImageRef>[],
    );
  });
}
