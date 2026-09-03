import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../desktop/desktop.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/filter/media_catalog_filter.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/action/media_item_action_target.dart';
import '../media_backend/media_image_ref.dart';
import '../media_backend/media_item_card.dart';
import '../models/media_collection_view_type.dart';
import '../models/media_item.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../widgets/common/track_option_sheet.dart';
import '../ui/catalog_filter_localizer.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_episode_subtitle.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/app_catalog_query_sheets.dart';
import '../widgets/app_atmospheric_background.dart';
import '../widgets/library/media_collection_layout_sheet.dart';
import '../widgets/library/media_library_list_tile.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

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

  /// 列表偏好持久化是飞牛专属（mdb 用户设置端点）；其它后端跳过写入。
  bool get _isFeiniuBackend =>
      context.read<MediaBackendProvider>().backend.capabilities.kind ==
      MediaBackendKind.feiniu;

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
    _filterFetchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    await _loadMeta();
    await _fetch();
  }

  Future<void> _loadMeta() async {
    if (_metaLoaded) return;
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final backend = context.read<MediaBackendProvider>().backend;
    final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
    final hasAncestor = widget.category.id.trim().isNotEmpty;
    UserListSetting? setting;
    // 列表排序/视图偏好是飞牛专属持久化（mdb 用户设置端点）；其它后端（Emby）无此口径，
    // 跳过读取，用页面默认值。
    if (hasAncestor && isFeiniu) {
      try {
        setting = await api.getUserListSetting(widget.category.id);
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load category list setting',
          id: widget.category.id,
          error: error,
          stackTrace: stackTrace,
          source: 'category_items_screen',
        );
      }
    }
    var schema = const MediaCatalogFilterSchema();
    try {
      schema = await backend.getCatalogFilterSchema(widget.category.id);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load category filter schema',
        id: widget.category.id,
        error: error,
        stackTrace: stackTrace,
        source: 'category_items_screen',
        details: 'backend=${backend.capabilities.kind.name}',
      );
    }

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

  Future<void> _fetch({bool showLoader = true}) async {
    final seq = ++_fetchSeq;
    setState(() {
      if (showLoader) _isLoading = true;
      _isLoadingMore = false;
      _error = null;
      _loadMoreError = null;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final page = await backend.queryCatalogItems(_buildQuery(page: 1));

      if (!mounted || seq != _fetchSeq) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _currentPage = 1;
        _hasMore = _items.length < _total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _fetchSeq) return;
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
    final l10n = AppLocalizations.of(context);
    final target = MediaItemActionTarget.fromCard(item);
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.defaultTitle(l10n, target),
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

  /// 右键菜单展示前预取已看/收藏态；列表内缓存可能过期，失败回退列表值。
  Future<({bool watched, bool favorite})> _loadItemFlags(
    MediaItemCard item,
  ) async {
    var watched = item.watched;
    var favorite = false;
    try {
      final detail = await context
          .read<MediaBackendProvider>()
          .backend
          .getItemDetail(item.id);
      watched = detail.watched;
      favorite = detail.favorite;
    } catch (error) {
      debugPrint('[UI][CATEGORY] item flags load failed ${item.id}: $error');
    }
    return (watched: watched, favorite: favorite);
  }

  /// 桌面档媒体卡右键菜单：动作与长按动作表（_showPosterItemActions）同源；
  /// 人物条目无「已看」语义，与长按 favoriteOnly 一致只保留详情 + 收藏。
  Future<void> _showItemContextMenu(MediaItemCard item, Offset position) async {
    final favoriteOnly = _isPersonItem(item);
    final flags = await _loadItemFlags(item);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    const controller = MediaItemActionSheetController();
    await showDesktopContextMenu(
      context,
      position: position,
      entries: <DesktopContextMenuEntry>[
        DesktopContextMenuEntry(
          label: l10n.homeActionViewDetail,
          icon: Icons.info_outline,
          onSelected: () => unawaited(_openItemDetail(item)),
        ),
        if (!favoriteOnly)
          DesktopContextMenuEntry(
            label: flags.watched
                ? l10n.actionMarkAsUnwatched
                : l10n.actionMarkAsWatched,
            icon: flags.watched
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            onSelected: () async {
              final state = await controller.setItemWatched(
                context,
                itemId: item.id,
                watched: !flags.watched,
              );
              if (state == null) return;
              _replaceItemLocally(
                item.id,
                (current) => current.copyWith(watched: state),
              );
            },
          ),
        DesktopContextMenuEntry(
          label: flags.favorite
              ? l10n.actionFavoriteRemove
              : l10n.actionFavoriteAdd,
          icon: flags.favorite ? Icons.favorite : Icons.favorite_border,
          onSelected: () => controller.setItemFavorite(
            context,
            itemId: item.id,
            favorite: !flags.favorite,
          ),
        ),
      ],
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
    if (_isLoading ||
        _isLoadingMore ||
        !_hasMore ||
        _error != null ||
        _silentRefreshInFlight) {
      return;
    }
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
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'prefetch category item detail',
        id: item.id,
        error: error,
        stackTrace: stackTrace,
        source: 'category_items_screen',
      );
    }
    if (!mounted) return;
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.id,
        heroTag: heroTag,
        initialItemDetail: initialDetail,
        // Emby 等直链后端：push 前预取详情 hero（背景图优先、海报兜底）。
        // 飞牛卡片这两个引用是空/相对路径，导航层自动回退旧管线。
        heroImageRefs: <MediaImageRef>[
          if (item.backdropImage.isNotEmpty) item.backdropImage,
          if (item.primaryImage.isNotEmpty) item.primaryImage,
        ],
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
    if (item.type.trim().toLowerCase() == 'episode') {
      return mediaEpisodeSubtitle(
        AppLocalizations.of(context),
        item.seasonNumber,
        item.episodeNumber,
        item.title,
      );
    }
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
      return AppLocalizations.of(context).commonOther;
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
      return AppLocalizations.of(context).listFilterButton;
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
    if (widget.category.id.trim().isNotEmpty && _isFeiniuBackend) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        widget.category.id,
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: next.storageValue,
      );
    }
  }

  Future<void> _openSortSheet() async {
    final localizer = _filterLocalizer;
    final result = await AppCatalogSortSheet.show(
      context,
      options: <AppCatalogSortOption>[
        for (final column in _sortColumns)
          AppCatalogSortOption(
            field: column,
            label: localizer.sortLabel(column),
          ),
      ],
      selectedField: _sortColumn,
      sortType: _sortType,
    );
    if (!mounted || result == null) return;
    await _applySortSelection(field: result.field, type: result.sortType);
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
              TrackOptionSheetItem(
                id: column,
                title: _filterLocalizer.sortLabel(column),
              ),
          ],
          selectedId: _sortColumn,
          onSelected: (field) =>
              _applySortSelection(field: field, type: _sortType),
        ),
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            TrackOptionSheetItem(id: 'ASC', title: l10n.listSortAsc),
            TrackOptionSheetItem(id: 'DESC', title: l10n.listSortDesc),
          ],
          selectedId: _sortType,
          onSelected: (type) =>
              _applySortSelection(field: _sortColumn, type: type),
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

  /// 桌面点击下拉直接落地排序（字段/方向各组独立选择）。
  Future<void> _applySortSelection({
    required String field,
    required String type,
  }) async {
    if (field == _sortColumn && type == _sortType) return;
    final nasProvider = context.read<NasProvider>();
    if (!mounted) return;
    setState(() {
      _sortColumn = field;
      _sortType = type;
    });
    if (widget.category.id.trim().isNotEmpty && _isFeiniuBackend) {
      await FeiniuApi(nasProvider).setUserListSetting(
        widget.category.id,
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: _viewType.storageValue,
      );
    }
    if (!mounted) return;
    _fetch();
  }

  /// 桌面点击下拉直接落地视图切换。
  Future<void> _applyLayoutSelection(MediaCollectionViewType next) async {
    if (!mounted || next == _viewType) return;
    setState(() => _viewType = next);
    if (widget.category.id.trim().isNotEmpty && _isFeiniuBackend) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        widget.category.id,
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: next.storageValue,
      );
    }
  }

  bool _filterPanelOpen = false;
  final LayerLink _filterAnchor = LayerLink();
  final OverlayPortalController _filterPortal = OverlayPortalController();
  Timer? _filterFetchDebounce;

  /// 静默刷新进行中：列表原地更新（不显示全屏 loading），期间禁止触底加载。
  bool _silentRefreshInFlight = false;

  /// 递增请求序号：内联筛选即点即刷可能连续触发 _fetch，
  /// 丢弃慢返回的旧响应，避免旧结果覆盖新结果。
  int _fetchSeq = 0;

  /// 筛选维度 → 内联面板 sections（type 锁定时隐藏该维度，空维度不展示）。
  List<AppCatalogFilterSection> _buildFilterSections() {
    final localizer = _filterLocalizer;
    return <AppCatalogFilterSection>[
      for (final dimension in _schema.dimensions)
        if (!(dimension.key == 'type' && _typeLocked) &&
            dimension.options.isNotEmpty)
          AppCatalogFilterSection(
            key: dimension.key,
            title: localizer.dimensionTitle(dimension),
            options: <AppCatalogFilterOption>[
              for (final option in dimension.options)
                AppCatalogFilterOption(
                  value: option.value,
                  label: localizer.optionLabel(dimension, option),
                ),
            ],
            selectedValues: Set<Object>.from(
              _selection[dimension.key] ?? const <String>{},
            ),
            multiSelect: dimension.multiSelect,
          ),
    ];
  }

  Future<void> _toggleFilterPanel() async {
    if (_filterPanelOpen) {
      _closeFilterPanel();
      return;
    }
    if (!_metaLoaded) await _loadMeta();
    if (!mounted) return;
    setState(() => _filterPanelOpen = true);
    _filterPortal.show();
  }

  void _closeFilterPanel() {
    if (!_filterPanelOpen) return;
    _filterPortal.hide();
    setState(() => _filterPanelOpen = false);
  }

  bool _usesFloatingFilterPanel(BuildContext context) {
    return DesktopEnvironment.isDesktopPlatform &&
        MediaQuery.sizeOf(context).width < DesktopBreakpoints.sidebarMinWidth;
  }

  /// 内联面板点选：立即更新选择，防抖后刷新列表。
  void _handleFilterOptionSelected(
    AppCatalogFilterSection section,
    Object? value,
  ) {
    final current = Set<Object>.from(
      _selection[section.key] ?? const <String>{},
    );
    if (value == null) {
      current.clear();
    } else if (section.multiSelect) {
      if (!current.add(value)) current.remove(value);
    } else if (current.contains(value)) {
      current.clear();
    } else {
      current
        ..clear()
        ..add(value);
    }
    setState(() {
      _selection[section.key] = current.map((v) => '$v').toSet();
    });
    _filterFetchDebounce?.cancel();
    _filterFetchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _refreshForFilterChange();
    });
  }

  /// 筛选变更后的静默刷新：不展示全屏 loading，工具栏和面板保持原地。
  Future<void> _refreshForFilterChange() async {
    _silentRefreshInFlight = true;
    try {
      await _fetch(showLoader: false);
    } finally {
      _silentRefreshInFlight = false;
    }
  }

  Widget _buildInlineFilterPanel({required bool floating}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _filterPanelOpen && !floating
          ? AppCatalogFilterInlinePanel(
              sections: _buildFilterSections(),
              onOptionSelected: _handleFilterOptionSelected,
              onCollapse: _closeFilterPanel,
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _buildFloatingFilterPanel(BuildContext overlayContext) {
    if (!_filterPanelOpen || !_usesFloatingFilterPanel(overlayContext)) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(overlayContext);
    final panelWidth = min(560.0, max(320.0, size.width - 24));
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeFilterPanel,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: CompositedTransformFollower(
            link: _filterAnchor,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: UnconstrainedBox(
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: DesktopFloatingPanel(
                  child: SizedBox(
                    width: panelWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: size.height * 0.72,
                      ),
                      child: SingleChildScrollView(
                        child: AppCatalogFilterInlinePanel(
                          sections: _buildFilterSections(),
                          onOptionSelected: _handleFilterOptionSelected,
                          onCollapse: _closeFilterPanel,
                          framed: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NasProvider>();
    final isFeiniu = _isFeiniuBackend;
    final colors = context.appColors;
    final atmosphere = AppAtmospherePalette.resolve(
      baseColors: context.baseAppColors,
      effectiveColors: colors,
      hasDynamicTheme: context.hasRuntimeAppColors,
    );
    return AppAtmosphericBackground(
      palette: atmosphere,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
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
        body: _buildBody(
          isFeiniu ? provider.baseUrl : '',
          isFeiniu ? provider.token : '',
          isFeiniu ? provider.accessCode : '',
        ),
      ),
    );
  }

  Widget _buildBody(String baseUrl, String token, String accessCode) {
    final layout = MediaLayoutProfile.of(context);
    final desktopTier = layout.isDesktopTier;
    final floatingFilter = _usesFloatingFilterPanel(context);
    final colors = context.appColors;
    if (_isLoading) return const Center(child: BirdLoader(size: 132));
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
                    desktopTapDropdownWrapper(
                      dropdownKey: _sortDropdownKey,
                      spec: _sortDropdownSpec,
                      child: InkWell(
                        onTap: _onSortTriggerTap,
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
              desktopTapDropdownWrapper(
                dropdownKey: _layoutDropdownKey,
                spec: _layoutDropdownSpec,
                child: _CategoryToolButton(
                  icon: Icons.grid_view_rounded,
                  active: _viewType != MediaCollectionViewType.list,
                  onTap: _onLayoutTriggerTap,
                ),
              ),
              const SizedBox(width: 10),
              OverlayPortal(
                controller: _filterPortal,
                overlayChildBuilder: _buildFloatingFilterPanel,
                child: CompositedTransformTarget(
                  link: _filterAnchor,
                  child: Tooltip(
                    message: _filterSummaryLabel,
                    child: _CategoryToolButton(
                      icon: Icons.filter_alt_outlined,
                      active: _hasActiveFilters || _filterPanelOpen,
                      onTap: _toggleFilterPanel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildInlineFilterPanel(floating: floatingFilter),
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
                    // 桌面档右键接管条目动作，长按只在触屏档保留。
                    return GestureDetector(
                      onSecondaryTapUp: desktopTier
                          ? (details) => unawaited(
                              _showItemContextMenu(
                                item,
                                details.globalPosition,
                              ),
                            )
                          : null,
                      child: MediaLibraryListTile(
                        images: mediaImageRequestForUrls(
                          _posterCandidates(baseUrl, item, width: 280),
                          token: token,
                          accessCode: accessCode,
                          baseUrl: baseUrl,
                        ),
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
                        onLongPress: desktopTier
                            ? null
                            : () => _showPosterItemActions(item),
                        onMoreTap: () => _showPosterItemActions(item),
                      ),
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

                        return GestureDetector(
                          onSecondaryTapUp: desktopTier
                              ? (details) => unawaited(
                                  _showItemContextMenu(
                                    item,
                                    details.globalPosition,
                                  ),
                                )
                              : null,
                          child: MediaPosterCard(
                            images: mediaImageRequestForUrls(
                              urls,
                              token: token,
                              accessCode: accessCode,
                              baseUrl: baseUrl,
                            ),
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
                            onLongPress: desktopTier
                                ? null
                                : () => _showPosterItemActions(item),
                          ),
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

                    return GestureDetector(
                      onSecondaryTapUp: desktopTier
                          ? (details) => unawaited(
                              _showItemContextMenu(
                                item,
                                details.globalPosition,
                              ),
                            )
                          : null,
                      child: MediaPosterCard(
                        images: mediaImageRequestForUrls(
                          urls,
                          token: token,
                          accessCode: accessCode,
                          baseUrl: baseUrl,
                        ),
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
                        onLongPress: desktopTier
                            ? null
                            : () => _showPosterItemActions(item),
                      ),
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
                      child: BirdGlyph(size: 20),
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
                      label: Text(
                        AppLocalizations.of(context).commonRefreshRetry,
                      ),
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
    final control = AppTonalControlPalette.resolve(
      colors: colors,
      active: active,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: control.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: control.border),
        ),
        child: Icon(icon, color: control.foreground, size: 21),
      ),
    );
  }
}
