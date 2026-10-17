import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../api/item_list_request.dart';
import '../controllers/item_playback_launcher.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/filter/media_catalog_filter.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_item_card.dart';
import '../providers/media_backend_provider.dart';
import '../models/media_collection_view_type.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../models/stream_list_option.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/detail_presentation.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/route_transition_gate.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_catalog_query_sheets.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/bird_loader.dart';
import '../widgets/common/liquid_glass.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import '../widgets/detail/detail_status_page.dart';
import '../desktop/desktop_environment.dart';
import '../desktop/desktop_hover_dropdown.dart';
import '../widgets/common/track_option_sheet.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/play_control_row.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import '../widgets/library/media_collection_browser.dart';
import '../widgets/library/media_collection_layout_sheet.dart';

/// 一页子项的加载结果。
///
/// - [items]：可直接渲染的条目（飞牛侧已过 [_MediaCollectionDetailPageState._filterItems]）；
/// - [raw] / [total]：服务器原样返回的行与总数，供分页累计与 hasMore 判定；
/// - [paginated]：false 表示这批数据来自 playInfo / streamList 兜底——那类没有服务端
///   分页，不能再续拉。
typedef _CollectionItemsPage = ({
  List<MediaLibraryItem> items,
  List<MediaLibraryItem> raw,
  int total,
  bool paginated,
});

class MediaCollectionDetailPage extends StatefulWidget {
  final String itemGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;
  final DetailPresentation presentation;

  const MediaCollectionDetailPage({
    super.key,
    required this.itemGuid,
    this.heroTag,
    this.initialItemDetail,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<MediaCollectionDetailPage> createState() =>
      _MediaCollectionDetailPageState();
}

class _MediaCollectionDetailPageState extends State<MediaCollectionDetailPage> {
  static const List<String> _sortColumns = <String>[
    'create_time',
    'release_date',
    'title',
    'vote_average',
  ];

  final ScrollController _scrollController = ScrollController();
  final DetailTopTip _topTip = DetailTopTip();
  // 路由门锚点：build 根无条件包 RouteGateAnchor(key: _gateKey)，_ModalScopeStatus
  // 依赖只落在锚点叶子 element，弹窗开/关不再触发整页重建。存 final 字段：setState
  // 重建与热重载都保留锚点 State；本页全部 gate 调用点共用同一 key。
  final GlobalKey<RouteGateAnchorState> _gateKey =
      GlobalKey<RouteGateAnchorState>();

  bool get _isPane => widget.presentation == DetailPresentation.pane;

  /// 飞牛走自有 FeiniuApi 完整路径（列表偏好 / PlayInfo 兜底）；非飞牛（Emby 等）复用本页
  /// 渲染，数据层走中立 getItemDetail + queryChildItems，隐藏飞牛专属能力。
  bool get _isFeiniuBackend =>
      context.read<MediaBackendProvider>().backend.capabilities.kind ==
      MediaBackendKind.feiniu;

  Map<String, dynamic> _detail = const <String, dynamic>{};
  List<MediaLibraryItem> _allItems = const <MediaLibraryItem>[];
  List<MediaLibraryItem> _items = const <MediaLibraryItem>[];
  bool _loading = true;
  AppException? _error;
  bool _liked = false;
  bool _watched = false;
  bool _favoriteUpdating = false;
  bool _watchedUpdating = false;
  String _sortColumn = 'create_time';
  String _sortType = 'DESC';
  String _settingsMdbGuid = '';
  MediaCollectionViewType _viewType = MediaCollectionViewType.list;
  String? _selectedResolutionFilter;
  int? _selectedWatchedFilter;

  /// 单页条数。
  ///
  /// 原实现首页固定一次拉 500 条（`page:1, page_size:500`）且**没有下一页**：第 501 条起
  /// 静默不可达（实测某个库该口径下 total=1317，即大半内容翻不到）。
  /// 50 对齐本项目其它列表的口径（`CategoryItemsScreen._pageSize`、`ItemListRequest.pageSize`
  /// 默认值都是 50）。
  static const int _pageSize = 50;
  static const double _loadMoreTriggerOffset = 400;

  /// 视口没填满时最多自动续拉几页。`mediadb` 的 4 类查询里季目录会被 [_filterItems]
  /// 丢掉（实测过滤比约 2:1），单页可见条目可能很少甚至为 0——若不自动续拉，用户会
  /// 卡在寥寥几条且滚不动。设上限防跑飞。
  static const int _maxAutoFillPages = 3;

  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  String? _loadMoreError;

  /// 服务器原样返回的行（未过 [_filterItems]）。分页累计与 hasMore 判定都基于它——
  /// [_filterItems] 会按 parent_guid 丢掉非顶层行，用它算会误判「还有更多」。
  List<MediaLibraryItem> _rawItems = const <MediaLibraryItem>[];

  /// 首次加载代次；换排序 / 换筛选时自增，用于丢弃过期的分页响应。
  int _itemLoadSeq = 0;

  /// 本次首屏已自动续拉的页数（上限 [_maxAutoFillPages]）。
  int _autoFillPages = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialItemDetail != null) {
      _applyDetail(widget.initialItemDetail!);
    }
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _topTip.dispose();
    super.dispose();
  }

  void _applyDetail(Map<String, dynamic> detail) {
    _detail = detail;
    _liked = _intValue(detail['is_favorite']) == 1;
    _watched = _intValue(detail['is_watched']) == 1;
    _settingsMdbGuid = _resolveSettingsMdbGuid(detail);
  }

  /// 统一入口。锚点已挂载（正常路径）：经叶子句柄等待，页根不注册任何依赖。
  /// 锚点未挂载（首帧竞态等不应发生的路径）：兜底走旧 API 保语义不破，且必须
  /// 留下全模式可观测痕迹（docs/plans/route-gate-popup-jank-fix.md §3.4/§3.5）。
  Future<void> _waitOwnTransition() {
    final gate = _gateKey.currentState;
    if (gate != null) {
      return gate.waitTransition();
    }
    // 兜底被触发的瞬间，页根 element 会经 of(context) 重新注册 _ModalScopeStatus
    // 依赖，整页重建无声复活——该痕迹不能只放在 assert 里（profile/release 零输出）。
    // logSwallowedError 无 debug 门控、落盘可导出，可从导出日志核对兜底是否触发过。
    unawaited(
      logSwallowedError(
        action: 'route gate anchor missing',
        error: StateError(
          'RouteGateAnchor 未挂载，回退 RouteTransitionGate.of；'
          '请确认锚点无条件包裹页面根',
        ),
        stackTrace: StackTrace.current,
        source: 'route_transition_gate',
      ),
    );
    assert(() {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'RouteGateAnchor 未挂载，回退 RouteTransitionGate.of',
          ),
          library: 'fly_play',
          context: ErrorDescription('while waiting route transition'),
        ),
      );
      return true;
    }());
    return RouteTransitionGate.of(context);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!_isFeiniuBackend) {
      // 非飞牛(Emby 合集 BoxSet):中立详情 + 子项查询,不走飞牛列表偏好/PlayInfo 兜底。
      try {
        final backend = context.read<MediaBackendProvider>().backend;
        final neutral = await backend.getItemDetail(widget.itemGuid);
        final items = await _loadNeutralItems(
          backend,
          sortColumn: _sortColumn,
          sortType: _sortType,
        );
        if (!mounted) return;
        await _waitOwnTransition();
        if (!mounted) return;
        _itemLoadSeq++;
        _autoFillPages = 0;
        setState(() {
          _applyDetail(_neutralDetailToMap(neutral));
          _rawItems = items.raw;
          _currentPage = 1;
          _hasMore = items.paginated && items.raw.length < items.total;
          _loadMoreError = null;
          _isLoadingMore = false;
          _allItems = items.items;
          _items = _applyLocalFilters(items.items);
          _loading = false;
        });
        _scheduleAutoFill();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = AppException.from(
            e,
            action: 'media collection detail',
            fallbackKind: AppExceptionKind.transient,
          );
          _loading = false;
        });
      }
      return;
    }
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail =
          widget.initialItemDetail ?? await api.getItemDetail(widget.itemGuid);
      final settingsMdbGuid = _resolveSettingsMdbGuid(detail);
      final setting = settingsMdbGuid.isNotEmpty
          ? await api.getUserListSetting(settingsMdbGuid)
          : null;
      final items = await _loadItems(
        api,
        detail: detail,
        sortColumn: _normalizeSortColumn(setting?.sortField),
        sortType: _normalizeSortType(setting?.sortType),
      );
      if (!mounted) return;
      // 把"骨架→正文"整树替换推迟到转场结束后，避免落在 380ms 转场窗口中段。
      await _waitOwnTransition();
      if (!mounted) return;
      _itemLoadSeq++;
      _autoFillPages = 0;
      setState(() {
        _applyDetail(detail);
        _rawItems = items.raw;
        _currentPage = 1;
        _hasMore = items.paginated && items.raw.length < items.total;
        _loadMoreError = null;
        // 代次已变时在途的续拉会提前 return，这里把加载态一并复位，避免页脚转圈卡住。
        _isLoadingMore = false;
        _allItems = items.items;
        _items = _applyLocalFilters(items.items);
        _sortColumn = _normalizeSortColumn(setting?.sortField);
        _sortType = _normalizeSortType(setting?.sortType);
        _viewType = MediaCollectionViewTypeX.fromStorage(
          setting?.viewType ?? 'list',
        );
        _loading = false;
      });
      _scheduleAutoFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'media collection detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  /// 中立详情 → 本页沿用的飞牛详情 map 形状（仅本页实际消费的键）。type 为中立小写类型
  /// （boxset），不落入 mediadb / directory 的飞牛专属分支。
  Map<String, dynamic> _neutralDetailToMap(MediaDetail detail) {
    return <String, dynamic>{
      'guid': detail.id,
      'title': detail.displayTitle,
      'type': detail.type.trim().toLowerCase(),
      'is_favorite': detail.favorite ? 1 : 0,
      'is_watched': detail.watched ? 1 : 0,
    };
  }

  /// 中立后端（Emby 合集 BoxSet）的一页子项。与 [_fetchItemPage] 同形，供分页共用。
  ///
  /// Emby 的 `queryChildItems` 本身就分页（`startIndex` / `limit`，并回 `totalRecordCount`），
  /// 所以这里可以安全地按 [_pageSize] 取，不会截断。
  Future<({List<MediaLibraryItem> items, int total})> _fetchNeutralItemPage(
    MediaBackend backend, {
    required String sortColumn,
    required String sortType,
    required int page,
  }) async {
    final result = await backend.queryChildItems(
      MediaCatalogQuery(
        catalogId: widget.itemGuid,
        sortField: sortColumn,
        sortType: sortType,
        page: page,
        pageSize: _pageSize,
      ),
    );
    return (
      items: result.items.map(_cardToLibraryItem).toList(growable: false),
      total: result.total,
    );
  }

  /// 中立侧首页加载。中立后端没有兜底源，恒可分页。
  Future<_CollectionItemsPage> _loadNeutralItems(
    MediaBackend backend, {
    required String sortColumn,
    required String sortType,
  }) async {
    final page = await _fetchNeutralItemPage(
      backend,
      sortColumn: sortColumn,
      sortType: sortType,
      page: 1,
    );
    return (
      items: page.items,
      raw: page.items,
      total: page.total,
      paginated: true,
    );
  }

  /// 非飞牛子项卡 → 飞牛列表模型的临时桥接,复用本页整套渲染（列表 / 网格 / 长按），与收藏页
  /// 同款。待合集页渲染层迁公共卡片后移除。
  MediaLibraryItem _cardToLibraryItem(MediaItemCard card) {
    return MediaLibraryItem(
      guid: card.id,
      title: card.title,
      tvTitle: card.secondaryTitle,
      type: card.type,
      poster: card.primaryImage.url,
      posterWidth: card.posterWidth,
      posterHeight: card.posterHeight,
      posterList: card.posters
          .map((ref) => ref.url)
          .where((url) => url.trim().isNotEmpty)
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
      ancestorGuid: card.seriesId,
      ancestorName: '',
      path: '',
      resolutions: card.resolutions,
      backdropUrl: card.backdropImage.url,
    );
  }

  /// 拉一页**原始行**（未过 [_filterItems]），并回传服务器 total 供分页判定。
  Future<({List<MediaLibraryItem> items, int total})> _fetchItemPage(
    FeiniuApi api, {
    required Map<String, dynamic> detail,
    required String sortColumn,
    required String sortType,
    required int page,
  }) async {
    final queryPayload = _buildItemListPayload(
      detail,
      sortColumn: sortColumn,
      sortType: sortType,
      page: page,
    );
    if (queryPayload == null) {
      return (items: const <MediaLibraryItem>[], total: 0);
    }
    final result = await api.getItemsPage(queryPayload);
    return (items: result.items, total: result.total);
  }

  /// 飞牛侧首页加载。
  ///
  /// [raw] / [total] 供分页累计；[paginated] 为 false 表示这批数据来自
  /// playInfo / streamList 兜底——那类数据没有服务端分页，不能再续拉。
  Future<_CollectionItemsPage> _loadItems(
    FeiniuApi api, {
    required Map<String, dynamic> detail,
    required String sortColumn,
    required String sortType,
  }) async {
    final page = await _fetchItemPage(
      api,
      detail: detail,
      sortColumn: sortColumn,
      sortType: sortType,
      page: 1,
    );
    final filtered = _filterItems(page.items, detail);
    if (filtered.isNotEmpty) {
      return (
        items: filtered,
        raw: page.items,
        total: page.total,
        paginated: true,
      );
    }
    final currentGuid = (detail['guid'] ?? '').toString().trim();
    if (currentGuid.isNotEmpty) {
      final playInfoItems = await _buildFallbackItemsFromPlayInfo(
        api,
        currentGuid,
        detail: detail,
      );
      if (playInfoItems.isNotEmpty) {
        return (
          items: playInfoItems,
          raw: const <MediaLibraryItem>[],
          total: playInfoItems.length,
          paginated: false,
        );
      }
    }
    final playItemGuid = (detail['play_item_guid'] ?? '').toString().trim();
    if (playItemGuid.isEmpty) {
      // 本页没有可显示的顶层行，但服务端可能还有后续页（例如 mediadb 首页整页
      // 都是会被 _filterItems 丢掉的季目录）——保留分页，让滚动继续拉。
      return (
        items: filtered,
        raw: page.items,
        total: page.total,
        paginated: true,
      );
    }
    return (
      items: await _buildFallbackItemsFromStreamList(api, playItemGuid),
      raw: const <MediaLibraryItem>[],
      total: 0,
      paginated: false,
    );
  }

  /// 滚动续拉下一页。
  void _onScroll() {
    // _loadMoreError 存在时不自动重试：留给页脚的重试按钮，避免反复打服务端。
    if (!_hasMore ||
        _isLoadingMore ||
        _loading ||
        _error != null ||
        _loadMoreError != null ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= _loadMoreTriggerOffset) {
      unawaited(_loadMoreItems());
    }
  }

  /// 首屏 / 续拉之后，若视口还没填满而服务端仍有数据，再补一页。
  void _scheduleAutoFill() {
    if (!_hasMore) return;
    // 上限只在「已经显示出内容」时生效。mediadb 的前几页可能整页都是会被 _filterItems
    // 丢掉的季目录，此时可见列表为空、内容也短于视口没有滚动事件——卡在上限会让页面
    // 永远空着且无法触发续拉。空结果时一直补到出现可见条目或服务端翻完为止。
    if (_items.isNotEmpty && _autoFillPages >= _maxAutoFillPages) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_hasMore ||
          _isLoadingMore ||
          _loading ||
          _loadMoreError != null ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > _loadMoreTriggerOffset) {
        return;
      }
      if (_items.isNotEmpty) _autoFillPages++;
      unawaited(_loadMoreItems());
    });
  }

  Future<void> _loadMoreItems() async {
    if (!mounted || !_hasMore || _isLoadingMore || _loading) return;
    final seq = _itemLoadSeq;
    final nextPage = _currentPage + 1;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final isFeiniu = _isFeiniuBackend;
      final nas = isFeiniu ? context.read<NasProvider>() : null;
      final backend = isFeiniu
          ? null
          : context.read<MediaBackendProvider>().backend;
      final next = isFeiniu
          ? await _fetchItemPage(
              FeiniuApi(nas!),
              detail: _detail,
              sortColumn: _sortColumn,
              sortType: _sortType,
              page: nextPage,
            )
          : await _fetchNeutralItemPage(
              backend!,
              sortColumn: _sortColumn,
              sortType: _sortType,
              page: nextPage,
            );
      if (!mounted || seq != _itemLoadSeq) return;
      final merged = <MediaLibraryItem>[..._rawItems, ...next.items];
      setState(() {
        _rawItems = merged;
        _currentPage = nextPage;
        _hasMore = next.items.isNotEmpty && merged.length < next.total;
        // 中立分支的 items 已是可直接渲染的条目，_filterItems 对飞牛详情 map 才生效。
        _allItems = _isFeiniuBackend ? _filterItems(merged, _detail) : merged;
        _items = _applyLocalFilters(_allItems);
        _isLoadingMore = false;
      });
      _scheduleAutoFill();
    } catch (error, stackTrace) {
      if (!mounted || seq != _itemLoadSeq) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = AppException.from(
          error,
          action: 'media collection load more',
          fallbackKind: AppExceptionKind.transient,
        ).message;
      });
      await logSwallowedError(
        action: 'media collection load more',
        id: widget.itemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'media_collection_detail_page',
      );
    }
  }

  Future<List<MediaLibraryItem>> _buildFallbackItemsFromPlayInfo(
    FeiniuApi api,
    String itemGuid, {
    required Map<String, dynamic> detail,
  }) async {
    try {
      final playInfo = await api.getPlayInfo(itemGuid);
      final baseItem = _mediaLibraryItemFromPlayInfo(playInfo, detail: detail);
      if (baseItem.guid.trim().isEmpty) {
        return const <MediaLibraryItem>[];
      }
      return _buildFallbackItemsFromStreamList(
        api,
        baseItem.guid,
        baseItem: baseItem,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load collection fallback play info',
        id: itemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'media_collection_detail_page',
      );
      return const <MediaLibraryItem>[];
    }
  }

  Future<List<MediaLibraryItem>> _buildFallbackItemsFromStreamList(
    FeiniuApi api,
    String playItemGuid, {
    MediaLibraryItem? baseItem,
  }) async {
    try {
      final resolvedBaseItem =
          baseItem ??
          MediaLibraryItem.fromJson(await api.getItemDetail(playItemGuid));
      final trackData = await api.getStreamTrackData(playItemGuid);
      final optionsByMediaGuid = <String, StreamListOption>{
        for (final option in trackData.options) option.mediaGuid: option,
      };
      final fallbackItems = <MediaLibraryItem>[];
      for (final entry in trackData.fileByMediaGuid.entries) {
        final file = entry.value;
        final option = optionsByMediaGuid[entry.key];
        final video = trackData.videoForMedia(entry.key);
        final resolutions = <String>{
          if (option != null && option.resolutionType.trim().isNotEmpty)
            option.resolutionType.trim(),
          if (video != null && video.resolutionType.trim().isNotEmpty)
            video.resolutionType.trim(),
        }.toList(growable: false);
        fallbackItems.add(
          resolvedBaseItem.copyWith(
            title: file.fileName.trim().isNotEmpty
                ? file.fileName.trim()
                : resolvedBaseItem.title,
            path: file.path.trim().isNotEmpty
                ? file.path.trim()
                : resolvedBaseItem.path,
            duration: option?.duration ?? resolvedBaseItem.duration,
            resolutions: resolutions.isNotEmpty
                ? resolutions
                : resolvedBaseItem.resolutions,
          ),
        );
      }
      if (fallbackItems.isNotEmpty) {
        return fallbackItems;
      }
      return <MediaLibraryItem>[resolvedBaseItem];
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load collection fallback stream list',
        id: playItemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'media_collection_detail_page',
      );
      return const <MediaLibraryItem>[];
    }
  }

  MediaLibraryItem _mediaLibraryItemFromPlayInfo(
    PlayInfoData playInfo, {
    required Map<String, dynamic> detail,
  }) {
    final item = playInfo.item;
    return MediaLibraryItem(
      guid: item.guid,
      title: item.title,
      tvTitle: item.tvTitle,
      type: item.type,
      poster: item.posters.trim().isNotEmpty
          ? item.posters.trim()
          : item.stillPath.trim(),
      releaseDate: item.releaseDate.trim().isNotEmpty
          ? item.releaseDate
          : item.airDate,
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: item.voteAverage,
      overview: item.overview,
      watched: item.isWatched,
      watchedTs: item.watchedTs,
      ts: playInfo.ts,
      duration: item.duration > 0 ? item.duration : item.runtime,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      numberOfSeasons: item.numberOfSeasons,
      numberOfEpisodes: item.numberOfEpisodes,
      localNumberOfSeasons: item.localNumberOfSeasons,
      localNumberOfEpisodes: item.localNumberOfEpisodes,
      parentGuid: playInfo.parentGuid,
      parentTitle: item.parentTitle,
      ancestorGuid: (detail['ancestor_guid'] ?? '').toString(),
      ancestorName: item.ancestorName,
      path: '',
      resolutions: item.resolutions,
    );
  }

  List<MediaLibraryItem> _filterItems(
    List<MediaLibraryItem> items,
    Map<String, dynamic> detail,
  ) {
    final type = _detailType(detail);
    final guid = (detail['guid'] ?? '').toString().trim();
    if (type == 'mediadb') {
      return items
          .where((item) => item.parentGuid.trim().isEmpty)
          .toList(growable: false);
    }
    if (type == 'directory') {
      return items
          .where((item) => item.parentGuid.trim() == guid)
          .toList(growable: false);
    }
    return items;
  }

  Map<String, dynamic>? _buildItemListPayload(
    Map<String, dynamic> detail, {
    required String sortColumn,
    required String sortType,
    required int page,
  }) {
    final type = _detailType(detail);
    if (type == 'directory') {
      final parentGuid = (detail['guid'] ?? '').toString().trim();
      if (parentGuid.isEmpty) {
        return null;
      }
      // 目录的直接子项可能是季 / 集（Season / Episode），所以这里**不能**锁类型，
      // 靠 parent_guid 收窄即可（实测锁成 Movie/TV/Directory/Video 会把这些子项滤掉）。
      return <String, dynamic>{
        'parent_guid': parentGuid,
        'page': page,
        'page_size': _pageSize,
        'sort_column': sortColumn,
        'sort_type': sortType,
        'tags': const <String, dynamic>{},
      };
    }

    final ancestorGuid = _resolveQueryAncestorGuid(detail);
    if (ancestorGuid.isEmpty) {
      return null;
    }
    // 注意 ancestor_guid 是**递归含后代**的（实测：库 guid 能查到其下 TV + Season +
    // Episode）。类型锁保留 Directory——部分库的顶层就是一个目录，滤掉会让页面空掉。
    return ItemListRequest(
      ancestorGuid: ancestorGuid,
      page: page,
      pageSize: _pageSize,
      sortColumn: sortColumn,
      sortType: sortType,
      tags: const <String, dynamic>{
        'type': <String>['Movie', 'TV', 'Directory', 'Video'],
      },
    ).toJson();
  }

  String _detailType(Map<String, dynamic> detail) {
    return (detail['type'] ?? '').toString().trim().toLowerCase();
  }

  String _resolveQueryAncestorGuid(Map<String, dynamic> detail) {
    if (_detailType(detail) == 'mediadb') {
      return (detail['guid'] ?? '').toString().trim();
    }
    return (detail['ancestor_guid'] ?? '').toString().trim();
  }

  String _resolveSettingsMdbGuid(Map<String, dynamic> detail) {
    if (_detailType(detail) == 'mediadb') {
      return (detail['guid'] ?? '').toString().trim();
    }
    return (detail['ancestor_guid'] ?? '').toString().trim();
  }

  String _normalizeSortColumn(String? value) {
    final normalized = (value ?? '').trim();
    return _sortColumns.contains(normalized) ? normalized : 'create_time';
  }

  String _normalizeSortType(String? value) {
    return (value ?? '').toUpperCase() == 'ASC' ? 'ASC' : 'DESC';
  }

  int _intValue(dynamic value) => int.tryParse('$value') ?? 0;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  String _crumbText() {
    final ancestor = (_detail['ancestor_name'] ?? '').toString().trim();
    if (ancestor.isNotEmpty) {
      return ancestor;
    }
    return (_detail['parent_title'] ?? '').toString().trim();
  }

  String _secondaryLine() {
    final type = _detailType(_detail);
    if (type == 'directory') {
      return _l10n.resourceTypeDirectory;
    }
    if (type == 'mediadb') {
      final category = (_detail['ancestor_category'] ?? '').toString().trim();
      return category.isNotEmpty ? category : _l10n.mediaLibraryFallbackName;
    }
    return '';
  }

  MediaLibraryItem? _primaryPlayableItem() {
    final type = _detailType(_detail);
    if (type == 'boxset') {
      // Emby 合集：成员即影片/剧集本身,主播放键起播首个成员（剧集在 _playPrimary 里
      // 先解析续看/首集）。
      return _items.isNotEmpty ? _items.first : null;
    }
    if (type == 'directory') {
      for (final item in _items) {
        if (item.type.trim().toLowerCase() == 'video') {
          return item;
        }
      }
      return null;
    }
    if (type == 'mediadb') {
      for (final item in _items) {
        final lower = item.type.trim().toLowerCase();
        if (lower == 'directory' || lower == 'video') {
          return item;
        }
      }
    }
    return null;
  }

  String _primaryText() {
    final item = _primaryPlayableItem();
    if (item == null) {
      return _l10n.detailPlay;
    }
    return item.ts > 0 || item.watchedTs > 0
        ? _l10n.detailContinuePlay
        : _l10n.detailPlay;
  }

  Future<void> _playPrimary() async {
    final item = _primaryPlayableItem();
    if (item == null || item.guid.trim().isEmpty) {
      return;
    }
    try {
      var targetGuid = item.guid;
      final lower = item.type.trim().toLowerCase();
      if (!_isFeiniuBackend && (lower == 'series' || lower == 'tv')) {
        // 系列不可直接起播（无 MediaSources）：先解析续看/首集再进播放入口。
        final resolved = await context
            .read<MediaBackendProvider>()
            .backend
            .resolveSeriesPlaybackTarget(item.guid);
        if (resolved.trim().isEmpty) {
          return;
        }
        targetGuid = resolved.trim();
      }
      if (!mounted) return;
      await const ItemPlaybackLauncher().open(
        context,
        itemGuid: targetGuid,
        fallbackTitle: item.displayTitle,
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorTopTip(
        AppException.from(
          e,
          action: 'play collection',
          fallbackKind: AppExceptionKind.transient,
        ).message,
      );
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteUpdating) {
      return;
    }
    final guid = (_detail['guid'] ?? '').toString().trim();
    if (guid.isEmpty) {
      return;
    }
    setState(() => _favoriteUpdating = true);
    final nas = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    try {
      final next = _isFeiniuBackend
          ? await FeiniuApi(nas).setFavorite(guid, favorite: !_liked)
          : await backend.setItemFavorite(guid, favorite: !_liked);
      if (!mounted) return;
      setState(() {
        _liked = next;
        _favoriteUpdating = false;
      });
      _topTip.show(
        context,
        message: next ? _l10n.actionFavoriteAdded : _l10n.actionFavoriteRemoved,
        color: const Color(0xFF166534),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _favoriteUpdating = false);
      _showErrorTopTip(
        AppException.from(
          e,
          action: 'favorite collection',
          fallbackKind: AppExceptionKind.transient,
        ).message,
      );
    }
  }

  Future<void> _toggleWatched() async {
    if (_watchedUpdating) {
      return;
    }
    final guid = (_detail['guid'] ?? '').toString().trim();
    if (guid.isEmpty) {
      return;
    }
    setState(() => _watchedUpdating = true);
    final nas = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    try {
      final next = _isFeiniuBackend
          ? await FeiniuApi(nas).setWatched(guid, watched: !_watched)
          : await backend.setItemWatched(guid, watched: !_watched);
      if (!mounted) return;
      setState(() {
        _watched = next;
        _watchedUpdating = false;
      });
      _topTip.show(
        context,
        message: next
            ? _l10n.actionMarkedAsWatched
            : _l10n.actionMarkedAsUnwatched,
        color: const Color(0xFF166534),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _watchedUpdating = false);
      _showErrorTopTip(
        AppException.from(
          e,
          action: 'watch collection',
          fallbackKind: AppExceptionKind.transient,
        ).message,
      );
    }
  }

  Future<void> _changeSort(String column, String sortType) async {
    setState(() {
      _sortColumn = column;
      _sortType = sortType;
    });
    // 立刻作废在途的分页请求：否则旧排序的第 N 页可能在下面的偏好写入 / 首页重取期间
    // 完成并通过代次校验，把旧排序的行追加进来；若重取随后失败，这些行会留在新排序下。
    _itemLoadSeq++;
    if (_settingsMdbGuid.isNotEmpty) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        _settingsMdbGuid,
        sortField: column,
        sortType: sortType,
        viewType: _viewType.storageValue,
      );
    }
    await _reloadItemsOnly();
  }

  /// 换排序 / 换筛选后重取首页。分页状态一并复位（旧排序的后续页不再有效）。
  Future<void> _reloadItemsOnly() async {
    // 在**发起请求之前**作废在途分页：等新首页回来再自增，会让旧排序 / 旧筛选的第 N 页
    // 在等待期间通过代次校验并追加进来；若重取随后失败，这些过期行会留在新状态下面。
    _itemLoadSeq++;
    _autoFillPages = 0;
    final nas = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    try {
      if (!_isFeiniuBackend) {
        final items = await _loadNeutralItems(
          backend,
          sortColumn: _sortColumn,
          sortType: _sortType,
        );
        if (!mounted) return;
        setState(() {
          _rawItems = items.raw;
          _currentPage = 1;
          _hasMore = items.paginated && items.raw.length < items.total;
          _loadMoreError = null;
          _isLoadingMore = false;
          _allItems = items.items;
          _items = _applyLocalFilters(items.items);
        });
        _scheduleAutoFill();
        return;
      }
      final items = await _loadItems(
        FeiniuApi(nas),
        detail: _detail,
        sortColumn: _sortColumn,
        sortType: _sortType,
      );
      if (!mounted) return;
      setState(() {
        _rawItems = items.raw;
        _currentPage = 1;
        _hasMore = items.paginated && items.raw.length < items.total;
        _loadMoreError = null;
        // 代次已变时在途的续拉会提前 return，这里把加载态一并复位，避免页脚转圈卡住。
        _isLoadingMore = false;
        _allItems = items.items;
        _items = _applyLocalFilters(items.items);
      });
      _scheduleAutoFill();
    } catch (e) {
      if (!mounted) return;
      _showErrorTopTip(
        AppException.from(
          e,
          action: 'reload collection list',
          fallbackKind: AppExceptionKind.transient,
        ).message,
      );
    }
  }

  Future<void> _openSortSheet() async {
    final result = await AppCatalogSortSheet.show(
      context,
      options: <AppCatalogSortOption>[
        for (final column in _sortColumns)
          AppCatalogSortOption(field: column, label: _sortLabelFor(column)),
      ],
      selectedField: _sortColumn,
      sortType: _sortType,
    );
    if (!mounted || result == null) return;
    await _changeSort(result.field, result.sortType);
  }

  String _sortLabelFor(String column) {
    switch (column) {
      case 'release_date':
        return _l10n.listSortReleaseDate;
      case 'title':
        return _l10n.listSortTitleField;
      case 'vote_average':
        return _l10n.listSortVoteAverage;
      case 'create_time':
      default:
        return _l10n.listSortCreateTime;
    }
  }

  List<MediaLibraryItem> _applyLocalFilters(List<MediaLibraryItem> items) {
    return items
        .where((item) {
          if (_selectedResolutionFilter != null) {
            final hasResolution = item.resolutions
                .map((value) => _normalizedResolution(value))
                .where((value) => value.isNotEmpty)
                .contains(_selectedResolutionFilter);
            if (!hasResolution) {
              return false;
            }
          }
          if (_selectedWatchedFilter != null &&
              item.watched != _selectedWatchedFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  String _normalizedResolution(String value) {
    final text = value.trim();
    final match = RegExp(
      r'^(\d{3,4})p$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      return match.group(1) ?? text;
    }
    return text.toUpperCase();
  }

  List<String> _availableResolutionFilters() {
    final values = _allItems
        .expand((item) => item.resolutions)
        .map(_normalizedResolution)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    const preferredOrder = <String>['4K', '1080', '720', '480'];
    values.sort((a, b) {
      final ai = preferredOrder.indexOf(a);
      final bi = preferredOrder.indexOf(b);
      if (ai >= 0 && bi >= 0) {
        return ai.compareTo(bi);
      }
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.compareTo(b);
    });
    return values;
  }

  Future<void> _openLayoutSheet() async {
    final next = await MediaCollectionLayoutSheet.show(
      context,
      currentViewType: _viewType,
    );
    if (!mounted || next == null) return;
    await _applyLayoutSelection(next);
  }

  final GlobalKey<DesktopHoverDropdownState> _sortDropdownKey =
      GlobalKey<DesktopHoverDropdownState>();
  final GlobalKey<DesktopHoverDropdownState> _layoutDropdownKey =
      GlobalKey<DesktopHoverDropdownState>();

  /// 桌面端排序/布局走点击式下拉（触屏保留原 sheet）。
  Future<void> _onSortTriggerTap() async {
    if (DesktopEnvironment.isDesktopPlatform) {
      _sortDropdownKey.currentState?.toggle();
      return;
    }
    await _openSortSheet();
  }

  Future<void> _onLayoutTriggerTap() async {
    if (DesktopEnvironment.isDesktopPlatform) {
      _layoutDropdownKey.currentState?.toggle();
      return;
    }
    await _openLayoutSheet();
  }

  DesktopHoverDropdownSpec get _sortDropdownSpec {
    final l10n = AppLocalizations.of(context);
    return DesktopHoverDropdownSpec(
      groups: <DesktopDropdownOptionGroup>[
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            for (final column in _sortColumns)
              TrackOptionSheetItem(id: column, title: _sortLabelFor(column)),
          ],
          selectedId: _sortColumn,
          onSelected: (field) => _changeSort(field, _sortType),
        ),
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            TrackOptionSheetItem(id: 'ASC', title: l10n.listSortAsc),
            TrackOptionSheetItem(id: 'DESC', title: l10n.listSortDesc),
          ],
          selectedId: _sortType,
          onSelected: (type) => _changeSort(_sortColumn, type),
        ),
      ],
    );
  }

  DesktopHoverDropdownSpec get _layoutDropdownSpec {
    final l10n = AppLocalizations.of(context);
    String label(MediaCollectionViewType type) {
      switch (type) {
        case MediaCollectionViewType.list:
          return l10n.collectionLayoutList;
        case MediaCollectionViewType.horizontalPoster:
          return l10n.collectionLayoutHorizontalPoster;
        case MediaCollectionViewType.verticalPoster:
          return l10n.collectionLayoutVerticalPoster;
      }
    }

    return DesktopHoverDropdownSpec(
      groups: <DesktopDropdownOptionGroup>[
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            for (final type in MediaCollectionViewType.values)
              TrackOptionSheetItem(id: type.storageValue, title: label(type)),
          ],
          selectedId: _viewType.storageValue,
          onSelected: (id) =>
              _applyLayoutSelection(MediaCollectionViewTypeX.fromStorage(id)),
        ),
      ],
    );
  }

  /// 桌面点击下拉直接落地视图切换。
  Future<void> _applyLayoutSelection(MediaCollectionViewType next) async {
    if (!mounted || next == _viewType) return;
    setState(() {
      _viewType = next;
    });
    if (_settingsMdbGuid.isNotEmpty) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        _settingsMdbGuid,
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: next.storageValue,
      );
    }
  }

  Future<void> _openFilterSheet() async {
    final resolutionOptions = _availableResolutionFilters();
    final l10n = AppLocalizations.of(context);
    final result = await AppCatalogFilterSheet.show(
      context,
      sections: <AppCatalogFilterSection>[
        AppCatalogFilterSection(
          key: 'resolution',
          title: l10n.listFilterResolution,
          options: <AppCatalogFilterOption>[
            for (final value in resolutionOptions)
              AppCatalogFilterOption(value: value, label: value),
          ],
          selectedValues: <Object>{
            if (_selectedResolutionFilter != null) _selectedResolutionFilter!,
          },
        ),
        AppCatalogFilterSection(
          key: 'watched',
          title: l10n.listFilterWatched,
          options: <AppCatalogFilterOption>[
            AppCatalogFilterOption(value: 1, label: l10n.listWatched),
            AppCatalogFilterOption(value: 0, label: l10n.listUnwatched),
          ],
          selectedValues: <Object>{
            if (_selectedWatchedFilter != null) _selectedWatchedFilter!,
          },
        ),
      ],
    );
    if (!mounted || result == null) return;

    final resolutions = result['resolution'] ?? const <Object>{};
    final watched = result['watched'] ?? const <Object>{};
    setState(() {
      _selectedResolutionFilter = resolutions.isEmpty
          ? null
          : '${resolutions.first}';
      _selectedWatchedFilter = watched.isEmpty ? null : watched.first as int;
      _items = _applyLocalFilters(_allItems);
    });
    // 本地筛选可能把已加载的这一页全部滤掉，而后续页里还有匹配项。此时既没有滚动事件
    // （内容短于视口）也没有页脚，必须主动补页，否则匹配项永远到不了。
    _autoFillPages = 0;
    _scheduleAutoFill();
  }

  void _replaceItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    setState(() {
      _allItems = _allItems
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
      _items = _applyLocalFilters(_allItems);
    });
  }

  Future<void> _openItemDetail(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) {
      return;
    }
    final provider = context.read<NasProvider>();
    Map<String, dynamic>? initialDetail;
    // 飞牛专属的详情预取加速；非飞牛由目标页自行按 backend 重取。
    if (_isFeiniuBackend) {
      try {
        initialDetail = await FeiniuApi(
          provider,
        ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 260));
      } catch (_) {}
    }
    if (!mounted) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.guid,
        initialItemDetail: initialDetail,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  Future<void> _showItemActions(MediaLibraryItem item) async {
    final l10n = AppLocalizations.of(context);
    final target = item.toActionTarget();
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.defaultTitle(l10n, target),
      initialWatched: item.watched == 1,
      onChanged: (state) {
        if (!mounted) return;
        _replaceItemLocally(
          item.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  void _showErrorTopTip(String message) {
    _topTip.show(context, message: message, color: context.appColors.danger);
  }

  @override
  Widget build(BuildContext context) {
    final (
      dynamicThemeEnabled: dynamicThemeEnabled,
      dynamicThemeIntensity: dynamicThemeIntensity,
    ) = context
        .select<
          AppThemeProvider,
          ({
            bool dynamicThemeEnabled,
            AppDynamicThemeIntensity dynamicThemeIntensity,
          })
        >(
          (themeProvider) => (
            dynamicThemeEnabled: themeProvider.dynamicThemeEnabled,
            dynamicThemeIntensity: themeProvider.dynamicThemeIntensity,
          ),
        );
    final provider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    String dynamicPosterPath = '';
    if (!_loading) {
      for (final item in _items.isNotEmpty ? _items : _allItems) {
        final candidate = item.poster.trim().isNotEmpty
            ? item.poster.trim()
            : '';
        if (candidate.isNotEmpty) {
          dynamicPosterPath = candidate;
          break;
        }
      }
    }
    final dynamicThemeImages = dynamicPosterPath.isEmpty
        ? MediaImageRequest.empty
        : DetailArtworkResolver(
            baseUrl: _isFeiniuBackend ? provider.baseUrl : '',
            token: _isFeiniuBackend ? provider.token : '',
            accessCode: _isFeiniuBackend ? provider.accessCode : '',
          ).resolvePath(dynamicPosterPath, width: 320);
    final dynamicThemeImageUrl = dynamicThemeImages.urls.isNotEmpty
        ? dynamicThemeImages.urls.first
        : '';
    final syncGlobalTheme = dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
      inPlayerPaneHost: inPlayerPaneHost,
      isPane: _isPane,
    );

    return RouteGateAnchor(
      key: _gateKey,
      // 锚点必须无条件包裹页面根（不进任何条件分支）；child 原样传入，
      // 勿包装/换 key，否则依赖翻转会连带重建被包子树（plan §3.3）。
      child: DynamicPageThemeScope(
        pageKey: widget.itemGuid,
        imageUrl: dynamicThemeImageUrl,
        imageHeaders: dynamicThemeImages.headers,
        enabled: dynamicThemeEnabled,
        syncGlobalTheme: syncGlobalTheme,
        deferLocalThemeApplyUntilGlobalSync: _isPane && syncGlobalTheme,
        intensity: dynamicThemeIntensity,
        builder: (context, _) {
          final colors = context.appColors;
          if (_loading) {
            return DetailLoadingSkeleton(presentation: widget.presentation);
          }
          if (_error != null) {
            return DetailStatusPage(
              child: SafeArea(
                child: AppErrorState(
                  error: _error!,
                  localeMap: const <String, dynamic>{},
                  onRetry: _load,
                ),
              ),
            );
          }

          final title = (_detail['title'] ?? '').toString().trim();
          final crumb = _crumbText();
          final path = (_detail['path'] ?? '').toString().trim();

          return Scaffold(
            backgroundColor: colors.backgroundBase,
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      DetailTokens.screenHorizontalPadding,
                      8,
                      DetailTokens.screenHorizontalPadding,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TopBarIconButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                onTap: () => unawaited(
                                  EmbeddedDetailLauncher.closeHostOrPop(
                                    context,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              _TopBarIconButton(
                                icon: Icons.more_horiz_rounded,
                                onTap: () => unawaited(
                                  showDetailMoreActionsSheet(
                                    context,
                                    pageKey: widget.itemGuid,
                                    pageTitle: title,
                                    suggestedThemeName: context
                                        .read<AppThemeProvider>()
                                        .nextSavedThemeNameFromBase(
                                          buildThemeSaveNameBase(
                                            l10n: AppLocalizations.of(context),
                                            title: title,
                                          ),
                                        ),
                                    clearRuntimeBroadcastToMain:
                                        !inPlayerPaneHost,
                                    extraActions: <DetailMoreActionItem>[
                                      DetailMoreActionItem(
                                        icon: Icons.grid_view_rounded,
                                        title: _l10n.collectionLayoutTitle,
                                        subtitle:
                                            _l10n.collectionLayoutSubtitle,
                                        onTap: (context) => _openLayoutSheet(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (crumb.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  color: colors.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    crumb,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                          Text(
                            title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              height: 1.08,
                            ),
                          ),
                          if (_secondaryLine().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              _secondaryLine(),
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          PlayControlRow(
                            primaryText: _primaryText(),
                            primaryEnabled: _primaryPlayableItem() != null,
                            liked: _liked,
                            watched: _watched,
                            onPrimaryTap: _playPrimary,
                            onLikeTap: _toggleFavorite,
                            onWatchedTap: _toggleWatched,
                          ),
                          if (path.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textMuted.withValues(alpha: 0.82),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    desktopTapDropdownWrapper(
                                      dropdownKey: _sortDropdownKey,
                                      spec: _sortDropdownSpec,
                                      child: InkWell(
                                        onTap: _onSortTriggerTap,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Row(
                                          children: [
                                            Text(
                                              _sortLabelFor(_sortColumn),
                                              style: TextStyle(
                                                color: colors.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              _sortType == 'ASC'
                                                  ? Icons.arrow_upward
                                                  : Icons.arrow_downward,
                                              size: 16,
                                              color: colors.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceStrong,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_items.length}',
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              desktopTapDropdownWrapper(
                                dropdownKey: _layoutDropdownKey,
                                spec: _layoutDropdownSpec,
                                child: _CollectionToolButton(
                                  icon: Icons.grid_view_rounded,
                                  active:
                                      _viewType != MediaCollectionViewType.list,
                                  onTap: _onLayoutTriggerTap,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _CollectionToolButton(
                                icon: Icons.filter_alt_outlined,
                                active:
                                    _selectedResolutionFilter != null ||
                                    _selectedWatchedFilter != null,
                                onTap: _openFilterSheet,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      DetailTokens.screenHorizontalPadding,
                      0,
                      DetailTokens.screenHorizontalPadding,
                      24,
                    ),
                    sliver: MediaCollectionBrowserSliver(
                      items: _items,
                      baseUrl: _isFeiniuBackend ? provider.baseUrl : '',
                      token: _isFeiniuBackend ? provider.token : '',
                      accessCode: _isFeiniuBackend ? provider.accessCode : '',
                      viewType: _viewType,
                      onItemTap: _openItemDetail,
                      onItemLongPress: _showItemActions,
                      onItemMoreTap: _showItemActions,
                    ),
                  ),
                  if (_isLoadingMore || _loadMoreError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Center(
                          child: _loadMoreError == null
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: BirdGlyph(size: 20),
                                )
                              : TextButton.icon(
                                  onPressed: () => unawaited(_loadMoreItems()),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(_l10n.commonRefreshRetry),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: liquidGlassDecoration(
          context,
          radius: 18,
          tone: LiquidGlassTone.strong,
        ),
        child: Icon(icon, color: colors.textPrimary, size: 20),
      ),
    );
  }
}

class _CollectionToolButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _CollectionToolButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  static const Color _activeIcon = Color(0xFFE5F0FF);
  static const Color _inactiveIcon = Color(0xFFB7C6D8);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: liquidGlassDecoration(
          context,
          radius: 12,
          tone: active ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
          selected: active,
        ),
        child: Icon(
          icon,
          color: active ? _activeIcon : _inactiveIcon,
          size: 21,
        ),
      ),
    );
  }
}
