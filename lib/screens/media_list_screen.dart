import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/item_playback_launcher.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_catalog.dart';
import '../media_backend/media_item_card.dart';
import '../providers/backend_session_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/home_data_cache.dart';
import '../services/parallel_browse_snapshot.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_localization_lookup.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/liquid_glass.dart';
import '../utils/nas_image_headers.dart';
import 'category_items_screen.dart';
import 'favorite_items_screen.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';

part 'media_list_screen_actions.dart';
part 'media_list_screen_widgets.dart';

enum _ContinueWatchingAction {
  viewDetail,
  markWatched,
  favorite,
  restart,
  remove,
}

class MediaListScreen extends StatefulWidget {
  final bool secondaryHost;

  const MediaListScreen({super.key, this.secondaryHost = false});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  static const int _fallbackContinueLimit = 12;
  static const int _secondaryContinueLimit = 4;
  static const int _defaultCategoryPreviewLimit = 12;
  static const int _secondaryCategoryPreviewLimit = 8;

  List<MediaItem> _categories = <MediaItem>[];
  Map<String, List<MediaLibraryItem>> _itemsByCategory =
      <String, List<MediaLibraryItem>>{};
  List<MediaLibraryItem> _continueWatching = <MediaLibraryItem>[];
  Map<String, dynamic> _mediaSummary = <String, dynamic>{};
  Map<String, dynamic> _localeMap = <String, dynamic>{};
  String _lastLoadKey = '';

  bool _isLoading = false;
  bool _loadingFromCache = false;
  AppException? _error;

  int get _continueLimit =>
      widget.secondaryHost ? _secondaryContinueLimit : _fallbackContinueLimit;

  int get _categoryPreviewLimit => widget.secondaryHost
      ? _secondaryCategoryPreviewLimit
      : _defaultCategoryPreviewLimit;

  double get _scrollCacheExtent => widget.secondaryHost ? 80 : 160;

  double _rowCacheExtent(double itemExtent) {
    final multiplier = widget.secondaryHost ? 0.45 : 0.75;
    return itemExtent * multiplier;
  }

  @override
  void initState() {
    super.initState();
    unawaited(DownloadTaskService.instance.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        EmbeddedDetailLauncher.reportBrowseSnapshot(
          const ParallelBrowseSnapshot.home(originTab: 0),
        ),
      );
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NasProvider>();
    final session = context.read<BackendSessionProvider>();
    // Emby 等公共后端激活（会话已认证）即可加载；飞牛需 NAS 已配置。
    final embyReady =
        session.currentKind == MediaBackendKind.emby && session.isConfigured;
    if (!embyReady && !provider.isConfigured) {
      _lastLoadKey = '';
      _categories = <MediaItem>[];
      _itemsByCategory = <String, List<MediaLibraryItem>>{};
      _continueWatching = <MediaLibraryItem>[];
      _mediaSummary = <String, dynamic>{};
      _localeMap = <String, dynamic>{};
      _error = null;
      _isLoading = false;
      _loadingFromCache = false;
      return;
    }
    final connection = session.currentConnection;
    final loadKey = embyReady
        ? 'emby|${connection?.serverUrl ?? ''}|${connection?.accessToken ?? ''}'
        : '${provider.baseUrl}|${provider.token}';
    if (loadKey != _lastLoadKey) {
      _lastLoadKey = loadKey;
      if (embyReady) {
        // Emby 首光：不读飞牛首页缓存（HomeDataCache 是飞牛态缓存，跨后端会串内容），直接拉取。
        _fetchHomeData();
      } else {
        _tryLoadFromCacheThenRefresh();
      }
    }
  }

  Future<void> _tryLoadFromCacheThenRefresh() async {
    final snapshot = await HomeDataCache.load();
    if (snapshot != null && snapshot.categories.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _categories = snapshot.categories;
        _itemsByCategory = snapshot.itemsByCategory;
        _mediaSummary = snapshot.mediaSummary;
        _continueWatching = snapshot.continueWatching;
        _loadingFromCache = true;
        _isLoading = false;
        _error = null;
      });
      // Refresh in background — update incrementally if changed.
      unawaited(_backgroundRefresh());
      return;
    }
    // No cache — full load with spinner.
    _fetchHomeData();
  }

  // 过渡期本地转换：把公共 [MediaCatalog] 还原成首页现有 UI 使用的 [MediaItem]。
  // 仅限本文件，不扩散；待整页迁移到公共模型后移除。posters/path 完整保留，
  // 保证分类条缩略图与迁移前一致。
  static MediaItem _catalogToMediaItem(MediaCatalog catalog) {
    return MediaItem(
      id: catalog.id,
      name: catalog.title,
      type: catalog.type,
      path: catalog.primaryImage.url,
      posters: catalog.posters
          .map((image) => image.url)
          .toList(growable: false),
    );
  }

  /// 公共 [MediaItemCard] → 首页用 [MediaLibraryItem]（仅非飞牛后端走此转换，喂首页现有
  /// `MediaLibraryItem` 渲染）。续播进度 `ts`/`watchedTs` 不在卡片模型，首光阶段置 0。
  static MediaLibraryItem _cardToMediaItem(MediaItemCard card) {
    return MediaLibraryItem(
      guid: card.id,
      title: card.title,
      tvTitle: card.secondaryTitle,
      type: card.type,
      poster: card.primaryImage.url,
      posterWidth: card.posterWidth,
      posterHeight: card.posterHeight,
      posterList: card.posters
          .map((image) => image.url)
          .toList(growable: false),
      releaseDate: card.releaseDate,
      firstAirDate: card.firstAirDate,
      lastAirDate: card.lastAirDate,
      voteAverage: card.rating,
      overview: '',
      watched: card.watched ? 1 : 0,
      watchedTs: 0,
      ts: 0,
      duration: card.durationSeconds,
      seasonNumber: card.seasonNumber,
      episodeNumber: card.episodeNumber,
      numberOfSeasons: card.numberOfSeasons,
      numberOfEpisodes: card.numberOfEpisodes,
      localNumberOfSeasons: card.localNumberOfSeasons,
      localNumberOfEpisodes: card.localNumberOfEpisodes,
      numberOfItem: card.numberOfItem,
      parentGuid: '',
      parentTitle: '',
      ancestorGuid: '',
      ancestorName: '',
      path: card.primaryImage.url,
      resolutions: card.resolutions,
    );
  }

  /// 继续观看数据源：飞牛走 FeiniuApi（保留续播进度 `ts`），其它公共后端（Emby）走
  /// `backend.getContinueWatching`（[MediaItemCard]→[MediaLibraryItem]，首光阶段无续播进度）。
  /// 数据层按后端能力选源，**非 UI 渲染分支**，UI 不写 `if (isEmby)`。
  Future<List<MediaLibraryItem>> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api, {
    bool forceRefresh = false,
  }) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return api.getPlayList(forceRefresh: forceRefresh);
    }
    final cards = await backend.getContinueWatching(forceRefresh: forceRefresh);
    return cards.map(_cardToMediaItem).toList();
  }

  /// 某库预览条目数据源：飞牛走 FeiniuApi，其它公共后端走 `getCatalogPreviewItems`。
  Future<List<MediaLibraryItem>> _loadCategoryItems(
    MediaBackend backend,
    FeiniuApi api,
    String catalogId,
  ) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return api.getItemsByCategoryGuid(
        catalogId,
        page: 1,
        limit: _categoryPreviewLimit,
      );
    }
    final cards = await backend.getCatalogPreviewItems(
      catalogId,
      limit: _categoryPreviewLimit,
    );
    return cards.map(_cardToMediaItem).toList();
  }

  Future<void> _fetchHomeData() async {
    debugPrint('[UI][HOME] start loading home data');
    final usingSpinner = !_loadingFromCache;
    if (usingSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final provider = context.read<NasProvider>();
      final api = FeiniuApi(provider);
      final backend = context.read<MediaBackendProvider>().backend;

      // 分类入口/概要走公共 MediaBackend。继续观看与分类条目按后端能力选源：飞牛走
      // FeiniuApi（保留续播进度等富字段），Emby 等走 backend（见 _loadContinueWatching /
      // _loadCategoryItems）。数据层分支，UI 渲染不感知后端类型。
      final parallelResults = await Future.wait([
        backend.getCatalogs(),
        backend.getHomeSummary(),
        _loadContinueWatching(backend, api),
      ]);
      final categories = (parallelResults[0] as List<MediaCatalog>)
          .map(_catalogToMediaItem)
          .toList();
      final summary = parallelResults[1] as Map<String, dynamic>;
      final playList = parallelResults[2] as List<MediaLibraryItem>;
      const localeMap = <String, dynamic>{};

      // Fetch all category items in parallel.
      final itemsByCategory = <String, List<MediaLibraryItem>>{};
      final allItems = <MediaLibraryItem>[];
      final categoryFutures = categories.map((category) async {
        try {
          final items = await _loadCategoryItems(backend, api, category.id);
          return (category.id, items);
        } catch (error) {
          debugPrint('[UI][HOME] category load failed ${category.id}: $error');
          return (category.id, <MediaLibraryItem>[]);
        }
      }).toList();
      final categoryResults = await Future.wait(categoryFutures);
      for (final (catId, items) in categoryResults) {
        itemsByCategory[catId] = items;
        allItems.addAll(items);
      }

      final continueWatching = playList.isNotEmpty
          ? playList.take(_continueLimit).toList()
          : _pickContinueWatching(allItems);

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _itemsByCategory = itemsByCategory;
        _continueWatching = continueWatching;
        _mediaSummary = summary;
        _localeMap = localeMap;
        _isLoading = false;
        _loadingFromCache = false;
        _error = null;
      });

      // Persist to cache（仅飞牛：HomeDataCache 是飞牛态缓存，Emby 数据不写入避免跨后端串内容）。
      if (backend.capabilities.kind == MediaBackendKind.feiniu) {
        unawaited(
          HomeDataCache.save(
            categories: categories,
            itemsByCategory: itemsByCategory,
            mediaSummary: summary,
            continueWatching: continueWatching,
          ),
        );
      }
    } catch (error) {
      debugPrint('[UI][HOME] load failed $error');
      if (!mounted) return;
      // If we have stale cache data, keep showing it.
      if (_loadingFromCache) return;
      setState(() {
        _error = AppException.from(
          error,
          action: 'home data',
          fallbackKind: AppExceptionKind.transient,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _backgroundRefresh() async {
    debugPrint('[UI][HOME] background refresh start');
    final provider = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    // 飞牛态需 NAS 已配置才刷新；Emby 等公共后端不依赖 NAS 会话。
    if (backend.capabilities.kind == MediaBackendKind.feiniu &&
        !provider.isConfigured) {
      return;
    }

    try {
      final api = FeiniuApi(provider);

      // 分类入口/概要走公共 MediaBackend；继续观看与分类条目按后端能力选源（同 _fetchHomeData）。
      final parallelResults = await Future.wait([
        backend.getCatalogs(),
        backend.getHomeSummary(),
        _loadContinueWatching(backend, api, forceRefresh: true),
      ]);
      final categories = (parallelResults[0] as List<MediaCatalog>)
          .map(_catalogToMediaItem)
          .toList();
      final summary = parallelResults[1] as Map<String, dynamic>;
      final playList = parallelResults[2] as List<MediaLibraryItem>;

      // Fetch all category items in parallel.
      final itemsByCategory = <String, List<MediaLibraryItem>>{};
      final allItems = <MediaLibraryItem>[];
      final categoryFutures = categories.map((category) async {
        try {
          final items = await _loadCategoryItems(backend, api, category.id);
          return (category.id, items);
        } catch (_) {
          return (category.id, <MediaLibraryItem>[]);
        }
      }).toList();
      final categoryResults = await Future.wait(categoryFutures);
      for (final (catId, items) in categoryResults) {
        itemsByCategory[catId] = items;
        allItems.addAll(items);
      }

      final continueWatching = playList.isNotEmpty
          ? playList.take(_continueLimit).toList()
          : _pickContinueWatching(allItems);

      if (!mounted) return;

      // Only update UI if data changed.
      final newSnapshot = HomeDataSnapshot(
        categories: categories,
        itemsByCategory: itemsByCategory,
        mediaSummary: summary,
        continueWatching: continueWatching,
        cachedAt: DateTime.now(),
      );

      final currentSnapshot = HomeDataSnapshot(
        categories: _categories,
        itemsByCategory: _itemsByCategory,
        mediaSummary: _mediaSummary,
        continueWatching: _continueWatching,
        cachedAt: DateTime.now(),
      );

      if (!newSnapshot.isSameAs(currentSnapshot)) {
        setState(() {
          _categories = categories;
          _itemsByCategory = itemsByCategory;
          _continueWatching = continueWatching;
          _mediaSummary = summary;
          _loadingFromCache = false;
        });
      } else {
        setState(() => _loadingFromCache = false);
      }

      // Always update cache with fresh data.
      unawaited(
        HomeDataCache.save(
          categories: categories,
          itemsByCategory: itemsByCategory,
          mediaSummary: summary,
          continueWatching: continueWatching,
        ),
      );
    } catch (error) {
      debugPrint('[UI][HOME] background refresh failed: $error');
      if (!mounted) return;
      setState(() => _loadingFromCache = false);
    }
  }

  Future<void> _refreshContinueWatching() async {
    final provider = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind == MediaBackendKind.feiniu &&
        !provider.isConfigured) {
      return;
    }

    try {
      final api = FeiniuApi(provider);
      final playList = await _loadContinueWatching(
        backend,
        api,
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _continueWatching = playList.take(_continueLimit).toList();
      });
    } catch (error) {
      debugPrint('[UI][HOME] continue watching refresh failed $error');
    }
  }

  void _showHomeSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    AppTopTip().show(
      context,
      message: message,
      color: backgroundColor ?? context.appColors.success,
    );
  }

  void _replaceItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _continueWatching = _continueWatching
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
      _itemsByCategory = _itemsByCategory.map((key, value) {
        return MapEntry(
          key,
          value
              .map((item) => item.guid == itemGuid ? transform(item) : item)
              .toList(growable: false),
        );
      });
    });
  }

  void _applyState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  List<MediaLibraryItem> _pickContinueWatching(List<MediaLibraryItem> items) {
    final watched =
        items
            .where(
              (item) => item.watched > 0 || item.watchedTs > 0 || item.ts > 0,
            )
            .toList()
          ..sort((a, b) => b.watchedTs.compareTo(a.watchedTs));

    if (watched.isNotEmpty) {
      return watched.take(_continueLimit).toList();
    }
    return items.take(_continueLimit).toList();
  }

  int _summaryInt(String key, int fallback) {
    final value = _mediaSummary[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return AppLocalizationLookup.text(
      AppLocalizations.of(context),
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: _t('auth.exit.title', 'Log out'),
      content: _t('auth.exit.content', 'Log out of the current account?'),
      cancelText: _t('common.actions.default.cancel', 'Cancel'),
      confirmText: _t('common.actions.default.default', 'Confirm'),
    );
    if (!mounted || !confirmed) return;
    await context.read<NasProvider>().logout();
  }

  void _openCategory(MediaItem category) {
    unawaited(_openCategoryAsync(category));
  }

  void _openAllItems() {
    unawaited(
      _openCategoryAsync(
        MediaItem(id: '', name: _t('layout.sidebar.allList', 'All media')),
      ),
    );
    return;
    // ignore: dead_code
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: MediaItem(
            id: '',
            name: _t('layout.sidebar.allList', 'All media'),
          ),
        ),
      ),
    );
  }

  void _openAllItemsByType(String title, List<String> types) {
    unawaited(
      _openCategoryAsync(
        MediaItem(id: '', name: title),
        initialTypeTags: types,
      ),
    );
    return;
    // ignore: dead_code
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: MediaItem(id: '', name: title),
          initialTypeTags: types,
        ),
      ),
    );
  }

  void _openFavorites() {
    unawaited(_openFavoritesAsync());
    return;
    // ignore: dead_code
    Navigator.of(
      context,
    ).push(AppTransitions.fadeSlideRoute(const FavoriteItemsScreen()));
  }

  Future<void> _openCategoryAsync(
    MediaItem category, {
    List<String>? initialTypeTags,
  }) async {
    if (await EmbeddedDetailLauncher.openCategory(
      context: context,
      category: category,
      initialTypeTags: initialTypeTags,
    )) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: category,
          initialTypeTags: initialTypeTags,
        ),
      ),
    );
  }

  Future<void> _openFavoritesAsync() async {
    if (await EmbeddedDetailLauncher.openFavorites(context: context)) {
      return;
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(AppTransitions.fadeSlideRoute(const FavoriteItemsScreen()));
  }

  Future<void> _openSearchAsync() async {
    if (await EmbeddedDetailLauncher.openSearch(context: context)) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(SearchScreen(initialLocaleMap: _localeMap)),
    );
  }

  Future<void> _openItemDetail(MediaLibraryItem item, {String? heroTag}) async {
    if (item.guid.trim().isEmpty) return;
    await AsyncActionGuard.run<void>(
      'media_list_detail:${item.type.trim().toLowerCase()}:${item.guid.trim()}',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        if (_isPersonItem(item)) {
          if (await EmbeddedDetailLauncher.openPersonDetail(
            context: context,
            personGuid: item.guid,
            initialName: item.displayTitle,
          )) {
            return;
          }
          if (!mounted) return;
          await Navigator.of(context).push(
            AppTransitions.leftToRightPageTurnRoute(
              PersonDetailScreen(
                personGuid: item.guid,
                initialName: item.displayTitle,
                initialLocaleMap: _localeMap,
              ),
            ),
          );
          return;
        }

        final navigator = Navigator.of(context);
        final provider = context.read<NasProvider>();
        final initialItemDetail = item.toJson();
        if (await EmbeddedDetailLauncher.openItemDetail(
          item.guid,
          context: context,
          initialItemDetail: initialItemDetail,
        )) {
          return;
        }
        if (!mounted) return;
        final warmupUrls = _posterCandidates(
          provider.baseUrl,
          item.poster.trim(),
          width: 560,
        );
        if (warmupUrls.isNotEmpty) {
          unawaited(
            precacheImage(
              NetworkImage(
                warmupUrls.first,
                headers: nasImageHeaders(provider.token, url: warmupUrls.first),
              ),
              navigator.context,
            ).timeout(const Duration(milliseconds: 140)).catchError((
              Object error,
              StackTrace stackTrace,
            ) {
              debugPrint(
                '[IMG][PRECACHE][HOME] failed url=${warmupUrls.first} error=$error',
              );
            }),
          );
        }

        if (!mounted) return;
        await navigator.push(
          AppTransitions.leftToRightPageTurnRoute(
            PlayDetailScreen(
              itemGuid: item.guid,
              heroTag: heroTag,
              initialItemDetail: initialItemDetail,
            ),
          ),
        );
        if (!mounted) return;
        unawaited(_refreshContinueWatching());
      },
    );
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  bool _isPersonItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  List<String> _posterCandidates(
    String baseUrl,
    String rawPath, {
    int width = 400,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _cardSubtitle(MediaLibraryItem item) {
    final start = item.firstAirDate.isNotEmpty
        ? item.firstAirDate
        : item.releaseDate;
    final startYear = _year(start);
    final endYear = _year(item.lastAirDate);
    final period =
        (startYear.isNotEmpty && endYear.isNotEmpty && endYear != startYear)
        ? '$startYear-$endYear'
        : startYear;

    final seasonCount = item.localNumberOfSeasons > 0
        ? item.localNumberOfSeasons
        : item.numberOfSeasons;
    final episodeCount = item.localNumberOfEpisodes > 0
        ? item.localNumberOfEpisodes
        : (item.numberOfEpisodes > 0
              ? item.numberOfEpisodes
              : item.episodeNumber);

    if (seasonCount == 1) {
      final episodes = episodeCount;
      if (episodes > 0) {
        final episodeText = _t(
          'layout.subheading.tv.episodes',
          '{count} episodes',
          params: <String, Object?>{'count': episodes},
        );
        if (period.isEmpty) return episodeText;
        return '$episodeText · $period';
      }
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '{count} seasons',
        params: <String, Object?>{'count': seasonCount},
      );
      if (period.isEmpty) return seasonText;
      return '$seasonText · $period';
    }
    return period;
  }

  String _resolutionLabel(String value) {
    final text = value.trim();
    final match = RegExp(
      r'^(\d{3,4})p$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return match.group(1) ?? text;
    return text;
  }

  String _episodeText(MediaLibraryItem item) {
    final season = item.seasonNumber > 0 ? item.seasonNumber : 1;
    final episode = item.episodeNumber > 0 ? item.episodeNumber : 1;
    final seasonText = _t(
      'layout.subheading.season.number',
      'Season {number}',
      params: <String, Object?>{'number': season},
    );
    final episodeText = _t(
      'layout.subheading.episode.number',
      'Episode {number}',
      params: <String, Object?>{'number': episode},
    );
    return '$seasonText · $episodeText';
  }

  String _continueEpisodeText(MediaLibraryItem item) {
    final episode = item.episodeNumber > 0 ? item.episodeNumber : 1;
    if (item.seasonNumber == 0) {
      final specialText = _t('layout.subheading.season.special', 'Special');
      final episodeText = _t(
        'layout.subheading.episode.number',
        'Episode {number}',
        params: <String, Object?>{'number': episode},
      );
      return '$specialText · $episodeText';
    }
    return _episodeText(item);
  }

  double _progressValue(MediaLibraryItem item) {
    if (item.duration <= 0) return 0;
    final watchedTs = item.ts > 0 ? item.ts : item.watchedTs;
    if (watchedTs <= 0) return 0;
    final raw = watchedTs / item.duration;
    return raw.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}
