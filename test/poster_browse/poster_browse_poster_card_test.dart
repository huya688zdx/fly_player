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
import 'package:fly_player/screens/poster_browse/poster_browse_media_info.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_poster_card.dart';

void main() {
  late HttpOverrides? previousHttpOverrides;

  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _FakeImageHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  testWidgets('海报卡显示文本评分进度且文本不在图片 Stack 内并响应点击', (tester) async {
    var tapped = false;
    final item = _item(
      title: '沙丘',
      ratingText: '9.1',
      durationSeconds: 120,
      resumePositionSeconds: 60,
    );

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowsePosterCard(
          item: item,
          focused: true,
          showProgress: true,
          imageUrl: 'https://images.example.test/poster.jpg',
          imageHeaders: const <String, String>{'Authorization': 'Bearer token'},
          secondaryLabel: '2024 · 科幻',
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('沙丘'), findsOneWidget);
    expect(find.text('2024 · 科幻'), findsOneWidget);
    expect(find.text('★ 9.1'), findsOneWidget);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.5);

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<NetworkImage>());
    final networkImage = provider as NetworkImage;
    expect(networkImage.url, 'https://images.example.test/poster.jpg');
    expect(networkImage.headers, const <String, String>{
      'Authorization': 'Bearer token',
    });

    expect(_hasStackAncestor(tester, find.text('沙丘')), isFalse);
    expect(_hasStackAncestor(tester, find.text('2024 · 科幻')), isFalse);

    await tester.tap(find.byType(PosterBrowsePosterCard));
    expect(tapped, isTrue);
  });

  testWidgets('海报卡隐藏空评分和无效进度并将超长进度截断为 1', (tester) async {
    final invalidItem = _item(
      title: '无进度',
      ratingText: '',
      durationSeconds: 0,
      resumePositionSeconds: 50,
    );

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowsePosterCard(
          item: invalidItem,
          focused: false,
          showProgress: true,
          imageUrl: '',
          imageHeaders: const <String, String>{},
          secondaryLabel: '',
          onTap: () {},
        ),
      ),
    );

    expect(find.textContaining('★'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final clampedItem = _item(
      title: '超长进度',
      ratingText: '',
      durationSeconds: 100,
      resumePositionSeconds: 150,
    );

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowsePosterCard(
          item: clampedItem,
          focused: false,
          showProgress: true,
          imageUrl: '',
          imageHeaders: const <String, String>{},
          secondaryLabel: '',
          onTap: () {},
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 1.0);
  });

  testWidgets('媒体信息区使用空 logo 回退标题并展示信息和按钮', (tester) async {
    var playTapped = false;
    var detailTapped = false;
    final item = _item(title: '星际穿越', overview: '一段跨越星际的旅程。');

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseMediaInfo(
          item: item,
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '2014 · 科幻',
          metaWidgets: const <Widget>[Text('4K'), Text('HDR')],
          compact: false,
          onPlay: () => playTapped = true,
          onDetail: () => detailTapped = true,
        ),
      ),
    );

    expect(find.text('星际穿越'), findsOneWidget);
    expect(find.text('2014 · 科幻'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HDR'), findsOneWidget);

    final overview = tester.widget<Text>(find.text('一段跨越星际的旅程。'));
    expect(overview.maxLines, 2);

    await tester.tap(find.text('播放'));
    await tester.tap(find.text('详情'));
    expect(playTapped, isTrue);
    expect(detailTapped, isTrue);

    await tester.pumpWidget(
      _localizedApp(
        PosterBrowseMediaInfo(
          item: item,
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '2014 · 科幻',
          metaWidgets: const <Widget>[Text('4K')],
          compact: true,
          onPlay: () {},
          onDetail: () {},
        ),
      ),
    );

    final compactOverview = tester.widget<Text>(find.text('一段跨越星际的旅程。'));
    expect(compactOverview.maxLines, 1);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
  });

  testWidgets('标题和 Logo 共用固定槽位，不改变后续信息的纵向位置', (tester) async {
    final item = _item(title: '短标题', overview: '简介');

    Future<double> secondaryTop(MediaImageRequest logoRequest) async {
      await tester.pumpWidget(
        _localizedApp(
          SizedBox(
            width: 520,
            child: PosterBrowseMediaInfo(
              item: item,
              logoRequest: logoRequest,
              secondaryLabel: '2026 · 动画',
              metaWidgets: const <Widget>[Text('1080p')],
              compact: false,
              onPlay: () {},
              onDetail: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .getTopLeft(
            find.byKey(const ValueKey('poster_browse_secondary_label')),
          )
          .dy;
    }

    final withoutLogo = await secondaryTop(MediaImageRequest.empty);
    final withLogo = await secondaryTop(
      const MediaImageRequest(
        urls: <String>['https://images.example.test/logo.png'],
        selfAuthenticated: true,
      ),
    );

    expect(withLogo, withoutLogo);
  });
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

PosterBrowseDisplayItem _item({
  String title = '标题',
  String ratingText = '',
  String overview = '',
  int durationSeconds = 0,
  int resumePositionSeconds = 0,
}) {
  return PosterBrowseDisplayItem(
    card: MediaItemCard(
      id: 'item-1',
      title: title,
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
      durationSeconds: durationSeconds,
      resumePositionSeconds: resumePositionSeconds,
    ),
    title: title,
    episodeTitle: '',
    type: 'Movie',
    seriesId: '',
    ratingText: ratingText,
    releaseYear: '',
    overview: overview,
    detailTargetId: 'item-1',
    seasonNumber: 0,
    episodeNumber: 0,
    numberOfSeasons: 0,
    numberOfEpisodes: 0,
    durationSeconds: durationSeconds,
    genres: const <String>[],
    resolutions: const <String>[],
    backgroundImages: const <MediaImageRef>[],
    logoImages: const <MediaImageRef>[],
    posterImages: const <MediaImageRef>[],
  );
}

bool _hasStackAncestor(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  var hasStack = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Stack) {
      hasStack = true;
      return false;
    }
    return true;
  });
  return hasStack;
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
  static final Uint8List _transparentPixel = Uint8List.fromList(<int>[
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

  @override
  int get contentLength => _transparentPixel.length;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      _transparentPixel,
    ]).listen(
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
