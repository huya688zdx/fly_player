import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_collection_view_type.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_localization_lookup.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/library/media_collection_layout_sheet.dart';
import '../widgets/library/media_library_list_tile.dart';
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

  Future<void> _initLoad() async {
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
    } catch (_) {}

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
      final episodeText = _t(
        'layout.subheading.tv.episodes',
        '{count} episodes',
        params: <String, Object?>{'count': episodeCount},
      );
      return period.isEmpty ? episodeText : '$episodeText · $period';
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '{count} seasons',
        params: <String, Object?>{'count': seasonCount},
      );
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
      return _t('stream.video.videoResolution.others', 'Other');
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
        return _t('layout.list.favoriteTabs.movie', 'Movies');
      case 'TV':
        return _t('layout.list.favoriteTabs.tv', 'TV');
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
        return _t('stream.audio.audioSpecs.dolbySurround', 'Dolby Surround');
      case 'DolbyAtmos':
        return _t('stream.audio.audioSpecs.dolbyAtmos', 'Dolby Atmos');
      case 'DTS':
        return _t('stream.audio.audioSpecs.dts', 'DTS');
      case 'Stereo':
        return _t('stream.audio.audioSpecs.stereo', 'Stereo');
      case 'Others':
        return _t('stream.audio.audioSpecs.others', 'Other');
      default:
        return raw;
    }
  }

  String _decadeLabel(dynamic value) {
    final raw = value.toString();
    if (raw == 'Recent') {
      return _t('layout.list.filter.decade.Recent', 'This year');
    }
    return raw;
  }

  String _recognitionStatusLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? 0;
    if (code == 1) {
      return _t('layout.list.filter.recognitionStatus.1', 'Unmatched');
    }
    if (code == 2) {
      return _t('layout.list.filter.recognitionStatus.2', 'Matched');
    }
    if (code == 3) {
      return _t('layout.list.filter.recognitionStatus.3', 'NFO matched');
    }
    return value.toString();
  }

  String _watchedLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? -1;
    if (code == 1) return _t('layout.list.filter.watched.1', 'Watched');
    if (code == 0) return _t('layout.list.filter.watched.0', 'Unwatched');
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
      return _t('layout.list.filter.filterButton', 'Filter');
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
    await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
      '',
      viewType: next.storageValue,
      key: _favoriteListSettingKey,
    );
  }

  _FavoriteTabData _dataOf(_FavoriteTab tab) => _tabData[tab]!;

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
      final page = await FeiniuApi(context.read<NasProvider>()).getFavoritePage(
        tags: _requestTags(tab),
        sortType: _sortType,
        sortColumn: _sortColumn,
        page: pageNo,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        data.total = page.total;
        data.currentPage = pageNo;
        data.items = reset
            ? page.items
            : <MediaLibraryItem>[...data.items, ...page.items];
        data.hasMore = data.items.length < data.total && page.items.isNotEmpty;
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
    await const MediaItemActionSheetController().show(
      context,
      item: item,
      title: MediaItemActionSheetController.defaultTitle(item),
      localeMap: _localeMap,
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
        return _t('layout.list.sort.sortField.createTime', 'By favorite date');
      case 'release_date':
        return _t('layout.list.sort.sortField.releaseDate', 'By release year');
      case 'title':
        return _t('layout.list.sort.sortField.title', 'By title');
      case 'vote_average':
        return _t('layout.list.sort.sortField.voteAverage', 'By rating');
      default:
        return _t('layout.list.sort.sortField.createTime', 'By favorite date');
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
    } catch (_) {
      // Keep the current episode still if parent poster lookup fails.
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
    } catch (_) {}
    if (!mounted) return;
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.guid,
        initialItemDetail: initialDetail,
      ),
      presentation: _detailPresentation,
    );
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}
