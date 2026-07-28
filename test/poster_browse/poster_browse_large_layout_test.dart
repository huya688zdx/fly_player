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
              kind: PosterBrowseRowKind.latest,
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
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    );

    expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
    expect(find.byType(PosterBrowsePosterTrack), findsOneWidget);
    expect(find.text('银翼杀手'), findsWidgets);
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('最近添加'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('poster_browse_mobile_carousel')),
      findsNothing,
    );
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
