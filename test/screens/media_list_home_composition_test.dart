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
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.latest,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('飞牛也按统一顺序展示有内容的 NextUp 和最近添加', () {
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
        HomeSectionKind.nextUp,
        HomeSectionKind.latest,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ]);
    });

    test('Emby 隐藏空续看和最近添加并保留有内容的摘要', () {
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
        HomeSectionKind.summary,
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
    final landscapeWidgetSource = File(
      'lib/screens/home/widgets/home_landscape_media_section.dart',
    ).readAsStringSync();

    expect(widgetsSource, contains('HomeCatalogSection('));
    expect(widgetsSource, isNot(contains('catalogStyle')));
    expect(widgetsSource, contains('const limit = 3;'));
    expect(widgetsSource, contains('presentation: catalogPresentation'));
    expect(widgetsSource, contains('homeCatalogImageRequestsForPresentation('));
    expect(widgetsSource, contains('previewBackdropRequests:'));
    expect(widgetsSource, contains('previewPrimaryRequests:'));
    expect(widgetsSource, contains('HomeContinueWatchingSection('));
    expect(widgetsSource, contains('HomeLandscapeMediaSection('));
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
      'stableImageCacheWidth: layout.continueDecodeWidth'.allMatches(
        widgetsSource,
      ),
      hasLength(2),
    );
    expect(
      widgetsSource,
      contains('stableImageCacheWidth: layout.homeCatalogDecodeWidth'),
    );
    expect(
      widgetsSource,
      contains('requestWidth: layout.homeCatalogRequestWidth'),
    );
    expect(widgetsSource, isNot(contains('categoryMiniPosterRequestWidth')));
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
    expect(continueWidgetSource, isNot(contains('trailingText')));
    expect(landscapeWidgetSource, isNot(contains('MediaPosterCard')));
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

  test('nextUp 使用 backdrop 优先的横版架且 latest 保持竖版海报', () {
    final screenSource = File(
      'lib/screens/media_list_screen.dart',
    ).readAsStringSync();
    final widgetsSource = File(
      'lib/screens/media_list_screen_widgets.dart',
    ).readAsStringSync();

    expect(
      screenSource,
      contains("import 'home/widgets/home_landscape_media_section.dart';"),
    );
    expect(widgetsSource, contains('Widget _buildHomeNextUpShelf({'));
    expect(widgetsSource, contains("storageKey: 'next-up'"));
    expect(widgetsSource, contains('contextText: _continueEpisodeText(item)'));
    expect(
      '_homeLandscapeImageRequest('.allMatches(widgetsSource),
      hasLength(3),
    );
    expect(
      'requestWidth: layout.homeContinueRequestWidth'.allMatches(widgetsSource),
      hasLength(2),
    );

    final sectionSwitchStart = widgetsSource.indexOf('return switch (section)');
    final sectionSwitchEnd = widgetsSource.indexOf(
      'Widget _buildHomeCatalogs',
      sectionSwitchStart,
    );
    final sectionSwitch = widgetsSource.substring(
      sectionSwitchStart,
      sectionSwitchEnd,
    );
    expect(
      sectionSwitch,
      contains('HomeSectionKind.nextUp => _buildHomeNextUpShelf('),
    );
    expect(
      sectionSwitch,
      contains('HomeSectionKind.latest => _buildHomeMediaShelf('),
    );

    final helperStart = widgetsSource.indexOf(
      'MediaImageRequest _homeLandscapeImageRequest(',
    );
    final helperEnd = widgetsSource.indexOf(
      'String _continueContextText(',
      helperStart,
    );
    final helperSource = widgetsSource.substring(helperStart, helperEnd);
    expect(
      helperSource.indexOf('_backdropImageRequests[item.guid]'),
      lessThan(helperSource.indexOf('_itemImageRequests[item.guid]')),
    );

    final contextStart = widgetsSource.indexOf('String _continueContextText(');
    final contextEnd = widgetsSource.indexOf(
      'Widget _buildHomeSummary(',
      contextStart,
    );
    final contextSource = widgetsSource.substring(contextStart, contextEnd);
    expect(contextSource, contains('_continueEpisodeText(item)'));
    expect(contextSource, isNot(contains('remainText')));
    expect(contextSource, isNot(contains('remaining')));
    expect(contextSource, isNot(contains('position')));
    expect(screenSource, isNot(contains('play_detail_formatters.dart')));
  });

  test('旧分页器与孤立响应式布局已删除', () {
    for (final path in <String>[
      'lib/screens/home/widgets/home_'
          'adaptive_'
          'pager.dart',
      'test/widgets/home_'
          'adaptive_'
          'pager_test.dart',
      'lib/screens/home/home_responsive_layout.dart',
      'test/screens/home/home_responsive_layout_test.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }

    for (final path in <String>[
      'lib/screens/home/widgets/home_continue_watching_section.dart',
      'lib/screens/home/widgets/home_catalog_section.dart',
      'lib/screens/home/widgets/home_horizontal_shelf.dart',
      'lib/screens/home/widgets/home_landscape_media_section.dart',
      'lib/screens/media_list_screen.dart',
      'lib/screens/media_list_screen_widgets.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(
          contains(
            'HomeAdaptive'
            'Pager',
          ),
        ),
        reason: path,
      );
      expect(
        source,
        isNot(
          contains(
            'home_'
            'adaptive_'
            'pager',
          ),
        ),
        reason: path,
      );
    }
  });

  test('媒体库生产组件使用连续横向架且不再渲染标题计数', () {
    final source = File(
      'lib/screens/home/widgets/home_catalog_section.dart',
    ).readAsStringSync();

    expect(source, contains('HomeHorizontalShelf<HomeCatalogCardData>('));
    expect(source, contains("storageKey: 'catalogs'"));
    expect(source, contains('minItemWidth: shelfMetrics.minWidth'));
    expect(source, contains('itemAspectRatio: shelfMetrics.aspectRatio'));
    expect(source, contains('class _FeiniuCatalogCardBody'));
    expect(source, contains('class _EmbyCatalogCardBody'));
    expect(source, contains('class _JellyfinCatalogCardBody'));
    expect(source, contains('.take(3)'));
    expect(
      source,
      isNot(
        contains(
          'HomeAdaptive'
          'Pager',
        ),
      ),
    );
    expect(source, isNot(contains('trailingText')));
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
