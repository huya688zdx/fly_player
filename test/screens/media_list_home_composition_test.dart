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
    final actionsSource = File(
      'lib/screens/media_list_screen_actions.dart',
    ).readAsStringSync();
    final continueWidgetSource = File(
      'lib/screens/home/widgets/home_continue_watching_section.dart',
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
      contains('stableImageCacheWidth: layout.continueDecodeWidth'),
    );
    expect(
      widgetsSource,
      contains('stableImageCacheWidth: layout.homeCatalogDecodeWidth'),
    );
    expect(widgetsSource, isNot(contains('miniPosterDecodeWidth')));
    expect(
      widgetsSource,
      contains(
        'layout.homePosterRowHeightFor(MediaQuery.textScalerOf(context))',
      ),
    );
    expect(widgetsSource, isNot(contains("heroTag: 'home_continue_")));
    expect(actionsSource, isNot(contains('required String heroTag')));
    expect(continueWidgetSource, isNot(contains('heroTag')));
    expect('continueDetailTarget('.allMatches(widgetsSource), hasLength(1));
    expect('continueDetailTarget('.allMatches(actionsSource), hasLength(1));

    expect(screenSource, contains('Future<void> _playContinueItem('));
    expect(screenSource, contains('_pendingContinueWatchingRefresh = true'));
    expect(screenSource, contains('ItemPlaybackLauncher().open('));
    expect(screenSource, contains('unawaited(_refreshContinueWatching())'));

    final playMethodStart = screenSource.indexOf(
      'Future<void> _playContinueItem(',
    );
    final playMethodEnd = screenSource.indexOf(
      'bool _isEpisodeItem(',
      playMethodStart,
    );
    final playMethodSource = screenSource.substring(
      playMethodStart,
      playMethodEnd,
    );
    expect(playMethodSource, contains('try {'));
    expect(playMethodSource, contains('catch (error, stackTrace)'));
    expect(playMethodSource, isNot(contains('finally {')));
    expect(playMethodSource, contains('logSwallowedError('));
    expect(playMethodSource, contains('stackTrace: stackTrace'));
    expect(playMethodSource, contains('detailPlayInfoFailed'));
    expect(playMethodSource, contains('_showHomeSnackBar('));
    expect(
      playMethodSource,
      isNot(contains('unawaited(_refreshContinueWatching())')),
    );

    final catchStart = playMethodSource.indexOf('catch (error, stackTrace)');
    final catchSource = playMethodSource.substring(catchStart);
    expect(catchSource, contains('_pendingContinueWatchingRefresh = false'));

    final lifecycleStart = screenSource.indexOf(
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );
    final lifecycleEnd = screenSource.indexOf(
      'void didChangeDependencies()',
      lifecycleStart,
    );
    final lifecycleSource = screenSource.substring(
      lifecycleStart,
      lifecycleEnd,
    );
    expect(lifecycleSource, contains('state == AppLifecycleState.resumed'));
    expect(lifecycleSource, contains('_pendingContinueWatchingRefresh'));
    expect(
      lifecycleSource,
      contains('_pendingContinueWatchingRefresh = false'),
    );
    expect(lifecycleSource, contains('unawaited(_refreshContinueWatching())'));
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
