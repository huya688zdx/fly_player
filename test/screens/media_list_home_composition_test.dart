import 'dart:io';

import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('visibleHomeSections', () {
    test('Jellyfin 只按配置顺序保留有内容的区块', () {
      final sections = visibleHomeSections(
        profile: HomePresentationProfile.forKind(MediaBackendKind.jellyfin),
        hasCatalogs: true,
        hasContinueWatching: true,
        hasSummary: false,
        hasNextUp: false,
        hasLatest: true,
      );

      expect(sections, <HomeSectionKind>[
        HomeSectionKind.continueWatching,
        HomeSectionKind.latest,
        HomeSectionKind.catalogs,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('飞牛不展示配置之外的 NextUp 和最近添加', () {
      final sections = visibleHomeSections(
        profile: HomePresentationProfile.forKind(MediaBackendKind.feiniu),
        hasCatalogs: true,
        hasContinueWatching: true,
        hasSummary: true,
        hasNextUp: true,
        hasLatest: true,
      );

      expect(sections, <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('Emby 隐藏空续看和最近添加且忽略摘要', () {
      final sections = visibleHomeSections(
        profile: HomePresentationProfile.forKind(MediaBackendKind.emby),
        hasCatalogs: true,
        hasContinueWatching: false,
        hasSummary: true,
        hasNextUp: true,
        hasLatest: false,
      );

      expect(sections, <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.nextUp,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('所有数据为空时不产生首页区块', () {
      final sections = visibleHomeSections(
        profile: HomePresentationProfile.forKind(MediaBackendKind.jellyfin),
        hasCatalogs: false,
        hasContinueWatching: false,
        hasSummary: false,
        hasNextUp: false,
        hasLatest: false,
      );

      expect(sections, isEmpty);
    });
  });

  test('首页只组合共享图片区块且续看播放走独立入口', () {
    final widgetsSource = File(
      'lib/screens/media_list_screen_widgets.dart',
    ).readAsStringSync();
    final screenSource = File(
      'lib/screens/media_list_screen.dart',
    ).readAsStringSync();

    expect(widgetsSource, contains('HomeCatalogSection('));
    expect(widgetsSource, contains('HomeContinueWatchingSection('));
    expect(widgetsSource, contains('visibleHomeSections('));
    expect(widgetsSource, isNot(contains('Widget _buildContinueItem(')));
    expect(widgetsSource, isNot(contains('class _CategoryPosterCard')));
    expect(widgetsSource, isNot(contains('class _PosterCluster')));
    expect(widgetsSource, isNot(contains('TextScaler.linear(1')));
    expect(widgetsSource, contains('titleFontWeight: FontWeight.w500'));
    expect(widgetsSource, contains('subtitleFontWeight: FontWeight.w400'));
    expect(
      widgetsSource,
      contains('stableImageDecodeLogicalWidth: layout.continueDecodeWidth'),
    );
    expect(
      widgetsSource,
      contains('stableImageDecodeLogicalWidth: layout.miniPosterDecodeWidth'),
    );

    expect(screenSource, contains('Future<void> _playContinueItem('));
    expect(screenSource, contains('_pendingContinueWatchingRefresh = true'));
    expect(screenSource, contains('ItemPlaybackLauncher().open('));
    expect(screenSource, contains('unawaited(_refreshContinueWatching())'));
  });

  test('旧首页固定卡片尺寸已从布局配置移除', () {
    final layoutSource = File('lib/ui/layout_adaptive.dart').readAsStringSync();

    for (final field in <String>[
      'categoryStripHeight',
      'categoryCardWidth',
      'categoryMiniPosterWidth',
      'categoryMiniPosterHeight',
      'continueCardWidth',
      'continueImageHeight',
      'continueRowHeight',
    ]) {
      expect(layoutSource, isNot(contains(field)), reason: field);
    }
  });
}
