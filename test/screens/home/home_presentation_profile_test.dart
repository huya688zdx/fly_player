import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaBackendCapabilities capabilitiesFor(MediaBackendKind kind) =>
      kind == MediaBackendKind.feiniu
      ? const MediaBackendCapabilities.feiniu()
      : MediaBackendCapabilities.server(kind: kind);

  group('HomePresentationProfile', () {
    test('三平台共同区块都保持媒体库、续看与可用扩展区顺序', () {
      for (final kind in MediaBackendKind.values) {
        final order = HomePresentationProfile.forCapabilities(
          capabilitiesFor(kind),
        ).sectionOrder;
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

    test('飞牛预留最近添加能力但现阶段不放入首页配置', () {
      expect(
        HomePresentationProfile.forCapabilities(
          const MediaBackendCapabilities.feiniu(),
        ).sectionOrder,
        <HomeSectionKind>[
          HomeSectionKind.catalogs,
          HomeSectionKind.continueWatching,
          HomeSectionKind.nextUp,
          HomeSectionKind.summary,
          HomeSectionKind.catalogPreviews,
        ],
      );
    });

    test('Emby 与 Jellyfin 保持完整首页顺序', () {
      const expected = <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.nextUp,
        HomeSectionKind.latest,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ];

      for (final kind in <MediaBackendKind>[
        MediaBackendKind.emby,
        MediaBackendKind.jellyfin,
      ]) {
        expect(
          HomePresentationProfile.forCapabilities(
            capabilitiesFor(kind),
          ).sectionOrder,
          expected,
          reason: kind.name,
        );
      }
    });
  });
}
