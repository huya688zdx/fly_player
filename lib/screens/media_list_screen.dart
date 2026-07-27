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
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_catalog.dart';
import '../media_backend/media_item_card.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../providers/backend_session_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/home_data_cache.dart';
import '../services/session_exit_bridge.dart';
import '../services/parallel_browse_snapshot.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_hero_image.dart';
import '../ui/detail_theme_prewarmer.dart';
import '../ui/layout_adaptive.dart';
import '../ui/route_transition_gate.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/liquid_glass.dart';
import '../ui/detail_artwork_resolver.dart';
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

class _MediaListScreenState extends State<MediaListScreen>
    with WidgetsBindingObserver {
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

  // 仅当用户从本页打开过条目(可能已播放)后,回前台才刷新一次「继续观看」。避免每次 resume
  // 都拉取(用户要求:考虑性能、不要实时刷新)。打开条目时置位,刷新后清零。
  bool _pendingContinueWatchingRefresh = false;

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
    final loadKey = serverReady
        ? '${session.currentKind.name}|${connection?.serverUrl ?? ''}|${connection?.accessToken ?? ''}'
        : '${provider.baseUrl}|${provider.token}';
    if (loadKey != _lastLoadKey) {
      _lastLoadKey = loadKey;
      if (serverReady) {
        // 服务器族首页不读飞牛 HomeDataCache，避免跨后端串内容。
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
      // Refresh in background 鈥?update incrementally if changed.
      unawaited(_backgroundRefresh());
      return;
    }
    // No cache 鈥?full load with spinner.
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

  /// 缁х画瑙傜湅鏁版嵁婧愶細椋炵墰璧?FeiniuApi锛堜繚鐣欑画鎾繘搴?`ts`锛夛紝鍏跺畠鍏叡鍚庣锛圗mby锛夎蛋
  /// `backend.getContinueWatching`锛圼MediaItemCard]鈫抂MediaLibraryItem]锛岄鍏夐樁娈垫棤缁挱杩涘害锛夈€?
  /// 数据层按后端能力选源，UI 不写具体服务器后端判断。
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

  /// 鏌愬簱棰勮鏉＄洰鏁版嵁婧愶細椋炵墰璧?FeiniuApi锛屽叾瀹冨叕鍏卞悗绔蛋 `getCatalogPreviewItems`銆?
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

      // 鍒嗙被鍏ュ彛/姒傝璧板叕鍏?MediaBackend銆傜户缁鐪嬩笌鍒嗙被鏉＄洰鎸夊悗绔兘鍔涢€夋簮锛氶鐗涜蛋
      // FeiniuApi锛堜繚鐣欑画鎾繘搴︾瓑瀵屽瓧娈碉級锛孍mby 绛夎蛋 backend锛堣 _loadContinueWatching /
      // _loadCategoryItems锛夈€傛暟鎹眰鍒嗘敮锛孶I 娓叉煋涓嶆劅鐭ュ悗绔被鍨嬨€?
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

      final continueWatching = _resolveContinueWatching(
        backend,
        playList,
        allItems,
      );

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

      // Persist to cache锛堜粎椋炵墰锛欻omeDataCache 鏄鐗涙€佺紦瀛橈紝Emby 鏁版嵁涓嶅啓鍏ラ伩鍏嶈法鍚庣涓插唴瀹癸級銆?
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
    // 椋炵墰鎬侀渶 NAS 宸查厤缃墠鍒锋柊锛汦mby 绛夊叕鍏卞悗绔笉渚濊禆 NAS 浼氳瘽銆?
    if (backend.capabilities.kind == MediaBackendKind.feiniu &&
        !provider.isConfigured) {
      return;
    }

    try {
      final api = FeiniuApi(provider);

      // 鍒嗙被鍏ュ彛/姒傝璧板叕鍏?MediaBackend锛涚户缁鐪嬩笌鍒嗙被鏉＄洰鎸夊悗绔兘鍔涢€夋簮锛堝悓 _fetchHomeData锛夈€?
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

      final continueWatching = _resolveContinueWatching(
        backend,
        playList,
        allItems,
      );

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
      // 与 _fetchHomeData 一致:经 _resolveContinueWatching 统一(飞牛空时回退分类挑选,
      // Emby 等留空)。否则返回时刷新与初始加载口径不一致会导致续播区抖动/消失。
      final continueWatching = _resolveContinueWatching(
        backend,
        playList,
        _itemsByCategory.values
            .expand((items) => items)
            .toList(growable: false),
      );
      // push 返回的 Future 在 pop 动画第一帧前就 resolve，回包大概率落在
      // 380ms pop 转场里；等转场结束再应用，且列表未变化时不整页重建。
      await RouteTransitionGate.of(context);
      if (!mounted) return;
      if (HomeDataSnapshot.itemsEqual(_continueWatching, continueWatching)) {
        return;
      }
      setState(() {
        _continueWatching = continueWatching;
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
          );
          if (!mounted) return;
          final heroProvider = DetailHeroImage.directUrlPrecacheProvider(
            url: item.backdropUrl,
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
