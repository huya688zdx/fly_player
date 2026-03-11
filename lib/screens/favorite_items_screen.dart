import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../ui/app_transitions.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/media_locale_store.dart';
import '../utils/media_locale_text.dart';
import '../widgets/common/app_error_state.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';

enum _FavoriteTab { all, movie, tv, episode, person }

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
  const FavoriteItemsScreen({super.key});

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

  Map<String, dynamic> _localeMap = {};
  Map<String, List<dynamic>> _tagOptions = {};
  Map<int, String> _genresFromApi = {};
  Map<String, String> _locateFromApi = {};

  _FavoriteTab _selectedTab = _FavoriteTab.all;
  String _sortColumn = 'create_time';
  String _sortType = 'DESC';

  Set<dynamic> _selectedGenres = {};
  Set<dynamic> _selectedMediaTypes = {};
  Set<dynamic> _selectedLocate = {};
  Set<dynamic> _selectedDecades = {};
  Set<dynamic> _selectedResolutions = {};
  Set<dynamic> _selectedColorRange = {};
  Set<dynamic> _selectedAudioType = {};
  Set<dynamic> _selectedRecognitionStatus = {};
  Set<dynamic> _selectedWatched = {};

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

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const {},
  }) {
    return MediaLocaleText.text(
      _localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _initLoad() async {
    final api = FeiniuApi(context.read<NasProvider>());
    final localeMap = await MediaLocaleStore.load(context.read<NasProvider>());
    final genresMap = await api.getTagGenresMap(lan: 'zh-CN');
    final locateMap = await api.getTagIso3166Map(lan: 'zh-CN');

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
    });
    await _fetch(tab: _selectedTab, reset: true);
  }

  List<String>? _tabTypeFilter(_FavoriteTab tab) {
    switch (tab) {
      case _FavoriteTab.all:
        return null;
      case _FavoriteTab.movie:
        return const ['Movie'];
      case _FavoriteTab.tv:
        return const ['TV'];
      case _FavoriteTab.episode:
        return const ['Episode'];
      case _FavoriteTab.person:
        return const ['Person'];
    }
  }

  Map<String, dynamic> _requestTags(_FavoriteTab tab) {
    final tags = <String, dynamic>{};
    final type = _tabTypeFilter(tab);
    if (tab == _FavoriteTab.all) {
      if (_selectedMediaTypes.isNotEmpty) {
        tags['type'] = _selectedMediaTypes.map((e) => '$e').toList();
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
        return '共 $workCount 个作品';
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
      final epText = _t(
        'layout.subheading.tv.episodes',
        '共 {count} 集',
        params: {'count': episodeCount},
      );
      return period.isEmpty ? epText : '$epText · $period';
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '共 {count} 季',
        params: {'count': seasonCount},
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
      return _t('stream.video.videoResolution.others', '其他');
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
        return _t('layout.list.favoriteTabs.movie', '电影');
      case 'TV':
        return _t('layout.list.favoriteTabs.tv', '电视剧');
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
        return _t('stream.audio.audioSpecs.dolbySurround', '杜比环绕');
      case 'DolbyAtmos':
        return _t('stream.audio.audioSpecs.dolbyAtmos', '杜比全景声');
      case 'DTS':
        return _t('stream.audio.audioSpecs.dts', 'DTS');
      case 'Stereo':
        return _t('stream.audio.audioSpecs.stereo', '立体声');
      case 'Others':
        return _t('stream.audio.audioSpecs.others', '其他');
      default:
        return raw;
    }
  }

  String _decadeLabel(dynamic value) {
    final raw = value.toString();
    if (raw == 'Recent') {
      return _t('layout.list.filter.decade.Recent', '今年');
    }
    return raw;
  }

  String _recognitionStatusLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? 0;
    if (code == 1) {
      return _t('layout.list.filter.recognitionStatus.1', '未匹配');
    }
    if (code == 2) {
      return _t('layout.list.filter.recognitionStatus.2', '已匹配');
    }
    if (code == 3) {
      return _t('layout.list.filter.recognitionStatus.3', 'NFO匹配');
    }
    return value.toString();
  }

  String _watchedLabel(dynamic value) {
    final code = int.tryParse(value.toString()) ?? -1;
    if (code == 1) return _t('layout.list.filter.watched.1', '已观看');
    if (code == 0) return _t('layout.list.filter.watched.0', '未观看');
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
      return _t('layout.list.filter.filterButton', '筛选');
    }
    return parts.join(' / ');
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
        data.items = reset ? page.items : [...data.items, ...page.items];
        data.hasMore = data.items.length < data.total && page.items.isNotEmpty;
        data.isLoading = false;
        data.isLoadingMore = false;
      });
      _prefetchAdjacentTabs(tab);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          data.isLoading = false;
          data.error = AppException.from(
            e,
            action: 'favorite list',
            fallbackKind: AppExceptionKind.transient,
          );
        } else {
          data.isLoadingMore = false;
          data.loadMoreError = AppException.from(
            e,
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

  void _prefetchAdjacentTabs(_FavoriteTab tab) {
    final index = tab.index;
    final candidates = <_FavoriteTab>[
      if (index - 1 >= 0) _FavoriteTab.values[index - 1],
      if (index + 1 < _FavoriteTab.values.length)
        _FavoriteTab.values[index + 1],
    ];
    for (final candidate in candidates) {
      final data = _dataOf(candidate);
      if (data.items.isNotEmpty || data.isLoading || data.isLoadingMore) {
        continue;
      }
      _fetch(tab: candidate, reset: true);
    }
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
        return _t('layout.list.sort.sortField.createTime', '按添加日期');
      case 'release_date':
        return _t('layout.list.sort.sortField.releaseDate', '按发行年份');
      case 'title':
        return _t('layout.list.sort.sortField.title', '按标题');
      case 'vote_average':
        return _t('layout.list.sort.sortField.voteAverage', '按评分');
      default:
        return _t('layout.list.sort.sortField.createTime', '按添加日期');
    }
  }

  Future<void> _openSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141C29),
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
                  _t('layout.list.sort.title', '排序'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final column in _sortColumns)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 0,
                    visualDensity: const VisualDensity(vertical: -1),
                    title: Text(
                      _sortLabelFor(column),
                      style: TextStyle(
                        color: column == _sortColumn
                            ? Colors.white
                            : Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    trailing: column == _sortColumn
                        ? Text(
                            _sortType == 'ASC'
                                ? '${_t('layout.list.sort.sortType.asc', '升序')} ↑'
                                : '${_t('layout.list.sort.sortType.desc', '降序')} ↓',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          )
                        : null,
                    onTap: () {
                      if (column == _sortColumn) {
                        _sortType = _sortType == 'ASC' ? 'DESC' : 'ASC';
                      } else {
                        _sortColumn = column;
                        _sortType = 'DESC';
                      }
                      Navigator.of(context).pop();
                      _reloadAfterQueryChanged();
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
    final tempMediaTypes = Set<dynamic>.from(_selectedMediaTypes);
    final tempGenres = Set<dynamic>.from(_selectedGenres);
    final tempLocate = Set<dynamic>.from(_selectedLocate);
    final tempDecades = Set<dynamic>.from(_selectedDecades);
    final tempResolutions = Set<dynamic>.from(_selectedResolutions);
    final tempColorRange = Set<dynamic>.from(_selectedColorRange);
    final tempAudioType = Set<dynamic>.from(_selectedAudioType);
    final tempRecognition = Set<dynamic>.from(_selectedRecognitionStatus);
    final tempWatched = Set<dynamic>.from(_selectedWatched);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141C29),
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
                    color: selected
                        ? const Color(0xFF0D4CA3)
                        : const Color(0xFF1D2735),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            Widget section(
              String title,
              List<dynamic> values,
              Set<dynamic> selected,
              String Function(dynamic) labeler,
            ) {
              if (values.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    children: [
                      chip(
                        _t('layout.list.filter.all', '全部'),
                        selected.isEmpty,
                        () => setModal(() => selected.clear()),
                      ),
                      for (final v in values)
                        chip(
                          labeler(v),
                          selected.contains(v),
                          () => setModal(() {
                            if (selected.contains(v)) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..add(v);
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
                            _t('layout.list.filter.filterButton', '筛选'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            section(
                              _t('layout.list.filter.tagMap.type', '影视类型'),
                              _selectedTab == _FavoriteTab.all
                                  ? const ['Movie', 'TV']
                                  : const [],
                              tempMediaTypes,
                              _mediaTypeLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.genres', '类型'),
                              _tagOptions['genres'] ?? const [],
                              tempGenres,
                              _genreLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.locate', '国家和地区'),
                              _tagOptions['locate'] ?? const [],
                              tempLocate,
                              _locateLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.decade', '发行年份'),
                              _tagOptions['decades'] ?? const [],
                              tempDecades,
                              _decadeLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.resolution', '分辨率'),
                              _tagOptions['resolutions'] ?? const [],
                              tempResolutions,
                              (v) => _resolutionLabel('$v'),
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.color_range',
                                '视频动态范围',
                              ),
                              _tagOptions['color_range'] ?? const [],
                              tempColorRange,
                              (v) => '$v',
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.audio_type',
                                '音频规格',
                              ),
                              _tagOptions['audio_type'] ?? const [],
                              tempAudioType,
                              _audioLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.recognition_status',
                                '匹配状态',
                              ),
                              _tagOptions['recognition_status'] ?? const [],
                              tempRecognition,
                              _recognitionStatusLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.watched', '是否已观看'),
                              const [1, 0],
                              tempWatched,
                              _watchedLabel,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModal(() {
                                  tempMediaTypes.clear();
                                  tempGenres.clear();
                                  tempLocate.clear();
                                  tempDecades.clear();
                                  tempResolutions.clear();
                                  tempColorRange.clear();
                                  tempAudioType.clear();
                                  tempRecognition.clear();
                                  tempWatched.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0x334F6B8F),
                                ),
                                foregroundColor: Colors.white70,
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('layout.list.filter.resetButton', '重置'),
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
                                  _selectedMediaTypes = tempMediaTypes;
                                  _selectedGenres = tempGenres;
                                  _selectedLocate = tempLocate;
                                  _selectedDecades = tempDecades;
                                  _selectedResolutions = tempResolutions;
                                  _selectedColorRange = tempColorRange;
                                  _selectedAudioType = tempAudioType;
                                  _selectedRecognitionStatus = tempRecognition;
                                  _selectedWatched = tempWatched;
                                });
                                _reloadAfterQueryChanged();
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('common.actions.default.default', '确定'),
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

  List<String> _posterCandidates(
    String baseUrl,
    String rawPath, {
    int width = 400,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  bool _isPersonItem(MediaLibraryItem item) {
    final t = item.type.trim().toLowerCase();
    return t == 'person';
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  Future<void> _openItemDetail(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) return;
    if (_isPersonItem(item)) {
      Navigator.of(context).push(
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

    final provider = context.read<NasProvider>();
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        provider,
      ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 240));
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        PlayDetailScreen(
          itemGuid: item.guid,
          heroTag: null,
          initialItemDetail: initialDetail,
        ),
      ),
    );
  }

  Widget _buildTabButton(_FavoriteTab tab, String text) {
    final selected = _selectedTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => _switchTab(tab),
        child: SizedBox(
          height: 42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: selected ? const Color(0xFF2D87FF) : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF2D87FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabPage(
    MediaLayoutProfile layout,
    NasProvider provider,
    _FavoriteTab tab,
  ) {
    return Column(
      children: [
        _buildSortFilterRow(layout, tab),
        Expanded(
          child: _buildGrid(
            tab: tab,
            baseUrl: provider.baseUrl,
            token: provider.token,
            layout: layout,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NasProvider>();
    final layout = MediaLayoutProfile.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101B),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        title: Text(_t('layout.sidebar.favorite', '收藏')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                AppTransitions.fadeSlideRoute(
                  SearchScreen(initialLocaleMap: _localeMap),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _buildTabButton(
                  _FavoriteTab.all,
                  _t('layout.list.favoriteTabs.all', '全部'),
                ),
                _buildTabButton(
                  _FavoriteTab.movie,
                  _t('layout.list.favoriteTabs.movie', '电影'),
                ),
                _buildTabButton(
                  _FavoriteTab.tv,
                  _t('layout.list.favoriteTabs.tv', '电视节目'),
                ),
                _buildTabButton(
                  _FavoriteTab.episode,
                  _t('layout.list.favoriteTabs.episode', '单集'),
                ),
                _buildTabButton(
                  _FavoriteTab.person,
                  _t('layout.list.favoriteTabs.person', '人物'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: _FavoriteTab.values
                  .map((tab) => _buildCurrentTabPage(layout, provider, tab))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortFilterRow(MediaLayoutProfile layout, _FavoriteTab tab) {
    final tabData = _dataOf(tab);
    final showFilter = tab != _FavoriteTab.person;
    return Padding(
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
                        _sortLabelFor(_sortColumn),
                        style: const TextStyle(
                          color: Colors.white,
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
                        color: Colors.white70,
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
                    color: const Color(0xFF1C2A3A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${max(tabData.total, tabData.items.length)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showFilter)
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: layout.categoryFilterSummaryMaxWidth,
                  ),
                  child: InkWell(
                    onTap: _openFilterSheet,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _filterSummaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF3B82F6),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: Color(0xFF3B82F6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid({
    required _FavoriteTab tab,
    required String baseUrl,
    required String token,
    required MediaLayoutProfile layout,
  }) {
    final data = _dataOf(tab);
    if (data.isLoading && data.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.error != null) {
      return AppErrorState(
        error: data.error!,
        localeMap: _localeMap,
        onRetry: () => _fetch(tab: tab, reset: true),
      );
    }
    if (data.items.isEmpty) {
      return Center(
        child: Text(
          _t('common.other.empty', '没有内容'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    final grid = GridView.builder(
      controller: _tabScrollControllers[tab],
      cacheExtent: MediaQuery.of(context).size.height * 2,
      padding: EdgeInsets.fromLTRB(
        layout.pageHorizontalPadding,
        0,
        layout.pageHorizontalPadding,
        16 + (data.isLoadingMore || data.loadMoreError != null ? 44 : 0),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.categoryGridColumns,
        mainAxisSpacing: layout.itemGap,
        crossAxisSpacing: layout.itemGap,
        mainAxisExtent: layout.categoryGridRowHeight,
      ),
      itemCount: data.items.length,
      itemBuilder: (context, index) {
        final item = data.items[index];
        final urls = _posterCandidates(
          baseUrl,
          item.poster,
          width: layout.categoryGridRequestWidth,
        );
        final rating = double.tryParse(item.voteAverage);
        final resolutions = item.resolutions
            .map(_resolutionLabel)
            .where((e) => e.isNotEmpty)
            .toList();
        final card = MediaPosterCard(
          urls: urls,
          token: token,
          title: item.displayTitle,
          subtitle: _cardSubtitle(item),
          rating: rating,
          resolutions: resolutions,
          imageHeight: layout.categoryGridImageHeight,
          titleFontSize: layout.homePosterTitleFontSize,
          subtitleFontSize: layout.homePosterSubtitleFontSize,
          expandImageToFit: false,
          imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
          heroTag: 'favorite_${tab.index}_${item.guid}_$index',
          onTap: () => _openItemDetail(item),
        );
        return card;
      },
    );

    return Stack(
      children: [
        grid,
        if (data.isLoadingMore)
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
        if (data.loadMoreError != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: Center(
              child: TextButton.icon(
                onPressed: () => _fetch(tab: tab, reset: false),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(_t('layout.globalError.refresh', '刷新重试')),
              ),
            ),
          ),
      ],
    );
  }
}
