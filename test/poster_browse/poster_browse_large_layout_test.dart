import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_large_layout.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_landscape_gesture_panel.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_media_info.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_track.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';

void main() {
  late HttpOverrides? previousHttpOverrides;

  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _FakeImageHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  testWidgets('大屏布局显示共享信息区海报轨标题回退和两个分组', (tester) async {
    final continueCard = _card(
      id: 'continue-1',
      title: '银翼杀手',
      resumePositionSeconds: 30,
      durationSeconds: 120,
    );
    final latestCard = _card(id: 'latest-1', title: '降临');
    final focused = _displayItem(continueCard, overview: '复制人与城市。');

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: [continueCard],
            ),
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '动漫 TV',
              items: [latestCard],
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: focused,
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '1982 · 科幻',
          metaWidgets: const <Widget>[Text('4K')],
          imageOf: _loadableImageOf,
          secondaryLabelOf: (item) => item.releaseYear,
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(find.byType(PosterBrowsePosterTrack), findsOneWidget);
    expect(find.text('动漫 TV'), findsOneWidget);
    expect(find.text('银翼杀手'), findsWidgets);
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('最近添加'), findsNothing);
    expect(
      find.byKey(const ValueKey('poster_browse_mobile_carousel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('矮视口大字号下两行标题卡片不溢出（横屏露底回归）', (tester) async {
    final card = _card(id: 'overflow-1', title: '辉夜大小姐想让我告白第二季');
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: PosterBrowseLargeLayout(
            rows: [
              PosterBrowseRow(
                kind: PosterBrowseRowKind.continueWatching,
                items: [card],
              ),
            ],
            displayItemOf: (card) => _displayItem(card),
            selectedRow: 0,
            focusedIndex: 0,
            focusedItem: _displayItem(card),
            logoRequest: MediaImageRequest.empty,
            secondaryLabel: '2026',
            metaWidgets: const <Widget>[],
            imageOf: _loadableImageOf,
            secondaryLabelOf: (item) => '第 1 季 第 3 集',
            onSelectRow: (_) {},
            onSelectItem: (_) {},
            onRetryCurrentRow: () {},
            onPlay: () {},
            onDetail: () {},
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('海报轨使用竖版卡片显示条目焦点进度并回调点击下标', (tester) async {
    var tappedIndex = -1;
    final first = _displayItem(
      _card(
        id: 'track-1',
        title: '沙丘',
        resumePositionSeconds: 50,
        durationSeconds: 100,
      ),
      releaseYear: '2021',
    );
    final second = _displayItem(
      _card(id: 'track-2', title: '沙丘2'),
      releaseYear: '2024',
    );

    await tester.pumpWidget(
      _localizedApp(
        SizedBox(
          width: 640,
          height: 260,
          child: PosterBrowsePosterTrack(
            items: [first, second],
            focusedIndex: 1,
            showProgress: true,
            imageOf: _loadableImageOf,
            secondaryLabelOf: (item) => '年份 ${item.releaseYear}',
            onItemTap: (index) => tappedIndex = index,
          ),
        ),
      ),
    );

    expect(find.byType(PosterBrowsePosterCard), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('poster_browse_track_item_track-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('poster_browse_track_item_track-2')),
      findsOneWidget,
    );
    expect(find.text('年份 2024'), findsOneWidget);

    final cards = tester
        .widgetList<PosterBrowsePosterCard>(find.byType(PosterBrowsePosterCard))
        .toList();
    expect(cards[0].focused, isFalse);
    expect(cards[1].focused, isTrue);
    expect(cards[0].showProgress, isTrue);
    expect(cards[0].width, 116);
    expect(cards[0].imageUrl, 'https://images.example.test/track-1.jpg');
    expect(cards[0].imageHeaders, const <String, String>{'X-Test': 'track-1'});
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('poster_browse_track_item_track-2')),
    );
    expect(tappedIndex, 1);
  });

  testWidgets('大屏布局响应最近添加分组返回播放详情', (tester) async {
    var selectedRow = -1;
    var playTapped = false;
    var detailTapped = false;
    var backTapped = false;
    final continueCard = _card(id: 'continue-1', title: '继续影片');
    final latestCard = _card(id: 'latest-1', title: '最近影片');

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: [continueCard],
            ),
            PosterBrowseRow(
              kind: PosterBrowseRowKind.latest,
              items: [latestCard],
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(continueCard),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '',
          metaWidgets: const <Widget>[],
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSelectRow: (index) => selectedRow = index,
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () => playTapped = true,
          onDetail: () => detailTapped = true,
          onBack: () => backTapped = true,
        ),
      ),
    );

    await tester.tap(find.text('最近添加'));
    await tester.tap(find.text('播放'));
    await tester.tap(find.text('详情'));
    await tester.tap(find.byIcon(Icons.arrow_back));

    expect(selectedRow, 1);
    expect(playTapped, isTrue);
    expect(detailTapped, isTrue);
    expect(backTapped, isTrue);
  });

  testWidgets('空海报轨安全收缩', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        PosterBrowsePosterTrack(
          items: const <PosterBrowseDisplayItem>[],
          focusedIndex: 0,
          showProgress: false,
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onItemTap: (_) {},
        ),
      ),
    );

    expect(find.byType(PosterBrowsePosterCard), findsNothing);
    final box = tester.renderObject<RenderBox>(
      find.byType(PosterBrowsePosterTrack),
    );
    expect(box.size, Size.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大屏分类选择器展示全部分类并横向滚动选择第四项', (tester) async {
    var selectedRow = -1;
    final focusedCard = _card(id: 'catalog-1', title: '电影');

    await tester.binding.setSurfaceSize(const Size(520, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '电影精选分类',
              items: [focusedCard],
            ),
            const PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '热门电视剧',
              items: <MediaItemCard>[],
            ),
            const PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '纪录片天地',
              items: <MediaItemCard>[],
            ),
            const PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '动漫 TV',
              items: <MediaItemCard>[],
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(focusedCard),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '',
          metaWidgets: const <Widget>[],
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSelectRow: (index) => selectedRow = index,
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    final scrollFinder = find.byKey(
      const ValueKey('poster_browse_row_selector_scroll'),
    );
    expect(find.text('动漫 TV'), findsOneWidget);
    expect(scrollFinder, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(scrollFinder).scrollDirection,
      Axis.horizontal,
    );
    final firstButton = find.ancestor(
      of: find.text('电影精选分类'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(firstButton).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('电影精选分类'))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );

    await tester.drag(scrollFinder, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('动漫 TV'));
    expect(selectedRow, 3);
  });

  testWidgets('大屏海报轨区域按当前分类显示加载失败和空库状态', (tester) async {
    final focusedCard = _card(id: 'fallback', title: '背景影片');
    var retryCount = 0;

    Widget buildLayout(PosterBrowseRowLoadState loadState) {
      return _localizedApp(
        PosterBrowseLargeLayout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '电影',
              items: const <MediaItemCard>[],
              loadState: loadState,
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(focusedCard),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '',
          metaWidgets: const <Widget>[],
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () => retryCount += 1,
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      );
    }

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.loading));
    expect(
      find.byKey(const ValueKey('poster_browse_row_loading')),
      findsOneWidget,
    );
    expect(find.byType(PosterBrowsePosterTrack), findsNothing);

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.failed));
    expect(find.text('加载失败，点按重试'), findsOneWidget);
    expect(find.byType(PosterBrowsePosterTrack), findsNothing);
    await tester.tap(find.text('加载失败，点按重试'));
    expect(retryCount, 1);

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.loaded));
    expect(find.text('此媒体库暂无内容'), findsOneWidget);
    expect(find.byType(PosterBrowsePosterTrack), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大屏当前分类无焦点项时隐藏信息区并保留分类选择器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: const [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '电影',
              items: <MediaItemCard>[],
            ),
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '动漫 TV',
              items: <MediaItemCard>[],
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: null,
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '',
          metaWidgets: const <Widget>[],
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsNothing);
    expect(find.text('动漫 TV'), findsOneWidget);
    expect(find.text('播放'), findsNothing);
    expect(find.text('详情'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('大屏目录索引失败行显示媒体库标签与重试按钮', (tester) async {
    var retryCount = 0;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: const <PosterBrowseRow>[
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[],
            ),
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalogIndex,
              items: <MediaItemCard>[],
              loadState: PosterBrowseRowLoadState.failed,
            ),
          ],
          displayItemOf: (card) => _displayItem(card),
          selectedRow: 1,
          focusedIndex: 0,
          focusedItem: null,
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '',
          metaWidgets: const <Widget>[],
          imageOf: (_) => MediaImageRequest.empty,
          secondaryLabelOf: (_) => '',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () => retryCount += 1,
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('加载失败，点按重试'), findsOneWidget);
    await tester.tap(find.text('加载失败，点按重试'));
    expect(retryCount, 1);
  });
  testWidgets('大屏海报轨在 853×384 真机横屏下不溢出并保留卡片文案', (tester) async {
    final card = _card(
      id: 'long-title',
      title: '吹响吧！上低音号特别篇',
      resumePositionSeconds: 30,
      durationSeconds: 120,
    );

    await tester.binding.setSurfaceSize(const Size(853, 384));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(853, 384),
            textScaler: TextScaler.linear(1.08),
          ),
          child: PosterBrowseLargeLayout(
            rows: <PosterBrowseRow>[
              PosterBrowseRow(
                kind: PosterBrowseRowKind.continueWatching,
                items: <MediaItemCard>[card],
              ),
            ],
            displayItemOf: _displayItem,
            selectedRow: 0,
            focusedIndex: 0,
            focusedItem: _displayItem(card),
            logoRequest: MediaImageRequest.empty,
            secondaryLabel: '第 1 季 第 1 集',
            metaWidgets: const <Widget>[],
            imageOf: _loadableImageOf,
            secondaryLabelOf: (_) => '第 1 季 第 1 集',
            onSelectRow: (_) {},
            onSelectItem: (_) {},
            onRetryCurrentRow: () {},
            onPlay: () {},
            onDetail: () {},
            onBack: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PosterBrowsePosterTrack)).height, 264);
    expect(find.byType(PosterBrowseLandscapeGesturePanel), findsOneWidget);
    expect(find.byType(PosterBrowseMediaInfo), findsNothing);

    final cardFinder = find.byType(PosterBrowsePosterCard);
    final title = tester.widget<Text>(
      find.descendant(of: cardFinder, matching: find.text(card.title)),
    );
    final subtitle = tester.widget<Text>(
      find.descendant(of: cardFinder, matching: find.text('第 1 季 第 1 集')),
    );
    expect(title.maxLines, 2);
    expect(subtitle.maxLines, 1);

    await tester.timedDrag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大屏海报轨在 701×331 超矮横屏下自适应高度且不溢出', (tester) async {
    final card = _card(
      id: 'ultra-short-landscape',
      title: '辉夜大小姐想让我告白',
      resumePositionSeconds: 30,
      durationSeconds: 120,
    );

    await tester.binding.setSurfaceSize(const Size(701, 331));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        MediaQuery(
          data: const MediaQueryData(size: Size(701, 331)),
          child: PosterBrowseLargeLayout(
            rows: <PosterBrowseRow>[
              PosterBrowseRow(
                kind: PosterBrowseRowKind.continueWatching,
                items: <MediaItemCard>[card],
              ),
            ],
            displayItemOf: _displayItem,
            selectedRow: 0,
            focusedIndex: 0,
            focusedItem: _displayItem(card),
            logoRequest: MediaImageRequest.empty,
            secondaryLabel: '第 1 季 第 1 集',
            metaWidgets: const <Widget>[],
            imageOf: _loadableImageOf,
            secondaryLabelOf: (_) => '第 1 季 第 1 集',
            onSelectRow: (_) {},
            onSelectItem: (_) {},
            onRetryCurrentRow: () {},
            onPlay: () {},
            onDetail: () {},
            onBack: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PosterBrowsePosterTrack)).height,
      lessThan(264),
    );
    expect(
      tester
          .widget<PosterBrowsePosterCard>(find.byType(PosterBrowsePosterCard))
          .width,
      lessThan(116),
    );

    await tester.timedDrag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, 80),
      const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('高分辨率横屏收起后只保留一份媒体信息并隐藏分类栏', (tester) async {
    final card = _card(id: 'collapse-info', title: '辉夜大小姐');

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: <PosterBrowseRow>[
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[card],
            ),
          ],
          displayItemOf: _displayItem,
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(card, overview: '用于验证收起态信息不会重复。'),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '第 1 季 第 1 集',
          metaWidgets: const <Widget>[Text('1080p')],
          imageOf: _loadableImageOf,
          secondaryLabelOf: (_) => '第 1 季 第 1 集',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(find.text('继续观看'), findsOneWidget);

    await tester.timedDrag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(find.text('继续观看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('高分辨率横屏上下拖动时信息和分类栏跟随手指位移淡出', (tester) async {
    final card = _card(id: 'vertical-motion', title: '上下联动影片');

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: <PosterBrowseRow>[
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[card],
            ),
          ],
          displayItemOf: _displayItem,
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(card, overview: '验证上下拖动跟手动画。'),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '第 1 集',
          metaWidgets: const <Widget>[],
          imageOf: _loadableImageOf,
          secondaryLabelOf: (_) => '',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    final initialInfoTop = tester
        .getTopLeft(find.byType(PosterBrowseMediaInfo))
        .dy;
    final initialSelectorTop = tester.getTopLeft(find.text('继续观看')).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      ),
    );
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();

    final infoOpacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('poster_browse_primary_collapse_opacity')),
    );
    final selectorOpacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('poster_browse_row_selector_collapse_opacity')),
    );
    expect(infoOpacity.opacity, inExclusiveRange(0, 1));
    expect(selectorOpacity.opacity, inExclusiveRange(0, 1));
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('poster_browse_primary_info_vertical-motion'),
            ),
          )
          .dy,
      greaterThan(initialInfoTop),
    );
    expect(
      tester.getTopLeft(find.text('继续观看')).dy,
      greaterThan(initialSelectorTop),
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('大屏主内容区左右滑动也能切换影视', (tester) async {
    final first = _card(id: 'wide-swipe-1', title: '影片一');
    final second = _card(id: 'wide-swipe-2', title: '影片二');
    var selectedIndex = -1;

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseLargeLayout(
          rows: <PosterBrowseRow>[
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[first, second],
            ),
          ],
          displayItemOf: _displayItem,
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(first, overview: '从主内容区横滑切换。'),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '第 1 集',
          metaWidgets: const <Widget>[],
          imageOf: _loadableImageOf,
          secondaryLabelOf: (_) => '',
          onSelectRow: (_) {},
          onSelectItem: (index) => selectedIndex = index,
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    await tester.timedDragFrom(
      const Offset(1000, 300),
      const Offset(-120, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);
  });

  testWidgets('大屏横滑切换时媒体信息按滑动方向位移过渡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(const _InteractiveLargeLayoutHarness()),
    );

    const firstKey = ValueKey('poster_browse_primary_info_animated-1');
    const secondKey = ValueKey('poster_browse_primary_info_animated-2');
    final restingLeft = tester.getTopLeft(find.byKey(firstKey)).dx;

    await tester.timedDragFrom(
      const Offset(1000, 300),
      const Offset(-120, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(firstKey), findsOneWidget);
    expect(find.byKey(secondKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(firstKey)).dx, lessThan(restingLeft));
    expect(
      tester.getTopLeft(find.byKey(secondKey)).dx,
      greaterThan(restingLeft),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(firstKey), findsNothing);
    expect(find.byKey(secondKey), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(1000, 300),
      const Offset(120, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      tester.getTopLeft(find.byKey(secondKey)).dx,
      greaterThan(restingLeft),
    );
    expect(tester.getTopLeft(find.byKey(firstKey)).dx, lessThan(restingLeft));
  });

  testWidgets('大屏收起后从屏幕顶部空白区域横滑也能切换影视', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(const _InteractiveLargeLayoutHarness()),
    );

    await tester.timedDrag(
      find.byKey(const ValueKey('poster_browse_landscape_gesture_panel')),
      const Offset(0, 180),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('动画影片一'), findsWidgets);
    final fullSwipeSurface = find.byKey(
      const ValueKey('poster_browse_full_horizontal_swipe_surface'),
    );
    expect(fullSwipeSurface, findsOneWidget);
    expect(tester.getSize(fullSwipeSurface), const Size(1920, 1080));

    await tester.timedDragFrom(
      const Offset(1000, 30),
      const Offset(-120, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(find.text('动画影片二'), findsWidgets);
  });
}

class _InteractiveLargeLayoutHarness extends StatefulWidget {
  const _InteractiveLargeLayoutHarness();

  @override
  State<_InteractiveLargeLayoutHarness> createState() =>
      _InteractiveLargeLayoutHarnessState();
}

class _InteractiveLargeLayoutHarnessState
    extends State<_InteractiveLargeLayoutHarness> {
  late final List<MediaItemCard> _cards = <MediaItemCard>[
    _card(id: 'animated-1', title: '动画影片一'),
    _card(id: 'animated-2', title: '动画影片二'),
  ];
  int _focusedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final focused = _displayItem(
      _cards[_focusedIndex],
      overview: '验证媒体信息的横向位移动画。',
    );
    return PosterBrowseLargeLayout(
      rows: <PosterBrowseRow>[
        PosterBrowseRow(
          kind: PosterBrowseRowKind.continueWatching,
          items: _cards,
        ),
      ],
      displayItemOf: _displayItem,
      selectedRow: 0,
      focusedIndex: _focusedIndex,
      focusedItem: focused,
      logoRequest: MediaImageRequest.empty,
      secondaryLabel: '第 ${_focusedIndex + 1} 集',
      metaWidgets: const <Widget>[],
      imageOf: _loadableImageOf,
      secondaryLabelOf: (_) => '',
      onSelectRow: (_) {},
      onSelectItem: (index) => setState(() => _focusedIndex = index),
      onRetryCurrentRow: () {},
      onPlay: () {},
      onDetail: () {},
      onBack: () {},
    );
  }
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

MediaItemCard _card({
  required String id,
  required String title,
  int durationSeconds = 0,
  int resumePositionSeconds = 0,
}) {
  return MediaItemCard(
    id: id,
    title: title,
    type: 'Movie',
    primaryImage: MediaImageRef.empty,
    durationSeconds: durationSeconds,
    resumePositionSeconds: resumePositionSeconds,
  );
}

PosterBrowseDisplayItem _displayItem(
  MediaItemCard card, {
  String overview = '',
  String releaseYear = '2024',
}) {
  return PosterBrowseDisplayItem(
    card: card,
    title: card.title,
    episodeTitle: '',
    type: card.type,
    seriesId: card.seriesId,
    ratingText: card.rating,
    releaseYear: releaseYear,
    overview: overview,
    detailTargetId: card.id,
    seasonNumber: card.seasonNumber,
    episodeNumber: card.episodeNumber,
    numberOfSeasons: card.numberOfSeasons,
    numberOfEpisodes: card.numberOfEpisodes,
    durationSeconds: card.durationSeconds,
    genres: card.genres,
    resolutions: card.resolutions,
    backgroundImages: const <MediaImageRef>[],
    logoImages: const <MediaImageRef>[],
    posterImages: const <MediaImageRef>[],
  );
}

MediaImageRequest _loadableImageOf(PosterBrowseDisplayItem item) {
  return MediaImageRequest(
    urls: ['https://images.example.test/${item.card.id}.jpg'],
    headers: <String, String>{'X-Test': item.card.id},
  );
}

class _FakeImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeImageHttpClient();
}

class _FakeImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeImageHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeImageHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_transparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final Uint8List _transparentPng = Uint8List.fromList(const <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
