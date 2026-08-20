import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_landscape_media_section.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/media_poster_card.dart';

const landscapeImage = MediaImageRequest(
  urls: <String>['https://example.test/backdrop.jpg'],
  headers: <String, String>{'Authorization': 'Bearer test'},
  selfAuthenticated: true,
);

const landscapeFixture = HomeLandscapeCardData(
  id: 'episode-1',
  title: '吹响吧！上低音号',
  contextText: '第 2 季 · 第 4 集',
  imageRequest: landscapeImage,
);

Widget testApp(
  Widget child, {
  double width = 390,
  double devicePixelRatio = 1,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      devicePixelRatio: devicePixelRatio,
      textScaler: textScaler,
    ),
    child: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  ),
);

NetworkImage networkImageOf(Image image) {
  final provider = image.image;
  return provider is ResizeImage
      ? provider.imageProvider as NetworkImage
      : provider as NetworkImage;
}

String networkUrlOf(Image image) => networkImageOf(image).url;

class _PendingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> withPendingHttp(Future<void> Function() body) async {
  final previousProvider = debugNetworkImageHttpClientProvider;
  debugNetworkImageHttpClientProvider = _PendingHttpClient.new;
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = previousProvider;
  }
}

void main() {
  testWidgets('横版剧集卡保持 16:10 图片、裁切与两行文字层级', (tester) async {
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[landscapeFixture],
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    final artwork = find.byKey(
      const ValueKey<String>('landscape-artwork-episode-1'),
    );
    final size = tester.getSize(artwork);
    expect(size.width / size.height, inInclusiveRange(1.55, 1.7));

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('landscape-image-episode-1')),
    );
    expect(image.fit, BoxFit.cover);
    expect(networkImageOf(image).headers, landscapeImage.headers);
    expect((image.image as ResizeImage).width, greaterThan(0));
    expect((image.image as ResizeImage).height, isNull);
    final title = tester.widget<Text>(find.text('吹响吧！上低音号'));
    final context = tester.widget<Text>(find.text('第 2 季 · 第 4 集'));
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(context.style?.fontSize, 12);
    expect(context.style?.fontWeight, FontWeight.w400);
    expect(find.byType(MediaPosterCard), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整张横版卡支持点击和长按', (tester) async {
    var tapped = '';
    var longPressed = '';
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[landscapeFixture],
          onOpenDetail: (item) => tapped = item.id,
          onLongPress: (item) => longPressed = item.id,
        ),
      ),
    );

    final card = find.byKey(const ValueKey<String>('landscape-card-episode-1'));
    await tester.tap(card);
    expect(tapped, 'episode-1');
    await tester.longPress(card);
    expect(longPressed, 'episode-1');
  });

  testWidgets('缺图显示剧集占位图标且空数据隐藏', (tester) async {
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[
            HomeLandscapeCardData(
              id: 'missing',
              title: '缺图',
              contextText: '第 1 集',
              imageRequest: MediaImageRequest.empty,
            ),
          ],
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    expect(find.byIcon(Icons.live_tv_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    final placeholder = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byIcon(Icons.live_tv_outlined),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    final themeColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    expect(placeholder.color, themeColors.surfaceStrong);

    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[],
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );
    expect(find.text('下一集'), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('图片候选失败时每帧只前进一个并限制解码尺寸', (tester) async {
    const fixture = HomeLandscapeCardData(
      id: 'fallback',
      title: '候选图',
      contextText: '第 1 集',
      imageRequest: MediaImageRequest(
        urls: <String>[
          'https://example.test/first.jpg',
          'https://example.test/second.jpg',
          'https://example.test/third.jpg',
        ],
        selfAuthenticated: true,
      ),
    );
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[fixture],
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('landscape-image-fallback'),
    );
    var image = tester.widget<Image>(finder);
    expect(networkUrlOf(image), endsWith('/first.jpg'));
    expect((image.image as ResizeImage).width, greaterThan(0));

    final context = tester.element(finder);
    image.errorBuilder!(context, StateError('首次失败'), StackTrace.empty);
    image.errorBuilder!(context, StateError('重复回调'), StackTrace.empty);
    await tester.pump();
    await tester.pump();
    image = tester.widget<Image>(finder);
    expect(networkUrlOf(image), endsWith('/second.jpg'));

    image.errorBuilder!(
      tester.element(finder),
      StateError('第二候选失败'),
      StackTrace.empty,
    );
    await tester.pump();
    await tester.pump();
    expect(networkUrlOf(tester.widget<Image>(finder)), endsWith('/third.jpg'));
  });

  testWidgets('稳定物理解码宽度不随 DPR 和卡宽改变', (tester) async {
    Widget section(double width, double devicePixelRatio) => testApp(
      width: width,
      devicePixelRatio: devicePixelRatio,
      HomeLandscapeMediaSection(
        title: '下一集',
        items: const <HomeLandscapeCardData>[landscapeFixture],
        stableImageCacheWidth: 520,
        onOpenDetail: (_) {},
        onLongPress: (_) {},
      ),
    );

    await tester.pumpWidget(section(336, 1));
    final narrowCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('landscape-card-episode-1')))
        .width;
    final narrowDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('landscape-image-episode-1'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    await tester.pumpWidget(section(570, 3));
    final wideCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('landscape-card-episode-1')))
        .width;
    final wideDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('landscape-image-episode-1'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    expect(narrowCardWidth, isNot(wideCardWidth));
    expect(narrowDecodeWidth, 512);
    expect(wideDecodeWidth, narrowDecodeWidth);
  });

  testWidgets('二倍文字不溢出卡片容器', (tester) async {
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: const <HomeLandscapeCardData>[landscapeFixture],
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
        width: 320,
        textScaler: const TextScaler.linear(2),
      ),
    );

    final listBounds = tester.getRect(find.byType(ListView));
    final contextBounds = tester.getRect(find.text('第 2 季 · 第 4 集'));
    expect(contextBounds.bottom, lessThanOrEqualTo(listBounds.bottom + .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('多张横版卡可连续拖动并停在首卡宽度内', (tester) async {
    final items = List<HomeLandscapeCardData>.generate(
      8,
      (index) => HomeLandscapeCardData(
        id: 'scroll-$index',
        title: '剧集 $index',
        contextText: '第 ${index + 1} 集',
        imageRequest: MediaImageRequest.empty,
      ),
    );
    await tester.pumpWidget(
      testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: items,
          onOpenDetail: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    final cardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('landscape-card-scroll-0')))
        .width;
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await tester.drag(find.byType(ListView), const Offset(-95, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(cardWidth));
  });

  testWidgets('图片请求变化会取消旧请求待执行的回退', (tester) async {
    await withPendingHttp(() async {
      Widget section(MediaImageRequest request) => testApp(
        HomeLandscapeMediaSection(
          title: '下一集',
          items: <HomeLandscapeCardData>[
            HomeLandscapeCardData(
              id: 'replace',
              title: '替换请求',
              contextText: '第 1 集',
              imageRequest: request,
            ),
          ],
          onOpenDetail: (_) {},
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
        const ValueKey<String>('landscape-image-replace'),
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
}
