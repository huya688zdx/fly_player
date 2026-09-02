import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../desktop/desktop.dart';
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/filter/media_catalog_filter.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_image_ref.dart';
import '../media_backend/media_item_card.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_collection_view_type.dart';
import '../models/media_library_item.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
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
import '../widgets/common/bird_loader.dart';
import 'search_screen.dart';

part 'favorite_items_screen_sheets.dart';
part 'favorite_items_screen_widgets.dart';

enum _FavoriteTab { all, movie, tv, episode, person }

const String _favoriteListSettingKey = 'mdb:list:setting:favorite';

class _FavoriteTabData {
  List<MediaLibraryItem> items = <MediaLibraryItem>[];
  int total = 0;
  int currentPage = 1;
  bool hasMore = true;
  bool isLoading = false;
  bool isLoadingMore = false;
  AppException? error;
  AppException? loadMoreError;
}

class FavoriteItemsScreen extends StatefulWidget {
  final bool secondaryHost;

  const FavoriteItemsScreen({super.key, this.secondaryHost = false});
  const FavoriteItemsScreen.secondaryHost({super.key}) : secondaryHost = true;

  @override
  State<FavoriteItemsScreen> createState() => _FavoriteItemsScreenState();
}

class _FavoriteItemsScreenState extends State<FavoriteItemsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 50;
  static const double _loadMoreTriggerOffset = 360;
  static const List<String> _sortColumns = <String>[
    'create_time',
    'release_date',
    'title',
    'vote_average',
  ];

  late final TabController _tabController;
  late final Map<_FavoriteTab, ScrollController> _tabScrollControllers;
  late final Map<_FavoriteTab, _FavoriteTabData> _tabData;

  Map<String, dynamic> _localeMap = <String, dynamic>{};
  Map<String, List<dynamic>> _tagOptions = <String, List<dynamic>>{};
  Map<int, String> _genresFromApi = <int, String>{};
  Map<String, String> _locateFromApi = <String, String>{};
  final Map<String, MediaLibraryItem> _episodePosterParentCache =
      <String, MediaLibraryItem>{};
  final Map<String, MediaImageRequest> _itemImageRequests =
      <String, MediaImageRequest>{};
  final Set<String> _episodePosterParentPending = <String>{};

  _FavoriteTab _selectedTab = _FavoriteTab.all;
  String _sortColumn = 'create_time';
  String _sortType = 'DESC';
  MediaCollectionViewType _viewType = MediaCollectionViewType.verticalPoster;

  Set<dynamic> _selectedGenres = <dynamic>{};
  Set<dynamic> _selectedMediaTypes = <dynamic>{};
  Set<dynamic> _selectedLocate = <dynamic>{};
  Set<dynamic> _selectedDecades = <dynamic>{};
  Set<dynamic> _selectedResolutions = <dynamic>{};
  Set<dynamic> _selectedColorRange = <dynamic>{};
  Set<dynamic> _selectedAudioType = <dynamic>{};
  Set<dynamic> _selectedRecognitionStatus = <dynamic>{};
  Set<dynamic> _selectedWatched = <dynamic>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _FavoriteTab.values.length,
      vsync: this,
      initialIndex: _selectedTab.index,
    )..addListener(_handleTabControllerChanged);
    _tabScrollControllers = <_FavoriteTab, ScrollController>{
      for (final tab in _FavoriteTab.values) tab: ScrollController(),
    };
    _tabData = <_FavoriteTab, _FavoriteTabData>{
      for (final tab in _FavoriteTab.values) tab: _FavoriteTabData(),
    };
    for (final entry in _tabScrollControllers.entries) {
      final tab = entry.key;
      entry.value.addListener(() => _onScroll(tab));
    }
    _initLoad();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabControllerChanged);
    _tabController.dispose();
    for (final controller in _tabScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setStateIfMounted(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  /// 当前是否飞牛后端。决定标签筛选行、服务端列表偏好持久化等飞牛专属能力是否可用;
  /// 非飞牛(Emby 等）复用本页渲染但隐藏这些专属能力。
  bool get _isFeiniuBackend =>
      context.read<MediaBackendProvider>().backend.capabilities.kind ==
      MediaBackendKind.feiniu;

  Future<void> _initLoad() async {
    // 非飞牛后端无飞牛标签字典 / 服务端列表偏好,直接加载收藏卡片(复用本页整套渲染)。
    if (context.read<MediaBackendProvider>().backend.capabilities.kind !=
        MediaBackendKind.feiniu) {
      await _fetch(tab: _selectedTab, reset: true);
      return;
    }
    final api = FeiniuApi(context.read<NasProvider>());
    const localeMap = <String, dynamic>{};
    final genresMap = await api.getTagGenresMap(lan: 'zh-CN');
    final locateMap = await api.getTagIso3166Map(lan: 'zh-CN');
    final setting = await api.getUserListSetting(
      '',
      key: _favoriteListSettingKey,
    );

    Map<String, List<dynamic>> tags = const <String, List<dynamic>>{};
    try {
      tags = await api.getTagList(isFavorite: 1);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load favorite tag filters',
        error: error,
        stackTrace: stackTrace,
        source: 'favorite_items_screen',
      );
    }

    if (!mounted) return;
    setState(() {
      _localeMap = localeMap;
      _genresFromApi = genresMap;
      _locateFromApi = locateMap;
      _tagOptions = tags;
      if (setting != null) {
        _sortColumn = setting.sortField;
        _sortType = setting.sortType == 'ASC' ? 'ASC' : 'DESC';
        _viewType = MediaCollectionViewTypeX.fromStorage(setting.viewType);
      }
    });
    await _fetch(tab: _selectedTab, reset: true);
  }

  List<String>? _tabTypeFilter(_FavoriteTab tab) {
    switch (tab) {
      case _FavoriteTab.all:
        return null;
      case _FavoriteTab.movie:
        return const <String>['Movie'];
      case _FavoriteTab.tv:
        return const <String>['TV'];
      case _FavoriteTab.episode:
        return const <String>['Episode'];
      case _FavoriteTab.person:
        return const <String>['Person'];
    }
  }

  Map<String, dynamic> _requestTags(_FavoriteTab tab) {
    final tags = <String, dynamic>{};
    final type = _tabTypeFilter(tab);
    if (tab == _FavoriteTab.all) {
      if (_selectedMediaTypes.isNotEmpty) {
        tags['type'] = _selectedMediaTypes.map((value) => '$value').toList();
      }
    } else if (type != null) {
      tags['type'] = type;
    }
    if (_selectedGenres.isNotEmpty) tags['genres'] = _selectedGenres.first;
    if (_selectedLocate.isNotEmpty) tags['locate'] = _selectedLocate.first;
    if (_selectedDecades.isNotEmpty) tags['decade'] = _selectedDecades.first;
    if (_selectedResolutions.isNotEmpty) {
      tags['resolution'] = _selectedResolutions.first;
    }
    if (_selectedColorRange.isNotEmpty) {
      tags['color_range'] = _selectedColorRange.first;
    }
    if (_selectedAudioType.isNotEmpty) {
      tags['audio_type'] = _selectedAudioType.first;
    }
    if (_selectedRecognitionStatus.isNotEmpty) {
      tags['recognition_status'] = '${_selectedRecognitionStatus.first}';
    }
    if (_selectedWatched.isNotEmpty) {
      tags['watched'] = '${_selectedWatched.first}';
    }
    return tags;
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _cardSubtitle(MediaLibraryItem item) {
    if (_isPersonItem(item)) {
      final workCount = item.numberOfItem;
      if (workCount > 0) {
        return AppLocalizations.of(context).mediaWorkCount(workCount);
      }
      return '';
    }

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
      ).detailEpisodeTotal(episodeCount);
      return period.isEmpty ? episodeText : '$episodeText · $period';
    }
    if (seasonCount > 0) {
      final seasonText = AppLocalizations.of(
        context,
      ).detailTvSeasonCount(seasonCount);
      return period.isEmpty ? seasonText : '$seasonText · $period';
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
    if (text == 'Others') {
      return AppLocalizations.of(context).commonOther;
    }
    return text;
  }

  String _genreLabel(dynamic value) {
    if (value is int) {
      return _genresFromApi[value] ?? value.toString();
    }
    return value.toString();
  }

  String _mediaTypeLabel(dynamic value) {
    final raw = value.toString();
    switch (raw) {
      case 'Movie':
        return AppLocalizations.of(context).listTypeMovie;
      case 'TV':
        return AppLocalizations.of(context).listTypeTv;
      default:
        return raw;
    }
  }

  String _locateLabel(dynamic value) {
    final code = value.toString().toUpperCase();
    return _locateFromApi[code] ?? value.toString();
  }

  String _audioLabel(dynamic value) {
    final raw = value.toString();
    switch (raw) {
      case 'DolbySurround':
        return AppLocalizations.of(context).audioSpecDolbySurround;
      case 'DolbyAtmos':
        return AppLocalizations.of(context).audioSpecDolbyAtmos;
      case 'DTS':
        return AppLocalizations.of(context).audioSpecDts;
      case 'Stereo':
        return AppLocalizations.of(context).audioSpecStereo;
      case 'Others':
        return AppLocalizations.of(context).commonOther;
      default:
        return raw;
    }
  }

  String _decadeLabel(dynamic value) {
    final raw = value.toString();
    if (raw == 'Recent') {
      return AppLocalizations.of(context).listFilterDecadeRecent;
    }
    return raw;
  }

  String _recognitionStatusLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? 0;
    if (code == 1) {
      return AppLocalizations.of(context).listRecognitionUnmatched;
    }
    if (code == 2) {
      return AppLocalizations.of(context).listRecognitionMatched;
    }
    if (code == 3) {
      return AppLocalizations.of(context).listRecognitionNfo;
    }
    return value.toString();
  }

  String _watchedLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? -1;
    if (code == 1) return AppLocalizations.of(context).listWatched;
    if (code == 0) return AppLocalizations.of(context).listUnwatched;
    return value.toString();
  }

  String get _filterSummaryLabel {
    final parts = <String>[];
    if (_selectedTab == _FavoriteTab.all && _selectedMediaTypes.isNotEmpty) {
      parts.add(_mediaTypeLabel(_selectedMediaTypes.first));
    }
    if (_selectedGenres.isNotEmpty) {
      parts.add(_genreLabel(_selectedGenres.first));
    }
    if (_selectedLocate.isNotEmpty) {
      parts.add(_locateLabel(_selectedLocate.first));
    }
    if (_selectedDecades.isNotEmpty) {
      parts.add(_decadeLabel(_selectedDecades.first));
    }
    if (_selectedColorRange.isNotEmpty) {
      parts.add(_selectedColorRange.first.toString());
    }
    if (_selectedResolutions.isNotEmpty) {
      parts.add(_resolutionLabel(_selectedResolutions.first.toString()));
    }
    if (_selectedAudioType.isNotEmpty) {
      parts.add(_audioLabel(_selectedAudioType.first));
    }
    if (_selectedRecognitionStatus.isNotEmpty) {
      parts.add(_recognitionStatusLabel(_selectedRecognitionStatus.first));
    }
    if (_selectedWatched.isNotEmpty) {
      parts.add(_watchedLabel(_selectedWatched.first));
    }
    if (parts.isEmpty) {
      return AppLocalizations.of(context).listFilterButton;
    }
    return parts.join(' / ');
  }

  bool get _hasActiveFilters =>
      (_selectedTab == _FavoriteTab.all && _selectedMediaTypes.isNotEmpty) ||
      _selectedGenres.isNotEmpty ||
      _selectedLocate.isNotEmpty ||
      _selectedDecades.isNotEmpty ||
      _selectedResolutions.isNotEmpty ||
      _selectedColorRange.isNotEmpty ||
      _selectedAudioType.isNotEmpty ||
      _selectedRecognitionStatus.isNotEmpty ||
      _selectedWatched.isNotEmpty;

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
    if (_isFeiniuBackend) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        '',
        viewType: next.storageValue,
        key: _favoriteListSettingKey,
      );
    }
  }

  _FavoriteTabData _dataOf(_FavoriteTab tab) => _tabData[tab]!;

  /// 非飞牛收藏卡 → 飞牛列表模型的临时桥接,使 Emby 等后端复用本页整套渲染
  /// （网格 / 视图切换 / 排序 / 长按）。待收藏页渲染层迁公共卡片后移除（批次 9）。
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
      // 保留 backdrop 直链：点击时 push 前预取详情 hero（与详情页同 URL 同缓存键）。
      backdropUrl: card.backdropImage.url,
    );
  }

  void _resetTabData(_FavoriteTabData data) {
    data.items = <MediaLibraryItem>[];
    data.total = 0;
    data.currentPage = 1;
    data.hasMore = true;
    data.isLoading = false;
    data.isLoadingMore = false;
    data.error = null;
    data.loadMoreError = null;
  }

  void _resetAllTabData() {
    for (final data in _tabData.values) {
      _resetTabData(data);
    }
  }

  Future<void> _reloadAfterQueryChanged() async {
    if (!mounted) return;
    setState(() {
      _resetAllTabData();
      for (final controller in _tabScrollControllers.values) {
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      }
    });
    await _fetch(tab: _selectedTab, reset: true);
  }

  Future<void> _fetch({required _FavoriteTab tab, required bool reset}) async {
    final data = _dataOf(tab);
    if ((data.isLoading || data.isLoadingMore) && !reset) return;

    if (reset) {
      setState(() {
        data.isLoading = true;
        data.isLoadingMore = false;
        data.error = null;
        data.loadMoreError = null;
        data.currentPage = 1;
        data.hasMore = true;
      });
    } else {
      setState(() {
        data.isLoadingMore = true;
        data.loadMoreError = null;
      });
    }

    try {
      final pageNo = reset ? 1 : (data.currentPage + 1);
      final backend = context.read<MediaBackendProvider>().backend;
      final provider = context.read<NasProvider>();
      final List<MediaLibraryItem> fetchedItems;
      final Map<String, MediaImageRequest> fetchedImageRequests;
      final int fetchedTotal;
      if (backend.capabilities.kind == MediaBackendKind.feiniu) {
        final page = await FeiniuApi(provider).getFavoritePage(
          tags: _requestTags(tab),
          sortType: _sortType,
          sortColumn: _sortColumn,
          page: pageNo,
          pageSize: _pageSize,
        );
        fetchedItems = page.items;
        fetchedImageRequests = const <String, MediaImageRequest>{};
        fetchedTotal = page.total;
      } else {
        // 非飞牛:走中立 queryFavoriteItems,卡片映射为列表模型以复用本页整套渲染。
        final type = _tabTypeFilter(tab);
        final result = await backend.queryFavoriteItems(
          MediaCatalogQuery(
            catalogId: '',
            selection: type == null
                ? const <String, List<String>>{}
                : <String, List<String>>{'type': type},
            sortField: _sortColumn,
            sortType: _sortType,
            page: pageNo,
            pageSize: _pageSize,
          ),
        );
        fetchedItems = result.items
            .map(_cardToLibraryItem)
            .toList(growable: false);
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
        fetchedImageRequests = <String, MediaImageRequest>{
          for (final card in result.items)
            if (card.id.trim().isNotEmpty)
              card.id: resolver.resolveRefs(<MediaImageRef>[
                card.primaryImage,
                ...card.posters,
              ]),
        };
        fetchedTotal = result.total;
      }
      if (!mounted) return;
      setState(() {
        final replacedItemIds = reset
            ? data.items.map((item) => item.guid).toSet()
            : const <String>{};
        for (final id in replacedItemIds) {
          _itemImageRequests.remove(id);
        }
        _itemImageRequests.addAll(fetchedImageRequests);
        data.total = fetchedTotal;
        data.currentPage = pageNo;
        data.items = reset
            ? fetchedItems
            : <MediaLibraryItem>[...data.items, ...fetchedItems];
        data.hasMore =
            data.items.length < data.total && fetchedItems.isNotEmpty;
        data.isLoading = false;
        data.isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          data.isLoading = false;
          data.error = AppException.from(
            error,
            action: 'favorite list',
            fallbackKind: AppExceptionKind.transient,
          );
        } else {
          data.isLoadingMore = false;
          data.loadMoreError = AppException.from(
            error,
            action: 'favorite list',
            fallbackKind: AppExceptionKind.transient,
          );
        }
      });
    }
  }

  void _onScroll(_FavoriteTab tab) {
    final controller = _tabScrollControllers[tab]!;
    final data = _dataOf(tab);
    if (!controller.hasClients) return;
    if (data.isLoading ||
        data.isLoadingMore ||
        !data.hasMore ||
        data.error != null) {
      return;
    }
    final remain =
        controller.position.maxScrollExtent - controller.position.pixels;
    if (remain <= _loadMoreTriggerOffset) {
      _fetch(tab: tab, reset: false);
    }
  }

  Future<void> _switchTab(_FavoriteTab tab) async {
    if (_selectedTab == tab) return;
    _ensureTabLoaded(tab);
    if (mounted) {
      setState(() {
        _selectedTab = tab;
      });
    }
    _tabController.animateTo(
      tab.index,
      duration: AppTransitions.switchDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _ensureTabLoaded(_FavoriteTab tab) async {
    final data = _dataOf(tab);
    if (data.items.isNotEmpty || data.isLoading) return;
    await _fetch(tab: tab, reset: true);
  }

  void _replaceFavoriteItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      for (final data in _tabData.values) {
        data.items = data.items
            .map((item) => item.guid == itemGuid ? transform(item) : item)
            .toList(growable: false);
      }
    });
  }

  void _removeFavoriteItemLocally(String itemGuid) {
    if (!mounted) return;
    setState(() {
      for (final data in _tabData.values) {
        final before = data.items.length;
        data.items = data.items
            .where((item) => item.guid != itemGuid)
            .toList(growable: false);
        final removed = before - data.items.length;
        if (removed > 0 && data.total > 0) {
          data.total = max(0, data.total - removed);
        }
        data.hasMore = data.items.length < data.total;
      }
    });
  }

  Future<void> _showFavoriteItemActions(MediaLibraryItem item) async {
    final l10n = AppLocalizations.of(context);
    final target = item.toActionTarget();
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.defaultTitle(l10n, target),
      favoriteOnly: _isPersonItem(item),
      initialFavorite: true,
      initialWatched: item.watched == 1,
      onChanged: (state) {
        if (!state.favorite) {
          _removeFavoriteItemLocally(item.guid);
          return;
        }
        _replaceFavoriteItemLocally(
          item.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  /// 右键菜单展示前预取已看/收藏态；列表内缓存可能过期，失败回退列表值。
  Future<({bool watched, bool favorite})> _loadItemFlags(
    MediaLibraryItem item,
  ) async {
    var watched = item.watched == 1;
    var favorite = true;
    try {
      final detail = await context
          .read<MediaBackendProvider>()
          .backend
          .getItemDetail(item.guid);
      watched = detail.watched;
      favorite = detail.favorite;
    } catch (error) {
      debugPrint('[UI][FAVORITE] item flags load failed ${item.guid}: $error');
    }
    return (watched: watched, favorite: favorite);
  }

  /// 桌面档媒体卡右键菜单：动作与长按动作表（_showFavoriteItemActions）同源；
  /// 人物条目无「已看」语义，与长按 favoriteOnly 一致只保留详情 + 收藏。
  /// 取消收藏后行从列表移除（与长按动作表 onChanged 同语义）。
  Future<void> _showFavoriteItemContextMenu(
    MediaLibraryItem item,
    Offset position,
  ) async {
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
                itemId: item.guid,
                watched: !flags.watched,
              );
              if (state == null) return;
              _replaceFavoriteItemLocally(
                item.guid,
                (current) => current.copyWith(watched: state ? 1 : 0),
              );
            },
          ),
        DesktopContextMenuEntry(
          label: flags.favorite
              ? l10n.actionFavoriteRemove
              : l10n.actionFavoriteAdd,
          icon: flags.favorite ? Icons.favorite : Icons.favorite_border,
          onSelected: () async {
            final state = await controller.setItemFavorite(
              context,
              itemId: item.guid,
              favorite: !flags.favorite,
            );
            if (state == null || state) return;
            _removeFavoriteItemLocally(item.guid);
          },
        ),
      ],
    );
  }

  void _handleTabControllerChanged() {
    final tab = _FavoriteTab.values[_tabController.index];
    if (_selectedTab != tab && mounted) {
      setState(() {
        _selectedTab = tab;
      });
    }
    if (!_tabController.indexIsChanging) {
      _ensureTabLoaded(tab);
    }
  }

  String _sortLabelFor(String column) {
    switch (column) {
      case 'create_time':
        return AppLocalizations.of(context).listSortCreateTime;
      case 'release_date':
        return AppLocalizations.of(context).listSortReleaseDate;
      case 'title':
        return AppLocalizations.of(context).listSortTitleField;
      case 'vote_average':
        return AppLocalizations.of(context).listSortVoteAverage;
      default:
        return AppLocalizations.of(context).listSortCreateTime;
    }
  }

  List<String> _posterCandidates(
    String baseUrl,
    MediaLibraryItem item, {
    int width = 400,
    bool preferDirectPath = false,
  }) {
    final paths = <String>[
      if (item.poster.trim().isNotEmpty) item.poster.trim(),
      ...item.posterList.where((path) => path.trim().isNotEmpty),
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

  /// F-031:海报图请求统一在此产出(经 [mediaImageRequestForUrls] 单一入口),
  /// 网格/列表构建不再向下透传 baseUrl/token。
  MediaImageRequest _posterImages(
    MediaLibraryItem item, {
    int width = 400,
    bool preferDirectPath = false,
  }) {
    final provider = context.read<NasProvider>();
    return preferPreservedImageRequest(
      preserved: _itemImageRequests[item.guid],
      fallbackUrls: _posterCandidates(
        provider.baseUrl,
        item,
        width: width,
        preferDirectPath: preferDirectPath,
      ),
      fallbackToken: _isFeiniuBackend ? provider.token : '',
      fallbackAccessCode: _isFeiniuBackend ? provider.accessCode : '',
      fallbackBaseUrl: _isFeiniuBackend ? provider.baseUrl : '',
    );
  }

  bool _isPersonItem(MediaLibraryItem item) {
    final type = item.type.trim().toLowerCase();
    return type == 'person';
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  DetailPresentation get _detailPresentation =>
      widget.secondaryHost ? DetailPresentation.pane : DetailPresentation.page;

  double _viewportCacheExtent(BuildContext context) {
    final factor = widget.secondaryHost ? 0.7 : 1.0;
    return min(MediaQuery.of(context).size.height * factor, 900.0);
  }

  MediaLibraryItem _posterWallDisplayItem(MediaLibraryItem item) {
    if (_viewType != MediaCollectionViewType.horizontalPoster ||
        !_isEpisodeItem(item)) {
      return item;
    }
    final parentGuid = item.parentGuid.trim();
    if (parentGuid.isEmpty) {
      return item;
    }
    final parentPoster = _episodePosterParentCache[parentGuid];
    if (parentPoster != null && parentPoster.poster.trim().isNotEmpty) {
      return item.copyWith(
        poster: parentPoster.poster,
        posterWidth: parentPoster.posterWidth,
        posterHeight: parentPoster.posterHeight,
        posterList: parentPoster.posterList,
      );
    }
    _ensureEpisodePosterParentLoaded(parentGuid);
    return item;
  }

  void _ensureEpisodePosterParentLoaded(String parentGuid) {
    if (parentGuid.isEmpty ||
        _episodePosterParentCache.containsKey(parentGuid) ||
        _episodePosterParentPending.contains(parentGuid)) {
      return;
    }
    _episodePosterParentPending.add(parentGuid);
    unawaited(_loadEpisodePosterParent(parentGuid));
  }

  Future<void> _loadEpisodePosterParent(String parentGuid) async {
    try {
      final detail = await FeiniuApi(
        context.read<NasProvider>(),
      ).getItemDetail(parentGuid).timeout(const Duration(seconds: 2));
      final parentItem = MediaLibraryItem.fromJson(detail);
      if (!mounted || parentItem.poster.trim().isEmpty) {
        return;
      }
      setState(() {
        _episodePosterParentCache[parentGuid] = parentItem;
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load favorite episode parent poster',
        id: parentGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'favorite_items_screen',
      );
    } finally {
      _episodePosterParentPending.remove(parentGuid);
    }
  }

  Future<void> _openItemDetail(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) return;
    if (_isPersonItem(item)) {
      await AdaptiveDetailNavigator.open<void>(
        context,
        AdaptiveDetailRequest.person(
          personGuid: item.guid,
          initialName: item.displayTitle,
          initialLocaleMap: _localeMap,
        ),
        presentation: _detailPresentation,
      );
      return;
    }

    final provider = context.read<NasProvider>();
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        provider,
      ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 240));
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'prefetch favorite item detail',
        id: item.guid,
        error: error,
        stackTrace: stackTrace,
        source: 'favorite_items_screen',
      );
    }
    if (!mounted) return;
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.guid,
        initialItemDetail: initialDetail,
        // Emby 等直链后端：push 前预取详情 hero（背景图优先、海报兜底）。
        // 飞牛条目这两个字段是空/相对路径，导航层自动回退旧管线。
        heroImageRefs: <MediaImageRef>[
          if (item.backdropUrl.trim().isNotEmpty)
            MediaImageRef(url: item.backdropUrl),
          if (item.poster.trim().startsWith('http'))
            MediaImageRef(url: item.poster),
        ],
      ),
      presentation: _detailPresentation,
    );
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}
