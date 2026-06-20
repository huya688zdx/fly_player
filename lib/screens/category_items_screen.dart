import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/filter/media_catalog_filter.dart';
import '../media_backend/media_item_card.dart';
import '../models/media_collection_view_type.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/catalog_filter_localizer.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_localization_lookup.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/library/media_collection_layout_sheet.dart';
import '../widgets/library/media_library_list_tile.dart';

class CategoryItemsScreen extends StatefulWidget {
  final MediaItem category;
  final List<String>? initialTypeTags;
  final bool secondaryHost;

  const CategoryItemsScreen({
    super.key,
    required this.category,
    this.initialTypeTags,
    this.secondaryHost = false,
  });

  @override
  State<CategoryItemsScreen> createState() => _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends State<CategoryItemsScreen> {
  static const int _pageSize = 50;
  static const double _loadMoreTriggerOffset = 360;

  static const List<String> _fallbackSortColumns = <String>[
    'create_time',
    'release_date',
    'title',
    'vote_average',
  ];
  List<MediaItemCard> _items = const <MediaItemCard>[];
  int _total = 0;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  AppException? _error;
  String? _loadMoreError;
  final ScrollController _scrollController = ScrollController();

  bool _metaLoaded = false;
  String _sortColumn = 'create_time';
  String _sortType = 'DESC';
  MediaCollectionViewType _viewType = MediaCollectionViewType.verticalPoster;

  /// 后端下发的筛选 / 排序 schema（含 genre / 地区数据字典）。
  MediaCatalogFilterSchema _schema = const MediaCatalogFilterSchema();
  Map<String, dynamic> _localeMap = {};

  /// 维度 key → 选中的原始 value 集合（飞牛各维度单选，集合至多一个元素）。
  final Map<String, Set<String>> _selection = <String, Set<String>>{};

  DetailPresentation get _detailPresentation =>
      widget.secondaryHost ? DetailPresentation.pane : DetailPresentation.page;

  /// 按当前 l10n + schema 构造筛选文案本地化器（schema 变更后自动反映）。
  CatalogFilterLocalizer get _filterLocalizer => CatalogFilterLocalizer(
    l10n: AppLocalizations.of(context),
    schema: _schema,
  );

  List<String> get _sortColumns {
    final schemaFields = _schema.sortOptions
        .map((option) => option.field.trim())
        .where((field) => field.isNotEmpty)
        .toList(growable: false);
    return schemaFields.isNotEmpty ? schemaFields : _fallbackSortColumns;
  }

  double _viewportCacheExtent(BuildContext context) {
    final factor = widget.secondaryHost ? 0.7 : 1.0;
    return min(MediaQuery.of(context).size.height * factor, 900.0);
  }

  bool get _typeLocked =>
      widget.initialTypeTags != null && widget.initialTypeTags!.isNotEmpty;

  List<String> get _lockedTypeTags => widget.initialTypeTags ?? const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initLoad();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    await _loadMeta();
    await _fetch();
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const {},
  }) {
    return AppLocalizationLookup.text(
      AppLocalizations.of(context),
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _loadMeta() async {
    if (_metaLoaded) return;
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final backend = context.read<MediaBackendProvider>().backend;
    final hasAncestor = widget.category.id.trim().isNotEmpty;
    UserListSetting? setting;
    if (hasAncestor) {
      try {
        setting = await api.getUserListSetting(widget.category.id);
      } catch (_) {}
    }
    var schema = const MediaCatalogFilterSchema();
    try {
      schema = await backend.getCatalogFilterSchema(widget.category.id);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _metaLoaded = true;
      _schema = schema;
      _localeMap = const <String, dynamic>{};
      if (setting != null) {
        _sortColumn = setting.sortField;
        _sortType = setting.sortType == 'ASC' ? 'ASC' : 'DESC';
        _viewType = MediaCollectionViewTypeX.fromStorage(setting.viewType);
      }
    });
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _error = null;
      _loadMoreError = null;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final page = await backend.queryCatalogItems(_buildQuery(page: 1));

      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _currentPage = 1;
        _hasMore = _items.length < _total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'category items',
          fallbackKind: AppExceptionKind.transient,
        );
        _isLoading = false;
      });
    }
  }

  void _replaceItemLocally(
    String itemId,
    MediaItemCard Function(MediaItemCard item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _items = _items
          .map((item) => item.id == itemId ? transform(item) : item)
          .toList(growable: false);
    });
  }

  Future<void> _showPosterItemActions(MediaItemCard item) async {
    final actionItem = _cardToActionItem(item);
    await const MediaItemActionSheetController().show(
      context,
      item: actionItem,
      title: MediaItemActionSheetController.defaultTitle(actionItem),
      localeMap: _localeMap,
      favoriteOnly: _isPersonItem(item),
      initialWatched: item.watched,
      onChanged: (state) {
        _replaceItemLocally(
          item.id,
          (current) => current.copyWith(watched: state.watched),
        );
      },
    );
  }

  /// 动作面板仅消费 guid / watched / type / season&episode 编号与标题字段，
  /// 这里按公共卡片回填一个最小 [MediaLibraryItem] 喂面板，避免在分类页保留飞牛模型。
  /// 仅限本文件使用，不向外扩散（复刻搜索页 Task 4-4 模式）。
  MediaLibraryItem _cardToActionItem(MediaItemCard card) {
    return MediaLibraryItem(
      guid: card.id,
      title: card.title,
      tvTitle: card.secondaryTitle,
      type: card.type,
      poster: card.primaryImage.url,
      releaseDate: '',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '',
      overview: '',
      watched: card.watched ? 1 : 0,
      watchedTs: 0,
      ts: 0,
      duration: 0,
      seasonNumber: card.seasonNumber,
      episodeNumber: card.episodeNumber,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: '',
      parentTitle: '',
      ancestorGuid: '',
      ancestorName: '',
      path: '',
    );
  }

  /// 把当前选择回填为公共分类查询；type 锁定时用锁定类型，否则用用户选择
  /// （空选择交由适配层回退到全类型）。
  MediaCatalogQuery _buildQuery({required int page}) {
    final selection = <String, List<String>>{};
    final typeValues = _typeLocked
        ? _lockedTypeTags
        : (_selection['type']?.toList(growable: false) ?? const <String>[]);
    if (typeValues.isNotEmpty) {
      selection['type'] = List<String>.from(typeValues);
    }
    for (final entry in _selection.entries) {
      if (entry.key == 'type') continue;
      if (entry.value.isNotEmpty) {
        selection[entry.key] = entry.value.toList(growable: false);
      }
    }

    return MediaCatalogQuery(
      catalogId: widget.category.id,
      selection: selection,
      sortField: _sortColumn,
      sortType: _sortType,
      page: page,
      pageSize: _pageSize,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore || _error != null) return;
    final position = _scrollController.position;
    final remain = position.maxScrollExtent - position.pixels;
    if (remain <= _loadMoreTriggerOffset) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final nextPage = _currentPage + 1;
      final backend = context.read<MediaBackendProvider>().backend;
      final page = await backend.queryCatalogItems(_buildQuery(page: nextPage));

      if (!mounted) return;
      setState(() {
        _currentPage = nextPage;
        _items = [..._items, ...page.items];
        _total = page.total;
        _hasMore = _items.length < _total && page.items.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = '$e';
      });
    }
  }

  Future<void> _openItemDetail(MediaItemCard item, {String? heroTag}) async {
    if (item.id.trim().isEmpty) return;
    if (_isPersonItem(item)) {
      await AdaptiveDetailNavigator.open<void>(
        context,
        AdaptiveDetailRequest.person(
          personGuid: item.id,
          initialName: item.displayTitle,
          initialLocaleMap: _localeMap,
        ),
        presentation: _detailPresentation,
      );
      return;
    }

    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        context.read<NasProvider>(),
      ).getItemDetail(item.id).timeout(const Duration(milliseconds: 240));
    } catch (_) {}
    if (!mounted) return;
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.id,
        heroTag: heroTag,
        initialItemDetail: initialDetail,
      ),
      presentation: _detailPresentation,
    );
  }

  List<String> _posterCandidates(
    String baseUrl,
    MediaItemCard item, {
    int width = 400,
    bool preferDirectPath = false,
  }) {
    final paths = <String>[
      if (item.primaryImage.url.trim().isNotEmpty) item.primaryImage.url.trim(),
      ...item.posters
          .map((ref) => ref.url)
          .where((path) => path.trim().isNotEmpty),
    ];
    final unique = <String>{};
    final ordered = <String>[];
    for (final path in paths) {
      if (unique.add(path)) {
        ordered.add(path);
      }
    }
    return ordered
        .expand(
          (path) => ApiUrlHelper.imageCandidates(
            baseUrl,
            path,
            width: width,
            preferDirectPath: preferDirectPath,
          ),
        )
        .toList(growable: false);
  }

  bool _isPersonItem(MediaItemCard item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  bool _isEpisodeItem(MediaItemCard item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _cardSubtitle(MediaItemCard item) {
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

    if (seasonCount == 1 && episodeCount > 0) {
      final episodeText = AppLocalizations.of(
        context,
      ).mediaEpisodeCount(episodeCount);
      return period.isEmpty ? episodeText : '$episodeText / $period';
    }
    if (seasonCount > 0) {
      final seasonText = AppLocalizations.of(
        context,
      ).mediaSeasonCount(seasonCount);
      return period.isEmpty ? seasonText : '$seasonText / $period';
    }
    return period;
  }

  /// 卡片清晰度角标文案（去掉尾部 p；与筛选 localizer 的 resolution 语义一致）。
  String _resolutionLabel(String value) {
    final text = value.trim();
    final match = RegExp(
      r'^(\d{3,4})p$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return match.group(1) ?? text;
    if (text == 'Others') {
      return _t('stream.video.videoResolution.others', 'Other');
    }
    return text;
  }

  String get _filterSummaryLabel {
    final localizer = _filterLocalizer;
    final parts = <String>[];
    for (final dim in _schema.dimensions) {
      final sel = _selection[dim.key];
      if (sel == null || sel.isEmpty) continue;
      if (dim.key == 'type' && (_typeLocked || sel.length >= 4)) continue;
      final value = sel.first;
      final option = dim.options.firstWhere(
        (o) => o.value == value,
        orElse: () => MediaFilterOption(value: value),
      );
      parts.add(localizer.optionLabel(dim, option));
    }
    if (parts.isEmpty) {
      return _t('layout.list.filter.filterButton', 'Filter');
    }
    return parts.join(' / ');
  }

  String get _sortLabel => _filterLocalizer.sortLabel(_sortColumn);

  IconData get _sortArrow =>
      _sortType == 'ASC' ? Icons.arrow_upward : Icons.arrow_downward;

  bool get _hasActiveFilters {
    for (final entry in _selection.entries) {
      if (entry.value.isEmpty) continue;
      if (entry.key == 'type') {
        if (!_typeLocked && entry.value.length < 4) return true;
        continue;
      }
      return true;
    }
    return false;
  }

  Future<void> _openLayoutSheet() async {
    final next = await MediaCollectionLayoutSheet.show(
      context,
      currentViewType: _viewType,
    );
    if (!mounted || next == null || next == _viewType) {
      return;
    }
    setState(() => _viewType = next);
    if (widget.category.id.trim().isNotEmpty) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        widget.category.id,
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: next.storageValue,
      );
    }
  }

  TextStyle get _bold12 => const TextStyle(
    color: Colors.white70,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  Future<void> _openSortSheet() async {
    final colors = context.appColors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('layout.list.sort.title', 'Sort'),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final column in _sortColumns)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 0,
                    visualDensity: const VisualDensity(vertical: -1),
                    title: Text(
                      _filterLocalizer.sortLabel(column),
                      style: TextStyle(
                        color: column == _sortColumn
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    trailing: column == _sortColumn
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _sortType == 'ASC'
                                    ? '${_t('layout.list.sort.sortType.asc', 'Ascending')} ^'
                                    : '${_t('layout.list.sort.sortType.desc', 'Descending')} v',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : null,
                    onTap: () async {
                      if (column == _sortColumn) {
                        _sortType = _sortType == 'ASC' ? 'DESC' : 'ASC';
                      } else {
                        _sortColumn = column;
                        _sortType = 'DESC';
                      }
                      Navigator.of(context).pop();
                      if (widget.category.id.trim().isNotEmpty) {
                        await FeiniuApi(
                          context.read<NasProvider>(),
                        ).setUserListSetting(
                          widget.category.id,
                          sortField: _sortColumn,
                          sortType: _sortType,
                          viewType: _viewType.storageValue,
                        );
                      }
                      _fetch();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFilterSheet() async {
    if (!_metaLoaded) await _loadMeta();
    if (!mounted) return;
    final colors = context.appColors;
    final localizer = _filterLocalizer;

    // 复制当前选择，弹窗内编辑，确认后回写。
    final temp = <String, Set<String>>{
      for (final entry in _selection.entries)
        entry.key: Set<String>.from(entry.value),
    };
    Set<String> tempFor(String key) => temp.putIfAbsent(key, () => <String>{});

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            Widget chip(String label, bool selected, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? colors.selection : colors.chipBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? colors.selection : colors.chipBorder,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? colors.textPrimary : colors.chipText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            Widget section(MediaFilterDimension dimension) {
              if (dimension.key == 'type' && _typeLocked) {
                return const SizedBox.shrink();
              }
              final options = dimension.options;
              if (options.isEmpty) return const SizedBox.shrink();
              final selected = tempFor(dimension.key);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizer.dimensionTitle(dimension), style: _bold12),
                  const SizedBox(height: 8),
                  Wrap(
                    children: [
                      chip(
                        _t('layout.list.filter.all', 'All'),
                        selected.isEmpty,
                        () => setModal(() => selected.clear()),
                      ),
                      for (final option in options)
                        chip(
                          localizer.optionLabel(dimension, option),
                          selected.contains(option.value),
                          () => setModal(() {
                            if (selected.contains(option.value)) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..add(option.value);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            _t('layout.list.filter.filterButton', 'Filter'),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final dimension in _schema.dimensions)
                              section(dimension),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModal(() {
                                  for (final values in temp.values) {
                                    values.clear();
                                  }
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: colors.chipBorder),
                                foregroundColor: colors.textSecondary,
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('layout.list.filter.resetButton', 'Reset'),
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
                                  _selection
                                    ..clear()
                                    ..addAll(<String, Set<String>>{
                                      for (final entry in temp.entries)
                                        entry.key: Set<String>.from(
                                          entry.value,
                                        ),
                                    });
                                });
                                _fetch();
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('common.actions.default.default', 'Confirm'),
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
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NasProvider>();
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        backgroundColor: colors.backgroundBase,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actionsIconTheme: IconThemeData(color: colors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            unawaited(
              widget.secondaryHost
                  ? EmbeddedDetailLauncher.closeHostOrPop(context)
                  : Navigator.of(context).maybePop(),
            );
          },
        ),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        title: Text(widget.category.name),
      ),
      body: _buildBody(provider.baseUrl, provider.token),
    );
  }

  Widget _buildBody(String baseUrl, String token) {
    final layout = MediaLayoutProfile.of(context);
    final colors = context.appColors;
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppErrorState(
        error: _error!,
        localeMap: _localeMap,
        onRetry: _fetch,
      );
    }

    final bottomPadding =
        16.0 + (_isLoadingMore || _loadMoreError != null ? 44.0 : 0.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
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
                            _sortLabel,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _sortArrow,
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
                        color: colors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${max(_total, _items.length)}',
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
              _CategoryToolButton(
                icon: Icons.grid_view_rounded,
                active: _viewType != MediaCollectionViewType.list,
                onTap: _openLayoutSheet,
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: _filterSummaryLabel,
                child: _CategoryToolButton(
                  icon: Icons.filter_alt_outlined,
                  active: _hasActiveFilters,
                  onTap: _openFilterSheet,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              if (_viewType == MediaCollectionViewType.list)
                ListView.separated(
                  controller: _scrollController,
                  cacheExtent: _viewportCacheExtent(context),
                  padding: EdgeInsets.fromLTRB(
                    layout.pageHorizontalPadding,
                    0,
                    layout.pageHorizontalPadding,
                    bottomPadding,
                  ),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return MediaLibraryListTile(
                      urls: _posterCandidates(baseUrl, item, width: 280),
                      token: token,
                      title: item.displayTitle,
                      subtitle: _cardSubtitle(item),
                      resolutions: item.resolutions
                          .map(_resolutionLabel)
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      onTap: () => _openItemDetail(
                        item,
                        heroTag:
                            'category_${widget.category.id}_${item.id}_$index',
                      ),
                      onLongPress: () => _showPosterItemActions(item),
                      onMoreTap: () => _showPosterItemActions(item),
                    );
                  },
                )
              else if (_viewType == MediaCollectionViewType.horizontalPoster)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = layout.isTablet ? 3 : 2;
                    final availableWidth =
                        constraints.maxWidth -
                        layout.pageHorizontalPadding * 2 -
                        layout.itemGap * (crossAxisCount - 1);
                    final cardWidth = availableWidth / crossAxisCount;
                    final imageHeight = cardWidth * 0.56;
                    final rowHeight = imageHeight + 58;

                    return GridView.builder(
                      controller: _scrollController,
                      cacheExtent: _viewportCacheExtent(context),
                      padding: EdgeInsets.fromLTRB(
                        layout.pageHorizontalPadding,
                        0,
                        layout.pageHorizontalPadding,
                        bottomPadding,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: layout.itemGap,
                        crossAxisSpacing: layout.itemGap,
                        mainAxisExtent: rowHeight,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final urls = _posterCandidates(
                          baseUrl,
                          item,
                          width: 720,
                          preferDirectPath: true,
                        );
                        final rating = double.tryParse(item.rating);
                        final resolutions = item.resolutions
                            .map(_resolutionLabel)
                            .where((e) => e.isNotEmpty)
                            .toList();

                        return MediaPosterCard(
                          urls: urls,
                          token: token,
                          title: item.displayTitle,
                          subtitle: _cardSubtitle(item),
                          imageAspectRatioHint: item.hasPosterSize
                              ? item.posterWidth / item.posterHeight
                              : null,
                          rating: rating,
                          resolutions: resolutions,
                          watched: item.watched,
                          imageHeight: imageHeight,
                          titleFontSize: layout.homePosterTitleFontSize,
                          subtitleFontSize: layout.homePosterSubtitleFontSize,
                          expandImageToFit: false,
                          imageFit: BoxFit.contain,
                          autoFitByImageAspect: false,
                          heroTag:
                              'category_${widget.category.id}_${item.id}_$index',
                          onTap: () => _openItemDetail(
                            item,
                            heroTag:
                                'category_${widget.category.id}_${item.id}_$index',
                          ),
                          onLongPress: () => _showPosterItemActions(item),
                        );
                      },
                    );
                  },
                )
              else
                GridView.builder(
                  controller: _scrollController,
                  cacheExtent: _viewportCacheExtent(context),
                  padding: EdgeInsets.fromLTRB(
                    layout.pageHorizontalPadding,
                    0,
                    layout.pageHorizontalPadding,
                    bottomPadding,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: layout.categoryGridColumns,
                    mainAxisSpacing: layout.itemGap,
                    crossAxisSpacing: layout.itemGap,
                    mainAxisExtent: layout.categoryGridRowHeight,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final urls = _posterCandidates(
                      baseUrl,
                      item,
                      width: layout.categoryGridRequestWidth,
                    );
                    final rating = double.tryParse(item.rating);
                    final resolutions = item.resolutions
                        .map(_resolutionLabel)
                        .where((e) => e.isNotEmpty)
                        .toList();

                    return MediaPosterCard(
                      urls: urls,
                      token: token,
                      title: item.displayTitle,
                      subtitle: _cardSubtitle(item),
                      rating: rating,
                      resolutions: resolutions,
                      watched: item.watched,
                      imageHeight: layout.categoryGridImageHeight,
                      titleFontSize: layout.homePosterTitleFontSize,
                      subtitleFontSize: layout.homePosterSubtitleFontSize,
                      expandImageToFit: false,
                      imageFit: _isEpisodeItem(item)
                          ? BoxFit.contain
                          : BoxFit.cover,
                      heroTag:
                          'category_${widget.category.id}_${item.id}_$index',
                      onTap: () => _openItemDetail(
                        item,
                        heroTag:
                            'category_${widget.category.id}_${item.id}_$index',
                      ),
                      onLongPress: () => _showPosterItemActions(item),
                    );
                  },
                ),
              if (_isLoadingMore)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_loadMoreError != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _fetchMore,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(_t('layout.globalError.refresh', 'Retry')),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryToolButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _CategoryToolButton({
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
          color: active ? colors.selectionSoft : colors.backgroundElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? colors.selection : colors.chipBorder,
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
