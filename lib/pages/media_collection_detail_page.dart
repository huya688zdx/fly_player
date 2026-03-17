import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../api/item_list_request.dart';
import '../controllers/item_playback_launcher.dart';
import '../controllers/media_item_action_sheet_controller.dart';
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
import '../ui/detail_presentation.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/play_control_row.dart';
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
    } catch (_) {
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
    } catch (_) {
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
      return '目录';
    }
    if (type == 'mediadb') {
      final category = (_detail['ancestor_category'] ?? '').toString().trim();
      return category.isNotEmpty ? category : '媒体库';
    }
    return '';
  }

  MediaLibraryItem? _primaryPlayableItem() {
    final type = _detailType(_detail);
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
      return '播放';
    }
    return item.ts > 0 || item.watchedTs > 0 ? '继续播放' : '播放';
  }

  Future<void> _playPrimary() async {
    final item = _primaryPlayableItem();
    if (item == null || item.guid.trim().isEmpty) {
      return;
    }
    try {
      await const ItemPlaybackLauncher().open(
        context,
        itemGuid: item.guid,
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
    try {
      final next = await FeiniuApi(
        context.read<NasProvider>(),
      ).setFavorite(guid, favorite: !_liked);
      if (!mounted) return;
      setState(() {
        _liked = next;
        _favoriteUpdating = false;
      });
      _topTip.show(
        context,
        message: next ? '已加入收藏' : '已取消收藏',
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
    try {
      final next = await FeiniuApi(
        context.read<NasProvider>(),
      ).setWatched(guid, watched: !_watched);
      if (!mounted) return;
      setState(() {
        _watched = next;
        _watchedUpdating = false;
      });
      _topTip.show(
        context,
        message: next ? '已标记为已观看' : '已标记为未观看',
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
    try {
      final items = await _loadItems(
        FeiniuApi(context.read<NasProvider>()),
        detail: _detail,
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '排序',
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
                            _sortType == 'ASC' ? '升序' : '降序',
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
        return '按发行年份';
      case 'title':
        return '按标题';
      case 'vote_average':
        return '按评分';
      case 'create_time':
      default:
        return '按添加日期';
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
                        '筛选',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '分辨率',
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
                          label: '全部',
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
                      '观看状态',
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
                          label: '全部',
                          selected: tempWatched == null,
                          onTap: () => setModal(() => tempWatched = null),
                        ),
                        chip(
                          label: '已观看',
                          selected: tempWatched == 1,
                          onTap: () => setModal(() => tempWatched = 1),
                        ),
                        chip(
                          label: '未观看',
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
                            child: const Text(
                              '重置',
                              style: TextStyle(fontWeight: FontWeight.w700),
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
                            child: const Text(
                              '确定',
                              style: TextStyle(fontWeight: FontWeight.w700),
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
    try {
      initialDetail = await FeiniuApi(
        provider,
      ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 260));
    } catch (_) {}
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
    await const MediaItemActionSheetController().show(
      context,
      item: item,
      title: MediaItemActionSheetController.defaultTitle(item),
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
    final themeProvider = context.watch<AppThemeProvider>();
    final provider = context.read<NasProvider>();
    String dynamicPosterPath = '';
    for (final item in _items.isNotEmpty ? _items : _allItems) {
      final candidate = item.poster.trim().isNotEmpty ? item.poster.trim() : '';
      if (candidate.isNotEmpty) {
        dynamicPosterPath = candidate;
        break;
      }
    }
    final dynamicThemeUrls = dynamicPosterPath.isEmpty
        ? const <String>[]
        : ApiUrlHelper.imageCandidates(
            provider.baseUrl,
            dynamicPosterPath,
            width: 320,
          );
    final dynamicThemeImageUrl = dynamicThemeUrls.isNotEmpty
        ? dynamicThemeUrls.first
        : '';

    return DynamicPageThemeScope(
      pageKey: widget.itemGuid,
      imageUrl: dynamicThemeImageUrl,
      token: provider.token,
      enabled: themeProvider.dynamicThemeEnabled,
      syncGlobalTheme: _isPane,
      intensity: themeProvider.dynamicThemeIntensity,
      builder: (context, _) {
        final colors = context.appColors;
        if (_loading) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            body: const SizedBox.shrink(),
          );
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
                    24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _isPane
                                ? const SizedBox(width: 40, height: 40)
                                : _TopBarIconButton(
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
                              onTap: _openLayoutSheet,
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
                        MediaCollectionBrowser(
                          items: _items,
                          baseUrl: provider.baseUrl,
                          token: provider.token,
                          viewType: _viewType,
                          onItemTap: _openItemDetail,
                          onItemLongPress: _showItemActions,
                          onItemMoreTap: _showItemActions,
                        ),
                      ],
                    ),
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
        decoration: BoxDecoration(
          color: colors.surfaceSubtle.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? colors.selectionSoft : colors.surfaceStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Icon(
          icon,
          color: active ? colors.selectionStrong : colors.textSecondary,
          size: 21,
        ),
      ),
    );
  }
}
