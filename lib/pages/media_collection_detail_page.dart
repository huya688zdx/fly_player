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
import '../widgets/common/app_error_state.dart';
import '../widgets/common/liquid_glass.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/play_control_row.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import '../widgets/library/media_collection_browser.dart';
import '../widgets/library/media_collection_layout_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialItemDetail != null) {
      _applyDetail(widget.initialItemDetail!);
    }
    _load();
  }

  @override
  void dispose() {
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
        await RouteTransitionGate.of(context);
        if (!mounted) return;
        setState(() {
          _applyDetail(_neutralDetailToMap(neutral));
          _allItems = items;
          _items = _applyLocalFilters(items);
          _loading = false;
        });
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
      await RouteTransitionGate.of(context);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _allItems = items;
        _items = _applyLocalFilters(items);
        _sortColumn = _normalizeSortColumn(setting?.sortField);
        _sortType = _normalizeSortType(setting?.sortType);
        _viewType = MediaCollectionViewTypeX.fromStorage(
          setting?.viewType ?? 'list',
        );
        _loading = false;
      });
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

  Future<List<MediaLibraryItem>> _loadNeutralItems(
    MediaBackend backend, {
    required String sortColumn,
    required String sortType,
  }) async {
    final result = await backend.queryChildItems(
      MediaCatalogQuery(
        catalogId: widget.itemGuid,
        sortField: sortColumn,
        sortType: sortType,
        page: 1,
        pageSize: 500,
      ),
    );
    return result.items.map(_cardToLibraryItem).toList(growable: false);
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

  Future<List<MediaLibraryItem>> _loadItems(
    FeiniuApi api, {
    required Map<String, dynamic> detail,
    required String sortColumn,
    required String sortType,
  }) async {
    final queryPayload = _buildItemListPayload(
      detail,
      sortColumn: sortColumn,
      sortType: sortType,
    );
    if (queryPayload == null) {
      return const <MediaLibraryItem>[];
    }
    final page = await api.getItemsPage(queryPayload);
    final filtered = _filterItems(page.items, detail);
    if (filtered.isNotEmpty) {
      return filtered;
    }
    final currentGuid = (detail['guid'] ?? '').toString().trim();
    if (currentGuid.isNotEmpty) {
      final playInfoItems = await _buildFallbackItemsFromPlayInfo(
        api,
        currentGuid,
        detail: detail,
      );
      if (playInfoItems.isNotEmpty) {
        return playInfoItems;
      }
    }
    final playItemGuid = (detail['play_item_guid'] ?? '').toString().trim();
    return playItemGuid.isEmpty
        ? filtered
        : _buildFallbackItemsFromStreamList(api, playItemGuid);
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
  }) {
    final type = _detailType(detail);
    if (type == 'directory') {
      final parentGuid = (detail['guid'] ?? '').toString().trim();
      if (parentGuid.isEmpty) {
        return null;
      }
      return <String, dynamic>{
        'parent_guid': parentGuid,
        'page': 1,
        'page_size': 500,
        'sort_column': sortColumn,
        'sort_type': sortType,
        'tags': const <String, dynamic>{},
      };
    }

    final ancestorGuid = _resolveQueryAncestorGuid(detail);
    if (ancestorGuid.isEmpty) {
      return null;
    }
    return ItemListRequest(
      ancestorGuid: ancestorGuid,
      page: 1,
      pageSize: 500,
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

  Future<void> _changeSort(String column) async {
    final nextColumn = column == _sortColumn ? _sortColumn : column;
    final nextType = column == _sortColumn
        ? (_sortType == 'ASC' ? 'DESC' : 'ASC')
        : 'DESC';
    setState(() {
      _sortColumn = nextColumn;
      _sortType = nextType;
    });
    if (_settingsMdbGuid.isNotEmpty) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        _settingsMdbGuid,
        sortField: nextColumn,
        sortType: nextType,
        viewType: _viewType.storageValue,
      );
    }
    await _reloadItemsOnly();
  }

  Future<void> _reloadItemsOnly() async {
    final nas = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    try {
      final items = _isFeiniuBackend
          ? await _loadItems(
              FeiniuApi(nas),
              detail: _detail,
              sortColumn: _sortColumn,
              sortType: _sortType,
            )
          : await _loadNeutralItems(
              backend,
              sortColumn: _sortColumn,
              sortType: _sortType,
            );
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _items = _applyLocalFilters(items);
      });
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colors = context.appColors;
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.listSortTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final column in _sortColumns)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _sortLabelFor(column),
                      style: TextStyle(
                        color: column == _sortColumn
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: column == _sortColumn
                        ? Text(
                            _sortType == 'ASC'
                                ? l10n.listSortAsc
                                : l10n.listSortDesc,
                            style: TextStyle(color: colors.textMuted),
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      _changeSort(column);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
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
    if (!mounted || next == null || next == _viewType) {
      return;
    }
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
    String? tempResolution = _selectedResolutionFilter;
    int? tempWatched = _selectedWatchedFilter;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            final colors = context.appColors;
            final l10n = AppLocalizations.of(context);
            Widget chip({
              required String label,
              required bool selected,
              required VoidCallback onTap,
            }) {
              final colors = context.appColors;
              return Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 10),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.selectionSoft
                          : colors.surfaceStrong,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? colors.selection
                            : colors.borderSubtle,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? colors.selectionStrong
                            : colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        l10n.listFilterButton,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.listFilterResolution,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      children: [
                        chip(
                          label: l10n.listFilterAll,
                          selected: tempResolution == null,
                          onTap: () => setModal(() => tempResolution = null),
                        ),
                        for (final value in resolutionOptions)
                          chip(
                            label: value,
                            selected: tempResolution == value,
                            onTap: () => setModal(() => tempResolution = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.listFilterWatched,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      children: [
                        chip(
                          label: l10n.listFilterAll,
                          selected: tempWatched == null,
                          onTap: () => setModal(() => tempWatched = null),
                        ),
                        chip(
                          label: l10n.listWatched,
                          selected: tempWatched == 1,
                          onTap: () => setModal(() => tempWatched = 1),
                        ),
                        chip(
                          label: l10n.listUnwatched,
                          selected: tempWatched == 0,
                          onTap: () => setModal(() => tempWatched = 0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setModal(() {
                                tempResolution = null;
                                tempWatched = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.borderSubtle),
                              foregroundColor: colors.textSecondary,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(
                              l10n.listFilterResetButton,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() {
                                _selectedResolutionFilter = tempResolution;
                                _selectedWatchedFilter = tempWatched;
                                _items = _applyLocalFilters(_allItems);
                              });
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(
                              l10n.commonConfirm,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
            baseUrl: provider.baseUrl,
            token: provider.token,
          ).resolvePath(dynamicPosterPath, width: 320);
    final dynamicThemeImageUrl = dynamicThemeImages.urls.isNotEmpty
        ? dynamicThemeImages.urls.first
        : '';
    final syncGlobalTheme = dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
      inPlayerPaneHost: inPlayerPaneHost,
      isPane: _isPane,
    );

    return DynamicPageThemeScope(
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
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            appBar: _isPane
                ? null
                : AppBar(backgroundColor: colors.backgroundBase),
            body: AppErrorState(
              error: _error!,
              localeMap: const <String, dynamic>{},
              onRetry: _load,
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
                                EmbeddedDetailLauncher.closeHostOrPop(context),
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
                                      subtitle: _l10n.collectionLayoutSubtitle,
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
                                  InkWell(
                                    onTap: _openSortSheet,
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
                            _CollectionToolButton(
                              icon: Icons.grid_view_rounded,
                              active: _viewType != MediaCollectionViewType.list,
                              onTap: _openLayoutSheet,
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
                    baseUrl: provider.baseUrl,
                    token: provider.token,
                    viewType: _viewType,
                    onItemTap: _openItemDetail,
                    onItemLongPress: _showItemActions,
                    onItemMoreTap: _showItemActions,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
