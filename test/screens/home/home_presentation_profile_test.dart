import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePresentationProfile', () {
    test('三平台共同区块都保持媒体库、续看、下一集与最近添加顺序', () {
      for (final kind in MediaBackendKind.values) {
        final order = HomePresentationProfile.forKind(kind).sectionOrder;
        final catalogs = order.indexOf(HomeSectionKind.catalogs);
        final continueWatching = order.indexOf(
          HomeSectionKind.continueWatching,
        );
        final nextUp = order.indexOf(HomeSectionKind.nextUp);
        final latest = order.indexOf(HomeSectionKind.latest);

        expect(catalogs, lessThan(continueWatching), reason: kind.name);
        if (nextUp >= 0) {
          expect(continueWatching, lessThan(nextUp), reason: kind.name);
        }
        if (latest >= 0) {
          expect(continueWatching, lessThan(latest), reason: kind.name);
        }
      }
    });

    test('三平台采用同一套完整首页顺序', () {
      const expected = <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.nextUp,
        HomeSectionKind.latest,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ];

      for (final kind in MediaBackendKind.values) {
        expect(
          HomePresentationProfile.forKind(kind).sectionOrder,
          expected,
          reason: kind.name,
        );
      }
    });
  });
}
