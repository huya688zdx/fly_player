import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePresentationProfile', () {
    test('飞牛使用海报拼贴，并按飞牛首页顺序展示', () {
      final profile = HomePresentationProfile.forKind(MediaBackendKind.feiniu);

      expect(profile.catalogStyle, HomeCatalogStyle.posterMosaic);
      expect(profile.sectionOrder, <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('Emby 使用横向图片，并优先展示继续观看', () {
      final profile = HomePresentationProfile.forKind(MediaBackendKind.emby);

      expect(profile.catalogStyle, HomeCatalogStyle.landscapeArtwork);
      expect(profile.sectionOrder, <HomeSectionKind>[
        HomeSectionKind.continueWatching,
        HomeSectionKind.catalogs,
        HomeSectionKind.nextUp,
        HomeSectionKind.latest,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('Jellyfin 使用图片网格，并优先展示动态内容', () {
      final profile = HomePresentationProfile.forKind(
        MediaBackendKind.jellyfin,
      );

      expect(profile.catalogStyle, HomeCatalogStyle.artworkGrid);
      expect(profile.sectionOrder, <HomeSectionKind>[
        HomeSectionKind.continueWatching,
        HomeSectionKind.nextUp,
        HomeSectionKind.latest,
        HomeSectionKind.catalogs,
        HomeSectionKind.catalogPreviews,
      ]);
    });
  });
}
