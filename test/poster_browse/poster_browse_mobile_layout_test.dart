import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_arc_carousel.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_media_info.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_mobile_layout.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_track.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';

void main() {
  testWidgets('手机布局显示信息区弧形轮盘两个分组且没有中心大海报', (tester) async {
    final cards = [
      _card(id: 'continue-1', title: '银翼杀手'),
      _card(id: 'continue-2', title: '降临'),
      _card(id: 'continue-3', title: '沙丘'),
    ];
    final latestCard = _card(id: 'latest-1', title: '瞬息全宇宙');

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: cards,
            ),
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '动漫 TV',
              items: [latestCard],
            ),
          ],
          focusedItem: _displayItem(cards.first, overview: '复制人与城市。'),
          metaWidgets: const <Widget>[Text('4K')],
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(find.byType(PosterBrowseArcCarousel), findsOneWidget);
    expect(find.text('动漫 TV'), findsOneWidget);
    expect(find.text('银翼杀手'), findsWidgets);
    expect(find.text('复制人与城市。'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('最近添加'), findsNothing);
    expect(find.byType(PosterBrowsePosterTrack), findsNothing);
    expect(find.byType(PosterBrowsePosterCard), findsNWidgets(cards.length));
    expect(find.text('降临'), findsOneWidget);
    expect(find.text('沙丘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组控件位于轮盘上方并可选择最近添加', (tester) async {
    var selectedRow = -1;
    final continueCard = _card(id: 'continue-1', title: '继续影片');
    final latestCard = _card(id: 'latest-1', title: '最近影片');

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
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
          focusedItem: _displayItem(continueCard),
          onSelectRow: (index) => selectedRow = index,
        ),
      ),
    );

    final switchTop = tester.getTopLeft(find.text('继续观看')).dy;
    final carouselTop = tester
        .getTopLeft(find.byType(PosterBrowseArcCarousel))
        .dy;
    expect(switchTop, lessThan(carouselTop));

    await tester.tap(find.text('最近添加'));
    expect(selectedRow, 1);
  });

  testWidgets('轮盘停靠中心点击播放详情返回均透传回调', (tester) async {
    int? settledIndex;
    int? centeredIndex;
    var playTapped = false;
    var detailTapped = false;
    var backTapped = false;
    final cards = [
      _card(id: 'continue-1', title: '第一部'),
      _card(id: 'continue-2', title: '第二部'),
      _card(id: 'continue-3', title: '第三部'),
    ];

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: cards,
            ),
          ],
          focusedItem: _displayItem(cards.first),
          onSelectItem: (index) => settledIndex = index,
          onCenteredTap: (index) => centeredIndex = index,
          onPlay: () => playTapped = true,
          onDetail: () => detailTapped = true,
          onBack: () => backTapped = true,
        ),
      ),
    );

    await tester.drag(
      find.byType(PosterBrowseArcCarousel),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(settledIndex, isNotNull);

    await tester.tap(find.byType(PosterBrowsePosterCard).last);
    expect(centeredIndex, isNotNull);

    await tester.tap(find.text('播放'));
    await tester.tap(find.text('详情'));
    await tester.tap(find.byIcon(Icons.arrow_back));

    expect(playTapped, isTrue);
    expect(detailTapped, isTrue);
    expect(backTapped, isTrue);
  });

  testWidgets('单组隐藏分组控件且空当前组安全收缩', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            const PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[],
            ),
          ],
          focusedItem: _displayItem(_card(id: 'fallback', title: '占位标题')),
        ),
      ),
    );

    expect(find.text('继续观看'), findsNothing);
    expect(find.text('最近添加'), findsNothing);
    expect(find.byType(PosterBrowsePosterCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机竖屏不溢出且横屏尺寸组件可构建', (tester) async {
    final cards = [
      _card(id: 'continue-1', title: '第一部'),
      _card(id: 'continue-2', title: '第二部'),
      _card(id: 'continue-3', title: '第三部'),
    ];

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: cards,
            ),
          ],
          focusedItem: _displayItem(
            cards.first,
            overview: '一段足够长但应该被紧凑信息区裁剪的简介文本。',
          ),
          metaWidgets: const <Widget>[Text('4K'), Text('HDR'), Text('杜比视界')],
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: cards,
            ),
          ],
          focusedItem: _displayItem(cards.first),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机横屏信息按钮不会被轮盘手势层遮挡', (tester) async {
    var playTapped = false;
    var detailTapped = false;
    final cards = [
      _card(id: 'continue-1', title: '第一部'),
      _card(id: 'continue-2', title: '第二部'),
      _card(id: 'continue-3', title: '第三部'),
    ];

    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: cards,
            ),
          ],
          focusedItem: _displayItem(cards.first, overview: '横屏下仍需显示的简介。'),
          metaWidgets: const <Widget>[Text('4K'), Text('HDR')],
          onPlay: () => playTapped = true,
          onDetail: () => detailTapped = true,
        ),
      ),
    );

    await tester.tap(find.text('播放'));
    await tester.tap(find.text('详情'));

    expect(playTapped, isTrue);
    expect(detailTapped, isTrue);
  });

  testWidgets('手机分类选择器展示全部分类并横向滚动选择第四项', (tester) async {
    var selectedRow = -1;
    final focusedCard = _card(id: 'catalog-1', title: '电影');

    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
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
          focusedItem: _displayItem(focusedCard),
          onSelectRow: (index) => selectedRow = index,
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

    await tester.drag(scrollFinder, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('动漫 TV'));
    expect(selectedRow, 3);
  });

  testWidgets('手机轮播区域按当前分类显示加载失败和空库状态', (tester) async {
    final focusedCard = _card(id: 'fallback', title: '背景影片');

    Widget buildLayout(PosterBrowseRowLoadState loadState) {
      return _localizedApp(
        _layout(
          rows: [
            PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '电影',
              items: const <MediaItemCard>[],
              loadState: loadState,
            ),
            const PosterBrowseRow(
              kind: PosterBrowseRowKind.catalog,
              title: '动漫 TV',
              items: <MediaItemCard>[],
            ),
          ],
          focusedItem: _displayItem(focusedCard),
        ),
      );
    }

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.loading));
    expect(
      find.byKey(const ValueKey('poster_browse_row_loading')),
      findsOneWidget,
    );
    expect(find.byType(PosterBrowseArcCarousel), findsNothing);

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.failed));
    expect(find.text('加载失败，点按重试'), findsOneWidget);
    expect(find.byType(PosterBrowseArcCarousel), findsNothing);

    await tester.pumpWidget(buildLayout(PosterBrowseRowLoadState.loaded));
    expect(find.text('此媒体库暂无内容'), findsOneWidget);
    expect(find.byType(PosterBrowseArcCarousel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机当前分类无焦点项时隐藏信息区并保留分类选择器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        _layout(
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
          focusedItem: null,
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsNothing);
    expect(find.text('动漫 TV'), findsOneWidget);
    expect(find.text('播放'), findsNothing);
    expect(find.text('详情'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

PosterBrowseMobileLayout _layout({
  required List<PosterBrowseRow> rows,
  required PosterBrowseDisplayItem? focusedItem,
  int selectedRow = 0,
  int focusedIndex = 0,
  List<Widget> metaWidgets = const <Widget>[],
  void Function(int index)? onSelectRow,
  void Function(int index)? onSelectItem,
  void Function(int index)? onCenteredTap,
  VoidCallback? onPlay,
  VoidCallback? onDetail,
  VoidCallback? onBack,
}) {
  return PosterBrowseMobileLayout(
    rows: rows,
    displayItemOf: (card) => _displayItem(card),
    selectedRow: selectedRow,
    focusedIndex: focusedIndex,
    focusedItem: focusedItem,
    logoRequest: MediaImageRequest.empty,
    secondaryLabel: '2024 · 科幻',
    metaWidgets: metaWidgets,
    imageOf: (_) => MediaImageRequest.empty,
    secondaryLabelOf: (item) => item.releaseYear,
    onSelectRow: onSelectRow ?? (_) {},
    onSelectItem: onSelectItem ?? (_) {},
    onCenteredTap: onCenteredTap ?? (_) {},
    onPlay: onPlay ?? () {},
    onDetail: onDetail ?? () {},
    onBack: onBack ?? () {},
  );
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
  int durationSeconds = 120,
  int resumePositionSeconds = 30,
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
    genres: const <String>[],
    resolutions: const <String>[],
    backgroundImages: const <MediaImageRef>[],
    logoImages: const <MediaImageRef>[],
    posterImages: const <MediaImageRef>[],
  );
}
