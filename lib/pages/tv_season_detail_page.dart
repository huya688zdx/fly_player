import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../controllers/tv_season_download_sheet_controller.dart';
import '../controllers/tv_season_playback_launcher.dart';
import '../models/media_library_item.dart';
import '../models/person_credit.dart';
import '../models/tv_episode_browser_models.dart';
import '../models/tv_episode_picker_mode.dart';
import '../models/play_info.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../services/detail_runtime_cache.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_presentation.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/media_locale_store.dart';
import '../utils/tv_hero_adaptive.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_header.dart';
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
  static const Duration _headerFadeDuration = Duration(milliseconds: 360);
  static const Duration _seasonDataFadeDuration = Duration(milliseconds: 240);
  static const Duration _deferredStartDelay = Duration(milliseconds: 160);
  static const Duration _deferredCreditsDelay = Duration(milliseconds: 140);

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  final DetailTopTip _topTip = DetailTopTip();
  final TvSeasonDownloadSheetController _downloadSheetController =
      const TvSeasonDownloadSheetController();
  final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
  Map<String, dynamic> _localeMap = const <String, dynamic>{};

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  bool _loading = true;
  AppException? _error;

  String _selectedSeasonGuid = '';
  String _selectedEpisodeGuid = '';
  List<MediaLibraryItem> _seasonItems = const [];
  List<MediaLibraryItem> _episodeItems = const [];
  List<PersonCredit> _personCredits = const [];
  Map<String, dynamic> _detail = const {};
  PlayInfoData? _playInfo;
  String _imdbId = '';
  String _trimId = '';

  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seasonSwitching = false;
  bool _playPreparing = false;
  int _episodeRangeIndex = 0;
  int _seasonLoadSeq = 0;

  bool _descriptionVisible = false;
  bool _creditsVisible = false;
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
    super.dispose();
  }

  void _handleDownloadTasksChanged() {
    if (!mounted) return;
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

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      _localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _ensureLocaleMapLoaded() async {
    if (_localeMap.isNotEmpty) return;
    final provider = context.read<NasProvider>();
    final localeMap = await MediaLocaleStore.load(provider);
    if (!mounted || localeMap.isEmpty) return;
    setState(() {
      _localeMap = localeMap;
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
      return _t(
        'layout.subheading.season.number',
        '第 {number} 季',
        params: {'number': season.seasonNumber},
      );
    }
    final title = season.title.trim();
    return title.isNotEmpty
        ? title
        : _t('layout.subheading.season.default', '季信息');
  }

  String _playLabel() {
    final episodeNo = _playInfo?.item.episodeNumber ?? 1;
    if (episodeNo > 0) {
      return _t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episodeNo},
      );
    }
    return _t('player.play.play', '播放');
  }

  String _suggestedThemeNameBase(MediaLibraryItem season) {
    final currentEpisode = _playInfo?.item.episodeNumber ?? 0;
    final seasonNumber = season.seasonNumber;
    if (currentEpisode > 0) {
      return buildThemeSaveNameBase(
        title: widget.seriesTitle,
        seriesTitle: widget.seriesTitle,
        seasonNumber: seasonNumber,
        episodeNumber: currentEpisode,
        isEpisode: true,
      );
    }
    return buildThemeSaveNameBase(
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
          : '$episodeNo.${_t('layout.subheading.episode.number', '第 {number} 集', params: {'number': episodeNo})}';
    }
    final fallback = cleanTitle.isNotEmpty
        ? cleanTitle
        : _t(
            'layout.subheading.episode.number',
            '第 {number} 集',
            params: {'number': index + 1},
          );
    return '${_t('layout.subheading.episode.unknown', '未知集数')}.$fallback';
  }

  String _durationText(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h小时$m分钟$s秒';
    if (m > 0) return '$m分钟$s秒';
    return '$s秒';
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
        text != _t('layout.details.overview.empty', '暂无简介') &&
        text != _t('layout.details.episode.empty', '暂无剧集信息');
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

  (String, Color, bool) _episodeStatus(MediaLibraryItem episode) {
    if (episode.watched == 1) {
      return ('已观看', context.appColors.textSecondary, false);
    }
    final duration = episode.duration;
    final watchedTs = episode.ts > 0 ? episode.ts : episode.watchedTs;
    if (duration > 0 && watchedTs > 0) {
      final percent = (watchedTs / duration * 100).clamp(0, 100).round();
      return ('$percent%', context.appColors.accent, false);
    }
    return ('', context.appColors.textSecondary, false);
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
        statusColor: status.$2,
        imageUrls: _imageCandidates(episode.poster, width: 720),
        resolutions: episode.resolutions,
        selected: episode.guid == (selectedGuid ?? _selectedEpisodeGuid),
        playing: status.$3,
        completed: episode.watched == 1,
        progress: _episodeProgress(episode),
      );
    }, growable: false);
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
      entries: _episodeCardEntries(episodes, selectedGuid: selectedGuid),
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
      } catch (_) {
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
          return await api.getPersonList(itemGuid);
        }
        return await DetailRuntimeCache.instance.getOrLoad<List<PersonCredit>>(
          bucket: 'person_list',
          key: itemGuid,
          loader: () => api.getPersonList(itemGuid),
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
      _episodeItems = const <MediaLibraryItem>[];
      _selectedEpisodeGuid = '';
      _episodeRangeIndex = 0;
      if (showLoading) {
        _personCredits = const [];
        _creditsVisible = false;
      }
      _descriptionVisible = !showLoading;
      _loading = false;
      _error = null;
    });
    _resetScrollToTop();
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
    return Row(
      children: [
        Text(
          '第',
          style: TextStyle(
            color: metaPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        AppTransitions.crossFadeSwitch(
          switchKey: 'season-no-$seasonNo',
          duration: _seasonDataFadeDuration,
          child: Text(
            '$seasonNo',
            key: ValueKey<int>(seasonNo),
            style: TextStyle(
              color: metaPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '季',
          style: TextStyle(
            color: metaPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
      _showTopTip(
        _t('layout.globalError.clickToRetry', '设置保存失败，请稍后重试'),
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
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          _t('layout.details.castAndCrew.imdb', '暂无 IMDB 链接'),
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          _t('layout.details.castAndCrew.imdbOpenFailed', '无法打开 IMDB 链接'),
          context.appColors.danger,
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip('暂无 TMDB 链接', context.appColors.warning);
      case ImdbLaunchResult.failed:
        _showTopTip('无法打开 TMDB 链接', context.appColors.danger);
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

  Future<void> _loadSeasonData(
    String requestedGuid, {
    required bool showLoading,
  }) async {
    unawaited(_ensureLocaleMapLoaded());
    _deferredLoadTimer?.cancel();
    if (showLoading) _resetEntryAnimations();
    final seq = ++_seasonLoadSeq;

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _descriptionVisible = false;
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

      Map<String, dynamic> detail;
      try {
        detail = await _loadItemDetail(api, target);
      } catch (error) {
        final detailError = AppException.from(
          error,
          action: 'tv season detail item',
          fallbackKind: AppExceptionKind.transient,
        );
        if (!detailError.isNoData) {
          rethrow;
        }
        detail = _fallbackSeasonDetail(fallbackSeason);
      }
      final playInfo = await _loadPlayInfoOrNull(api, target);
      final episodes = await _loadEpisodesForSeason(
        target,
        forceRefresh: showLoading,
      );

      if (!mounted || seq != _seasonLoadSeq) return;
      final selectedEpisodeGuid = _preferredEpisodeGuid(episodes);
      setState(() {
        _seasonItems = seasons;
        _selectedSeasonGuid = target;
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
        if (showLoading) {
          _personCredits = const [];
          _creditsVisible = false;
        }
        _descriptionVisible = !showLoading;
        _loading = false;
        _error = null;
      });
      _resetScrollToTop();
      if (showLoading) _startEntryAnimations();
      _startDeferredLoad(seq: seq, seasonGuid: target);
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
      setState(() => _descriptionVisible = true);
      unawaited(_loadDeferredSections(seq: seq, seasonGuid: seasonGuid));
    });
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
    } catch (_) {
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
    }
  }

  Future<void> _switchSeason(String seasonGuid) async {
    if (_selectedSeasonGuid == seasonGuid || _seasonSwitching) return;
    _resetScrollToTop();
    setState(() {
      _seasonSwitching = true;
      _selectedSeasonGuid = seasonGuid;
      _detail = const <String, dynamic>{};
      _playInfo = null;
      _imdbId = '';
      _error = null;
      _episodeItems = const [];
      _selectedEpisodeGuid = '';
      _personCredits = const [];
      _episodeRangeIndex = 0;
      _creditsVisible = false;
      _descriptionVisible = false;
    });
    try {
      await _loadSeasonData(seasonGuid, showLoading: false);
    } finally {
      if (mounted) {
        _resetScrollToTop();
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
    try {
      final result = await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: episodeGuid,
        seriesTitle: widget.seriesTitle,
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
    } catch (_) {
      _showTopTip(
        _t('player.play.playInfoFailed', '获取播放信息失败'),
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

  Future<void> _toggleWatched() async {
    final season = _currentSeason();
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后重试'),
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
            ? _t('common.actions.watched.markedAsWatched', '已标记为已观看')
            : _t('common.actions.watched.markedAsUnwatched', '已标记为未观看'),
        watched ? const Color(0xFF19A35B) : const Color(0xFF3B4A5E),
      );
    } catch (_) {
      _showTopTip(
        _watched
            ? _t('common.actions.watched.markedAsUnwatchedFailed', '取消已观看失败')
            : _t('common.actions.watched.markedAsWatchedFailed', '标记已观看失败'),
        context.appColors.danger,
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  // ignore: unused_element
  void _onDownloadTap() {
    _showTopTip(
      _t('common.actions.download.placeholder', '下载接口已预留'),
      const Color(0xFF3B4A5E),
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
    } catch (_) {}
  }

  Future<void> _openEpisodeDetail(MediaLibraryItem episode) async {
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await _loadItemDetail(
        FeiniuApi(context.read<NasProvider>()),
        episode.guid,
      ).timeout(const Duration(milliseconds: 240));
    } catch (_) {}
    if (!mounted) return;
    await AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: episode.guid,
        initialItemDetail: initialDetail,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
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
      sectionTitle: _t('layout.details.overview.overview', '简介'),
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
    await const MediaItemActionSheetController().show(
      context,
      item: episode,
      title: MediaItemActionSheetController.episodeTitle(
        widget.seriesTitle,
        episode,
      ),
      localeMap: _localeMap,
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
      title: _t('layout.details.episode.title', '选集'),
      seasons: _seasonOptionEntries(),
      initialSeasonGuid: _selectedSeasonGuid,
      initialEpisodeGuid: _selectedEpisodeGuid,
      initialMode: _episodePickerMode,
      rangeSize: _episodePageSize,
      emptyText: _t('layout.details.episode.empty', '暂无剧集信息'),
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
    final themeProvider = context.watch<AppThemeProvider>();
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    final dynamicBackdropUrls = widget.backdropPath.trim().isEmpty
        ? const <String>[]
        : ApiUrlHelper.imageCandidates(
            nasProvider.baseUrl,
            widget.backdropPath,
            width: 360,
          );
    final dynamicThemeKey = widget.parentGuid.trim().isNotEmpty
        ? 'tv-season-series:${widget.parentGuid.trim()}'
        : (widget.backdropPath.trim().isNotEmpty
              ? 'tv-season-backdrop:${widget.backdropPath.trim()}'
              : (_selectedSeasonGuid.trim().isNotEmpty
                    ? _selectedSeasonGuid
                    : widget.seasonItem.guid));

    final dynamicThemeIntensity = themeProvider.dynamicThemeIntensity;
    return DynamicPageThemeScope(
      pageKey: dynamicThemeKey,
      imageUrl: dynamicBackdropUrls.isNotEmpty ? dynamicBackdropUrls.first : '',
      token: nasProvider.token,
      enabled: themeProvider.dynamicThemeEnabled,
      syncGlobalTheme: dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
        inPlayerPaneHost: inPlayerPaneHost,
        isPane: _isPane,
      ),
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
        final posterHeight = math
            .min(screenSize.height * posterHeightRatio, screenSize.width / 1.55)
            .clamp(260.0, screenSize.height * 0.42)
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
        final backdropRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio * 1.2 : 1200.0)
                .clamp(720.0, 1200.0)
                .round();

        final backdropUrls = _imageCandidates(
          widget.backdropPath,
          width: backdropRequestWidth,
        );
        final posterUrls = _imageCandidates(season.poster, width: 560);
        final episodeEntries = _episodeCardEntries(_episodeItems);
        final episodeEmptyText = _t('layout.details.episode.empty', '暂无剧集信息');
        final episodeDetailText = _t(
          'layout.details.castAndCrew.showMore',
          '详情',
        );
        final episodeTotalLabel = _t(
          'layout.details.episode.total',
          '共 {count} 集',
          params: {'count': _episodeItems.length},
        );

        final creditItems = _personCredits
            .map(
              (p) => CreditPersonItem(
                personGuid: p.personGuid,
                name: p.displayName,
                subtitle: p.displaySubTitle,
                imageUrls: _imageCandidates(p.profilePath, width: 280),
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

        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: AppTransitions.crossFadeSwitch(
            switchKey: 'page-state-${_loading ? 'loading' : 'ready'}',
            duration: _seasonDataFadeDuration,
            child: _loading
                ? const SizedBox.expand()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: _scrollOffsetNotifier,
                        builder: (context, offset, _) {
                          return ImmersiveDetailBackground(
                            urls: backdropUrls,
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
                            useMonetTint: false,
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
                                const SizedBox(height: 10),
                                Container(
                                  color: colors.backgroundBase,
                                  padding: const EdgeInsets.fromLTRB(
                                    DetailTokens.screenHorizontalPadding,
                                    0,
                                    DetailTokens.screenHorizontalPadding,
                                    24,
                                  ),
                                  child: TvSeasonDetailPanel(
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
                                                  _t(
                                                    'layout.rating.score',
                                                    '{score} 分',
                                                    params: {
                                                      'score': rating
                                                          .toStringAsFixed(1),
                                                    },
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
                                    downloaded:
                                        _isCurrentSeasonFullyDownloaded(),
                                    descriptionVisible: _descriptionVisible,
                                    switchDuration: _seasonDataFadeDuration,
                                    overview: overview,
                                    hasOverview: hasOverview,
                                    episodeSection: _seasonItems.isNotEmpty
                                        ? TvEpisodeBrowserSection(
                                            title: _t(
                                              'layout.details.episode.title',
                                              '选集',
                                            ),
                                            totalLabel: episodeTotalLabel,
                                            seasons: _seasonOptionEntries(),
                                            episodes: episodeEntries,
                                            selectedRangeIndex:
                                                _episodeRangeIndex,
                                            rangeSize: _episodePageSize,
                                            previewCount: 4,
                                            emptyText: episodeEmptyText,
                                            detailText: episodeDetailText,
                                            token: provider.token,
                                            mode: _episodePickerMode,
                                            onSeasonSelected: _switchSeason,
                                            onRangeSelected: (index) {
                                              setState(
                                                () =>
                                                    _episodeRangeIndex = index,
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
                                        (_creditsVisible &&
                                            creditItems.isNotEmpty)
                                        ? CreditsSection(
                                            title: _t(
                                              'layout.details.castAndCrew.title',
                                              '演职人员',
                                            ),
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
                                        sectionTitle: _t(
                                          'layout.details.overview.overview',
                                          '简介',
                                        ),
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
                            showBack: !_isPane,
                          );
                        },
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
