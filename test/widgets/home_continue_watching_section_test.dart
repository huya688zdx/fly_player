import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_continue_watching_section.dart';
import 'package:fly_player/theme/app_theme.dart';

const continueFixture = HomeContinueCardData(
  id: 'item-1',
  title: '吹响吧！上低音号',
  contextText: '第 1 季 · 第 9 集 · 剩 18 分钟',
  progress: .5,
  imageRequest: MediaImageRequest.empty,
  downloaded: false,
);

Widget testApp(
  Widget child, {
  AppThemeColors? runtimeColors,
  double width = 390,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: AppRuntimeColorScope(
    colors: runtimeColors,
    hasRuntimeColors: runtimeColors != null,
    child: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: textScaler),
      child: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Widget responsiveTestApp({
  required double width,
  required double devicePixelRatio,
  required Widget child,
}) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      devicePixelRatio: devicePixelRatio,
    ),
    child: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  ),
);

String networkUrlOf(Image image) {
  final provider = image.image;
  final network = provider is ResizeImage
      ? provider.imageProvider as NetworkImage
      : provider as NetworkImage;
  return network.url;
}

Finder downloadedBadgeFinder() => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == '已下载',
);

void expectRectInside(Rect inner, Rect outer) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

class _PendingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> withPendingHttp(Future<void> Function() body) =>
    _withPendingNetworkImageClient(body);

Future<void> _withPendingNetworkImageClient(
  Future<void> Function() body,
) async {
  final previousProvider = debugNetworkImageHttpClientProvider;
  debugNetworkImageHttpClientProvider = _PendingHttpClient.new;
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = previousProvider;
  }
}

void main() {
  testWidgets('续看卡主体、播放键、长按分别调用独立回调', (tester) async {
    var detail = 0;
    var play = 0;
    var longPress = 0;
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[continueFixture],
          onOpenDetail: (_) => detail++,
          onPlay: (_) => play++,
          onLongPress: (_) => longPress++,
        ),
      ),
    );

    expect(find.text('查看全部'), findsNothing);
    expect(find.text('1 条'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('continue-card-item-1')),
    );
    expect(detail, 1);
    expect(play, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('continue-play-item-1')),
    );
    expect(play, 1);
    expect(detail, 1);

    await tester.longPress(
      find.byKey(const ValueKey<String>('continue-card-item-1')),
    );
    expect(longPress, 1);
    expect(detail, 1);
  });

  testWidgets('八张续看卡使用连续横向架并可停在首卡宽度内', (tester) async {
    final items = List<HomeContinueCardData>.generate(
      8,
      (index) => HomeContinueCardData(
        id: 'scroll-$index',
        title: '续看 $index',
        contextText: '第 1 季 · 第 ${index + 1} 集',
        progress: .2,
        imageRequest: MediaImageRequest.empty,
        downloaded: false,
      ),
    );

    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: items,
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.bySemanticsLabel(RegExp('第 .* 页')), findsNothing);
    expect(find.textContaining('8 条'), findsNothing);

    final cardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('continue-card-scroll-0')))
        .width;
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await tester.drag(find.byType(ListView), const Offset(-95, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(cardWidth));
  });

  testWidgets('续看使用动态强调色、对比前景和本地化下载文字', (tester) async {
    const imageFixture = HomeContinueCardData(
      id: 'image-item',
      title: '标题',
      contextText: '第 2 季 · 第 4 集',
      progress: .25,
      imageRequest: MediaImageRequest(
        urls: <String>['https://example.test/backdrop.jpg'],
        selfAuthenticated: true,
      ),
      downloaded: true,
    );
    const accent = Color(0xFFFFE14A);
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    final runtimeColors = baseColors.copyWith(accent: accent);

    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[imageFixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
        runtimeColors: runtimeColors,
      ),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('continue-image-image-item')),
    );
    expect(image.fit, BoxFit.cover);
    expect(
      tester.widget<Text>(find.text('标题')).style?.fontWeight,
      FontWeight.w500,
    );
    expect(
      tester.widget<Text>(find.text('第 2 季 · 第 4 集')).style?.fontWeight,
      FontWeight.w400,
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey<String>('continue-progress-image-item')),
    );
    expect(progress.color, accent);

    final playButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    expect(
      playButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      Color.lerp(Colors.white, accent, .12),
    );
    final visual = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('continue-play-visual-image-item')),
    );
    final decoration = visual.decoration as BoxDecoration;
    expect(decoration.color, isNot(accent));
    expect(decoration.color!.a, lessThan(1));
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('continue-play-visual-image-item')),
      ),
      const Size.square(36),
    );
    expect(find.text('已下载'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '已下载',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);
    final downloaded = tester.widget<Text>(find.text('已下载'));
    expect(downloaded.style?.color, Colors.white);
    expect(downloaded.style?.fontSize, 11);
    expect(downloaded.style?.fontWeight, FontWeight.w600);
    final targetSize = tester.getSize(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    expect(targetSize.width, greaterThanOrEqualTo(48));
    expect(targetSize.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);

    const darkAccent = Color(0xFF173A5E);
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[imageFixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
        runtimeColors: baseColors.copyWith(accent: darkAccent),
      ),
    );
    final darkPlayButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    expect(
      darkPlayButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      Color.lerp(Colors.white, darkAccent, .12),
    );
    final darkVisual = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('continue-play-visual-image-item')),
    );
    final darkDecoration = darkVisual.decoration as BoxDecoration;
    expect(darkDecoration.color, isNot(darkAccent));
    expect(darkDecoration.border, isNotNull);
  });

  testWidgets('常规卡宽的下载文字在图片右上且播放键在右下', (tester) async {
    const fixture = HomeContinueCardData(
      id: 'regular-download',
      title: '常规布局',
      contextText: '第 1 季 · 第 2 集',
      progress: .4,
      imageRequest: MediaImageRequest.empty,
      downloaded: true,
    );

    for (final width in <double>[176, 360]) {
      await tester.pumpWidget(
        testApp(
          HomeContinueWatchingSection(
            items: const <HomeContinueCardData>[fixture],
            onOpenDetail: (_) {},
            onPlay: (_) {},
            onLongPress: (_) {},
          ),
          width: width,
        ),
      );

      final card = tester.getRect(
        find.byKey(const ValueKey<String>('continue-card-regular-download')),
      );
      final artwork = tester.getRect(find.byType(ClipRRect));
      final badge = tester.getRect(downloadedBadgeFinder());
      final play = tester.getRect(
        find.byKey(const ValueKey<String>('continue-play-regular-download')),
      );

      expectRectInside(badge, card);
      expectRectInside(play, card);
      expect(badge.overlaps(play), isFalse);
      expect(badge.top - artwork.top, closeTo(9, .01));
      expect(artwork.right - badge.right, closeTo(9, .01));
      expect(artwork.right - play.right, closeTo(8, .01));
      expect(artwork.bottom - play.bottom, closeTo(4, .01));
      expect(find.text(fixture.contextText), findsOneWidget);
      expect(
        tester.getSize(find.byType(ListView)).height,
        closeTo(card.width / (16 / 10) + 44, .01),
      );
      expect(tester.takeException(), isNull, reason: '卡宽 $width');
    }
  });

  testWidgets('极窄卡宽保留季集并在其下独立显示下载文字', (tester) async {
    const fixture = HomeContinueCardData(
      id: 'compact-download',
      title: '极窄布局下仍然需要看到标题',
      contextText: '第 1 季 · 第 12 集',
      progress: .7,
      imageRequest: MediaImageRequest.empty,
      downloaded: true,
    );
    const cases = <({double width, double scale})>[
      (width: 160, scale: 3),
      (width: 120, scale: 2),
      (width: 120, scale: 3),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        testApp(
          HomeContinueWatchingSection(
            items: const <HomeContinueCardData>[fixture],
            onOpenDetail: (_) {},
            onPlay: (_) {},
            onLongPress: (_) {},
          ),
          width: testCase.width,
          textScaler: TextScaler.linear(testCase.scale),
        ),
      );

      final card = tester.getRect(
        find.byKey(const ValueKey<String>('continue-card-compact-download')),
      );
      final artwork = tester.getRect(find.byType(ClipRRect));
      final contextFinder = find.text(fixture.contextText);
      expect(contextFinder, findsOneWidget);
      final context = tester.getRect(contextFinder);
      final badge = tester.getRect(downloadedBadgeFinder());
      final play = tester.getRect(
        find.byKey(const ValueKey<String>('continue-play-compact-download')),
      );

      expectRectInside(badge, card);
      expectRectInside(play, card);
      expectRectInside(context, card);
      expect(badge.overlaps(play), isFalse);
      expect(context.top, greaterThanOrEqualTo(artwork.bottom));
      expect(badge.top - context.bottom, closeTo(3, .01));
      expect(
        tester.getSize(find.byType(ListView)).height,
        closeTo(card.width / (16 / 10) + 68 * testCase.scale, .01),
      );
      expect(
        tester.widget<Text>(find.text('已下载')).overflow,
        TextOverflow.ellipsis,
      );
      expect(tester.widget<Text>(find.text('已下载')).maxLines, 1);
      expect(
        tester.takeException(),
        isNull,
        reason: '卡宽 ${testCase.width}，文字 ${testCase.scale}x',
      );
    }
  });

  testWidgets('续看卡使用普通路由转场且不创建单端 Hero', (tester) async {
    const fixture = HomeContinueCardData(
      id: 'hero-item',
      title: 'Hero 标题',
      contextText: '第 1 季 · 第 2 集',
      progress: .3,
      imageRequest: MediaImageRequest(
        urls: <String>['https://example.test/hero.jpg'],
        selfAuthenticated: true,
      ),
      downloaded: false,
    );

    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[fixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    expect(find.byType(Hero), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('continue-image-hero-item')),
      findsOneWidget,
    );
  });

  testWidgets('窄屏二倍和三倍文字保持完整布局', (tester) async {
    for (final scale in <double>[2, 3]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SizedBox(
                width: 320,
                child: HomeContinueWatchingSection(
                  items: const <HomeContinueCardData>[continueFixture],
                  onOpenDetail: (_) {},
                  onPlay: (_) {},
                  onLongPress: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: '文字缩放 $scale 不应溢出');
    }
  });

  testWidgets('续看图片候选失败时每帧只前进一个并限制解码尺寸', (tester) async {
    const fixture = HomeContinueCardData(
      id: 'fallback',
      title: '候选图',
      contextText: '测试',
      progress: 0,
      imageRequest: MediaImageRequest(
        urls: <String>[
          'https://example.test/first.jpg',
          'https://example.test/second.jpg',
          'https://example.test/third.jpg',
        ],
        selfAuthenticated: true,
      ),
      downloaded: false,
    );
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[fixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('continue-image-fallback'),
    );
    var image = tester.widget<Image>(finder);
    expect(networkUrlOf(image), endsWith('/first.jpg'));
    final resized = image.image as ResizeImage;
    expect(resized.width, isNotNull);
    expect(resized.width, greaterThan(0));
    expect(resized.height, isNull);

    final context = tester.element(finder);
    image.errorBuilder!(context, StateError('首次失败'), StackTrace.empty);
    image.errorBuilder!(context, StateError('重复回调'), StackTrace.empty);
    await tester.pump();
    await tester.pump();

    image = tester.widget<Image>(finder);
    expect(networkUrlOf(image), endsWith('/second.jpg'));

    final secondContext = tester.element(finder);
    image.errorBuilder!(secondContext, StateError('第二候选失败'), StackTrace.empty);
    await tester.pump();
    await tester.pump();
    expect(networkUrlOf(tester.widget<Image>(finder)), endsWith('/third.jpg'));
  });

  testWidgets('续看图片请求变化会取消旧请求待执行的回退', (tester) async {
    await withPendingHttp(() async {
      Widget section(MediaImageRequest request) => testApp(
        HomeContinueWatchingSection(
          items: <HomeContinueCardData>[
            HomeContinueCardData(
              id: 'replace',
              title: '替换请求',
              contextText: '测试',
              progress: 0,
              imageRequest: request,
              downloaded: false,
            ),
          ],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
      );

      await tester.pumpWidget(
        section(
          const MediaImageRequest(
            urls: <String>['https://old.test/1.jpg', 'https://old.test/2.jpg'],
            selfAuthenticated: true,
          ),
        ),
      );
      final finder = find.byKey(
        const ValueKey<String>('continue-image-replace'),
      );
      final oldImage = tester.widget<Image>(finder);
      oldImage.errorBuilder!(
        tester.element(finder),
        StateError('旧请求失败'),
        StackTrace.empty,
      );

      await tester.pumpWidget(
        section(
          const MediaImageRequest(
            urls: <String>['https://new.test/1.jpg', 'https://new.test/2.jpg'],
            selfAuthenticated: true,
          ),
        ),
      );
      await tester.pump();

      expect(
        networkUrlOf(tester.widget<Image>(finder)),
        'https://new.test/1.jpg',
      );
    });
  });

  testWidgets('稳定物理解码宽度不随 DPR 和续看卡宽改变', (tester) async {
    final items = List<HomeContinueCardData>.generate(
      4,
      (index) => HomeContinueCardData(
        id: 'stable-$index',
        title: '续看 $index',
        contextText: '测试',
        progress: .2,
        imageRequest: const MediaImageRequest(
          urls: <String>['https://example.test/stable.jpg'],
          selfAuthenticated: true,
        ),
        downloaded: false,
      ),
    );

    Widget section(double width, double devicePixelRatio) => responsiveTestApp(
      width: width,
      devicePixelRatio: devicePixelRatio,
      child: HomeContinueWatchingSection(
        items: items,
        stableImageCacheWidth: 520,
        onOpenDetail: (_) {},
        onPlay: (_) {},
        onLongPress: (_) {},
      ),
    );

    await tester.pumpWidget(section(336, 1));
    final narrowCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('continue-card-stable-0')))
        .width;
    final narrowDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('continue-image-stable-0'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    await tester.pumpWidget(section(570, 3));
    final wideCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('continue-card-stable-0')))
        .width;
    final wideDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('continue-image-stable-0'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    expect(narrowCardWidth, isNot(wideCardWidth));
    expect(narrowDecodeWidth, wideDecodeWidth);
    expect(narrowDecodeWidth, 512);
    expect(
      (tester
                  .widget<Image>(
                    find.byKey(
                      const ValueKey<String>('continue-image-stable-0'),
                    ),
                  )
                  .image
              as ResizeImage)
          .height,
      isNull,
    );
  });
}
