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
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/home_catalog_presentation.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_catalog.dart';
import '../media_backend/media_image_ref.dart';
import '../media_backend/media_item_card.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../providers/backend_session_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/home_data_cache.dart';
import '../services/session_exit_bridge.dart';
import '../services/parallel_browse_snapshot.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/detail_hero_image.dart';
import '../ui/detail_theme_prewarmer.dart';
import '../ui/layout_adaptive.dart';
import '../ui/main_navigation_metrics.dart';
import '../ui/route_transition_gate.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_action_sheet.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/liquid_glass.dart';
import '../ui/detail_artwork_resolver.dart';
import 'category_items_screen.dart';
import 'favorite_items_screen.dart';
import 'home/continue_detail_target.dart';
import 'home/home_presentation_profile.dart';
import 'home/home_view_data.dart';
import 'home/widgets/home_catalog_section.dart';
import 'home/widgets/home_continue_watching_section.dart';
import 'home/widgets/home_landscape_media_section.dart';
import 'home/widgets/home_section_header.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'poster_browse/poster_browse_artwork_enricher.dart';
import 'poster_browse/poster_browse_artwork_prewarmer.dart';
import 'poster_browse/poster_browse_loader.dart';
import 'poster_browse/poster_browse_session_key.dart';
import 'search_screen.dart';
import '../widgets/app_atmospheric_background.dart';

part 'media_list_screen_actions.dart';
part 'media_list_screen_widgets.dart';

enum _ContinueWatchingAction {
  viewDetail,
  markWatched,
  favorite,
  restart,
  remove,
}

typedef _MediaItemsWithImages = ({
  List<MediaLibraryItem> items,
  Map<String, MediaImageRequest> imageRequests,
  Map<String, MediaImageRequest> backdropImageRequests,
});

const _MediaItemsWithImages _emptyMediaItemsWithImages = (
  items: <MediaLibraryItem>[],
  imageRequests: <String, MediaImageRequest>{},
  backdropImageRequests: <String, MediaImageRequest>{},
);

class MediaListScreen extends StatefulWidget {
  final bool secondaryHost;

  const MediaListScreen({super.key, this.secondaryHost = false});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen>
    with WidgetsBindingObserver {
  static const int _fallbackContinueLimit = 8;
  static const int _secondaryContinueLimit = 4;
  static const int _defaultCategoryPreviewLimit = 12;
  static const int _secondaryCategoryPreviewLimit = 8;

  HomeViewData _homeData = const HomeViewData.empty();
  String _homeDataLoadKey = '';
  final HomeLoadGeneration _homeLoadGeneration = HomeLoadGeneration();
  final HomeCacheWriteCoordinator _homeCacheWrites =
      HomeCacheWriteCoordinator();

  bool _isCurrentHomeLoad(int generation) =>
      mounted && _homeLoadGeneration.isCurrent(generation);

  int _beginHomeLoad() {
    final generation = _homeLoadGeneration.begin();
    _homeCacheWrites.advanceTo(generation);
    return generation;
  }

  void _invalidateHomeLoads() {
    final generation = _homeLoadGeneration.invalidate();
    _homeCacheWrites.advanceTo(generation);
  }

  List<MediaItem> get _categories => _homeData.catalogs;
  set _categories(List<MediaItem> value) {
    _homeData = _homeData.copyWith(catalogs: value);
  }

  Map<String, List<MediaLibraryItem>> get _itemsByCategory =>
      _homeData.catalogPreviewItems;
  set _itemsByCategory(Map<String, List<MediaLibraryItem>> value) {
    _homeData = _homeData.copyWith(catalogPreviewItems: value);
  }

  List<MediaLibraryItem> get _continueWatching => _homeData.continueWatching;
  set _continueWatching(List<MediaLibraryItem> value) {
    _homeData = _homeData.copyWith(continueWatching: value);
  }

  // 首页区块组件将在后续 UI 接线中直接读取该兼容入口。
  // ignore: unused_element
  List<MediaLibraryItem> get _nextUp => _homeData.nextUp;
  set _nextUp(List<MediaLibraryItem> value) {
    _homeData = _homeData.copyWith(nextUp: value);
  }

  // 首页区块组件将在后续 UI 接线中直接读取该兼容入口。
  // ignore: unused_element
  List<MediaLibraryItem> get _latest => _homeData.latest;
  set _latest(List<MediaLibraryItem> value) {
    _homeData = _homeData.copyWith(latest: value);
  }

  Map<String, dynamic> get _mediaSummary => _homeData.summary;
  set _mediaSummary(Map<String, dynamic> value) {
    _homeData = _homeData.copyWith(summary: value);
  }

  Map<String, List<MediaImageRequest>> get _catalogImageRequests =>
      _homeData.catalogImageRequests;
  set _catalogImageRequests(Map<String, List<MediaImageRequest>> value) {
    _homeData = _homeData.copyWith(catalogImageRequests: value);
  }

  Map<String, MediaImageRequest> get _itemImageRequests =>
      _homeData.itemImageRequests;
  set _itemImageRequests(Map<String, MediaImageRequest> value) {
    _homeData = _homeData.copyWith(itemImageRequests: value);
  }

  Map<String, MediaImageRequest> get _backdropImageRequests =>
      _homeData.backdropImageRequests;
  set _backdropImageRequests(Map<String, MediaImageRequest> value) {
    _homeData = _homeData.copyWith(backdropImageRequests: value);
  }

  Map<String, dynamic> _localeMap = <String, dynamic>{};
  String _lastLoadKey = '';

  bool _isLoading = false;
  bool _loadingFromCache = false;
  AppException? _error;

  // 仅当用户从本页打开过条目(可能已播放)后,回前台才刷新一次「继续观看」。避免每次 resume
  // 都拉取(用户要求:考虑性能、不要实时刷新)。打开条目时置位,刷新后清零。
  bool _pendingContinueWatchingRefresh = false;
  int _posterBrowsePrewarmGeneration = 0;

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
    WidgetsBinding.instance.addObserver(this);
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
    _invalidateHomeLoads();
    _posterBrowsePrewarmGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 回到前台时刷新「继续观看」:原生壳全屏播放/分屏退出后,首页引擎从 paused→resumed,
    // 而分屏/pane 流程没有 Navigator.push 返回点(那条路径才刷新),故此处兜底。
    // 性能:仅当本页确实打开过条目(_pendingContinueWatchingRefresh)且已加载过时刷一次,
    // 不做实时/每次 resume 刷新。
    if (state == AppLifecycleState.resumed &&
        _pendingContinueWatchingRefresh &&
        _lastLoadKey.isNotEmpty) {
      _pendingContinueWatchingRefresh = false;
      unawaited(_refreshContinueWatching());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NasProvider>();
    final session = context.read<BackendSessionProvider>();
    // 服务器族后端会话已认证即可加载；飞牛仍要求 NAS 已配置。
    final serverReady =
        session.currentKind.isServerFamily && session.isConfigured;
    if (!serverReady && !provider.isConfigured) {
      _invalidateHomeLoads();
      _lastLoadKey = '';
      _posterBrowsePrewarmGeneration += 1;
      _homeData = const HomeViewData.empty();
      _homeDataLoadKey = '';
      _localeMap = <String, dynamic>{};
      _error = null;
      _isLoading = false;
      _loadingFromCache = false;
      return;
    }
    final connection = session.currentConnection;
    final loadKey = serverReady
        ? '${session.currentKind.name}|${connection?.serverUrl ?? ''}|${connection?.accessToken ?? ''}'
        : '${provider.baseUrl}|${provider.token}';
    if (loadKey != _lastLoadKey) {
      _posterBrowsePrewarmGeneration += 1;
      _lastLoadKey = loadKey;
      if (_homeDataLoadKey != loadKey) {
        _homeData = const HomeViewData.empty();
        _homeDataLoadKey = loadKey;
      }
      if (serverReady) {
        // 服务器族首页不读飞牛 HomeDataCache，避免跨后端串内容。
        _fetchHomeData();
      } else {
        _tryLoadFromCacheThenRefresh();
      }
    }
  }

  Future<void> _tryLoadFromCacheThenRefresh() async {
    final loadGeneration = _beginHomeLoad();
    final loadKey = _lastLoadKey;
    final snapshot = await HomeDataCache.load();
    if (!_isCurrentHomeLoad(loadGeneration)) return;
    if (snapshot != null && snapshot.categories.isNotEmpty) {
      setState(() {
        _categories = snapshot.categories;
        _itemsByCategory = snapshot.itemsByCategory;
        _catalogImageRequests = <String, List<MediaImageRequest>>{};
        _itemImageRequests = <String, MediaImageRequest>{};
        _backdropImageRequests = <String, MediaImageRequest>{};
        _mediaSummary = snapshot.mediaSummary;
        _continueWatching = snapshot.continueWatching;
        _nextUp = <MediaLibraryItem>[];
        _latest = <MediaLibraryItem>[];
        _homeDataLoadKey = loadKey;
        _loadingFromCache = true;
        _isLoading = false;
        _error = null;
      });
      // Refresh in background 鈥?update incrementally if changed.
      unawaited(_backgroundRefresh());
      return;
    }
    // No cache 鈥?full load with spinner.
    if (!_isCurrentHomeLoad(loadGeneration)) return;
    _fetchHomeData();
  }

  // 杩囨浮鏈熸湰鍦拌浆鎹細鎶婂叕鍏?[MediaCatalog] 杩樺師鎴愰椤电幇鏈?UI 浣跨敤鐨?[MediaItem]銆?
  // 浠呴檺鏈枃浠讹紝涓嶆墿鏁ｏ紱寰呮暣椤佃縼绉诲埌鍏叡妯″瀷鍚庣Щ闄ゃ€俻osters/path 瀹屾暣淇濈暀锛?
  // 淇濊瘉鍒嗙被鏉＄缉鐣ュ浘涓庤縼绉诲墠涓€鑷淬€?
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

  /// 鍏叡 [MediaItemCard] 鈫?棣栭〉鐢?[MediaLibraryItem]锛堜粎闈為鐗涘悗绔蛋姝よ浆鎹紝鍠傞椤电幇鏈?
  /// `MediaLibraryItem` 娓叉煋锛夈€傜画鎾繘搴?`ts`/`watchedTs` 涓嶅湪鍗＄墖妯″瀷锛岄鍏夐樁娈电疆 0銆?
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
      // 续看进度位 → watchedTs（首页继续观看进度条数据源 _progressValue）。
      watchedTs: card.resumePositionSeconds,
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
      // 单集卡片携带系列 guid 作祖先：「继续观看」单集点进时据此打开系列 TV 详情（有选集）。
      ancestorGuid: card.seriesId,
      ancestorName: card.secondaryTitle,
      path: card.primaryImage.url,
      resolutions: card.resolutions,
      // 保留 backdrop 直链：点击时 push 前预取详情 hero（与详情页同 URL 同缓存键）。
      backdropUrl: card.backdropImage.url,
    );
  }

  static List<MediaImageRequest> _requestsForRefs(
    DetailArtworkResolver resolver,
    Iterable<MediaImageRef> refs, {
    required int width,
  }) {
    return refs
        .map((ref) => resolver.resolveRef(ref, width: width))
        .where((request) => request.isNotEmpty)
        .toList(growable: false);
  }

  static _MediaItemsWithImages _cardsToMediaItems(
    DetailArtworkResolver resolver,
    Iterable<MediaItemCard> cards,
  ) {
    final items = <MediaLibraryItem>[];
    final imageRequests = <String, MediaImageRequest>{};
    final backdropImageRequests = <String, MediaImageRequest>{};
    for (final card in cards) {
      items.add(_cardToMediaItem(card));
      final request = resolver.resolveRefs(<MediaImageRef>[
        card.primaryImage,
        ...card.posters,
      ]);
      if (request.isNotEmpty) {
        imageRequests[card.id] = request;
      }
      final backdropRequest = resolver.resolveRef(card.backdropImage);
      if (backdropRequest.isNotEmpty) {
        backdropImageRequests[card.id] = backdropRequest;
      }
    }
    return (
      items: items,
      imageRequests: imageRequests,
      backdropImageRequests: backdropImageRequests,
    );
  }

  void _scheduleHomeCacheSave(int generation, HomeViewData data) {
    unawaited(
      _homeCacheWrites.schedule(
        generation: generation,
        canWrite: () => _isCurrentHomeLoad(generation),
        write: () => HomeDataCache.save(
          categories: data.catalogs,
          itemsByCategory: data.catalogPreviewItems,
          mediaSummary: data.summary,
          continueWatching: data.continueWatching,
        ),
      ),
    );
  }

  /// 继续观看数据源：飞牛走 FeiniuApi，其它公共后端走 backend。
  Future<_MediaItemsWithImages> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api,
    DetailArtworkResolver resolver, {
    bool forceRefresh = false,
    ValueChanged<List<MediaItemCard>>? onCardsLoaded,
  }) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      final items = await api.getPlayList(forceRefresh: forceRefresh);
      onCardsLoaded?.call(
        items.map(cardFromLibraryItem).toList(growable: false),
      );
      return (
        items: items,
        imageRequests: const <String, MediaImageRequest>{},
        backdropImageRequests: const <String, MediaImageRequest>{},
      );
    }
    final cards = await backend.getContinueWatching(forceRefresh: forceRefresh);
    onCardsLoaded?.call(cards);
    return _cardsToMediaItems(resolver, cards);
  }

  Future<HomeSectionLoadResult<List<MediaItemCard>>> _loadOptionalCards(
    String label,
    Future<List<MediaItemCard>> Function() loader,
  ) async {
    try {
      return HomeSectionLoadResult<List<MediaItemCard>>.success(await loader());
    } catch (error, stackTrace) {
      debugPrint(
        '[UI][HOME] optional section failed $label: $error\n$stackTrace',
      );
      await logSwallowedError(
        action: 'optional section failed $label',
        error: error,
        stackTrace: stackTrace,
        source: 'home',
      );
      return const HomeSectionLoadResult<List<MediaItemCard>>.failure();
    }
  }

  Future<HomeSectionLoadResult<_MediaItemsWithImages>>
  _loadContinueWatchingSafely(
    MediaBackend backend,
    FeiniuApi api,
    DetailArtworkResolver resolver, {
    bool forceRefresh = false,
    ValueChanged<List<MediaItemCard>>? onCardsLoaded,
  }) async {
    try {
      return HomeSectionLoadResult<_MediaItemsWithImages>.success(
        await _loadContinueWatching(
          backend,
          api,
          resolver,
          forceRefresh: forceRefresh,
          onCardsLoaded: onCardsLoaded,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[UI][HOME] optional section failed continueWatching: '
        '$error\n$stackTrace',
      );
      await logSwallowedError(
        action: 'optional section failed continueWatching',
        error: error,
        stackTrace: stackTrace,
        source: 'home',
      );
      return const HomeSectionLoadResult<_MediaItemsWithImages>.failure();
    }
  }

  /// 某库预览条目数据源：飞牛走 FeiniuApi，其它公共后端走 backend。
  Future<_MediaItemsWithImages> _loadCategoryItems(
    MediaBackend backend,
    FeiniuApi api,
    DetailArtworkResolver resolver,
    String catalogId,
  ) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return (
        items: await api.getItemsByCategoryGuid(
          catalogId,
          page: 1,
          limit: _categoryPreviewLimit,
        ),
        imageRequests: const <String, MediaImageRequest>{},
        backdropImageRequests: const <String, MediaImageRequest>{},
      );
    }
    final cards = await backend.getCatalogPreviewItems(
      catalogId,
      limit: _categoryPreviewLimit,
    );
    return _cardsToMediaItems(resolver, cards);
  }

  Future<void> _fetchHomeData() async {
    final loadGeneration = _beginHomeLoad();
    final loadKey = _lastLoadKey;
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
      final imageCredentials = mediaImageCredentialsForBackend(
        backendKind: backend.capabilities.kind,
        token: provider.token,
        accessCode: provider.accessCode,
        baseUrl: provider.baseUrl,
      );
      final resolver = DetailArtworkResolver(
        baseUrl: imageCredentials.baseUrl,
        token: imageCredentials.token,
        accessCode: imageCredentials.accessCode,
      );
      final profile = HomePresentationProfile.forCapabilities(
        backend.capabilities,
      );
      final needsNextUp = profile.sectionOrder.contains(HomeSectionKind.nextUp);
      final needsLatest = profile.sectionOrder.contains(HomeSectionKind.latest);

      // 鍒嗙被鍏ュ彛/姒傝璧板叕鍏?MediaBackend銆傜户缁鐪嬩笌鍒嗙被鏉＄洰鎸夊悗绔兘鍔涢€夋簮锛氶鐗涜蛋
      // FeiniuApi锛堜繚鐣欑画鎾繘搴︾瓑瀵屽瓧娈碉級锛孍mby 绛夎蛋 backend锛堣 _loadContinueWatching /
      // _loadCategoryItems锛夈€傛暟鎹眰鍒嗘敮锛孶I 娓叉煋涓嶆劅鐭ュ悗绔被鍨嬨€?
      final parallelResults = await Future.wait([
        backend.getCatalogs(),
        backend.getHomeSummary(),
        _loadContinueWatchingSafely(
          backend,
          api,
          resolver,
          onCardsLoaded: (cards) {
            if (!_isCurrentHomeLoad(loadGeneration)) return;
            unawaited(
              _prewarmPosterBrowseArtwork(
                backend: backend,
                nas: provider,
                cards: cards,
              ),
            );
          },
        ),
        needsNextUp
            ? _loadOptionalCards(
                'nextUp',
                () => backend.getNextUpItems(limit: 8),
              )
            : Future<HomeSectionLoadResult<List<MediaItemCard>>>.value(
                const HomeSectionLoadResult<List<MediaItemCard>>.success(
                  <MediaItemCard>[],
                ),
              ),
        needsLatest
            ? _loadOptionalCards(
                'latest',
                () => backend.getLatestItems(limit: 12),
              )
            : Future<HomeSectionLoadResult<List<MediaItemCard>>>.value(
                const HomeSectionLoadResult<List<MediaItemCard>>.success(
                  <MediaItemCard>[],
                ),
              ),
      ]);
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      final rawCatalogs = parallelResults[0] as List<MediaCatalog>;
      final categories = rawCatalogs.map(_catalogToMediaItem).toList();
      final catalogImageRequests = <String, List<MediaImageRequest>>{
        for (final catalog in rawCatalogs)
          catalog.id: _requestsForRefs(
            resolver,
            catalog.posters.isNotEmpty
                ? catalog.posters
                : <MediaImageRef>[catalog.primaryImage],
            width: MediaLayoutProfile.homeCatalogRequestWidthValue,
          ),
      };
      final summary = parallelResults[1] as Map<String, dynamic>;
      final playListLoad =
          parallelResults[2] as HomeSectionLoadResult<_MediaItemsWithImages>;
      final playListResult = playListLoad.valueOr(_emptyMediaItemsWithImages);
      final playList = playListResult.items;
      final nextUpLoad =
          parallelResults[3] as HomeSectionLoadResult<List<MediaItemCard>>;
      final latestLoad =
          parallelResults[4] as HomeSectionLoadResult<List<MediaItemCard>>;
      final nextUpResult = _cardsToMediaItems(
        resolver,
        nextUpLoad.valueOr(const <MediaItemCard>[]),
      );
      final latestResult = _cardsToMediaItems(
        resolver,
        latestLoad.valueOr(const <MediaItemCard>[]),
      );
      const localeMap = <String, dynamic>{};

      // Fetch all category items in parallel.
      final itemsByCategory = <String, List<MediaLibraryItem>>{};
      final itemImageRequests = <String, MediaImageRequest>{};
      final backdropImageRequests = <String, MediaImageRequest>{};
      final allItems = <MediaLibraryItem>[];
      final categoryFutures = categories.map((category) async {
        try {
          final result = await _loadCategoryItems(
            backend,
            api,
            resolver,
            category.id,
          );
          return (category.id, result);
        } catch (error) {
          debugPrint('[UI][HOME] category load failed ${category.id}: $error');
          return (
            category.id,
            (
              items: <MediaLibraryItem>[],
              imageRequests: <String, MediaImageRequest>{},
              backdropImageRequests: <String, MediaImageRequest>{},
            ),
          );
        }
      }).toList();
      final categoryResults = await Future.wait(categoryFutures);
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      for (final (catId, result) in categoryResults) {
        itemsByCategory[catId] = result.items;
        allItems.addAll(result.items);
        itemImageRequests.addAll(result.imageRequests);
        backdropImageRequests.addAll(result.backdropImageRequests);
      }

      final continueSection = playListLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: _resolveContinueWatching(backend, playList, allItems),
                imageRequests: playListResult.imageRequests,
                backdropImageRequests: playListResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final nextUpSection = nextUpLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: nextUpResult.items,
                imageRequests: nextUpResult.imageRequests,
                backdropImageRequests: nextUpResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final latestSection = latestLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: latestResult.items,
                imageRequests: latestResult.imageRequests,
                backdropImageRequests: latestResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final homeData = mergeHomeOptionalSections(
        current: homeDataFallbackForLoadKey(
          snapshot: _homeData,
          snapshotLoadKey: _homeDataLoadKey,
          requestLoadKey: loadKey,
        ),
        refreshedBase: HomeViewData(
          catalogs: categories,
          catalogPreviewItems: itemsByCategory,
          summary: summary,
          catalogImageRequests: catalogImageRequests,
          itemImageRequests: itemImageRequests,
          backdropImageRequests: backdropImageRequests,
        ),
        continueWatching: continueSection,
        nextUp: nextUpSection,
        latest: latestSection,
      );

      if (!_isCurrentHomeLoad(loadGeneration)) return;
      setState(() {
        _homeData = homeData;
        _homeDataLoadKey = loadKey;
        _localeMap = localeMap;
        _isLoading = false;
        _loadingFromCache = false;
        _error = null;
      });

      if (playListLoad.isSuccess &&
          playList.isEmpty &&
          homeData.continueWatching.isNotEmpty) {
        if (!_isCurrentHomeLoad(loadGeneration)) return;
        unawaited(
          _prewarmPosterBrowseArtwork(
            backend: backend,
            nas: provider,
            cards: homeData.continueWatching
                .map(cardFromLibraryItem)
                .toList(growable: false),
          ),
        );
      }

      // Persist to cache锛堜粎椋炵墰锛欻omeDataCache 鏄鐗涙€佺紦瀛橈紝Emby 鏁版嵁涓嶅啓鍏ラ伩鍏嶈法鍚庣涓插唴瀹癸級銆?
      if (backend.capabilities.kind == MediaBackendKind.feiniu) {
        if (!_isCurrentHomeLoad(loadGeneration)) return;
        _scheduleHomeCacheSave(loadGeneration, homeData);
      }
    } catch (error) {
      debugPrint('[UI][HOME] load failed $error');
      if (!_isCurrentHomeLoad(loadGeneration)) return;
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
    final loadGeneration = _beginHomeLoad();
    final loadKey = _lastLoadKey;
    debugPrint('[UI][HOME] background refresh start');
    final provider = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    // 椋炵墰鎬侀渶 NAS 宸查厤缃墠鍒锋柊锛汦mby 绛夊叕鍏卞悗绔笉渚濊禆 NAS 浼氳瘽銆?
    if (backend.capabilities.kind == MediaBackendKind.feiniu &&
        !provider.isConfigured) {
      return;
    }

    try {
      final api = FeiniuApi(provider);
      final imageCredentials = mediaImageCredentialsForBackend(
        backendKind: backend.capabilities.kind,
        token: provider.token,
        accessCode: provider.accessCode,
        baseUrl: provider.baseUrl,
      );
      final resolver = DetailArtworkResolver(
        baseUrl: imageCredentials.baseUrl,
        token: imageCredentials.token,
        accessCode: imageCredentials.accessCode,
      );

      // 鍒嗙被鍏ュ彛/姒傝璧板叕鍏?MediaBackend锛涚户缁鐪嬩笌鍒嗙被鏉＄洰鎸夊悗绔兘鍔涢€夋簮锛堝悓 _fetchHomeData锛夈€?
      final profile = HomePresentationProfile.forCapabilities(
        backend.capabilities,
      );
      final needsNextUp = profile.sectionOrder.contains(HomeSectionKind.nextUp);
      final needsLatest = profile.sectionOrder.contains(HomeSectionKind.latest);
      final parallelResults = await Future.wait([
        backend.getCatalogs(),
        backend.getHomeSummary(),
        _loadContinueWatchingSafely(
          backend,
          api,
          resolver,
          forceRefresh: true,
          onCardsLoaded: (cards) {
            if (!_isCurrentHomeLoad(loadGeneration)) return;
            unawaited(
              _prewarmPosterBrowseArtwork(
                backend: backend,
                nas: provider,
                cards: cards,
              ),
            );
          },
        ),
        needsNextUp
            ? _loadOptionalCards(
                'nextUp',
                () => backend.getNextUpItems(limit: 8),
              )
            : Future<HomeSectionLoadResult<List<MediaItemCard>>>.value(
                const HomeSectionLoadResult<List<MediaItemCard>>.success(
                  <MediaItemCard>[],
                ),
              ),
        needsLatest
            ? _loadOptionalCards(
                'latest',
                () => backend.getLatestItems(limit: 12),
              )
            : Future<HomeSectionLoadResult<List<MediaItemCard>>>.value(
                const HomeSectionLoadResult<List<MediaItemCard>>.success(
                  <MediaItemCard>[],
                ),
              ),
      ]);
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      final rawCatalogs = parallelResults[0] as List<MediaCatalog>;
      final categories = rawCatalogs.map(_catalogToMediaItem).toList();
      final catalogImageRequests = <String, List<MediaImageRequest>>{
        for (final catalog in rawCatalogs)
          catalog.id: _requestsForRefs(
            resolver,
            catalog.posters.isNotEmpty
                ? catalog.posters
                : <MediaImageRef>[catalog.primaryImage],
            width: MediaLayoutProfile.homeCatalogRequestWidthValue,
          ),
      };
      final summary = parallelResults[1] as Map<String, dynamic>;
      final playListLoad =
          parallelResults[2] as HomeSectionLoadResult<_MediaItemsWithImages>;
      final playListResult = playListLoad.valueOr(_emptyMediaItemsWithImages);
      final playList = playListResult.items;
      final nextUpLoad =
          parallelResults[3] as HomeSectionLoadResult<List<MediaItemCard>>;
      final latestLoad =
          parallelResults[4] as HomeSectionLoadResult<List<MediaItemCard>>;
      final nextUpResult = _cardsToMediaItems(
        resolver,
        nextUpLoad.valueOr(const <MediaItemCard>[]),
      );
      final latestResult = _cardsToMediaItems(
        resolver,
        latestLoad.valueOr(const <MediaItemCard>[]),
      );

      // Fetch all category items in parallel.
      final itemsByCategory = <String, List<MediaLibraryItem>>{};
      final itemImageRequests = <String, MediaImageRequest>{};
      final backdropImageRequests = <String, MediaImageRequest>{};
      final allItems = <MediaLibraryItem>[];
      final categoryFutures = categories.map((category) async {
        try {
          final result = await _loadCategoryItems(
            backend,
            api,
            resolver,
            category.id,
          );
          return (category.id, result);
        } catch (_) {
          return (
            category.id,
            (
              items: <MediaLibraryItem>[],
              imageRequests: <String, MediaImageRequest>{},
              backdropImageRequests: <String, MediaImageRequest>{},
            ),
          );
        }
      }).toList();
      final categoryResults = await Future.wait(categoryFutures);
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      for (final (catId, result) in categoryResults) {
        itemsByCategory[catId] = result.items;
        allItems.addAll(result.items);
        itemImageRequests.addAll(result.imageRequests);
        backdropImageRequests.addAll(result.backdropImageRequests);
      }

      final continueSection = playListLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: _resolveContinueWatching(backend, playList, allItems),
                imageRequests: playListResult.imageRequests,
                backdropImageRequests: playListResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final nextUpSection = nextUpLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: nextUpResult.items,
                imageRequests: nextUpResult.imageRequests,
                backdropImageRequests: nextUpResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final latestSection = latestLoad.isSuccess
          ? HomeSectionLoadResult<HomeMediaSectionData>.success(
              HomeMediaSectionData(
                items: latestResult.items,
                imageRequests: latestResult.imageRequests,
                backdropImageRequests: latestResult.backdropImageRequests,
              ),
            )
          : const HomeSectionLoadResult<HomeMediaSectionData>.failure();
      final homeData = mergeHomeOptionalSections(
        current: homeDataFallbackForLoadKey(
          snapshot: _homeData,
          snapshotLoadKey: _homeDataLoadKey,
          requestLoadKey: loadKey,
        ),
        refreshedBase: HomeViewData(
          catalogs: categories,
          catalogPreviewItems: itemsByCategory,
          summary: summary,
          catalogImageRequests: catalogImageRequests,
          itemImageRequests: itemImageRequests,
          backdropImageRequests: backdropImageRequests,
        ),
        continueWatching: continueSection,
        nextUp: nextUpSection,
        latest: latestSection,
      );

      if (!_isCurrentHomeLoad(loadGeneration)) return;
      setState(() {
        _homeData = homeData;
        _homeDataLoadKey = loadKey;
        _loadingFromCache = false;
      });

      if (playListLoad.isSuccess &&
          playList.isEmpty &&
          homeData.continueWatching.isNotEmpty) {
        if (!_isCurrentHomeLoad(loadGeneration)) return;
        unawaited(
          _prewarmPosterBrowseArtwork(
            backend: backend,
            nas: provider,
            cards: homeData.continueWatching
                .map(cardFromLibraryItem)
                .toList(growable: false),
          ),
        );
      }

      // Always update cache with fresh data.
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      _scheduleHomeCacheSave(loadGeneration, homeData);
    } catch (error) {
      debugPrint('[UI][HOME] background refresh failed: $error');
      if (!_isCurrentHomeLoad(loadGeneration)) return;
      setState(() => _loadingFromCache = false);
    }
  }

  Future<void> _refreshContinueWatching() async {
    final refreshLoadKey = _lastLoadKey;
    final provider = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind == MediaBackendKind.feiniu &&
        !provider.isConfigured) {
      return;
    }

    try {
      final api = FeiniuApi(provider);
      final imageCredentials = mediaImageCredentialsForBackend(
        backendKind: backend.capabilities.kind,
        token: provider.token,
        accessCode: provider.accessCode,
        baseUrl: provider.baseUrl,
      );
      final resolver = DetailArtworkResolver(
        baseUrl: imageCredentials.baseUrl,
        token: imageCredentials.token,
        accessCode: imageCredentials.accessCode,
      );
      final playListResult = await _loadContinueWatching(
        backend,
        api,
        resolver,
        forceRefresh: true,
        onCardsLoaded: (cards) {
          if (!mounted || refreshLoadKey != _lastLoadKey) return;
          unawaited(
            _prewarmPosterBrowseArtwork(
              backend: backend,
              nas: provider,
              cards: cards,
            ),
          );
        },
      );
      if (!mounted || refreshLoadKey != _lastLoadKey) return;
      // 与 _fetchHomeData 一致:经 _resolveContinueWatching 统一(飞牛空时回退分类挑选,
      // Emby 等留空)。否则返回时刷新与初始加载口径不一致会导致续播区抖动/消失。
      final continueWatching = _resolveContinueWatching(
        backend,
        playListResult.items,
        _itemsByCategory.values
            .expand((items) => items)
            .toList(growable: false),
      );
      // push 返回的 Future 在 pop 动画第一帧前就 resolve，回包大概率落在
      // 380ms pop 转场里；等转场结束再应用，且列表未变化时不整页重建。
      await RouteTransitionGate.of(context);
      if (!mounted || refreshLoadKey != _lastLoadKey) return;
      final oldContinueIds = _continueWatching.map((item) => item.guid).toSet();
      final itemsUnchanged = HomeDataSnapshot.itemsEqual(
        _continueWatching,
        continueWatching,
      );
      var itemImageRequests = _itemImageRequests;
      var backdropImageRequests = _backdropImageRequests;
      if (backend.capabilities.kind.isServerFamily) {
        itemImageRequests = Map<String, MediaImageRequest>.of(
          _itemImageRequests,
        );
        backdropImageRequests = Map<String, MediaImageRequest>.of(
          _backdropImageRequests,
        );
        for (final id in oldContinueIds) {
          itemImageRequests.remove(id);
          backdropImageRequests.remove(id);
        }
        itemImageRequests.addAll(playListResult.imageRequests);
        backdropImageRequests.addAll(playListResult.backdropImageRequests);
      }
      setState(() {
        _homeData = _homeData.copyWith(
          continueWatching: itemsUnchanged
              ? _continueWatching
              : continueWatching,
          itemImageRequests: itemImageRequests,
          backdropImageRequests: backdropImageRequests,
        );
      });
      if (playListResult.items.isEmpty && continueWatching.isNotEmpty) {
        unawaited(
          _prewarmPosterBrowseArtwork(
            backend: backend,
            nas: provider,
            cards: continueWatching
                .map(cardFromLibraryItem)
                .toList(growable: false),
          ),
        );
      }
    } catch (error) {
      debugPrint('[UI][HOME] continue watching refresh failed $error');
    }
  }

  Future<void> _prewarmPosterBrowseArtwork({
    required MediaBackend backend,
    required NasProvider nas,
    required List<MediaItemCard> cards,
  }) async {
    if (cards.isEmpty || !mounted) return;
    final size = MediaQuery.sizeOf(context);
    final visibleCount = PosterBrowseInitialArtworkPolicy.visibleCountFor(
      width: size.width,
      height: size.height,
    );
    final centerIndex = PosterBrowseInitialArtworkPolicy.centerIndexFor(
      width: size.width,
      height: size.height,
    );
    final backendSession = context.read<BackendSessionProvider>();
    final connection = backendSession.currentConnection;
    final sessionKey = buildPosterBrowseBackendSessionKey(
      backendKind: backend.capabilities.kind,
      nasBaseUrl: nas.baseUrl,
      nasToken: nas.token,
      serverBaseUrl: connection?.serverUrl ?? '',
      serverToken: connection?.accessToken ?? '',
    );
    final generation = _posterBrowsePrewarmGeneration + 1;
    _posterBrowsePrewarmGeneration = generation;
    final enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: sessionKey,
      maxEntries: 4,
    );

    await PosterBrowseArtworkPrewarmCache.shared.warmFirst(
      sessionKey: sessionKey,
      items: cards,
      centerIndex: centerIndex,
      limit: visibleCount,
      maxConcurrent: 1,
      load: enricher.enrich,
      isActive: () => mounted && generation == _posterBrowsePrewarmGeneration,
    );
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

  /// 统一计算首页「继续观看」列表（初始 / 后台刷新 / 返回刷新三处同口径）。
  ///
  /// 续播列表（飞牛 `getPlayList` / 其它后端 `getContinueWatching`）非空时直接取前 N。
  /// 为空时**仅飞牛**回退到从分类条目挑选——飞牛分类条目带 `ts`/`watchedTs` 进度，回退合理；
  /// Emby 等公共后端的分类条目无进度，回退会把片库前几个当“在看”并把竖版海报塞进横版卡，
  /// 故留空（无真实续播即隐藏该区）。数据层按 backend kind 分支，UI 不写具体服务器后端判断。
  List<MediaLibraryItem> _resolveContinueWatching(
    MediaBackend backend,
    List<MediaLibraryItem> playList,
    List<MediaLibraryItem> allItems,
  ) {
    if (playList.isNotEmpty) {
      return playList.take(_continueLimit).toList();
    }
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return _pickContinueWatching(allItems);
    }
    return const <MediaLibraryItem>[];
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

  Future<void> _confirmLogout() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppLocalizations.of(context).authExitTitle,
      content: AppLocalizations.of(context).authExitContent,
      cancelText: AppLocalizations.of(context).commonCancel,
      confirmText: AppLocalizations.of(context).commonConfirm,
    );
    if (!mounted || !confirmed) return;
    final session = context.read<BackendSessionProvider>();
    if (session.currentKind.isServerFamily) {
      final serverConnection = session.currentConnection;
      if (serverConnection != null) {
        await session.saveConnection(
          MediaBackendConnection(
            kind: serverConnection.kind,
            serverUrl: serverConnection.serverUrl,
            displayName: serverConnection.displayName,
            userName: serverConnection.userName,
            secret: serverConnection.rememberSecret
                ? serverConnection.secret
                : '',
            rememberSecret: serverConnection.rememberSecret,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
      // 退出服务器族：清掉 token / userId，保留服务器、用户名和已记住的密码。
      await session.saveActive(
        const MediaBackendConnection(
          kind: MediaBackendKind.feiniu,
          serverUrl: '',
        ),
      );
      // 与飞牛登出一致：重置分屏副栏 UI，避免退出后右侧仍停留在已登录详情（左右双登录）。
      await SessionExitBridge.logoutAndResetParallelUi();
      return;
    }
    await context.read<NasProvider>().logout();
  }

  void _openCategory(MediaItem category) {
    unawaited(_openCategoryAsync(category));
  }

  void _openAllItems() {
    unawaited(
      _openCategoryAsync(
        MediaItem(
          id: '',
          name: AppLocalizations.of(context).mediaAllItemsTitle,
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
  }

  void _openFavorites() {
    unawaited(_openFavoritesAsync());
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
    // 打开非人物条目可能进入播放;标记回前台时刷新一次「继续观看」(人物页不涉及进度)。
    if (!_isPersonItem(item)) {
      _pendingContinueWatchingRefresh = true;
    }
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

        // 闈為鐗涘悗绔紙褰撳墠涓?Emby锛夛細澶嶇敤鐪熻鎯呴〉 PlayDetailScreen锛堝叕鏈夊寲鈥斺€斿墠绔叡鐢ㄥ悓涓€椤碉紝
        // 椤甸潰鍐呮寜 backend 鑳藉姏璇讳腑绔?MediaDetail 娓叉煋锛夈€傛寜 backend 鑳藉姏鍦ㄥ鑸眰鍒嗘敮锛岄潪 UI
        // 不写具体服务器后端判断；存在分屏 pane host 时经 EmbeddedDetailLauncher 在 pane 内打开。
        // 锛堜笌椋炵墰鍒嗗睆涓€鑷?涓?pane 鍦ㄥ綋鍓嶅凡灏辩华寮曟搸銆佹湁 Emby 浼氳瘽锛?鍚﹀垯鍏ㄥ睆 Navigator.push銆?
        // 涓嶈蛋鍘熺敓鐙珛寮曟搸(DetailActivity)璺緞鈥斺€斿叾浼氳瘽寮傛鍔犺浇鏈夌珵鎬併€佸彲鑳借鍒ら鐗涖€?
        final backend = context.read<MediaBackendProvider>().backend;
        if (backend.capabilities.kind != MediaBackendKind.feiniu) {
          // 与飞牛一致:无条件经 EmbeddedDetailLauncher 打开——存在 pane host 则在 pane 内,
          // 否则走原生 openItemDetail 通道(分屏/平行窗口)。副引擎会话竞态已由 _load 的
          // BackendSessionProvider.ensureReady 兜底(等会话就绪再读后端,不会误判飞牛)。
          final handled = await EmbeddedDetailLauncher.openItemDetail(
            item.guid,
            context: context,
          );
          if (!mounted) return;
          if (handled) {
            unawaited(_refreshContinueWatching());
            return;
          }
          // 原生/分屏不可用(如非 Android、无平行窗口能力)时回退全屏 Navigator.push。
          final neutralNavigator = Navigator.of(context);
          // push 前预热目标页取色 scheme + 提前应用全局主题 + 预取 hero backdrop
          // 直链（与详情页背景组件同 URL 即同缓存键；URL 自带 api_key）。
          // await：push 同步置起转场计数，晚于它的主题发布会被推迟到转场后。
          await DetailThemePrewarmer.warmUp(
            context,
            pageKey: item.guid,
            imageUrl: item.backdropUrl.trim().isNotEmpty
                ? item.backdropUrl
                : item.poster,
            imageHeaders:
                _backdropImageRequests[item.guid]?.headers ??
                const <String, String>{},
          );
          if (!mounted) return;
          // 服务器族 backdropUrl 是完整自鉴权直链;经统一入口包成请求(token 传空,
          // 与旧 directUrlPrecacheProvider 不带 header 的行为一致)。
          final heroImages = preferPreservedImageRequest(
            preserved: _backdropImageRequests[item.guid],
            fallbackUrls: item.backdropUrl.trim().isNotEmpty
                ? <String>[item.backdropUrl.trim()]
                : const <String>[],
            fallbackToken: '',
            fallbackAccessCode: '',
            fallbackBaseUrl: '',
          );
          final heroProvider = DetailHeroImage.precacheProvider(
            images: heroImages,
            screenWidth: MediaQuery.of(context).size.width,
            devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
          );
          if (heroProvider != null) {
            unawaited(
              precacheImage(
                heroProvider,
                neutralNavigator.context,
              ).catchError((_) {}),
            );
          }
          await neutralNavigator.push(
            AppTransitions.leftToRightPageTurnRoute(
              PlayDetailScreen(itemGuid: item.guid, heroTag: heroTag),
            ),
          );
          if (!mounted) return;
          unawaited(_refreshContinueWatching());
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
        final warmupImages = mediaImageRequestForUrls(
          _posterCandidates(provider.baseUrl, item.poster.trim(), width: 560),
          token: provider.token,
          accessCode: provider.accessCode,
          baseUrl: provider.baseUrl,
        );
        final warmupUrls = warmupImages.urls;
        if (warmupUrls.isNotEmpty) {
          unawaited(
            precacheImage(
              NetworkImage(warmupUrls.first, headers: warmupImages.headers),
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
        // push 前预热目标页取色 scheme + 提前应用全局主题（seed 命中缓存时详情
        // 首帧免 HCT 冷跑，转场里两页已是目标配色）。await 原因见 prewarmer 注释。
        await DetailThemePrewarmer.warmUp(context, pageKey: item.guid);
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

  /// 从首页继续观看卡直接恢复播放，返回首页后只刷新续看区块。
  Future<void> _playContinueItem(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) return;
    _pendingContinueWatchingRefresh = true;
    try {
      await const ItemPlaybackLauncher().open(
        context,
        itemGuid: item.guid,
        fallbackTitle: item.displayTitle,
      );
    } catch (error, stackTrace) {
      _pendingContinueWatchingRefresh = false;
      await logSwallowedError(
        action: 'play continue watching item',
        error: error,
        stackTrace: stackTrace,
        source: 'media_list_screen',
        id: item.guid,
      );
      if (!mounted) return;
      _showHomeSnackBar(
        AppLocalizations.of(context).detailPlayInfoFailed,
        backgroundColor: context.appColors.danger,
      );
    }
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
        final episodeText = AppLocalizations.of(
          context,
        ).detailEpisodeTotal(episodes);
        if (period.isEmpty) return episodeText;
        return '$episodeText · $period';
      }
    }
    if (seasonCount > 0) {
      final seasonText = AppLocalizations.of(
        context,
      ).detailTvSeasonCount(seasonCount);
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
    final seasonText = AppLocalizations.of(context).detailSeasonNumber(season);
    final episodeText = AppLocalizations.of(
      context,
    ).detailEpisodeNumber(episode);
    return '$seasonText · $episodeText';
  }

  String _continueEpisodeText(MediaLibraryItem item) {
    final episode = item.episodeNumber > 0 ? item.episodeNumber : 1;
    if (item.seasonNumber == 0) {
      final specialText = AppLocalizations.of(context).detailSeasonSpecial;
      final episodeText = AppLocalizations.of(
        context,
      ).detailEpisodeNumber(episode);
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
