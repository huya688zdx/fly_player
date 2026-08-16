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
}
