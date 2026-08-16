import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';
import 'package:fly_player/screens/home/widgets/home_catalog_section.dart';
import 'package:fly_player/theme/app_theme.dart';

const loadableImage = MediaImageRequest(
  urls: <String>['https://example.test/artwork.jpg'],
  selfAuthenticated: true,
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
  testWidgets('单图媒体库卡铺满裁切且不再使用迷你海报', (tester) async {
    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
          style: HomeCatalogStyle.landscapeArtwork,
          items: const <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'lib-1',
              title: '动漫 TV',
              mediaType: HomeCatalogMediaType.series,
              imageRequests: <MediaImageRequest>[loadableImage],
            ),
          ],
          onTap: (_) {},
        ),
      ),
    );

    expect(
      tester
          .widget<Image>(
            find.byKey(const ValueKey<String>('catalog-image-lib-1')),
          )
          .fit,
      BoxFit.cover,
    );
    expect(
      find.byKey(const ValueKey<String>('catalog-mini-poster-lib-1')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('动漫 TV')).style?.fontWeight,
      FontWeight.w500,
    );
  });

  testWidgets('飞牛海报簇使用最多三张真实图片铺满主体', (tester) async {
    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
          style: HomeCatalogStyle.posterMosaic,
          items: const <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'lib-1',
              title: '动漫电影',
              mediaType: HomeCatalogMediaType.movies,
              imageRequests: <MediaImageRequest>[
                loadableImage,
                loadableImage,
                loadableImage,
                loadableImage,
              ],
            ),
          ],
          onTap: (_) {},
        ),
      ),
    );

    expect(find.byType(Image), findsNWidgets(3));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect(image.fit, BoxFit.cover);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('方形媒体库卡缺图时显示媒体类型图标并可点击', (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
          style: HomeCatalogStyle.artworkGrid,
          items: const <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'lib-empty',
              title: '合集',
              mediaType: HomeCatalogMediaType.collections,
              imageRequests: <MediaImageRequest>[],
            ),
          ],
          onTap: (item) => tapped = item.id,
        ),
      ),
    );

    expect(find.byIcon(Icons.video_collection_outlined), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('catalog-card-lib-empty')),
    );
    expect(tapped, 'lib-empty');
    expect(tester.takeException(), isNull);
  });

  testWidgets('媒体库图片候选失败时不连跳且限制解码尺寸', (tester) async {
    const candidates = MediaImageRequest(
      urls: <String>[
        'https://example.test/first.jpg',
        'https://example.test/second.jpg',
        'https://example.test/third.jpg',
      ],
      selfAuthenticated: true,
    );
    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
          style: HomeCatalogStyle.landscapeArtwork,
          items: const <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'fallback',
              title: '候选图',
              mediaType: HomeCatalogMediaType.movies,
              imageRequests: <MediaImageRequest>[candidates],
            ),
          ],
          onTap: (_) {},
        ),
      ),
    );

    final finder = find.byKey(const ValueKey<String>('catalog-image-fallback'));
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

  testWidgets('媒体库图片请求变化会取消旧请求待执行的回退', (tester) async {
    await withPendingHttp(() async {
      Widget section(MediaImageRequest request) => testApp(
        HomeCatalogSection(
          style: HomeCatalogStyle.landscapeArtwork,
          items: <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'replace',
              title: '替换请求',
              mediaType: HomeCatalogMediaType.movies,
              imageRequests: <MediaImageRequest>[request],
            ),
          ],
          onTap: (_) {},
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
        const ValueKey<String>('catalog-image-replace'),
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

  testWidgets('稳定解码宽度不随响应式视觉卡宽改变', (tester) async {
    final items = List<HomeCatalogCardData>.generate(
      4,
      (index) => HomeCatalogCardData(
        id: 'stable-$index',
        title: '媒体库 $index',
        mediaType: HomeCatalogMediaType.movies,
        imageRequests: const <MediaImageRequest>[loadableImage],
      ),
    );

    Widget section(double width) => responsiveTestApp(
      width: width,
      devicePixelRatio: 2.5,
      child: HomeCatalogSection(
        style: HomeCatalogStyle.landscapeArtwork,
        items: items,
        stableImageDecodeLogicalWidth: 180,
        onTap: (_) {},
      ),
    );

    await tester.pumpWidget(section(336));
    final narrowCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('catalog-card-stable-0')))
        .width;
    final narrowDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('catalog-image-stable-0'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    await tester.pumpWidget(section(570));
    final wideCardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('catalog-card-stable-0')))
        .width;
    final wideDecodeWidth =
        (tester
                    .widget<Image>(
                      find.byKey(
                        const ValueKey<String>('catalog-image-stable-0'),
                      ),
                    )
                    .image
                as ResizeImage)
            .width;

    expect(narrowCardWidth, isNot(wideCardWidth));
    expect(narrowDecodeWidth, wideDecodeWidth);
    expect(narrowDecodeWidth, 448);
  });
}
