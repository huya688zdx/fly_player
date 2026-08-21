import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/home_catalog_presentation.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_catalog_section.dart';
import 'package:fly_player/theme/app_theme.dart';

const loadableImage = MediaImageRequest(
  urls: <String>['https://example.test/artwork.jpg'],
  headers: <String, String>{'Authorization': 'Bearer test'},
  selfAuthenticated: true,
);

Widget testApp(Widget child, {AppThemeColors? runtimeColors}) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: AppRuntimeColorScope(
    colors: runtimeColors,
    hasRuntimeColors: runtimeColors != null,
    child: Scaffold(body: SizedBox(width: 390, child: child)),
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
  return networkImageOf(image).url;
}

NetworkImage networkImageOf(Image image) {
  final provider = image.image;
  return provider is ResizeImage
      ? provider.imageProvider as NetworkImage
      : provider as NetworkImage;
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
  test('媒体库图片按后端选择真实可用来源并保留加载回退', () {
    const catalog = MediaImageRequest(
      urls: <String>['https://example.test/catalog.jpg'],
      selfAuthenticated: true,
    );
    const backdrop = MediaImageRequest(
      urls: <String>['https://example.test/backdrop.jpg'],
      selfAuthenticated: true,
    );
    const primary = MediaImageRequest(
      urls: <String>['https://example.test/primary.jpg'],
      selfAuthenticated: true,
    );

    final feiniu = homeCatalogImageRequestsForPresentation(
      presentation: HomeCatalogPresentation.officialCollage,
      catalogRequests: const <MediaImageRequest>[
        catalog,
        backdrop,
        primary,
        catalog,
      ],
    );
    final emby = homeCatalogImageRequestsForPresentation(
      presentation: HomeCatalogPresentation.cinematicBackdrop,
      catalogRequests: const <MediaImageRequest>[catalog],
      previewBackdropRequests: const <MediaImageRequest>[backdrop],
      previewPrimaryRequests: const <MediaImageRequest>[primary],
    );
    final jellyfin = homeCatalogImageRequestsForPresentation(
      presentation: HomeCatalogPresentation.clearGallery,
      catalogRequests: const <MediaImageRequest>[catalog],
      previewBackdropRequests: const <MediaImageRequest>[backdrop],
      previewPrimaryRequests: const <MediaImageRequest>[primary],
    );

    expect(feiniu, hasLength(3));
    expect(emby.single.urls, <String>[
      'https://example.test/backdrop.jpg',
      'https://example.test/catalog.jpg',
      'https://example.test/primary.jpg',
    ]);
    expect(jellyfin.single.urls, <String>[
      'https://example.test/catalog.jpg',
      'https://example.test/backdrop.jpg',
      'https://example.test/primary.jpg',
    ]);
  });

  testWidgets('缺图媒体库卡显示媒体类型图标并可点击', (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
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

  testWidgets('媒体库卡保持透明外层并使用动态主题强调色', (tester) async {
    const accent = Color(0xFF12A4D9);
    const surface = Color(0xFF24313A);
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    final runtimeColors = baseColors.copyWith(
      accent: accent,
      surfaceStrong: surface,
    );

    await tester.pumpWidget(
      testApp(
        HomeCatalogSection(
          presentation: HomeCatalogPresentation.cinematicBackdrop,
          items: const <HomeCatalogCardData>[
            HomeCatalogCardData(
              id: 'themed',
              title: '动态主题',
              mediaType: HomeCatalogMediaType.mixed,
              imageRequests: <MediaImageRequest>[],
            ),
          ],
          onTap: (_) {},
        ),
        runtimeColors: runtimeColors,
      ),
    );

    final material = tester.widget<Material>(
      find.byKey(const ValueKey<String>('catalog-card-themed')),
    );
    expect(material.color, Colors.transparent);
    final accentBox = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('catalog-accent-themed')),
    );
    expect(accentBox.color, accent);
    expect(tester.widget<Text>(find.text('动态主题')).style?.color, Colors.white);
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

  testWidgets('稳定物理解码宽度不随 DPR 和响应式卡宽改变', (tester) async {
    final items = List<HomeCatalogCardData>.generate(
      4,
      (index) => HomeCatalogCardData(
        id: 'stable-$index',
        title: '媒体库 $index',
        mediaType: HomeCatalogMediaType.movies,
        imageRequests: const <MediaImageRequest>[loadableImage],
      ),
    );

    Widget section(double width, double devicePixelRatio) => responsiveTestApp(
      width: width,
      devicePixelRatio: devicePixelRatio,
      child: HomeCatalogSection(
        items: items,
        stableImageCacheWidth: 440,
        onTap: (_) {},
      ),
    );

    await tester.pumpWidget(section(280, 1));
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

    await tester.pumpWidget(section(570, 3));
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
    expect(
      (tester
                  .widget<Image>(
                    find.byKey(
                      const ValueKey<String>('catalog-image-stable-0'),
                    ),
                  )
                  .image
              as ResizeImage)
          .height,
      isNull,
    );
  });
}
