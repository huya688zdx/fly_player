import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_landscape_gesture_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('横屏海报面板默认展开并支持下滑收起上滑展开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(853, 384));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        PosterBrowseLandscapeGesturePanel(
          items: _items(),
          focusedIndex: 1,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '第 1 季',
          onItemTap: (_) {},
          collapsedContent: const Text('影片详情'),
        ),
      ),
    );

    expect(_trackOpacity(tester), 1);
    expect(_handleOpacity(tester), 0);

    await tester.drag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(_trackOpacity(tester), 0);
    expect(_handleOpacity(tester), 1);
    expect(_infoOpacity(tester), 1);
    expect(find.text('影片详情'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(_trackOpacity(tester), 1);
    expect(_handleOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏海报面板左滑只切换到下一部', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(-100, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('横屏海报面板右滑只切换到上一部', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(100, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(selected, <int>[0]);
  });

  testWidgets('横屏海报面板短距离横拖回弹且不切换', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(-25, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
  });

  testWidgets('横屏海报面板在首尾不会横滑越界', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 0, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(100, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(selected, isEmpty);

    await _pumpPanel(tester, focusedIndex: 2, onItemTap: selected.add);
    await tester.timedDrag(
      _panelFinder,
      const Offset(-100, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('横屏海报面板点按海报仍上报对应索引', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.tap(
      find.byKey(const ValueKey('poster_browse_track_item_item-0')),
    );

    expect(selected, <int>[0]);
  });

  testWidgets('横屏海报面板收起后仍可左滑切换影视', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      _panelFinder,
      const Offset(-100, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('展开态快速甩动跨多张海报并聚焦落点', (tester) async {
    final selected = <int>[];
    await _pumpPanel(
      tester,
      focusedIndex: 1,
      itemCount: 8,
      onItemTap: selected.add,
    );

    await tester.timedDrag(
      _panelFinder,
      const Offset(-480, 0),
      const Duration(milliseconds: 150),
    );
    await tester.pumpAndSettle();

    expect(selected, <int>[7]);
  });

  testWidgets('收起态快速甩动仍只切换一部', (tester) async {
    final selected = <int>[];
    await _pumpPanel(tester, focusedIndex: 1, onItemTap: selected.add);

    await tester.timedDrag(
      _panelFinder,
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      _panelFinder,
      const Offset(-480, 0),
      const Duration(milliseconds: 150),
    );
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('横屏海报面板收起后信息按切换方向位移过渡', (tester) async {
    const firstKey = ValueKey('collapsed-info-1');
    const secondKey = ValueKey('collapsed-info-2');
    await _pumpPanel(
      tester,
      focusedIndex: 1,
      onItemTap: (_) {},
      collapsedContent: const Text('影片详情一', key: firstKey),
    );
    await tester.timedDrag(
      _panelFinder,
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    final restingLeft = tester.getTopLeft(find.byKey(firstKey)).dx;

    await _pumpPanel(
      tester,
      focusedIndex: 2,
      onItemTap: (_) {},
      collapsedContent: const Text('影片详情二', key: secondKey),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(firstKey), findsOneWidget);
    expect(find.byKey(secondKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(firstKey)).dx, lessThan(restingLeft));
    expect(
      tester.getTopLeft(find.byKey(secondKey)).dx,
      greaterThan(restingLeft),
    );
  });
}

final Finder _panelFinder = find.byKey(
  const ValueKey('poster_browse_landscape_gesture_panel'),
);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required int focusedIndex,
  required void Function(int index) onItemTap,
  Widget collapsedContent = const Text('影片详情'),
  int itemCount = 3,
}) async {
  await tester.binding.setSurfaceSize(const Size(853, 384));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _testApp(
      PosterBrowseLandscapeGesturePanel(
        items: _items(itemCount),
        focusedIndex: focusedIndex,
        showProgress: false,
        imageOf: (_) => MediaImageRequest.empty,
        secondaryLabelOf: (_) => '第 1 季',
        onItemTap: onItemTap,
        collapsedContent: collapsedContent,
      ),
    ),
  );
}

double _trackOpacity(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.byKey(const ValueKey('poster_browse_landscape_track_opacity')),
      )
      .opacity;
}

double _handleOpacity(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.byKey(const ValueKey('poster_browse_landscape_expand_handle')),
      )
      .opacity;
}

double _infoOpacity(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.byKey(const ValueKey('poster_browse_landscape_info_opacity')),
      )
      .opacity;
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 853, height: 264, child: child),
      ),
    ),
  );
}

List<PosterBrowseDisplayItem> _items([int count = 3]) {
  return List<PosterBrowseDisplayItem>.generate(count, (index) {
    final card = MediaItemCard(
      id: 'item-$index',
      title: '影片 $index',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    return PosterBrowseDisplayItem(
      card: card,
      title: card.title,
      episodeTitle: '',
      type: card.type,
      seriesId: '',
      ratingText: '',
      releaseYear: '2026',
      overview: '',
      detailTargetId: card.id,
      seasonNumber: 1,
      episodeNumber: 1,
      numberOfSeasons: 1,
      numberOfEpisodes: 1,
      durationSeconds: 0,
      genres: const <String>[],
      resolutions: const <String>[],
      backgroundImages: const <MediaImageRef>[],
      logoImages: const <MediaImageRef>[],
      posterImages: const <MediaImageRef>[],
    );
  });
}
