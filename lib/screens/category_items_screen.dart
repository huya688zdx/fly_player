import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../api/item_list_request.dart';
import '../models/media_item.dart';
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

class CategoryItemsScreen extends StatefulWidget {
  final MediaItem category;
  final List<String>? initialTypeTags;

  const CategoryItemsScreen({
    super.key,
    required this.category,
    this.initialTypeTags,
  });

  @override
  State<CategoryItemsScreen> createState() => _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends State<CategoryItemsScreen> {
  static const int _pageSize = 50;
  static const double _loadMoreTriggerOffset = 360;

  static const List<String> _sortColumns = <String>[
    'create_time',
    'release_date',
    'title',
    'vote_average',
  ];
  List<MediaLibraryItem> _items = [];
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

  Map<String, List<dynamic>> _tagOptions = {};
  Map<int, String> _genresFromApi = {};
  Map<String, String> _locateFromApi = {};
  Map<String, dynamic> _localeMap = {};

  Set<String> _selectedType = {};
  Set<dynamic> _selectedGenres = {};
  Set<dynamic> _selectedLocate = {};
  Set<dynamic> _selectedDecades = {};
  Set<dynamic> _selectedResolutions = {};
  Set<dynamic> _selectedColorRange = {};
  Set<dynamic> _selectedAudioType = {};
  Set<dynamic> _selectedRecognitionStatus = {};
  Set<dynamic> _selectedWatched = {};

  bool get _typeLocked =>
      widget.initialTypeTags != null && widget.initialTypeTags!.isNotEmpty;

  List<String> get _lockedTypeTags => widget.initialTypeTags ?? const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialTypeTags != null && widget.initialTypeTags!.isNotEmpty) {
      _selectedType = widget.initialTypeTags!.toSet();
    }
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
    return MediaLocaleText.text(
      _localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _loadMeta() async {
    if (_metaLoaded) return;
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final hasAncestor = widget.category.id.trim().isNotEmpty;
    UserListSetting? setting;
    if (hasAncestor) {
      try {
        setting = await api.getUserListSetting(widget.category.id);
      } catch (_) {}
    }
    Map<String, List<dynamic>> tags = const <String, List<dynamic>>{};
    try {
      tags = await api.getTagList(
        ancestorGuid: hasAncestor ? widget.category.id : '',
        isFavorite: 0,
      );
    } catch (_) {}
    final genresMap = await api.getTagGenresMap(lan: 'zh-CN');
    final locateMap = await api.getTagIso3166Map(lan: 'zh-CN');
    final localeMap = await MediaLocaleStore.load(provider);

    if (!mounted) return;
    setState(() {
      _metaLoaded = true;
      _tagOptions = tags;
      _genresFromApi = genresMap;
      _locateFromApi = locateMap;
      _localeMap = localeMap;
      if (setting != null) {
        _sortColumn = setting.sortField;
        _sortType = setting.sortType == 'ASC' ? 'ASC' : 'DESC';
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
      final api = FeiniuApi(context.read<NasProvider>());
      final request = _buildRequest(page: 1);
      final page = await api.getItemsPageByRequest(request);

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

  ItemListRequest _buildRequest({required int page}) {
    final effectiveType = _typeLocked
        ? _lockedTypeTags
        : (_selectedType.isNotEmpty
        ? _selectedType.toList()
        : const ['Movie', 'TV', 'Directory', 'Video']);
    final tags = <String, dynamic>{'type': effectiveType};
    if (_selectedGenres.isNotEmpty) {
      tags['genres'] = _selectedGenres.first;
    }
    if (_selectedLocate.isNotEmpty) {
      tags['locate'] = _selectedLocate.first;
    }
    if (_selectedDecades.isNotEmpty) {
      tags['decade'] = _selectedDecades.first;
    }
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

    return ItemListRequest(
      ancestorGuid: widget.category.id,
      page: page,
      pageSize: _pageSize,
      sortColumn: _sortColumn,
      sortType: _sortType,
      tags: tags,
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
      final request = _buildRequest(page: nextPage);
      final page = await FeiniuApi(
        context.read<NasProvider>(),
      ).getItemsPageByRequest(request);

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

  Future<void> _openItemDetail(MediaLibraryItem item, {String? heroTag}) async {
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

  List<String> _posterCandidates(
      String baseUrl,
      String rawPath, {
        int width = 400,
      }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  bool _isPersonItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
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

    if (seasonCount == 1 && episodeCount > 0) {
      if (period.isEmpty) return '共$episodeCount集';
      return '共$episodeCount集 · $period';
    }
    if (seasonCount > 0) {
      if (period.isEmpty) return '共$seasonCount季';
      return '共$seasonCount季 · $period';
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

  String get _filterSummaryLabel {
    final parts = <String>[];
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
    if (!_typeLocked && _selectedType.isNotEmpty && _selectedType.length < 4) {
      parts.add(_typeLabel(_selectedType.first));
    }
    if (parts.isEmpty) {
      return _t('layout.list.filter.filterButton', '筛选');
    }
    return parts.join(' / ');
  }

  String _genreLabel(dynamic value) {
    if (value is int) {
      return _genresFromApi[value] ?? value.toString();
    }
    return value.toString();
  }

  String _locateLabel(dynamic value) {
    final code = value.toString().toUpperCase();
    return _locateFromApi[code] ?? value.toString();
  }

  String _audioLabel(dynamic value) {
    final raw = value.toString();
    switch (raw) {
      case 'DolbySurround':
        return _t(
          'stream.audio.audioSpecs.dolbySurround',
          '杜比环绕',
        );
      case 'DolbyAtmos':
        return _t(
          'stream.audio.audioSpecs.dolbyAtmos',
          '杜比全景声',
        );
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

  String _typeLabel(String value) {
    switch (value) {
      case 'Movie':
        return _t('layout.list.filter.type.movie', '电影');
      case 'TV':
        return _t('layout.list.filter.type.tv', '电视剧');
      case 'Directory':
        return _t('common.resourceType.directory', '目录');
      case 'Video':
        return _t('common.resourceType.video', '视频');
      default:
        return value;
    }
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
    if (code == 1)
      return _t('layout.list.filter.watched.1', '已观看');
    if (code == 0)
      return _t('layout.list.filter.watched.0', '未观看');
    return value.toString();
  }

  String get _sortLabel {
    return _sortLabelFor(_sortColumn);
  }

  String _sortLabelFor(String column) {
    switch (column) {
      case 'create_time':
        return _t(
          'layout.list.sort.sortField.createTime',
          '按添加日期',
        );
      case 'release_date':
        return _t(
          'layout.list.sort.sortField.releaseDate',
          '按发行年份',
        );
      case 'title':
        return _t('layout.list.sort.sortField.title', '按标题');
      case 'vote_average':
        return _t(
          'layout.list.sort.sortField.voteAverage',
          '按评分',
        );
      default:
        return _t(
          'layout.list.sort.sortField.createTime',
          '按添加日期',
        );
    }
  }

  IconData get _sortArrow =>
      _sortType == 'ASC' ? Icons.arrow_upward : Icons.arrow_downward;

  TextStyle get _bold12 => const TextStyle(
    color: Colors.white70,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

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
                  style: TextStyle(
                    color: Colors.white,
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
                        ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _sortType == 'ASC'
                              ? '${_t('layout.list.sort.sortType.asc', '升序')} ↑'
                              : '${_t('layout.list.sort.sortType.desc', '降序')} ↓',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
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

    final tempType = Set<String>.from(_selectedType);
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
                  Text(title, style: _bold12),
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
                            _t(
                              'layout.list.filter.filterButton',
                              '筛选',
                            ),
                            style: TextStyle(
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
                            if (!_typeLocked)
                              section(
                                _t(
                                  'layout.list.filter.tagMap.type',
                                  '影视分类',
                                ),
                                const ['Movie', 'TV'],
                                tempType,
                                    (v) => v == 'Movie'
                                    ? _t(
                                  'layout.list.filter.type.movie',
                                  '电影',
                                )
                                    : _t(
                                  'layout.list.filter.type.tv',
                                  '电视剧',
                                ),
                              ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.genres',
                                '类型',
                              ),
                              _tagOptions['genres'] ?? const [],
                              tempGenres,
                              _genreLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.locate',
                                '国家和地区',
                              ),
                              _tagOptions['locate'] ?? const [],
                              tempLocate,
                              _locateLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.decade',
                                '发行年份',
                              ),
                              _tagOptions['decades'] ?? const [],
                              tempDecades,
                              _decadeLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.resolution',
                                '分辨率',
                              ),
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
                              _t(
                                'layout.list.filter.tagMap.watched',
                                '是否观看',
                              ),
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
                                  tempType
                                    ..clear()
                                    ..addAll(_lockedTypeTags);
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
                                _t(
                                  'layout.list.filter.resetButton',
                                  '重置',
                                ),
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
                                  _selectedType = _typeLocked
                                      ? _lockedTypeTags.toSet()
                                      : tempType;
                                  _selectedGenres = tempGenres;
                                  _selectedLocate = tempLocate;
                                  _selectedDecades = tempDecades;
                                  _selectedResolutions = tempResolutions;
                                  _selectedColorRange = tempColorRange;
                                  _selectedAudioType = tempAudioType;
                                  _selectedRecognitionStatus = tempRecognition;
                                  _selectedWatched = tempWatched;
                                });
                                _fetch();
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t(
                                  'common.actions.default.default',
                                  '确定',
                                ),
                                style: TextStyle(fontWeight: FontWeight.w700),
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
        title: Text(widget.category.name),
      ),
      body: _buildBody(provider.baseUrl, provider.token),
    );
  }

  Widget _buildBody(String baseUrl, String token) {
    final layout = MediaLayoutProfile.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppErrorState(
        error: _error!,
        localeMap: _localeMap,
        onRetry: _fetch,
      );
    }

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
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(_sortArrow, size: 16, color: Colors.white70),
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
                        '${max(_total, _items.length)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
        ),
        Expanded(
          child: Stack(
            children: [
              GridView.builder(
                controller: _scrollController,
                cacheExtent: MediaQuery.of(context).size.height * 2,
                padding: EdgeInsets.fromLTRB(
                  layout.pageHorizontalPadding,
                  0,
                  layout.pageHorizontalPadding,
                  16 + (_isLoadingMore || _loadMoreError != null ? 44 : 0),
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
                    item.poster,
                    width: layout.categoryGridRequestWidth,
                  );
                  final rating = double.tryParse(item.voteAverage);
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
                    imageHeight: layout.categoryGridImageHeight,
                    titleFontSize: layout.homePosterTitleFontSize,
                    subtitleFontSize: layout.homePosterSubtitleFontSize,
                    expandImageToFit: false,
                    imageFit: _isEpisodeItem(item)
                        ? BoxFit.contain
                        : BoxFit.cover,
                    heroTag:
                    'category_${widget.category.id}_${item.guid}_$index',
                    onTap: () => _openItemDetail(
                      item,
                      heroTag:
                      'category_${widget.category.id}_${item.guid}_$index',
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
                      label: Text(
                        _t('layout.globalError.refresh', '加载更多失败，点击重试'),
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