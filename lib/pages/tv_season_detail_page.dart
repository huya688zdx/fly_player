import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../api/person_list_request.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../controllers/tv_season_download_sheet_controller.dart';
import '../controllers/tv_season_playback_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/detail/media_episode_summary.dart';
import '../media_backend/detail/media_season_summary.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../models/media_library_item.dart';
import '../models/person_credit.dart';
import '../models/tv_episode_browser_models.dart';
import '../models/tv_episode_picker_mode.dart';
import '../models/play_info.dart';
import '../providers/app_theme_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/detail_runtime_cache.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/native_playback_reentry.dart';
import '../services/native_player_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../theme/dynamic_theme_runtime_controller.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/credit_person_presenter.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/detail_presentation.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/route_transition_gate.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/swallowed_error_logger.dart';
import '../utils/tv_hero_adaptive.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import '../widgets/detail/tv_episode_browser_section.dart';
import '../widgets/detail/tv_episode_picker_sheet.dart';
import '../widgets/detail/tv_season_detail_panel.dart';
import 'long_text_overlay_page.dart';

class TvSeasonDetailPage extends StatefulWidget {
  final String parentGuid;
  final String seriesTitle;
  final String backdropPath;
  final MediaLibraryItem seasonItem;
  final List<MediaLibraryItem>? initialSeasonItems;
  final DetailPresentation presentation;

  const TvSeasonDetailPage({
    super.key,
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    required this.seasonItem,
    this.initialSeasonItems,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<TvSeasonDetailPage> createState() => _TvSeasonDetailPageState();
}

class _TvSeasonDetailPageState extends State<TvSeasonDetailPage>
    with TickerProviderStateMixin {
  static const int _episodePageSize = 30;
  static const String _playlistViewTypeCard = 'card';
  static const String _playlistViewTypeButton = 'button';
  static const double _landscapePanelDropRatio = 0.10;
  static const double _portraitPanelDropRatio = 0.04;
  static const double _topInsetPosterRatio = 0.55;
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);
  static const Duration _headerFadeDuration = Duration(milliseconds: 220);
  static const Duration _seasonDataFadeDuration = Duration(milliseconds: 120);
  static const Duration _deferredStartDelay = Duration(milliseconds: 160);
  static const Duration _deferredCreditsDelay = Duration(milliseconds: 140);
  static const PersonListRequest _creditsRequest = PersonListRequest(
    page: 1,
    pageSize: 200,
  );

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  final DetailTopTip _topTip = DetailTopTip();
  final TvSeasonDownloadSheetController _downloadSheetController =
      const TvSeasonDownloadSheetController();
  final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
  // 本页下载态唯一出口是“整季是否已全部下载”这个 bool；缓存它以在下载任务变化时
  // 跳过无关的全页重建（P7）。
  bool? _seasonFullyDownloadedCache;
  final Map<String, dynamic> _localeMap = const <String, dynamic>{};

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  bool _loading = true;
  AppException? _error;

  String _selectedSeasonGuid = '';
  String _selectedEpisodeGuid = '';
  List<MediaLibraryItem> _seasonItems = const [];
  List<MediaLibraryItem> _episodeItems = const [];
  Object? _reentryToken;
  List<PersonCredit> _personCredits = const [];
  Map<String, dynamic> _detail = const {};
  PlayInfoData? _playInfo;
  String _imdbId = '';
  String _trimId = '';
  // 中立(Emby)展示态:`_neutralDisplayOnly` 时飞牛 build/加载整段不进,走中立路
  // (季列表 + 选集列表 + 季详情来自 MediaBackend,播放/下载/原生 reentry 占位禁用)。
  bool _neutralDisplayOnly = false;
  MediaDetail? _neutralDetail;
  // 中立(Emby)季页面「收藏整部剧」态(收藏 widget.parentGuid 系列本身)。飞牛季页面不显示此键。
  bool _neutralSeriesFavorite = false;
  bool _seriesFavoriteUpdating = false;
  // 中立(Emby)季评分回退:Emby 季条目通常无 CommunityRating(评分挂在系列上),取系列评分兜底,
  // 使季页面 meta 与飞牛一致显示「X.X 分 / 年份」。
  String _neutralSeriesRating = '';
  List<MediaSeasonSummary> _neutralSeasons = const [];
  List<MediaEpisodeSummary> _neutralEpisodes = const [];
  // 按季缓存详情 / 选集:切回已加载的季瞬时返回(追平飞牛切季速度)。
  final Map<String, MediaDetail> _neutralDetailCache = <String, MediaDetail>{};
  final Map<String, List<MediaEpisodeSummary>> _neutralEpisodeCache =
      <String, List<MediaEpisodeSummary>>{};

  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seasonSwitching = false;
  bool _playPreparing = false;
  int _episodeRangeIndex = 0;
  int _seasonLoadSeq = 0;

  bool _descriptionVisible = false;
  bool _creditsVisible = false;
  bool _episodeItemsResolved = false;
  bool _artworkReady = false;
  TvEpisodePickerMode _episodePickerMode = TvEpisodePickerMode.list;
  Timer? _deferredLoadTimer;
  String _cachedImageBaseUrl = '';
  final Map<String, List<String>> _imageCandidateCache =
      <String, List<String>>{};
  final Map<String, List<MediaLibraryItem>> _episodeCache =
      <String, List<MediaLibraryItem>>{};
  final Map<String, Future<List<MediaLibraryItem>>> _episodeInflight =
      <String, Future<List<MediaLibraryItem>>>{};
  List<MediaLibraryItem>? _seasonListCache;
  Future<List<MediaLibraryItem>>? _seasonListInflight;
  final Map<String, Map<String, dynamic>> _seasonDetailCache =
      <String, Map<String, dynamic>>{};
  final Map<String, Future<Map<String, dynamic>>> _seasonDetailInflight =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, PlayInfoData?> _seasonPlayInfoCache =
      <String, PlayInfoData?>{};
  final Map<String, Future<PlayInfoData?>> _seasonPlayInfoInflight =
      <String, Future<PlayInfoData?>>{};
  final Map<String, List<PersonCredit>> _personCreditsCache =
      <String, List<PersonCredit>>{};
  final Map<String, Future<List<PersonCredit>>> _personCreditsInflight =
      <String, Future<List<PersonCredit>>>{};

  late final AnimationController _headerFadeController;
  late final Animation<double> _headerMetaOpacity;

  @override
  void initState() {
    super.initState();
    _headerFadeController = AnimationController(
      vsync: this,
      duration: _headerFadeDuration,
    );
    _headerMetaOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.34, 1.0, curve: Curves.linear),
    );

    final initialSeasonItems = widget.initialSeasonItems;
    if (initialSeasonItems != null && initialSeasonItems.isNotEmpty) {
      _seasonListCache = List<MediaLibraryItem>.unmodifiable(
        initialSeasonItems,
      );
    }
    _selectedSeasonGuid = widget.seasonItem.guid;
    _scrollController.addListener(_onScroll);
    _downloadTaskService.addListener(_handleDownloadTasksChanged);
    unawaited(_downloadTaskService.initialize());
    unawaited(_loadEpisodePickerModeSetting());
    _loadSeasonData(_selectedSeasonGuid, showLoading: true);
  }

  @override
  void dispose() {
    _downloadTaskService.removeListener(_handleDownloadTasksChanged);
    _topTip.dispose();
    _deferredLoadTimer?.cancel();
    _headerFadeController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    TvSeasonDownloadSheetController.clearCache();
    if (_reentryToken != null) {
      NativePlayerBridge.unbindReentry(_reentryToken!);
      _reentryToken = null;
    }
    super.dispose();
  }

  void _handleDownloadTasksChanged() {
    if (!mounted) return;
    // 下载服务在任意任务的每个进度 tick 都 notifyListeners；但本页只用到“整季是否全部下载”
    // 这一个 bool（line ~2246 的 downloaded:），它只在某集状态类别变化时翻转、不随进度变。
    // 故仅在该 bool 变化时整页 setState，避免详情页可见期间被无关下载进度每帧重建打满。
    final fullyDownloaded = _isCurrentSeasonFullyDownloaded();
    if (fullyDownloaded == _seasonFullyDownloadedCache) return;
    _seasonFullyDownloadedCache = fullyDownloaded;
    setState(() {});
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffsetNotifier.value).abs() > 0.5) {
      _scrollOffsetNotifier.value = offset;
    }
  }

  void _resetScrollToTop() {
    if (_scrollOffsetNotifier.value != 0) {
      _scrollOffsetNotifier.value = 0;
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollOffsetNotifier.value != 0) {
        _scrollOffsetNotifier.value = 0;
      }
      if (_scrollController.hasClients && _scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
    });
  }

  int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  Map<String, dynamic> _itemMap(Map<String, dynamic> raw) {
    final item = raw['item'];
    if (item is Map<String, dynamic>) return item;
    return raw;
  }

  MediaLibraryItem _currentSeason() {
    for (final season in _seasonItems) {
      if (season.guid == _selectedSeasonGuid) return season;
    }
    return widget.seasonItem;
  }

  String _seasonLabel(MediaLibraryItem season) {
    if (season.seasonNumber > 0) {
      return AppLocalizations.of(
        context,
      ).detailSeasonNumber(season.seasonNumber);
    }
    final title = season.title.trim();
    return title.isNotEmpty
        ? title
        : AppLocalizations.of(context).detailSeasonInfoDefault;
  }

  String _playLabel() {
    final episodeNo = _playInfo?.item.episodeNumber ?? 1;
    if (episodeNo > 0) {
      return AppLocalizations.of(context).detailEpisodeNumber(episodeNo);
    }
    return AppLocalizations.of(context).detailPlay;
  }

  String _suggestedThemeNameBase(MediaLibraryItem season) {
    final currentEpisode = _playInfo?.item.episodeNumber ?? 0;
    final seasonNumber = season.seasonNumber;
    if (currentEpisode > 0) {
      return buildThemeSaveNameBase(
        l10n: AppLocalizations.of(context),
        title: widget.seriesTitle,
        seriesTitle: widget.seriesTitle,
        seasonNumber: seasonNumber,
        episodeNumber: currentEpisode,
        isEpisode: true,
      );
    }
    return buildThemeSaveNameBase(
      l10n: AppLocalizations.of(context),
      title: '${widget.seriesTitle}·${_seasonLabel(season)}',
    );
  }

  TvEpisodePickerMode _episodePickerModeFromSetting(String? viewType) {
    return viewType == _playlistViewTypeButton
        ? TvEpisodePickerMode.grid
        : TvEpisodePickerMode.list;
  }

  String _playlistViewTypeFromMode(TvEpisodePickerMode mode) {
    return mode == TvEpisodePickerMode.grid
        ? _playlistViewTypeButton
        : _playlistViewTypeCard;
  }

  String _episodeTitle(MediaLibraryItem item, int index) {
    final cleanTitle = item.title.trim().replaceAll(
      RegExp(r'\.(mkv|mp4|m4v|avi|ts|flv|mov)$', caseSensitive: false),
      '',
    );
    final episodeNo = item.episodeNumber;
    if (episodeNo > 0) {
      return cleanTitle.isNotEmpty
          ? '$episodeNo.$cleanTitle'
          : '$episodeNo.${AppLocalizations.of(context).detailEpisodeNumber(episodeNo)}';
    }
    final fallback = cleanTitle.isNotEmpty
        ? cleanTitle
        : AppLocalizations.of(context).detailEpisodeNumber(index + 1);
    return '${AppLocalizations.of(context).detailEpisodeUnknown}.$fallback';
  }

  String _durationText(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final l10n = AppLocalizations.of(context);
    if (h > 0) return l10n.commonDurationHoursMinutes(h, m);
    if (m > 0) return l10n.commonDurationMinutesSeconds(m, s);
    return l10n.commonDurationSeconds(s);
  }

  String _currentPlaybackEpisodeGuid() => _playInfo?.item.guid.trim() ?? '';

  String _preferredEpisodeGuid(List<MediaLibraryItem> episodes) {
    final selectedGuid = _selectedEpisodeGuid.trim();
    if (selectedGuid.isNotEmpty) {
      for (final episode in episodes) {
        if (episode.guid == selectedGuid) return selectedGuid;
      }
    }

    final playGuid = _currentPlaybackEpisodeGuid();
    if (playGuid.isNotEmpty) {
      for (final episode in episodes) {
        if (episode.guid == playGuid) return playGuid;
      }
    }

    for (final episode in episodes) {
      if (episode.ts > 0 || episode.watchedTs > 0 || episode.watched == 1) {
        return episode.guid;
      }
    }
    return episodes.isNotEmpty ? episodes.first.guid : '';
  }

  int _rangeIndexForEpisodeGuid(
    List<MediaLibraryItem> episodes,
    String episodeGuid,
  ) {
    if (episodes.isEmpty || episodeGuid.trim().isEmpty) return 0;
    final index = episodes.indexWhere((episode) => episode.guid == episodeGuid);
    if (index < 0) return 0;
    return index ~/ _episodePageSize;
  }

  bool _hasMeaningfulText(String? value) {
    final text = (value ?? '').trim();
    return text.isNotEmpty &&
        text != AppLocalizations.of(context).detailOverviewEmpty &&
        text != AppLocalizations.of(context).detailEpisodeEmpty;
  }

  String _extractImdbId(Map<String, dynamic> data) {
    final direct = (data['imdb_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['imdb_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _extractTrimId(Map<String, dynamic> data) {
    final direct = (data['trim_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['trim_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  Future<List<MediaLibraryItem>> _loadEpisodesForSeason(
    String seasonGuid, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = _episodeCache[seasonGuid];
      if (cached != null) return Future<List<MediaLibraryItem>>.value(cached);
      final inflight = _episodeInflight[seasonGuid];
      if (inflight != null) return inflight;
    }

    final future = FeiniuApi(context.read<NasProvider>())
        .getEpisodeList(seasonGuid)
        .catchError((error) {
          final appError = AppException.from(
            error,
            action: 'episode list',
            fallbackKind: AppExceptionKind.transient,
          );
          if (appError.isNoData) {
            return <MediaLibraryItem>[];
          }
          throw error;
        })
        .then((episodes) {
          _episodeCache[seasonGuid] = episodes;
          return episodes;
        })
        .whenComplete(() {
          _episodeInflight.remove(seasonGuid);
        });
    _episodeInflight[seasonGuid] = future;
    return future;
  }

  (String, TvEpisodeStatusTone, bool) _episodeStatus(MediaLibraryItem episode) {
    if (episode.watched == 1) {
      return (
        AppLocalizations.of(context).listWatched,
        TvEpisodeStatusTone.secondary,
        false,
      );
    }
    final duration = episode.duration;
    final watchedTs = episode.ts > 0 ? episode.ts : episode.watchedTs;
    if (duration > 0 && watchedTs > 0) {
      final percent = (watchedTs / duration * 100).clamp(0, 100).round();
      return ('$percent%', TvEpisodeStatusTone.accent, false);
    }
    return ('', TvEpisodeStatusTone.secondary, false);
  }

  double _episodeProgress(MediaLibraryItem episode) {
    if (episode.watched == 1) return 1;
    final duration = episode.duration;
    final watchedTs = episode.ts > 0 ? episode.ts : episode.watchedTs;
    if (duration <= 0 || watchedTs <= 0) return 0;
    return (watchedTs / duration).clamp(0.0, 1.0);
  }

  String _episodeShortLabel(MediaLibraryItem episode, int index) {
    final number = episode.episodeNumber;
    if (number > 0) return '$number';
    return '${index + 1}';
  }

  List<TvEpisodeCardData> _episodeCardEntries(
    List<MediaLibraryItem> episodes, {
    String? selectedGuid,
    bool includeImages = true,
  }) {
    return List<TvEpisodeCardData>.generate(episodes.length, (index) {
      final episode = episodes[index];
      final status = _episodeStatus(episode);
      return TvEpisodeCardData(
        guid: episode.guid,
        shortLabel: _episodeShortLabel(episode, index),
        title: _episodeTitle(episode, index),
        summary: _hasMeaningfulText(episode.overview)
            ? episode.overview.trim()
            : '',
        durationText: _durationText(episode.duration),
        statusLabel: status.$1,
        statusTone: status.$2,
        imageUrls: includeImages
            ? _imageCandidates(episode.poster, width: 720)
            : const <String>[],
        resolutions: episode.resolutions,
        selected: episode.guid == (selectedGuid ?? _selectedEpisodeGuid),
        playing: status.$3,
        completed: episode.watched == 1,
        progress: _episodeProgress(episode),
      );
    }, growable: false);
  }

  List<TvEpisodeCardData> _episodePlaceholderEntries(int episodeCount) {
    final placeholderCount = episodeCount > 0
        ? math.min(episodeCount, _episodePageSize)
        : 4;
    return List<TvEpisodeCardData>.generate(placeholderCount, (index) {
      final number = index + 1;
      return TvEpisodeCardData(
        guid: 'placeholder-episode-$number',
        shortLabel: '$number',
        title: AppLocalizations.of(context).detailEpisodeNumber(number),
        summary: '',
        durationText: AppLocalizations.of(context).commonLoading,
        statusLabel: '',
        statusTone: TvEpisodeStatusTone.none,
        imageUrls: const <String>[],
        resolutions: const <String>[],
        selected: false,
        playing: false,
        completed: false,
        progress: 0,
      );
    }, growable: false);
  }

  int _expectedEpisodeCount() {
    final item = _itemMap(_detail);
    final localCount = _asInt(item['local_number_of_episodes']);
    if (localCount > 0) return localCount;
    final totalCount = _asInt(item['number_of_episodes']);
    if (totalCount > 0) return totalCount;
    final season = _currentSeason();
    if (season.localNumberOfEpisodes > 0) {
      return season.localNumberOfEpisodes;
    }
    return season.numberOfEpisodes;
  }

  List<TvEpisodeSeasonOptionData> _seasonOptionEntries() {
    return _seasonItems
        .map(
          (season) => TvEpisodeSeasonOptionData(
            guid: season.guid,
            label: _seasonLabel(season),
            selected: season.guid == _selectedSeasonGuid,
          ),
        )
        .toList(growable: false);
  }

  Future<TvEpisodePickerPayload> _episodePickerPayloadForSeason(
    String seasonGuid,
  ) async {
    final episodes = await _loadEpisodesForSeason(seasonGuid);
    final selectedGuid = seasonGuid == _selectedSeasonGuid
        ? _preferredEpisodeGuid(episodes)
        : (episodes.isNotEmpty ? episodes.first.guid : '');
    final payload = TvEpisodePickerPayload(
      totalCount: episodes.length,
      entries: _episodeCardEntries(
        episodes,
        selectedGuid: selectedGuid,
        includeImages: _artworkReady,
      ),
    );
    return payload;
  }

  List<String> _imageCandidates(String rawPath, {int width = 860}) {
    final provider = context.read<NasProvider>();
    final baseUrl = provider.baseUrl;
    if (_cachedImageBaseUrl != baseUrl) {
      _cachedImageBaseUrl = baseUrl;
      _imageCandidateCache.clear();
    }
    final key = '$width|$rawPath';
    final cached = _imageCandidateCache[key];
    if (cached != null) return cached;
    final generated = List<String>.unmodifiable(
      ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width),
    );
    _imageCandidateCache[key] = generated;
    return generated;
  }

  String _seasonDynamicThemeKey() {
    final parentGuid = widget.parentGuid.trim();
    if (parentGuid.isNotEmpty) {
      return 'tv-season-series:$parentGuid';
    }
    final backdropPath = widget.backdropPath.trim();
    if (backdropPath.isNotEmpty) {
      return 'tv-season-backdrop:$backdropPath';
    }
    final selectedSeasonGuid = _selectedSeasonGuid.trim();
    if (selectedSeasonGuid.isNotEmpty) {
      return selectedSeasonGuid;
    }
    return widget.seasonItem.guid;
  }

  String _episodeDynamicThemeImageUrl(Map<String, dynamic> detail) {
    final item = _itemMap(detail);
    final candidates = <String>[
      '${item['backdrops'] ?? ''}',
      '${item['still_path'] ?? ''}',
      '${item['posters'] ?? ''}',
      widget.backdropPath,
    ];
    for (final rawPath in candidates) {
      final trimmed = rawPath.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final urls = _imageCandidates(trimmed, width: 360);
      if (urls.isNotEmpty) {
        return urls.first;
      }
    }
    return '';
  }

  void _primeEpisodeThemeSeed(
    MediaLibraryItem episode,
    Map<String, dynamic> initialDetail,
  ) {
    final episodeGuid = episode.guid.trim();
    if (episodeGuid.isEmpty) {
      return;
    }
    DynamicThemeRuntimeController.instance.primePageSeed(
      key: episodeGuid,
      imageUrl: _episodeDynamicThemeImageUrl(initialDetail),
    );
  }

  Future<PlayInfoData?> _loadPlayInfoOrNull(
    FeiniuApi api,
    String guid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      if (_seasonPlayInfoCache.containsKey(guid)) {
        return _seasonPlayInfoCache[guid];
      }
      final inflight = _seasonPlayInfoInflight[guid];
      if (inflight != null) return inflight;
    } else {
      _seasonPlayInfoCache.remove(guid);
      _seasonPlayInfoInflight.remove(guid);
    }

    final future = () async {
      try {
        if (!_useRuntimeCache) {
          return await api.getPlayInfo(guid);
        }
        return await DetailRuntimeCache.instance.getOrLoad<PlayInfoData>(
          bucket: 'play_info',
          key: guid,
          loader: () => api.getPlayInfo(guid),
        );
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load season play info',
          id: guid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
        );
        return null;
      }
    }();

    _seasonPlayInfoInflight[guid] = future;
    try {
      final result = await future;
      _seasonPlayInfoCache[guid] = result;
      return result;
    } finally {
      _seasonPlayInfoInflight.remove(guid);
    }
  }

  Future<List<MediaLibraryItem>> _loadSeasonItems(
    FeiniuApi api,
    String itemGuid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _seasonListCache;
      if (cached != null) return cached;
      final inflight = _seasonListInflight;
      if (inflight != null) return inflight;
    } else {
      _seasonListCache = null;
      _seasonListInflight = null;
    }

    final future = () {
      if (!_useRuntimeCache) {
        return api.getSeasonList(itemGuid);
      }
      return DetailRuntimeCache.instance.getOrLoad<List<MediaLibraryItem>>(
        bucket: 'season_list',
        key: itemGuid,
        loader: () => api.getSeasonList(itemGuid),
      );
    }();
    _seasonListInflight = future;
    try {
      final seasons = await future;
      _seasonListCache = seasons;
      return seasons;
    } finally {
      _seasonListInflight = null;
    }
  }

  Future<Map<String, dynamic>> _loadItemDetail(
    FeiniuApi api,
    String itemGuid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _seasonDetailCache[itemGuid];
      if (cached != null) return cached;
      final inflight = _seasonDetailInflight[itemGuid];
      if (inflight != null) return inflight;
    } else {
      _seasonDetailCache.remove(itemGuid);
      _seasonDetailInflight.remove(itemGuid);
    }

    final future = () {
      if (!_useRuntimeCache) {
        return api.getItemDetail(itemGuid);
      }
      return DetailRuntimeCache.instance.getOrLoad<Map<String, dynamic>>(
        bucket: 'item_detail',
        key: itemGuid,
        loader: () => api.getItemDetail(itemGuid),
      );
    }();
    _seasonDetailInflight[itemGuid] = future;
    try {
      final detail = await future;
      _seasonDetailCache[itemGuid] = detail;
      return detail;
    } finally {
      _seasonDetailInflight.remove(itemGuid);
    }
  }

  Future<List<PersonCredit>> _loadPersonCredits(
    FeiniuApi api,
    String itemGuid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _personCreditsCache[itemGuid];
      if (cached != null) return cached;
      final inflight = _personCreditsInflight[itemGuid];
      if (inflight != null) return inflight;
    } else {
      _personCreditsCache.remove(itemGuid);
      _personCreditsInflight.remove(itemGuid);
    }

    final future = () async {
      try {
        if (!_useRuntimeCache) {
          return await api.getPersonList(itemGuid, request: _creditsRequest);
        }
        return await DetailRuntimeCache.instance.getOrLoad<List<PersonCredit>>(
          bucket: 'person_list',
          key: itemGuid,
          loader: () => api.getPersonList(itemGuid, request: _creditsRequest),
        );
      } catch (error, stackTrace) {
        final appError = AppException.from(
          error,
          action: 'tv season detail credits',
          fallbackKind: AppExceptionKind.transient,
          stackTrace: stackTrace,
        );
        if (appError.isNoData) {
          return const <PersonCredit>[];
        }
        rethrow;
      }
    }();

    _personCreditsInflight[itemGuid] = future;
    try {
      final credits = await future;
      _personCreditsCache[itemGuid] = credits;
      return credits;
    } finally {
      _personCreditsInflight.remove(itemGuid);
    }
  }

  Map<String, dynamic> _fallbackSeasonDetail(MediaLibraryItem season) {
    return <String, dynamic>{
      'item': <String, dynamic>{
        'guid': season.guid,
        'type': season.type,
        'title': season.title,
        'tv_title': widget.seriesTitle,
        'overview': season.overview,
        'release_date': season.releaseDate,
        'first_air_date': season.firstAirDate,
        'last_air_date': season.lastAirDate,
        'vote_average': season.voteAverage,
        'posters': season.poster,
        'season_number': season.seasonNumber,
        'number_of_episodes': season.numberOfEpisodes,
        'local_number_of_episodes': season.localNumberOfEpisodes,
        'is_watched': season.watched,
      },
    };
  }

  void _applyFallbackSeasonState({
    required List<MediaLibraryItem> seasons,
    required String target,
    required MediaLibraryItem fallbackSeason,
    required bool showLoading,
  }) {
    setState(() {
      _seasonItems = seasons.isNotEmpty
          ? seasons
          : <MediaLibraryItem>[widget.seasonItem];
      _selectedSeasonGuid = target;
      _detail = _fallbackSeasonDetail(fallbackSeason);
      _playInfo = null;
      _imdbId = '';
      _trimId = '';
      _watched = fallbackSeason.watched == 1;
      if (showLoading) {
        _episodeItems = const <MediaLibraryItem>[];
        _episodeItemsResolved = true;
        _selectedEpisodeGuid = '';
        _episodeRangeIndex = 0;
        _artworkReady = false;
        _personCredits = const [];
        _creditsVisible = false;
        _descriptionVisible = false;
      } else {
        _selectedEpisodeGuid = '';
        _episodeRangeIndex = 0;
        _descriptionVisible = true;
        _artworkReady = _artworkReady || _episodeItemsResolved;
      }
      _loading = false;
      _error = null;
    });
    if (showLoading) _resetScrollToTop();
    if (showLoading) _startEntryAnimations();
    _startDeferredLoad(seq: _seasonLoadSeq, seasonGuid: target);
  }

  Widget _seasonNumberWidget(AppThemeColors colors, MediaLibraryItem season) {
    final metaPrimary = colors.backgroundBase.computeLuminance() >= 0.58
        ? const Color(0xFF182132)
        : colors.textPrimary;
    final seasonNo = season.seasonNumber;
    if (seasonNo <= 0) {
      return Text(
        _seasonLabel(season),
        style: TextStyle(
          color: metaPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return AppTransitions.crossFadeSwitch(
      switchKey: 'season-no-$seasonNo',
      duration: _seasonDataFadeDuration,
      child: Text(
        AppLocalizations.of(context).detailSeasonNumber(seasonNo),
        key: ValueKey<int>(seasonNo),
        style: TextStyle(
          color: metaPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _loadEpisodePickerModeSetting() async {
    final viewType = await FeiniuApi(
      context.read<NasProvider>(),
    ).getPlaylistViewType();
    if (!mounted || viewType == null) return;
    final mode = _episodePickerModeFromSetting(viewType);
    if (_episodePickerMode == mode) return;
    setState(() => _episodePickerMode = mode);
  }

  Future<void> _persistEpisodePickerMode(TvEpisodePickerMode mode) async {
    final saved = await FeiniuApi(
      context.read<NasProvider>(),
    ).setPlaylistViewType(_playlistViewTypeFromMode(mode));
    if (!saved) {
      if (!mounted) {
        throw StateError('playlist view type save failed');
      }
      _showTopTip(
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.danger,
      );
      throw StateError('playlist view type save failed');
    }
    if (!mounted || _episodePickerMode == mode) return;
    setState(() => _episodePickerMode = mode);
  }

  void _startEntryAnimations() {
    _headerFadeController.forward(from: 0);
  }

  void _resetEntryAnimations() {
    _headerFadeController.reset();
  }

  Future<void> _openImdb() async {
    final result = await ImdbLauncher.openExternal(_imdbId);
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailImdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailImdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  void _openCreditPerson(CreditPersonItem person) {
    final guid = person.personGuid.trim();
    if (guid.isEmpty) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.person(
        personGuid: guid,
        initialName: person.name,
        initialLocaleMap: _localeMap,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  /// 中立(Emby)季数据加载:季列表 + 目标季详情 + 选集列表。播放接线一律不取(占位)。
  Future<void> _loadSeasonDataNeutral(
    String requestedGuid, {
    required bool showLoading,
  }) async {
    _deferredLoadTimer?.cancel();
    if (showLoading) _resetEntryAnimations();
    final seq = ++_seasonLoadSeq;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _descriptionVisible = false;
        _episodeItemsResolved = false;
        _artworkReady = false;
      });
    }
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      // 季列表 best-effort(空列表 → 单季降级)。
      List<MediaSeasonSummary> seasons;
      try {
        seasons = await backend.getItemSeasons(widget.parentGuid);
        seasons = List<MediaSeasonSummary>.of(seasons)
          ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load neutral season list',
          id: widget.parentGuid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
          details: 'backend=${backend.capabilities.kind.name}',
        );
        seasons = const <MediaSeasonSummary>[];
      }
      final target = seasons.any((s) => s.id == requestedGuid)
          ? requestedGuid
          : (seasons.isNotEmpty ? seasons.first.id : requestedGuid);
      final detail = await backend.getItemDetail(target);
      // best-effort 查整部剧收藏态(收藏键收藏的是系列本身,非当前季)+ 系列评分(季无评分时兜底)。
      bool seriesFavorite = _neutralSeriesFavorite;
      String seriesRating = _neutralSeriesRating;
      try {
        final seriesId = widget.parentGuid.trim();
        if (seriesId.isEmpty || seriesId == target) {
          seriesFavorite = detail.favorite;
          seriesRating = detail.rating;
        } else {
          final seriesDetail = await backend.getItemDetail(seriesId);
          seriesFavorite = seriesDetail.favorite;
          seriesRating = seriesDetail.rating;
        }
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load neutral series detail fallback',
          id: widget.parentGuid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
          details: 'seasonGuid=$target',
        );
      }
      List<MediaEpisodeSummary> episodes;
      try {
        episodes = await backend.getSeasonEpisodes(target);
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load neutral season episodes',
          id: target,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
          details: 'backend=${backend.capabilities.kind.name}',
        );
        episodes = const <MediaEpisodeSummary>[];
      }
      if (!mounted || seq != _seasonLoadSeq) return;
      await RouteTransitionGate.of(context);
      if (!mounted || seq != _seasonLoadSeq) return;
      _neutralDetailCache[target] = detail;
      _neutralEpisodeCache[target] = episodes;
      setState(() {
        _neutralDisplayOnly = true;
        _neutralSeasons = seasons;
        _neutralDetail = detail;
        _neutralSeriesFavorite = seriesFavorite;
        _neutralSeriesRating = seriesRating;
        _neutralEpisodes = episodes;
        _selectedSeasonGuid = target;
        _imdbId = detail.externalIds.imdbId;
        _trimId = detail.externalIds.tmdbId;
        _watched = detail.watched;
        _selectedEpisodeGuid = _neutralPreferredEpisodeGuid(episodes);
        _episodeRangeIndex = _neutralRangeIndexFor(
          episodes,
          _selectedEpisodeGuid,
        );
        _episodeItemsResolved = true;
        _artworkReady = true;
        _descriptionVisible = true;
        _loading = false;
        _error = null;
      });
      if (showLoading) _resetScrollToTop();
      if (showLoading) _startEntryAnimations();
      unawaited(_resolveNeutralPlayTarget(backend, target, episodes));
    } catch (e) {
      if (!mounted || seq != _seasonLoadSeq) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'tv season detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  /// 中立切季:命中缓存瞬时切换(追平飞牛);未命中则先显占位再并行取详情+选集。
  Future<void> _switchSeasonNeutral(String seasonGuid) async {
    if (seasonGuid == _selectedSeasonGuid || _seasonSwitching) return;
    final cachedDetail = _neutralDetailCache[seasonGuid];
    final cachedEpisodes = _neutralEpisodeCache[seasonGuid];
    if (cachedDetail != null && cachedEpisodes != null) {
      // 已加载过:瞬时切换,无网络等待。
      setState(() {
        _selectedSeasonGuid = seasonGuid;
        _neutralDetail = cachedDetail;
        _neutralEpisodes = cachedEpisodes;
        _imdbId = cachedDetail.externalIds.imdbId;
        _trimId = cachedDetail.externalIds.tmdbId;
        _watched = cachedDetail.watched;
        _selectedEpisodeGuid = _neutralPreferredEpisodeGuid(cachedEpisodes);
        _episodeRangeIndex = _neutralRangeIndexFor(
          cachedEpisodes,
          _selectedEpisodeGuid,
        );
        _episodeItemsResolved = true;
      });
      unawaited(
        _resolveNeutralPlayTarget(
          context.read<MediaBackendProvider>().backend,
          seasonGuid,
          cachedEpisodes,
        ),
      );
      return;
    }
    // 未缓存:先把选中季切过去并显占位(不空白),再后台取。
    final seq = ++_seasonLoadSeq;
    setState(() {
      _seasonSwitching = true;
      _selectedSeasonGuid = seasonGuid;
      _selectedEpisodeGuid = '';
      _episodeRangeIndex = 0;
      _episodeItemsResolved = false;
    });
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final results = await Future.wait(<Future<Object?>>[
        backend.getItemDetail(seasonGuid),
        backend
            .getSeasonEpisodes(seasonGuid)
            .catchError((_) => const <MediaEpisodeSummary>[]),
      ]);
      if (!mounted || seq != _seasonLoadSeq) return;
      final detail = results[0] as MediaDetail;
      final episodes = results[1] as List<MediaEpisodeSummary>;
      _neutralDetailCache[seasonGuid] = detail;
      _neutralEpisodeCache[seasonGuid] = episodes;
      setState(() {
        _neutralDetail = detail;
        _neutralEpisodes = episodes;
        _imdbId = detail.externalIds.imdbId;
        _trimId = detail.externalIds.tmdbId;
        _watched = detail.watched;
        _selectedEpisodeGuid = _neutralPreferredEpisodeGuid(episodes);
        _episodeRangeIndex = _neutralRangeIndexFor(
          episodes,
          _selectedEpisodeGuid,
        );
        _episodeItemsResolved = true;
      });
      unawaited(_resolveNeutralPlayTarget(backend, seasonGuid, episodes));
    } finally {
      if (mounted) {
        setState(() => _seasonSwitching = false);
      } else {
        _seasonSwitching = false;
      }
    }
  }

  String _neutralPreferredEpisodeGuid(List<MediaEpisodeSummary> episodes) {
    if (episodes.isEmpty) return '';
    // 优先：有断点续看进度的一集（即「正在看」的那集）——反映最新播放进度。
    for (final ep in episodes) {
      if (ep.resumePositionSeconds > 0) return ep.id;
    }
    // 其次：首个未看完的一集（看完前几集后应落在「下一集」，而非死锁第 1 集）。
    for (final ep in episodes) {
      if (!ep.watched) return ep.id;
    }
    // 全部看完：回到第 1 集。
    return episodes.first.id;
  }

  /// 与系列详情页同口径:用 [MediaBackend.resolveSeriesNextUpEpisode]（内部走
  /// continue-watching，即首页「继续观看」那条权威「最新播放」数据）解析本剧最新在看的一集；
  /// 若它落在本季选集内，则作为播放按钮文案 / 默认起播目标。否则保持本季 resume/watched 扫描
  /// 的兜底结果（命中其它季时不动本季选中）。异步、不阻塞首帧；季 guid 守卫防竞态。
  Future<void> _resolveNeutralPlayTarget(
    MediaBackend backend,
    String seasonGuid,
    List<MediaEpisodeSummary> episodes,
  ) async {
    if (episodes.isEmpty) return;
    try {
      final target = await backend.resolveSeriesNextUpEpisode(
        widget.parentGuid,
      );
      if (!mounted || seasonGuid != _selectedSeasonGuid) return;
      if (target == null || target.id.trim().isEmpty) return;
      if (!episodes.any((e) => e.id == target.id)) return;
      if (_selectedEpisodeGuid == target.id) return;
      setState(() {
        _selectedEpisodeGuid = target.id;
        _episodeRangeIndex = _neutralRangeIndexFor(episodes, target.id);
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'resolve neutral next episode',
        id: seasonGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
    }
  }

  int _neutralRangeIndexFor(
    List<MediaEpisodeSummary> episodes,
    String episodeGuid,
  ) {
    if (episodes.isEmpty || episodeGuid.trim().isEmpty) return 0;
    final index = episodes.indexWhere((e) => e.id == episodeGuid);
    if (index < 0) return 0;
    return index ~/ _episodePageSize;
  }

  String _neutralSeasonLabel(MediaSeasonSummary season) {
    if (season.seasonNumber > 0) {
      return AppLocalizations.of(
        context,
      ).detailSeasonNumber(season.seasonNumber);
    }
    final title = season.title.trim();
    return title.isNotEmpty
        ? title
        : AppLocalizations.of(context).detailSeasonInfoDefault;
  }

  MediaSeasonSummary? _neutralCurrentSeason() {
    for (final s in _neutralSeasons) {
      if (s.id == _selectedSeasonGuid) return s;
    }
    return _neutralSeasons.isNotEmpty ? _neutralSeasons.first : null;
  }

  List<TvEpisodeSeasonOptionData> _neutralSeasonOptionEntries() {
    return _neutralSeasons
        .map(
          (s) => TvEpisodeSeasonOptionData(
            guid: s.id,
            label: _neutralSeasonLabel(s),
            selected: s.id == _selectedSeasonGuid,
          ),
        )
        .toList(growable: false);
  }

  List<TvEpisodeCardData> _neutralEpisodeCardEntries(
    DetailArtworkResolver resolver,
  ) {
    return _neutralEpisodeCardEntriesFrom(
      _neutralEpisodes,
      resolver,
      selectedGuid: _selectedEpisodeGuid,
    );
  }

  List<TvEpisodeCardData> _neutralEpisodeCardEntriesFrom(
    List<MediaEpisodeSummary> episodes,
    DetailArtworkResolver resolver, {
    required String selectedGuid,
  }) {
    return List<TvEpisodeCardData>.generate(episodes.length, (index) {
      final ep = episodes[index];
      final number = ep.episodeNumber > 0 ? ep.episodeNumber : index + 1;
      final cleanTitle = ep.title.trim();
      final title = cleanTitle.isNotEmpty
          ? '$number.$cleanTitle'
          : '$number.${AppLocalizations.of(context).detailEpisodeNumber(number)}';
      String statusLabel = '';
      var statusTone = TvEpisodeStatusTone.secondary;
      double progress = 0;
      if (ep.watched) {
        statusLabel = AppLocalizations.of(context).listWatched;
        progress = 1;
      } else if (ep.durationSeconds > 0 && ep.resumePositionSeconds > 0) {
        final percent = (ep.resumePositionSeconds / ep.durationSeconds * 100)
            .clamp(0, 100)
            .round();
        statusLabel = '$percent%';
        statusTone = TvEpisodeStatusTone.accent;
        progress = (ep.resumePositionSeconds / ep.durationSeconds).clamp(
          0.0,
          1.0,
        );
      }
      return TvEpisodeCardData(
        guid: ep.id,
        shortLabel: '$number',
        title: title,
        summary: _hasMeaningfulText(ep.overview) ? ep.overview.trim() : '',
        durationText: _durationText(ep.durationSeconds),
        statusLabel: statusLabel,
        statusTone: statusTone,
        imageUrls: resolver.resolveRef(ep.primaryImage, width: 720).urls,
        resolutions: ep.resolutions,
        selected: ep.id == selectedGuid,
        playing: false,
        completed: ep.watched,
        progress: progress,
      );
    }, growable: false);
  }

  /// 中立选集 picker 的按季加载器:当前季用已加载列表,其余季按需取。
  Future<TvEpisodePickerPayload> _neutralEpisodePickerPayload(
    String seasonGuid,
  ) async {
    final provider = context.read<NasProvider>();
    final resolver = DetailArtworkResolver(
      baseUrl: provider.baseUrl,
      token: provider.token,
    );
    List<MediaEpisodeSummary> episodes;
    if (seasonGuid == _selectedSeasonGuid) {
      episodes = _neutralEpisodes;
    } else {
      try {
        episodes = await context
            .read<MediaBackendProvider>()
            .backend
            .getSeasonEpisodes(seasonGuid);
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'load neutral picker episodes',
          id: seasonGuid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
        );
        episodes = const <MediaEpisodeSummary>[];
      }
    }
    final selectedGuid = seasonGuid == _selectedSeasonGuid
        ? _selectedEpisodeGuid
        : (episodes.isNotEmpty ? episodes.first.id : '');
    return TvEpisodePickerPayload(
      totalCount: episodes.length,
      entries: _neutralEpisodeCardEntriesFrom(
        episodes,
        resolver,
        selectedGuid: selectedGuid,
      ),
    );
  }

  Future<void> _openNeutralEpisodePicker(BuildContext sheetContext) async {
    if (_neutralSeasons.isEmpty && _neutralEpisodes.isEmpty) return;
    final result = await TvEpisodePickerSheet.show(
      sheetContext,
      title: AppLocalizations.of(context).detailEpisodeTitle,
      seasons: _neutralSeasonOptionEntries(),
      initialSeasonGuid: _selectedSeasonGuid,
      initialEpisodeGuid: _selectedEpisodeGuid,
      initialMode: _episodePickerMode,
      rangeSize: _episodePageSize,
      emptyText: AppLocalizations.of(context).detailEpisodeEmpty,
      token: '',
      loader: _neutralEpisodePickerPayload,
      onModeChanged: (mode) async {
        if (!mounted) return;
        setState(() => _episodePickerMode = mode);
      },
    );
    if (!mounted || result == null) return;
    if (result.seasonGuid != _selectedSeasonGuid) {
      await _switchSeasonNeutral(result.seasonGuid);
    }
    if (!mounted) return;
    if (result.openDetail) {
      _openNeutralEpisode(result.episodeGuid);
      return;
    }
    setState(() {
      _episodePickerMode = result.mode;
      _selectedEpisodeGuid = result.episodeGuid;
      _episodeRangeIndex = _neutralRangeIndexFor(
        _neutralEpisodes,
        result.episodeGuid,
      );
    });
  }

  void _openNeutralEpisode(String episodeGuid) {
    if (episodeGuid.trim().isEmpty) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: episodeGuid,
        seriesGuid: widget.parentGuid,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  void _openNeutralEpisodeSummary(String episodeGuid) {
    final index = _neutralEpisodes.indexWhere((e) => e.id == episodeGuid);
    if (index < 0) return;
    final ep = _neutralEpisodes[index];
    final summary = ep.overview.trim();
    if (!_hasMeaningfulText(summary)) return;
    final number = ep.episodeNumber > 0 ? ep.episodeNumber : index + 1;
    final cleanTitle = ep.title.trim();
    LongTextOverlayPage.show(
      context,
      title: cleanTitle.isNotEmpty ? '$number.$cleanTitle' : '$number',
      sectionTitle: AppLocalizations.of(context).detailOverviewTitle,
      content: summary,
    );
  }

  /// 中立(Emby)季详情:沉浸背景 + hero + meta + 播放占位 + 描述 + 选集浏览器 + 演职员 + 链接。
  /// 飞牛专属(海报桥接/原生 reentry/下载/播放 launcher)不进;图源走 [DetailArtworkResolver]
  /// (Emby 完整 api_key 直链直接透传)。播放/已看本阶段占位禁用。
  String _neutralPlayLabel() {
    final guid = _selectedEpisodeGuid.trim();
    var index = guid.isNotEmpty
        ? _neutralEpisodes.indexWhere((e) => e.id == guid)
        : -1;
    if (index < 0 && _neutralEpisodes.isNotEmpty) index = 0;
    final number = index >= 0 ? _neutralEpisodes[index].episodeNumber : 0;
    if (number > 0) {
      return AppLocalizations.of(context).detailEpisodeNumber(number);
    }
    return AppLocalizations.of(context).detailPlay;
  }

  void _neutralComingSoon() {
    _showTopTip(
      AppLocalizations.of(context).detailFeatureComingSoon,
      context.appColors.textMuted,
    );
  }

  /// 中立(Emby)季详情:与飞牛同布局——沉浸背景 + 海报桥接卡 + 标题/季/评分 + 播放(占位)+
  /// 描述 + 选集浏览器 + 演职员 + 链接,复用 [TvSeasonDetailPanel](回应「相同组件」)。
  Future<void> _toggleNeutralSeriesFavorite() async {
    if (_seriesFavoriteUpdating) return;
    final seriesId = widget.parentGuid.trim().isNotEmpty
        ? widget.parentGuid.trim()
        : _selectedSeasonGuid;
    if (seriesId.isEmpty) return;
    setState(() => _seriesFavoriteUpdating = true);
    final target = !_neutralSeriesFavorite;
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemFavorite(seriesId, favorite: target);
      if (!mounted) return;
      setState(() => _neutralSeriesFavorite = state);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'toggle neutral series favorite',
        id: seriesId,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
    } finally {
      if (mounted) setState(() => _seriesFavoriteUpdating = false);
    }
  }

  Widget _buildNeutralSeasonBody(AppThemeColors colors, Color? ambientTint) {
    final detail = _neutralDetail!;
    final favoriteSupported = context
        .read<MediaBackendProvider>()
        .backend
        .capabilities
        .supportsFavorite;
    final provider = context.read<NasProvider>();
    final artworkResolver = DetailArtworkResolver(
      baseUrl: provider.baseUrl,
      token: provider.token,
    );
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final textScale = media.textScaler.scale(1).clamp(1.0, 1.35);
    final aspect = screenSize.height / screenSize.width;
    final shortestSide = screenSize.shortestSide;
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = shortestSide >= 720.0;
    final heroAdaptive = TvHeroAdaptive.resolve(
      screenSize,
      devicePixelRatio: media.devicePixelRatio,
    );
    final posterHeightRatio = isLandscape ? 0.42 : 0.31;
    final heroImageAlignment = isLandscape
        ? Alignment(heroAdaptive.imageAlignX, heroAdaptive.imageAlignY)
        : Alignment(heroAdaptive.imageAlignX, -1.0);
    final posterHeightMax = screenSize.height * 0.42;
    final posterHeightMin = math.min(260.0, posterHeightMax);
    final posterHeight = math
        .min(screenSize.height * posterHeightRatio, screenSize.width / 1.55)
        .clamp(posterHeightMin, posterHeightMax)
        .toDouble();
    final collapseRange = (posterHeight - media.padding.top - kToolbarHeight)
        .clamp(120.0, 360.0);

    final heroFogBase = Color.alphaBlend(
      (ambientTint ?? colors.backgroundElevated).withValues(
        alpha: colors.backgroundBase.computeLuminance() >= 0.58 ? 0.18 : 0.28,
      ),
      colors.backgroundBase,
    );
    final heroFogShadow = Color.alphaBlend(
      colors.overlayScrim.withValues(alpha: 0.12),
      heroFogBase,
    );

    final title = widget.seriesTitle.trim().isNotEmpty
        ? widget.seriesTitle.trim()
        : detail.displayTitle;
    final season = _neutralCurrentSeason();
    final seasonLabel = season != null ? _neutralSeasonLabel(season) : '';
    final overview = detail.overview.trim();
    final hasOverview = overview.isNotEmpty;
    final year = _year(detail.releaseDate);
    // 季评分回退系列评分(Emby 季多无评分),与飞牛季页面同样显示「X.X 分」。
    final ratingText = detail.rating.trim().isNotEmpty
        ? detail.rating.trim()
        : _neutralSeriesRating.trim();
    final rating = double.tryParse(ratingText) ?? 0;

    // 背景:系列 backdrop 完整直链(Phase C 透传),回退季详情 backdrop/海报。
    final backdropUrls = widget.backdropPath.trim().isNotEmpty
        ? <String>[widget.backdropPath.trim()]
        : artworkResolver
              .resolveRef(
                detail.backdropImage.isNotEmpty
                    ? detail.backdropImage
                    : detail.primaryImage,
              )
              .urls;
    // 海报卡:季自身海报(优先季摘要,回退季详情主图)。
    final posterRef = (season != null && season.primaryImage.isNotEmpty)
        ? season.primaryImage
        : detail.primaryImage;
    final posterUrls = artworkResolver.resolveRef(posterRef, width: 560).urls;

    final creditItems = detail.people
        .map(
          (p) => CreditPersonItem(
            personGuid: p.id,
            name: CreditPersonPresenter.displayName(
              p,
              AppLocalizations.of(context),
            ),
            subtitle: CreditPersonPresenter.displaySubTitle(
              p,
              AppLocalizations.of(context),
            ),
            imageUrls: artworkResolver.resolveRef(p.avatar, width: 180).urls,
          ),
        )
        .toList();

    final expectedCount = season?.numberOfEpisodes ?? _neutralEpisodes.length;
    final episodeEntries = _episodeItemsResolved
        ? _neutralEpisodeCardEntries(artworkResolver)
        : _episodePlaceholderEntries(expectedCount);
    final showEpisodes = _episodeItemsResolved
        ? _neutralEpisodes.isNotEmpty
        : expectedCount > 0;

    final posterWidth = (screenSize.width * (isLandscape ? 0.30 : 0.36)).clamp(
      136.0,
      isLandscape ? 182.0 : 188.0,
    );
    final posterCardHeight = posterWidth * 1.45;
    final posterBridgeOverlap = (posterCardHeight * 0.45).clamp(52.0, 92.0);
    final panelDropOffset = isLandscape
        ? (posterHeight * _landscapePanelDropRatio).clamp(24.0, 80.0)
        : (posterHeight * _portraitPanelDropRatio).clamp(8.0, 36.0);
    final tallComp = ((aspect - 1.90) * 80.0).clamp(0.0, 36.0);
    final tabletInsetComp = isTablet
        ? (screenSize.height * (isLandscape ? 0.06 : 0.075)).clamp(
            isLandscape ? 80.0 : 120.0,
            isLandscape ? 220.0 : 280.0,
          )
        : 0.0;
    final headerBodyTopPadding =
        (posterCardHeight - posterBridgeOverlap + 12 - panelDropOffset).clamp(
          60.0,
          360.0,
        );
    final topContentInset =
        media.padding.top +
        kToolbarHeight +
        (posterCardHeight * _topInsetPosterRatio) +
        panelDropOffset +
        tallComp +
        tabletInsetComp;
    final titleFontSize = isLandscape
        ? (screenSize.width * 0.028).clamp(30.0, 38.0)
        : 24.0;
    final playLabelFontSize = (20.0 * textScale).clamp(18.0, 24.0);

    final metaPrimary = colors.backgroundBase.computeLuminance() >= 0.58
        ? const Color(0xFF182132)
        : colors.textPrimary;
    final metaContent = AppTransitions.crossFadeSwitch(
      switchKey: 'neutral-meta-$_selectedSeasonGuid',
      duration: _seasonDataFadeDuration,
      child: Column(
        key: ValueKey<String>('neutral-meta-content-$_selectedSeasonGuid'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            seasonLabel,
            style: TextStyle(
              color: metaPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (rating > 0)
                Text(
                  AppLocalizations.of(
                    context,
                  ).detailRatingScore(rating.toStringAsFixed(1)),
                  style: const TextStyle(
                    color: Color(0xFFF2D34B),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (rating > 0 && year.isNotEmpty)
                Text(
                  '  /  ',
                  style: TextStyle(color: colors.textSecondary, fontSize: 17),
                ),
              if (year.isNotEmpty)
                Text(
                  year,
                  style: TextStyle(color: colors.textSecondary, fontSize: 17),
                ),
            ],
          ),
        ],
      ),
    );

    final pageBody = Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _scrollOffsetNotifier,
          builder: (context, offset, _) {
            return ImmersiveDetailBackground(
              urls: backdropUrls,
              lowResUrls: const <String>[],
              token: '',
              scrollOffset: offset,
              posterHeight: posterHeight,
              imageScale: 1.0,
              imageFit: BoxFit.cover,
              imageAlignment: heroImageAlignment,
              parallaxFactor: 1.0,
              fillGapsWithImage: false,
              enableBottomFade: true,
              fadeStart: 0.16,
              fadeMid: 0.42,
              ambientTintOverride: ambientTint,
              bottomFadeTintColor: heroFogBase,
              bottomFadeBackgroundColor: colors.backgroundBase,
              bottomFadeExtraHeight: 340,
              overlayOpacity: 0.0,
            );
          },
        ),
        ValueListenableBuilder<double>(
          valueListenable: _scrollOffsetNotifier,
          builder: (context, offset, _) {
            final parallaxMax = (screenSize.height * 0.85).clamp(180.0, 560.0);
            final collapseShift = offset
                .clamp(0.0, double.infinity)
                .clamp(0.0, parallaxMax);
            final pullDownShift = (-offset).clamp(0.0, 180.0);
            return Positioned(
              left: 0,
              right: 0,
              top: pullDownShift - collapseShift,
              height: topContentInset + 10 + pullDownShift,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        heroFogBase.withValues(alpha: 0.05),
                        heroFogBase.withValues(alpha: 0.11),
                        heroFogShadow.withValues(alpha: 0.22),
                        heroFogShadow.withValues(alpha: 0.34),
                        colors.backgroundBase,
                      ],
                      stops: const [0.0, 0.36, 0.56, 0.74, 0.88, 1.0],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Container(
                    color: colors.backgroundBase,
                    padding: const EdgeInsets.fromLTRB(
                      DetailTokens.screenHorizontalPadding,
                      0,
                      DetailTokens.screenHorizontalPadding,
                      20,
                    ),
                    child: TvSeasonDetailPanel.legacy(
                      title: title,
                      titleFontSize: titleFontSize,
                      token: '',
                      ambientTint: ambientTint,
                      posterUrls: posterUrls,
                      posterWidth: posterWidth.toDouble(),
                      posterCardHeight: posterCardHeight.toDouble(),
                      posterBridgeOverlap: posterBridgeOverlap.toDouble(),
                      panelDropOffset: panelDropOffset.toDouble(),
                      headerBodyTopPadding: headerBodyTopPadding.toDouble(),
                      headerMetaOpacity: _headerMetaOpacity,
                      metaContent: metaContent,
                      playLabel: _neutralPlayLabel(),
                      playLabelFontSize: playLabelFontSize.toDouble(),
                      watched: _watched,
                      downloaded: false,
                      descriptionVisible: _descriptionVisible,
                      switchDuration: _seasonDataFadeDuration,
                      overview: overview,
                      hasOverview: hasOverview,
                      episodeSection: showEpisodes
                          ? TvEpisodeBrowserSection(
                              title: AppLocalizations.of(
                                context,
                              ).detailEpisodeTitle,
                              totalLabel: !_episodeItemsResolved
                                  ? (expectedCount > 0
                                        ? AppLocalizations.of(
                                            context,
                                          ).detailEpisodeTotal(expectedCount)
                                        : AppLocalizations.of(
                                            context,
                                          ).commonLoading)
                                  : AppLocalizations.of(
                                      context,
                                    ).detailEpisodeTotal(
                                      _neutralEpisodes.length,
                                    ),
                              seasons: _neutralSeasonOptionEntries(),
                              episodes: episodeEntries,
                              selectedRangeIndex: _episodeRangeIndex,
                              rangeSize: _episodePageSize,
                              previewCount: 4,
                              emptyText: AppLocalizations.of(
                                context,
                              ).detailEpisodeEmpty,
                              detailText: AppLocalizations.of(
                                context,
                              ).commonDetails,
                              token: '',
                              mode: _episodePickerMode,
                              onSeasonSelected: _switchSeasonNeutral,
                              onRangeSelected: (index) {
                                setState(() => _episodeRangeIndex = index);
                              },
                              onEpisodeSelected: _openNeutralEpisode,
                              onEpisodeLongPress: (_) {},
                              onEpisodeDetailTap: _openNeutralEpisodeSummary,
                              onOpenPicker: () =>
                                  unawaited(_openNeutralEpisodePicker(context)),
                            )
                          : const SizedBox.shrink(),
                      creditsSection: creditItems.isNotEmpty
                          ? CreditsSection(
                              title: AppLocalizations.of(
                                context,
                              ).detailCastCrewTitle,
                              items: creditItems,
                              token: '',
                              onTap: _openCreditPerson,
                            )
                          : null,
                      linkSection:
                          (_imdbId.trim().isNotEmpty ||
                              _trimId.trim().isNotEmpty)
                          ? LinkSection(
                              imdbId: _imdbId,
                              tmdbId: _trimId,
                              onImdbTap: _openImdb,
                              onTmdbTap: _openTmdb,
                            )
                          : null,
                      onPlayTap: _onNeutralPlayTap,
                      onDownloadTap: _neutralComingSoon,
                      onWatchedTap: _neutralComingSoon,
                      favorite: favoriteSupported
                          ? _neutralSeriesFavorite
                          : null,
                      onFavoriteTap: favoriteSupported
                          ? _toggleNeutralSeriesFavorite
                          : null,
                      onOverviewTap: () {
                        LongTextOverlayPage.show(
                          context,
                          title: title,
                          sectionTitle: AppLocalizations.of(
                            context,
                          ).detailOverviewTitle,
                          content: overview,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ValueListenableBuilder<double>(
          valueListenable: _scrollOffsetNotifier,
          builder: (context, offset, _) {
            final collapseT = (offset / collapseRange).clamp(0.0, 1.0);
            final centerTitleOpacity = ((collapseT - 0.82) / 0.16).clamp(
              0.0,
              1.0,
            );
            final barTitle = seasonLabel.isNotEmpty
                ? '$title $seasonLabel'
                : title;
            return DetailFloatingTopBar(
              onBack: () =>
                  unawaited(EmbeddedDetailLauncher.closeHostOrPop(context)),
              onMore: () => unawaited(
                showDetailMoreActionsSheet(
                  context,
                  pageKey: _selectedSeasonGuid.trim().isNotEmpty
                      ? _selectedSeasonGuid
                      : widget.seasonItem.guid,
                  pageTitle: barTitle,
                  suggestedThemeName: context
                      .read<AppThemeProvider>()
                      .nextSavedThemeNameFromBase(barTitle),
                  clearRuntimeBroadcastToMain:
                      PlayerPaneHostScope.maybeOf(context) == null,
                ),
              ),
              title: barTitle,
              titleOpacity: centerTitleOpacity,
              showBack: true,
            );
          },
        ),
      ],
    );

    return Scaffold(backgroundColor: colors.backgroundBase, body: pageBody);
  }

  Future<void> _loadSeasonData(
    String requestedGuid, {
    required bool showLoading,
  }) async {
    // 非飞牛后端(Emby):走中立加载,不调任何 FeiniuApi。飞牛分支整段保持原样。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      await _loadSeasonDataNeutral(requestedGuid, showLoading: showLoading);
      return;
    }
    _deferredLoadTimer?.cancel();
    if (showLoading) _resetEntryAnimations();
    final seq = ++_seasonLoadSeq;

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _descriptionVisible = false;
        _episodeItemsResolved = false;
        _artworkReady = false;
      });
    }

    List<MediaLibraryItem> seasons = _seasonItems;
    String target = requestedGuid;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      seasons = await _loadSeasonItems(api, widget.parentGuid);
      target = seasons.any((s) => s.guid == requestedGuid)
          ? requestedGuid
          : (seasons.isNotEmpty ? seasons.first.guid : requestedGuid);
      MediaLibraryItem fallbackSeason = widget.seasonItem;
      for (final season in seasons) {
        if (season.guid == target) {
          fallbackSeason = season;
          break;
        }
      }

      final detailFuture = () async {
        try {
          return await _loadItemDetail(api, target);
        } catch (error) {
          final detailError = AppException.from(
            error,
            action: 'tv season detail item',
            fallbackKind: AppExceptionKind.transient,
          );
          if (!detailError.isNoData) {
            rethrow;
          }
          return _fallbackSeasonDetail(fallbackSeason);
        }
      }();
      final playInfoFuture = _loadPlayInfoOrNull(api, target);
      final episodesFuture = _loadEpisodesForSeason(
        target,
        forceRefresh: showLoading,
      );
      final detail = await detailFuture;
      final playInfo = await playInfoFuture;

      if (!mounted || seq != _seasonLoadSeq) return;
      // 首次进入（showLoading）时把"骨架→正文"整树替换推迟到转场结束后；
      // 切季（showLoading=false）路由已稳定，gate 立即返回，无额外延迟。
      await RouteTransitionGate.of(context);
      if (!mounted || seq != _seasonLoadSeq) return;
      setState(() {
        _seasonItems = seasons;
        _selectedSeasonGuid = target;
        _detail = detail;
        _playInfo = playInfo;
        _imdbId = _extractImdbId(detail);
        _trimId = _extractTrimId(detail);
        _watched = _asInt(_itemMap(detail)['is_watched']) == 1;
        _selectedEpisodeGuid = playInfo?.item.guid.trim() ?? '';
        if (showLoading) {
          _episodeItems = const <MediaLibraryItem>[];
          _episodeItemsResolved = false;
          _episodeRangeIndex = 0;
          _artworkReady = false;
          _personCredits = const [];
          _creditsVisible = false;
          _descriptionVisible = false;
        } else {
          _episodeRangeIndex = 0;
          _descriptionVisible = true;
          _artworkReady = _artworkReady || _episodeItemsResolved;
        }
        _loading = false;
        _error = null;
      });
      if (showLoading) _resetScrollToTop();
      if (showLoading) _startEntryAnimations();
      _startDeferredLoad(seq: seq, seasonGuid: target);
      unawaited(
        _resolveEpisodeItems(
          seq: seq,
          seasonGuid: target,
          episodesFuture: episodesFuture,
        ),
      );
    } catch (e) {
      if (!mounted || seq != _seasonLoadSeq) return;
      final appError = AppException.from(
        e,
        action: 'tv season detail',
        fallbackKind: AppExceptionKind.transient,
      );
      MediaLibraryItem fallbackSeason = widget.seasonItem;
      for (final season in seasons) {
        if (season.guid == target) {
          fallbackSeason = season;
          break;
        }
      }
      final canFallback =
          fallbackSeason.guid.trim().isNotEmpty &&
          (appError.isNoData || fallbackSeason.guid == requestedGuid);
      if (canFallback) {
        _applyFallbackSeasonState(
          seasons: seasons,
          target: target,
          fallbackSeason: fallbackSeason,
          showLoading: showLoading,
        );
        return;
      }
      setState(() {
        _error = appError;
        _loading = false;
      });
    }
  }

  void _startDeferredLoad({required int seq, required String seasonGuid}) {
    _deferredLoadTimer?.cancel();
    _deferredLoadTimer = Timer(_deferredStartDelay, () {
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() {
        _descriptionVisible = true;
        _artworkReady = _episodeItemsResolved;
      });
      unawaited(_loadDeferredSections(seq: seq, seasonGuid: seasonGuid));
    });
  }

  Future<void> _resolveEpisodeItems({
    required int seq,
    required String seasonGuid,
    required Future<List<MediaLibraryItem>> episodesFuture,
  }) async {
    try {
      final episodes = await episodesFuture;
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      final selectedEpisodeGuid = _preferredEpisodeGuid(episodes);
      setState(() {
        _episodeItems = episodes;
        _episodeItemsResolved = true;
        _selectedEpisodeGuid = selectedEpisodeGuid;
        _episodeRangeIndex = _rangeIndexForEpisodeGuid(
          episodes,
          selectedEpisodeGuid,
        );
        _artworkReady = _descriptionVisible;
      });
      unawaited(_prefetchDownloadData(episodes, selectedEpisodeGuid));
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'resolve feiniu episode items',
        id: seasonGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() {
        _episodeItems = const <MediaLibraryItem>[];
        _episodeItemsResolved = true;
        _selectedEpisodeGuid = '';
        _episodeRangeIndex = 0;
        _artworkReady = _descriptionVisible;
      });
    }
  }

  Future<void> _loadDeferredSections({
    required int seq,
    required String seasonGuid,
  }) async {
    await Future<void>.delayed(_deferredCreditsDelay);
    if (!mounted ||
        seq != _seasonLoadSeq ||
        seasonGuid != _selectedSeasonGuid) {
      return;
    }
    final api = FeiniuApi(context.read<NasProvider>());
    try {
      final people = await _loadPersonCredits(api, seasonGuid);
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() {
        _personCredits = people;
        _creditsVisible = people.isNotEmpty;
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu season credits',
        id: seasonGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
    }
  }

  Future<void> _switchSeason(String seasonGuid) async {
    if (_selectedSeasonGuid == seasonGuid || _seasonSwitching) return;
    MediaLibraryItem targetSeason = widget.seasonItem;
    for (final season in _seasonItems) {
      if (season.guid == seasonGuid) {
        targetSeason = season;
        break;
      }
    }
    setState(() {
      _seasonSwitching = true;
      _selectedSeasonGuid = seasonGuid;
      _detail = _fallbackSeasonDetail(targetSeason);
      _playInfo = null;
      _imdbId = '';
      _trimId = '';
      _error = null;
      _selectedEpisodeGuid = '';
      _episodeRangeIndex = 0;
      _descriptionVisible = true;
      _artworkReady = true;
    });
    try {
      await _loadSeasonData(seasonGuid, showLoading: false);
    } finally {
      if (mounted) {
        setState(() {
          _seasonSwitching = false;
        });
      } else {
        _seasonSwitching = false;
      }
    }
  }

  Future<void> _onPlayTap() async {
    final episodeGuid = _selectedEpisodeGuid.trim().isNotEmpty
        ? _selectedEpisodeGuid.trim()
        : _currentPlaybackEpisodeGuid();
    if (episodeGuid.isEmpty || _playPreparing) return;
    setState(() => _playPreparing = true);
    // 进原生壳前绑定反向 handler：原生壳「选集」回到这里复用 launcher 解析新集，
    // 退出/暂停回到这里写回进度（最近发起的 detail page 生效）。
    _bindNativePlayerReentry();
    try {
      final result = await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: episodeGuid,
        seriesTitle: widget.seriesTitle,
        seriesGuid: widget.parentGuid,
        episodes: _nativeEpisodesPayload(),
      );
      if (!mounted) return;
      final nextEpisodeGuid = result?.itemGuid.trim().isNotEmpty == true
          ? result!.itemGuid.trim()
          : episodeGuid;
      setState(() {
        _selectedEpisodeGuid = nextEpisodeGuid;
        _episodeRangeIndex = _rangeIndexForEpisodeGuid(
          _episodeItems,
          nextEpisodeGuid,
        );
      });
      unawaited(_refreshAfterPlayback(nextEpisodeGuid));
    } catch (error, stackTrace) {
      unawaited(
        logSwallowedError(
          action: 'launch feiniu episode playback',
          id: episodeGuid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
        ),
      );
      _showTopTip(
        AppLocalizations.of(context).detailPlayInfoFailed,
        context.appColors.danger,
      );
    } finally {
      if (mounted) {
        setState(() => _playPreparing = false);
      } else {
        _playPreparing = false;
      }
    }
  }

  /// 本季剧集映射成原生壳「选集」对话框所需的精简列表（随 loadArgs 透传）。
  List<Map<String, dynamic>> _nativeEpisodesPayload() {
    return <Map<String, dynamic>>[
      for (var i = 0; i < _episodeItems.length; i++)
        <String, dynamic>{
          'itemGuid': _episodeItems[i].guid,
          'episodeNumber': _episodeItems[i].episodeNumber,
          'title': _episodeTitle(_episodeItems[i], i),
          'shortLabel': _episodeShortLabel(_episodeItems[i], i),
          'poster': _episodeItems[i].poster,
        },
    ];
  }

  /// 中立(Emby)选集 → 原生壳「选集」精简列表（封面为 api_key 自鉴权直链）。
  List<Map<String, dynamic>> _neutralNativeEpisodesPayload() {
    return <Map<String, dynamic>>[
      for (var i = 0; i < _neutralEpisodes.length; i++)
        <String, dynamic>{
          'itemGuid': _neutralEpisodes[i].id,
          'episodeNumber': _neutralEpisodes[i].episodeNumber,
          'title': _neutralEpisodes[i].title,
          'shortLabel': _neutralEpisodes[i].episodeNumber > 0
              ? '${_neutralEpisodes[i].episodeNumber}'
              : '${i + 1}',
          'poster': _neutralEpisodes[i].primaryImage.url,
        },
    ];
  }

  /// 中立(Emby)季播放：播选中集（无则首集），走 [TvSeasonPlaybackLauncher]（与飞牛同入口、
  /// 原生壳）。进原生壳前绑定 Emby 最小反向通道，使壳内「选集」能切到本季其它 Emby 单集。
  Future<void> _onNeutralPlayTap() async {
    final episodeGuid = _selectedEpisodeGuid.trim().isNotEmpty
        ? _selectedEpisodeGuid.trim()
        : (_neutralEpisodes.isNotEmpty ? _neutralEpisodes.first.id : '');
    if (episodeGuid.isEmpty || _playPreparing) return;
    setState(() => _playPreparing = true);
    _bindEmbyNativePlayerReentry();
    try {
      final result = await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: episodeGuid,
        seriesTitle: widget.seriesTitle,
        seriesGuid: widget.parentGuid,
        episodes: _neutralNativeEpisodesPayload(),
      );
      if (!mounted) return;
      final nextEpisodeGuid = result?.itemGuid.trim().isNotEmpty == true
          ? result!.itemGuid.trim()
          : episodeGuid;
      final idx = _neutralEpisodes.indexWhere((e) => e.id == nextEpisodeGuid);
      setState(() {
        _selectedEpisodeGuid = nextEpisodeGuid;
        if (idx >= 0) _episodeRangeIndex = idx ~/ _episodePageSize;
      });
    } catch (error, stackTrace) {
      unawaited(
        logSwallowedError(
          action: 'launch neutral episode playback',
          id: episodeGuid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
        ),
      );
      if (mounted) {
        _showTopTip(
          AppLocalizations.of(context).detailPlayInfoFailed,
          context.appColors.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _playPreparing = false);
      } else {
        _playPreparing = false;
      }
    }
  }

  /// 绑定 Emby 反向通道：选集 → 复用 launcher 原地换源 + 更新选中集高亮。其余标准回调（进度
  /// 回写 / 选集数据 / 跨季 / 外挂字幕）由 [NativePlaybackReentry] 按后端统一接线，与飞牛同口径。
  void _bindEmbyNativePlayerReentry() {
    final backend = context.read<MediaBackendProvider>().backend;
    final nas = context.read<NasProvider>();
    _reentryToken = NativePlaybackReentry.bind(
      backend: backend,
      nas: nas,
      l10n: AppLocalizations.of(context),
      fallbackEpisodes: _neutralNativeEpisodesPayload,
      onResolvePlayback:
          (
            itemGuid, {
            audioGuid,
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
          }) async {
            if (!mounted) return null;
            final resolved = await const TvSeasonPlaybackLauncher()
                .resolveForNative(
                  context,
                  itemGuid: itemGuid,
                  seriesTitle: widget.seriesTitle,
                  seriesGuid: widget.parentGuid,
                  episodes: _neutralNativeEpisodesPayload(),
                  audioGuid: audioGuid,
                  qualityIndex: qualityIndex,
                  qualityMediaGuid: qualityMediaGuid,
                  startPositionMs: startPositionMs,
                  subtitleGuid: subtitleGuid,
                  audioTrackIndex: audioTrackIndex,
                  subtitleTrackIndex: subtitleTrackIndex,
                  preferredQualityResolution: preferredQualityResolution,
                );
            // 仅选集（无切画质/轨道）更新选中集高亮。
            if (resolved != null &&
                mounted &&
                qualityIndex == null &&
                subtitleGuid == null &&
                audioGuid == null) {
              final idx = _neutralEpisodes.indexWhere((e) => e.id == itemGuid);
              setState(() {
                _selectedEpisodeGuid = itemGuid;
                if (idx >= 0) _episodeRangeIndex = idx ~/ _episodePageSize;
              });
            }
            return resolved;
          },
    );
  }

  /// 绑定原生壳反向通道：选集 → 复用 launcher 原地换源 + 更新选中集高亮 + 刷新。其余标准回调
  /// （进度回写 / 外挂字幕 / 服务端会话重载 / 选集数据）由 [NativePlaybackReentry] 统一接线。
  void _bindNativePlayerReentry() {
    final nas = context.read<NasProvider>();
    final backend = context.read<MediaBackendProvider>().backend;
    _reentryToken = NativePlaybackReentry.bind(
      backend: backend,
      nas: nas,
      l10n: AppLocalizations.of(context),
      fallbackEpisodes: _nativeEpisodesPayload,
      onResolvePlayback:
          (
            itemGuid, {
            audioGuid,
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
          }) async {
            if (!mounted) return null;
            final resolved = await const TvSeasonPlaybackLauncher()
                .resolveForNative(
                  context,
                  itemGuid: itemGuid,
                  seriesTitle: widget.seriesTitle,
                  seriesGuid: widget.parentGuid,
                  episodes: _nativeEpisodesPayload(),
                  audioGuid: audioGuid,
                  qualityIndex: qualityIndex,
                  qualityMediaGuid: qualityMediaGuid,
                  startPositionMs: startPositionMs,
                  subtitleGuid: subtitleGuid,
                  audioTrackIndex: audioTrackIndex,
                  subtitleTrackIndex: subtitleTrackIndex,
                  preferredQualityResolution: preferredQualityResolution,
                );
            // 仅选集（无 qualityIndex、非字幕/音轨重载）更新选中集高亮；切画质/轨道保持当前集不动。
            if (resolved != null &&
                mounted &&
                qualityIndex == null &&
                subtitleGuid == null &&
                audioGuid == null) {
              setState(() {
                _selectedEpisodeGuid = itemGuid;
                _episodeRangeIndex = _rangeIndexForEpisodeGuid(
                  _episodeItems,
                  itemGuid,
                );
              });
              unawaited(_refreshAfterPlayback(itemGuid));
            }
            return resolved;
          },
    );
  }

  Future<void> _toggleWatched() async {
    final season = _currentSeason();
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.warning,
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    try {
      final watched = await FeiniuApi(
        context.read<NasProvider>(),
      ).setWatched(season.guid, watched: !_watched);
      if (!mounted) return;
      setState(() => _watched = watched);
      unawaited(_refreshAfterPlayback(_selectedEpisodeGuid));
      _showTopTip(
        watched
            ? AppLocalizations.of(context).actionMarkedAsWatched
            : AppLocalizations.of(context).actionMarkedAsUnwatched,
        watched ? const Color(0xFF19A35B) : const Color(0xFF3B4A5E),
      );
    } catch (error, stackTrace) {
      unawaited(
        logSwallowedError(
          action: 'toggle feiniu season watched',
          id: season.guid,
          error: error,
          stackTrace: stackTrace,
          source: 'tv_season_detail_page',
        ),
      );
      _showTopTip(
        _watched
            ? AppLocalizations.of(context).detailMarkUnwatchedFailed
            : AppLocalizations.of(context).detailMarkWatchedFailed,
        context.appColors.danger,
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  // ignore: unused_element
  void _onDownloadTap() {
    _showTopTip(
      AppLocalizations.of(context).detailDownloadPlaceholder,
      const Color(0xFF3B4A5E),
    );
  }

  Future<void> _prefetchDownloadData(
    List<MediaLibraryItem> episodes,
    String selectedEpisodeGuid,
  ) async {
    if (episodes.isEmpty) return;
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return;
    final api = FeiniuApi(provider);
    final candidates = <String>{
      selectedEpisodeGuid.trim(),
      _playInfo?.item.guid ?? '',
      episodes.first.guid,
      _selectedSeasonGuid,
      widget.seasonItem.guid,
    }.where((g) => g.isNotEmpty).toList(growable: false);
    await TvSeasonDownloadSheetController.prefetchSeasonDownloadData(
      api,
      candidateItemGuids: candidates,
    );
  }

  void _handleDownloadTap() {
    final episodeEntries = _episodeCardEntries(_episodeItems);
    unawaited(
      _downloadSheetController.show(
        context,
        episode: _selectedDownloadEpisode(),
        candidateItemGuids: <String>[
          _selectedEpisodeGuid,
          _currentPlaybackEpisodeGuid(),
          _playInfo?.item.guid ?? '',
          if (_episodeItems.isNotEmpty) _episodeItems.first.guid,
          _selectedSeasonGuid,
          widget.seasonItem.guid,
        ],
        episodeEntries: episodeEntries,
        initialRangeIndex: _episodeRangeIndex,
        rangeSize: _episodePageSize,
        seriesTitle: widget.seriesTitle,
        preferredSubtitleGuid: _playInfo?.subtitleGuid ?? '',
        localeMap: _localeMap,
      ),
    );
  }

  MediaLibraryItem? _selectedDownloadEpisode() {
    if (_episodeItems.isNotEmpty) {
      final preferredGuid = _preferredEpisodeGuid(_episodeItems).trim();
      if (preferredGuid.isNotEmpty) {
        for (final episode in _episodeItems) {
          if (episode.guid == preferredGuid) {
            return episode;
          }
        }
      }
      return _episodeItems.first;
    }

    final playItem = _playInfo?.item;
    if (playItem != null && playItem.guid.trim().isNotEmpty) {
      return MediaLibraryItem(
        guid: playItem.guid.trim(),
        title: playItem.title,
        tvTitle: playItem.tvTitle,
        type: playItem.type,
        poster: playItem.posters,
        releaseDate: playItem.releaseDate,
        firstAirDate: playItem.airDate,
        lastAirDate: '',
        voteAverage: playItem.voteAverage,
        overview: playItem.overview,
        watched: playItem.isWatched,
        watchedTs: playItem.watchedTs,
        ts: playItem.watchedTs,
        duration: playItem.duration,
        seasonNumber: playItem.seasonNumber,
        episodeNumber: playItem.episodeNumber,
        numberOfSeasons: playItem.numberOfSeasons,
        numberOfEpisodes: playItem.numberOfEpisodes,
        localNumberOfSeasons: playItem.localNumberOfSeasons,
        localNumberOfEpisodes: playItem.localNumberOfEpisodes,
        parentGuid: _playInfo?.parentGuid ?? '',
        parentTitle: playItem.parentTitle,
        ancestorGuid: '',
        ancestorName: playItem.ancestorName,
        path: '',
        resolutions: playItem.resolutions,
      );
    }

    final selectedGuid = _selectedEpisodeGuid.trim();
    if (selectedGuid.isNotEmpty) {
      return MediaLibraryItem(
        guid: selectedGuid,
        title: '',
        tvTitle: widget.seriesTitle,
        type: 'Episode',
        poster: '',
        releaseDate: '',
        firstAirDate: '',
        lastAirDate: '',
        voteAverage: '',
        overview: '',
        watched: 0,
        watchedTs: 0,
        ts: 0,
        duration: 0,
        seasonNumber: _currentSeason().seasonNumber,
        episodeNumber: 0,
        numberOfSeasons: 0,
        numberOfEpisodes: 0,
        localNumberOfSeasons: 0,
        localNumberOfEpisodes: 0,
        parentGuid: _selectedSeasonGuid,
        parentTitle: _currentSeason().title,
        ancestorGuid: '',
        ancestorName: '',
        path: '',
      );
    }

    return null;
  }

  bool _isCurrentSeasonFullyDownloaded() {
    if (_episodeItems.isNotEmpty) {
      var downloadableCount = 0;
      for (final episode in _episodeItems) {
        final guid = episode.guid.trim();
        if (guid.isEmpty) continue;
        downloadableCount += 1;
        if (!_downloadTaskService.actionStateForItem(guid).downloaded) {
          return false;
        }
      }
      return downloadableCount > 0;
    }

    final selectedEpisode = _selectedDownloadEpisode();
    final selectedGuid = selectedEpisode?.guid.trim() ?? '';
    final totalEpisodes = _currentSeason().localNumberOfEpisodes > 0
        ? _currentSeason().localNumberOfEpisodes
        : _currentSeason().numberOfEpisodes;
    if (totalEpisodes <= 1 && selectedGuid.isNotEmpty) {
      return _downloadTaskService.actionStateForItem(selectedGuid).downloaded;
    }
    return false;
  }

  Future<void> _refreshAfterPlayback(String episodeGuid) async {
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail = await _loadItemDetail(
        api,
        _selectedSeasonGuid,
        forceRefresh: true,
      );
      final playInfo = await _loadPlayInfoOrNull(
        api,
        _selectedSeasonGuid,
        forceRefresh: true,
      );
      final episodes = await _loadEpisodesForSeason(
        _selectedSeasonGuid,
        forceRefresh: true,
      );
      if (!mounted) return;
      final selectedEpisodeGuid = episodeGuid.trim().isNotEmpty
          ? episodeGuid.trim()
          : _preferredEpisodeGuid(episodes);
      setState(() {
        _detail = detail;
        _playInfo = playInfo;
        _imdbId = _extractImdbId(detail);
        _trimId = _extractTrimId(detail);
        _watched = _asInt(_itemMap(detail)['is_watched']) == 1;
        _episodeItems = episodes;
        _selectedEpisodeGuid = selectedEpisodeGuid;
        _episodeRangeIndex = _rangeIndexForEpisodeGuid(
          episodes,
          selectedEpisodeGuid,
        );
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'refresh season after playback',
        id: episodeGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
    }
  }

  Future<void> _openEpisodeDetail(MediaLibraryItem episode) async {
    var initialDetail = _buildEpisodeInitialDetailFallback(episode);
    try {
      final hydrated = await _loadItemDetail(
        FeiniuApi(context.read<NasProvider>()),
        episode.guid,
      ).timeout(const Duration(milliseconds: 240));
      if (hydrated.isNotEmpty) {
        initialDetail = hydrated;
      }
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'prefetch episode detail',
        id: episode.guid,
        error: error,
        stackTrace: stackTrace,
        source: 'tv_season_detail_page',
      );
    }
    if (!mounted) return;
    _primeEpisodeThemeSeed(episode, initialDetail);
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: episode.guid,
        seriesGuid: widget.parentGuid,
        initialItemDetail: initialDetail,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  Map<String, dynamic> _buildEpisodeInitialDetailFallback(
    MediaLibraryItem episode,
  ) {
    final season = _currentSeason();
    final resolvedSeasonGuid = episode.parentGuid.trim().isNotEmpty
        ? episode.parentGuid.trim()
        : (_selectedSeasonGuid.trim().isNotEmpty
              ? _selectedSeasonGuid.trim()
              : widget.seasonItem.guid.trim());
    final resolvedBackdropPath = widget.backdropPath.trim().isNotEmpty
        ? widget.backdropPath.trim()
        : (season.poster.trim().isNotEmpty
              ? season.poster.trim()
              : episode.poster.trim());
    final resolvedPosterPath = episode.poster.trim().isNotEmpty
        ? episode.poster.trim()
        : season.poster.trim();
    final item = <String, dynamic>{
      'guid': episode.guid,
      'type': episode.type,
      'title': episode.title,
      'display_title': episode.displayTitle,
      'tv_title': episode.tvTitle.trim().isNotEmpty
          ? episode.tvTitle
          : widget.seriesTitle,
      'parent_title': episode.parentTitle.trim().isNotEmpty
          ? episode.parentTitle
          : season.title,
      'posters': resolvedPosterPath,
      'backdrops': resolvedBackdropPath,
      'still_path': resolvedPosterPath,
      'vote_average': episode.voteAverage,
      'overview': episode.overview,
      'release_date': episode.releaseDate,
      'air_date': episode.firstAirDate,
      'watched_ts': episode.watchedTs,
      'season_number': episode.seasonNumber,
      'episode_number': episode.episodeNumber,
      'number_of_seasons': season.numberOfSeasons,
      'local_number_of_seasons': season.localNumberOfSeasons,
      'number_of_episodes': season.numberOfEpisodes,
      'local_number_of_episodes': season.localNumberOfEpisodes,
      'ancestor_name': episode.ancestorName,
      'is_watched': episode.watched,
      'can_play': 1,
      'media_stream': <String, dynamic>{'resolutions': episode.resolutions},
    };
    return <String, dynamic>{
      'guid': episode.guid,
      'item': item,
      'parent_guid': resolvedSeasonGuid,
      'grand_guid': widget.parentGuid,
      'imdb_id': '',
      'trim_id': '',
    };
  }

  void _openEpisodeDetailByGuid(String episodeGuid) {
    final index = _episodeItems.indexWhere(
      (episode) => episode.guid == episodeGuid,
    );
    if (index < 0) return;
    unawaited(_openEpisodeDetail(_episodeItems[index]));
  }

  void _openEpisodeSummaryByGuid(
    BuildContext themedContext,
    String episodeGuid,
  ) {
    final index = _episodeItems.indexWhere(
      (episode) => episode.guid == episodeGuid,
    );
    if (index < 0) return;
    final episode = _episodeItems[index];
    final summary = episode.overview.trim();
    if (!_hasMeaningfulText(summary)) {
      return;
    }
    LongTextOverlayPage.show(
      themedContext,
      title: _episodeTitle(episode, index),
      sectionTitle: AppLocalizations.of(context).detailOverviewTitle,
      content: summary,
    );
  }

  void _replaceEpisodeItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _episodeItems = _episodeItems
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
    });
  }

  Future<void> _showEpisodeCardActions(String episodeGuid) async {
    final index = _episodeItems.indexWhere(
      (episode) => episode.guid == episodeGuid,
    );
    if (index < 0) return;
    final episode = _episodeItems[index];
    final l10n = AppLocalizations.of(context);
    final target = episode.toActionTarget();
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.episodeTitle(
        l10n,
        widget.seriesTitle,
        target,
      ),
      initialWatched: episode.watched == 1,
      onChanged: (state) {
        _replaceEpisodeItemLocally(
          episode.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
        unawaited(_refreshAfterPlayback(episode.guid));
      },
    );
  }

  Future<void> _openEpisodePicker(BuildContext sheetContext) async {
    if (_seasonItems.isEmpty) return;
    final result = await TvEpisodePickerSheet.show(
      sheetContext,
      title: AppLocalizations.of(context).detailEpisodeTitle,
      seasons: _seasonOptionEntries(),
      initialSeasonGuid: _selectedSeasonGuid,
      initialEpisodeGuid: _selectedEpisodeGuid,
      initialMode: _episodePickerMode,
      rangeSize: _episodePageSize,
      emptyText: AppLocalizations.of(context).detailEpisodeEmpty,
      token: context.read<NasProvider>().token,
      loader: _episodePickerPayloadForSeason,
      onModeChanged: _persistEpisodePickerMode,
    );
    if (!mounted || result == null) return;
    if (result.seasonGuid != _selectedSeasonGuid) {
      await _switchSeason(result.seasonGuid);
    }
    if (!mounted) return;
    if (result.openDetail) {
      _openEpisodeDetailByGuid(result.episodeGuid);
      return;
    }
    setState(() {
      _episodePickerMode = result.mode;
      _selectedEpisodeGuid = result.episodeGuid;
      _episodeRangeIndex = _rangeIndexForEpisodeGuid(
        _episodeItems,
        result.episodeGuid,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dynamicThemeIntensity = context
        .select<AppThemeProvider, AppDynamicThemeIntensity>(
          (themeProvider) => themeProvider.dynamicThemeIntensity,
        );
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    final dynamicThemeKey = _seasonDynamicThemeKey();

    return DynamicPageThemeScope(
      pageKey: dynamicThemeKey,
      imageUrl: '',
      token: nasProvider.token,
      // Season pages never sample their own color. They display the sticky
      // global runtime color carried over from whatever episode/detail page
      // last sampled it, so popping back from an episode keeps the episode's
      // color instead of switching to the season's own palette. enabled:false
      // makes this scope produce no local seed and fall through to that global
      // color (via context.appColors → AppRuntimeColorScope).
      enabled: false,
      allowLiveResolve: false,
      syncGlobalTheme: false,
      deferLocalThemeApplyUntilGlobalSync: false,
      intensity: dynamicThemeIntensity,
      builder: (context, ambientTint) {
        final colors = context.appColors;
        final heroFogBase = Color.alphaBlend(
          (ambientTint ?? colors.backgroundElevated).withValues(
            alpha: colors.backgroundBase.computeLuminance() >= 0.58
                ? 0.18
                : 0.28,
          ),
          colors.backgroundBase,
        );
        final heroFogShadow = Color.alphaBlend(
          colors.overlayScrim.withValues(alpha: 0.12),
          heroFogBase,
        );
        if (_error != null) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            appBar: _isPane
                ? null
                : AppBar(backgroundColor: colors.backgroundBase),
            body: AppErrorState(
              error: _error!,
              localeMap: _localeMap,
              onRetry: () =>
                  _loadSeasonData(_selectedSeasonGuid, showLoading: true),
            ),
          );
        }

        // 中立(Emby)展示路:飞牛 build 整段不进。
        if (_neutralDisplayOnly && _neutralDetail != null) {
          return _buildNeutralSeasonBody(colors, ambientTint);
        }

        final provider = context.read<NasProvider>();
        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final textScale = media.textScaler.scale(1).clamp(1.0, 1.35);
        final aspect = screenSize.height / screenSize.width;
        final shortestSide = screenSize.shortestSide;
        final isLandscape = screenSize.width > screenSize.height;
        final isTablet = shortestSide >= 720.0;
        final heroAdaptive = TvHeroAdaptive.resolve(
          screenSize,
          devicePixelRatio: media.devicePixelRatio,
        );
        final posterHeightRatio = isLandscape ? 0.42 : 0.31;
        const heroImageFit = BoxFit.cover;
        final heroImageAlignment = isLandscape
            ? Alignment(heroAdaptive.imageAlignX, heroAdaptive.imageAlignY)
            : Alignment(heroAdaptive.imageAlignX, -1.0);
        final posterHeightMax = screenSize.height * 0.42;
        final posterHeightMin = math.min(260.0, posterHeightMax);
        final posterHeight = math
            .min(screenSize.height * posterHeightRatio, screenSize.width / 1.55)
            .clamp(posterHeightMin, posterHeightMax)
            .toDouble();
        final collapseRange =
            (posterHeight - media.padding.top - kToolbarHeight).clamp(
              120.0,
              360.0,
            );

        final item = _itemMap(_detail);
        final season = _currentSeason();
        final overview = (item['overview'] ?? season.overview)
            .toString()
            .trim();
        final hasOverview = _hasMeaningfulText(overview);
        final year = _year(season.releaseDate);
        final rating = double.tryParse(season.voteAverage) ?? 0;
        final title = widget.seriesTitle;
        final playLabel = _playLabel();
        final deferAuxiliaryArtwork = !_artworkReady;
        final backdropRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio * 1.2 : 1200.0)
                .clamp(720.0, 1200.0)
                .round();

        final backdropUrls = _imageCandidates(
          widget.backdropPath,
          width: backdropRequestWidth,
        );
        final backdropLowResUrls = _imageCandidates(
          widget.backdropPath,
          width: 360,
        );
        final posterUrls = _imageCandidates(season.poster, width: 560);
        final expectedEpisodeCount = _expectedEpisodeCount();
        final episodeEntries = _episodeItemsResolved
            ? _episodeCardEntries(
                _episodeItems,
                includeImages: !deferAuxiliaryArtwork,
              )
            : _episodePlaceholderEntries(expectedEpisodeCount);
        final episodeEmptyText = AppLocalizations.of(
          context,
        ).detailEpisodeEmpty;
        final episodeDetailText = AppLocalizations.of(context).commonDetails;
        final episodeTotalLabel = AppLocalizations.of(
          context,
        ).detailEpisodeTotal(_episodeItems.length);

        final creditItems = _personCredits
            .map(
              (p) => CreditPersonItem(
                personGuid: p.personGuid,
                name: p.displayName,
                subtitle: p.displaySubTitle,
                imageUrls: deferAuxiliaryArtwork
                    ? const <String>[]
                    : _imageCandidates(p.profilePath, width: 180),
              ),
            )
            .toList();

        final posterWidth = (screenSize.width * (isLandscape ? 0.30 : 0.36))
            .clamp(136.0, isLandscape ? 182.0 : 188.0);
        final posterCardHeight = posterWidth * 1.45;
        final posterBridgeOverlap = (posterCardHeight * 0.45).clamp(52.0, 92.0);
        final panelDropOffset = isLandscape
            ? (posterHeight * _landscapePanelDropRatio).clamp(24.0, 80.0)
            : (posterHeight * _portraitPanelDropRatio).clamp(8.0, 36.0);
        final tallComp = ((aspect - 1.90) * 80.0).clamp(0.0, 36.0);
        final tabletInsetComp = isTablet
            ? (screenSize.height * (isLandscape ? 0.06 : 0.075)).clamp(
                isLandscape ? 80.0 : 120.0,
                isLandscape ? 220.0 : 280.0,
              )
            : 0.0;
        final headerBodyTopPadding =
            (posterCardHeight - posterBridgeOverlap + 12 - panelDropOffset)
                .clamp(60.0, 360.0);
        final baseTopContentInset =
            media.padding.top +
            kToolbarHeight +
            (posterCardHeight * _topInsetPosterRatio) +
            panelDropOffset +
            tallComp +
            tabletInsetComp;
        final topContentInset = baseTopContentInset;
        const heroImageScale = 1.0;
        final titleFontSize = isLandscape
            ? (screenSize.width * 0.028).clamp(30.0, 38.0)
            : 24.0;
        final playLabelFontSize = (20.0 * textScale).clamp(18.0, 24.0);

        final pageBody = _loading
            ? DetailLoadingSkeleton(presentation: widget.presentation)
            : Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _scrollOffsetNotifier,
                    builder: (context, offset, _) {
                      return ImmersiveDetailBackground(
                        urls: backdropUrls,
                        lowResUrls: backdropLowResUrls,
                        token: provider.token,
                        scrollOffset: offset,
                        posterHeight: posterHeight,
                        imageScale: heroImageScale,
                        imageFit: heroImageFit,
                        imageAlignment: heroImageAlignment,
                        parallaxFactor: 1.0,
                        fillGapsWithImage: false,
                        enableBottomFade: true,
                        fadeStart: 0.16,
                        fadeMid: 0.42,
                        ambientTintOverride: ambientTint,
                        bottomFadeTintColor: heroFogBase,
                        bottomFadeBackgroundColor: colors.backgroundBase,
                        bottomFadeExtraHeight: 340,
                        overlayOpacity: 0.0,
                      );
                    },
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _scrollOffsetNotifier,
                    builder: (context, offset, _) {
                      final parallaxMax = (screenSize.height * 0.85).clamp(
                        180.0,
                        560.0,
                      );
                      final collapseShift = offset
                          .clamp(0.0, double.infinity)
                          .clamp(0.0, parallaxMax);
                      final pullDownShift = (-offset).clamp(0.0, 180.0);
                      return Positioned(
                        left: 0,
                        right: 0,
                        top: pullDownShift - collapseShift,
                        height: topContentInset + 10 + pullDownShift,
                        child: IgnorePointer(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      heroFogBase.withValues(alpha: 0.05),
                                      heroFogBase.withValues(alpha: 0.11),
                                      heroFogShadow.withValues(alpha: 0.22),
                                      heroFogShadow.withValues(alpha: 0.34),
                                      colors.backgroundBase,
                                    ],
                                    stops: const [
                                      0.0,
                                      0.36,
                                      0.56,
                                      0.74,
                                      0.88,
                                      1.0,
                                    ],
                                  ),
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(0.18, 0.72),
                                    radius: 0.92,
                                    colors: [
                                      heroFogShadow.withValues(alpha: 0.16),
                                      heroFogBase.withValues(alpha: 0.07),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.42, 1.0],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: topContentInset),
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Container(
                              color: colors.backgroundBase,
                              padding: const EdgeInsets.fromLTRB(
                                DetailTokens.screenHorizontalPadding,
                                0,
                                DetailTokens.screenHorizontalPadding,
                                20,
                              ),
                              child: TvSeasonDetailPanel.legacy(
                                title: title,
                                titleFontSize: titleFontSize,
                                token: provider.token,
                                ambientTint: ambientTint,
                                posterUrls: posterUrls,
                                posterWidth: posterWidth,
                                posterCardHeight: posterCardHeight,
                                posterBridgeOverlap: posterBridgeOverlap,
                                panelDropOffset: panelDropOffset,
                                headerBodyTopPadding: headerBodyTopPadding,
                                headerMetaOpacity: _headerMetaOpacity,
                                metaContent: AppTransitions.crossFadeSwitch(
                                  switchKey: 'meta-$_selectedSeasonGuid',
                                  duration: _seasonDataFadeDuration,
                                  child: Column(
                                    key: ValueKey<String>(
                                      'meta-content-$_selectedSeasonGuid',
                                    ),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _seasonNumberWidget(colors, season),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (rating > 0)
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              ).detailRatingScore(
                                                rating.toStringAsFixed(1),
                                              ),
                                              style: const TextStyle(
                                                color: Color(0xFFF2D34B),
                                                fontSize: 17,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (rating > 0 && year.isNotEmpty)
                                            Text(
                                              '  /  ',
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                                fontSize: 17,
                                              ),
                                            ),
                                          if (year.isNotEmpty)
                                            Text(
                                              year,
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                                fontSize: 17,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                playLabel: playLabel,
                                playLabelFontSize: playLabelFontSize,
                                watched: _watched,
                                downloaded: _isCurrentSeasonFullyDownloaded(),
                                descriptionVisible: _descriptionVisible,
                                switchDuration: _seasonDataFadeDuration,
                                overview: overview,
                                hasOverview: hasOverview,
                                episodeSection: _seasonItems.isNotEmpty
                                    ? TvEpisodeBrowserSection(
                                        title: AppLocalizations.of(
                                          context,
                                        ).detailEpisodeTitle,
                                        totalLabel: !_episodeItemsResolved
                                            ? (expectedEpisodeCount > 0
                                                  ? AppLocalizations.of(
                                                      context,
                                                    ).detailEpisodeTotal(
                                                      expectedEpisodeCount,
                                                    )
                                                  : AppLocalizations.of(
                                                      context,
                                                    ).commonLoading)
                                            : episodeTotalLabel,
                                        seasons: _seasonOptionEntries(),
                                        episodes: episodeEntries,
                                        selectedRangeIndex: _episodeRangeIndex,
                                        rangeSize: _episodePageSize,
                                        previewCount: 4,
                                        emptyText: episodeEmptyText,
                                        detailText: episodeDetailText,
                                        token: provider.token,
                                        mode: _episodePickerMode,
                                        onSeasonSelected: _switchSeason,
                                        onRangeSelected: (index) {
                                          setState(
                                            () => _episodeRangeIndex = index,
                                          );
                                        },
                                        onEpisodeSelected:
                                            _openEpisodeDetailByGuid,
                                        onEpisodeLongPress: (episodeGuid) {
                                          unawaited(
                                            _showEpisodeCardActions(
                                              episodeGuid,
                                            ),
                                          );
                                        },
                                        onEpisodeDetailTap: (episodeGuid) =>
                                            _openEpisodeSummaryByGuid(
                                              context,
                                              episodeGuid,
                                            ),
                                        onOpenPicker: () =>
                                            _openEpisodePicker(context),
                                      )
                                    : const SizedBox.shrink(),
                                creditsSection:
                                    (_creditsVisible && creditItems.isNotEmpty)
                                    ? CreditsSection(
                                        title: AppLocalizations.of(
                                          context,
                                        ).detailCastCrewTitle,
                                        items: creditItems,
                                        token: provider.token,
                                        onTap: _openCreditPerson,
                                      )
                                    : null,
                                linkSection:
                                    (_imdbId.trim().isNotEmpty ||
                                        _trimId.trim().isNotEmpty)
                                    ? LinkSection(
                                        imdbId: _imdbId,
                                        tmdbId: _trimId,
                                        onImdbTap: _openImdb,
                                        onTmdbTap: _openTmdb,
                                      )
                                    : null,
                                onPlayTap: _onPlayTap,
                                onDownloadTap: _handleDownloadTap,
                                onWatchedTap: _toggleWatched,
                                onOverviewTap: () {
                                  LongTextOverlayPage.show(
                                    context,
                                    title: title,
                                    sectionTitle: AppLocalizations.of(
                                      context,
                                    ).detailOverviewTitle,
                                    content: overview,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _scrollOffsetNotifier,
                    builder: (context, offset, _) {
                      final collapseT = (offset / collapseRange).clamp(
                        0.0,
                        1.0,
                      );
                      final centerTitleOpacity = ((collapseT - 0.82) / 0.16)
                          .clamp(0.0, 1.0);
                      return DetailFloatingTopBar(
                        onBack: () => unawaited(
                          EmbeddedDetailLauncher.closeHostOrPop(context),
                        ),
                        onMore: () => unawaited(
                          showDetailMoreActionsSheet(
                            context,
                            pageKey: _selectedSeasonGuid.trim().isNotEmpty
                                ? _selectedSeasonGuid
                                : widget.seasonItem.guid,
                            pageTitle: '$title ${_seasonLabel(season)}',
                            suggestedThemeName: context
                                .read<AppThemeProvider>()
                                .nextSavedThemeNameFromBase(
                                  _suggestedThemeNameBase(season),
                                ),
                            clearRuntimeBroadcastToMain: !inPlayerPaneHost,
                          ),
                        ),
                        title: '$title ${_seasonLabel(season)}',
                        titleOpacity: centerTitleOpacity,
                        showBack: true,
                      );
                    },
                  ),
                ],
              );
        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: _isPane
              ? pageBody
              : AppTransitions.crossFadeSwitch(
                  switchKey: 'page-state-${_loading ? 'loading' : 'ready'}',
                  duration: _seasonDataFadeDuration,
                  child: pageBody,
                ),
        );
      },
    );
  }
}
