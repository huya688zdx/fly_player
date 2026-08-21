import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/home_catalog_presentation.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_catalog_section.dart';
import 'package:fly_player/theme/app_theme.dart';

const _image = MediaImageRequest(
  urls: <String>['https://example.test/library.jpg'],
  selfAuthenticated: true,
);

class _PendingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _withPendingImages(Future<void> Function() body) async {
  final previousProvider = debugNetworkImageHttpClientProvider;
  debugNetworkImageHttpClientProvider = _PendingHttpClient.new;
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = previousProvider;
  }
}

Widget _app(HomeCatalogPresentation presentation) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: Scaffold(
    body: SizedBox(
      width: 390,
      child: HomeCatalogSection(
        presentation: presentation,
        items: const <HomeCatalogCardData>[
          HomeCatalogCardData(
            id: 'library',
            title: '动漫 TV',
            mediaType: HomeCatalogMediaType.series,
            imageRequests: <MediaImageRequest>[_image, _image, _image],
          ),
        ],
        onTap: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('飞牛按官方样式连续均分三张封面且标题覆盖在底部', (tester) async {
    await _withPendingImages(() async {
      await tester.pumpWidget(_app(HomeCatalogPresentation.officialCollage));

      final artwork = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-artwork-library')),
      );
      final posters = <Rect>[
        for (var index = 0; index < 3; index++)
          tester.getRect(
            find.byKey(ValueKey<String>('catalog-poster-library-$index')),
          ),
      ];
      expect(find.byType(Image), findsNWidgets(3));
      expect(posters.first.left, closeTo(artwork.left, 1));
      expect(posters.last.right, closeTo(artwork.right, 1));
      for (var index = 1; index < posters.length; index++) {
        expect(posters[index - 1].right, closeTo(posters[index].left, 1));
      }
      for (final poster in posters) {
        expect(poster.width / poster.height, closeTo(2 / 3, .03));
        expect(poster.top, closeTo(artwork.top, 1));
        expect(poster.bottom, lessThan(artwork.bottom));
      }
      final title = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-title-library')),
      );
      expect(title.bottom, lessThanOrEqualTo(artwork.bottom));
      expect(title.top, greaterThan(artwork.center.dy));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Emby 使用单张十六比九影院横幅并在图内显示标题和取色强调线', (tester) async {
    await _withPendingImages(() async {
      await tester.pumpWidget(_app(HomeCatalogPresentation.cinematicBackdrop));

      expect(find.byType(Image), findsOneWidget);
      final artwork = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-artwork-library')),
      );
      expect(artwork.width / artwork.height, closeTo(16 / 9, .03));
      final title = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-title-library')),
      );
      expect(title.bottom, lessThanOrEqualTo(artwork.bottom));
      expect(
        find.byKey(const ValueKey<String>('catalog-accent-library')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Jellyfin 使用单张清晰横图且标题独立位于图片下方', (tester) async {
    await _withPendingImages(() async {
      await tester.pumpWidget(_app(HomeCatalogPresentation.clearGallery));

      expect(find.byType(Image), findsOneWidget);
      final artwork = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-artwork-library')),
      );
      expect(artwork.width / artwork.height, closeTo(16 / 9, .03));
      final title = tester.getRect(
        find.byKey(const ValueKey<String>('catalog-title-library')),
      );
      expect(title.top, greaterThanOrEqualTo(artwork.bottom));
      expect(
        find.byKey(const ValueKey<String>('catalog-accent-library')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
