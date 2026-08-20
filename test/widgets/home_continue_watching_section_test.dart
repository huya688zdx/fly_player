import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Widget testApp(Widget child) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: Scaffold(body: SizedBox(width: 390, child: child)),
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
    expect(find.text('1 条'), findsOneWidget);

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

  testWidgets('续看使用可访问字重、封面裁切和语义主题色', (tester) async {
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
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[imageFixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
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
    expect(progress.color, AppThemePalette.fallback.accent);

    final playButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    final scheme = AppThemeBuilder.build(AppThemePreset.midnight).colorScheme;
    expect(
      playButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      scheme.onPrimary,
    );
    final visual = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('continue-play-visual-image-item')),
    );
    expect((visual.decoration as BoxDecoration).color, scheme.primary);
    final targetSize = tester.getSize(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    expect(targetSize.width, greaterThanOrEqualTo(48));
    expect(targetSize.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
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
