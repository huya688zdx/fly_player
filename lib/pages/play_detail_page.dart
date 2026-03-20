import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../controllers/play_detail_download_sheet_controller.dart';
import '../controllers/play_detail_item_actions.dart';
import '../controllers/play_detail_sheet_controller.dart';
import '../models/authorized_dir_entry.dart';
import '../models/download_task_record.dart';
import '../models/playback_stream.dart';
import '../models/play_info.dart';
import '../models/person_credit.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import 'long_text_overlay_page.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../services/detail_runtime_cache.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/capability_badge_mapper.dart';
import '../ui/detail_presentation.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_layout_solver.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/media_language_mapper.dart';
import '../utils/media_locale_store.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/player_title_formatter.dart';
import '../utils/play_detail_formatters.dart';
import '../utils/play_detail_track_selector.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_hero_overlay.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/detail_meta_lines.dart';
import '../widgets/detail/detail_selector_row.dart';
import '../widgets/detail/detail_resolution_section.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/file_info_section.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/play_action_bar.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import '../widgets/detail/video_info_section.dart';

class PlayDetailPage extends StatefulWidget {
  final String itemGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;
  final DetailPresentation presentation;

  const PlayDetailPage({
    super.key,
    required this.itemGuid,
    this.heroTag,
    this.initialItemDetail,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<PlayDetailPage> createState() => _PlayDetailPageState();
}

class _PlayDetailPageState extends State<PlayDetailPage>
    with TickerProviderStateMixin {
  static const Duration _headerFadeDuration = Duration(milliseconds: 360);
  static const Duration _actionsPopDuration = Duration(milliseconds: 300);
  static const Duration _descriptionPopDuration = Duration(milliseconds: 320);
  static const Duration _asyncContentFadeDuration = Duration(milliseconds: 220);
  static const Duration _phase2Delay = Duration(milliseconds: 120);
  static const Duration _deferredSectionStartDelay = Duration(
    milliseconds: 160,
  );
  static const Duration _deferredSectionStepDelay = Duration(milliseconds: 140);
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  final PlayDetailDownloadSheetController _downloadSheetController =
      const PlayDetailDownloadSheetController();
  final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
  static const Duration _favoriteTapCooldown = Duration(milliseconds: 900);
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  PlayInfoData? _data;
  late String _currentItemGuid;
  List<PersonCredit> _personCredits = const [];
  List<StreamListOption> _streamOptions = const [];
  StreamTrackData? _streamTrackData;
  bool _loading = true;
  AppException? _error;
  int? _selectedStreamIndex;
  String? _selectedSubtitleGuid;
  String? _selectedAudioGuid;
  String _imdbId = '';
  String _trimId = '';
  bool _liked = false;
  bool _favoriteUpdating = false;
  DateTime _lastFavoriteTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  final DetailTopTip _topTip = DetailTopTip();
  Map<String, dynamic> _localeMap = const <String, dynamic>{};
  Map<int, String> _genresMapZhCn = const <int, String>{};
  Map<String, String> _locateMapZhCn = const <String, String>{};
  List<AuthorizedDirEntry> _authorizedDirs = const <AuthorizedDirEntry>[];
  bool _descriptionVisible = false;
  bool _creditsVisible = false;
  bool _fileInfoVisible = false;
  bool _videoInfoVisible = false;
  bool _linkVisible = false;
  bool _heroAsyncSectionsResolved = false;
  bool _subtitleSelectorExpanded = false;
  bool _audioSelectorExpanded = false;
  bool _deferredSectionLoadStarted = false;
  bool _playerRouteActive = false;
  ImageProvider<Object>? _warmedHeroImageProvider;
  Timer? _entryActionTimer;
  Timer? _deferredSectionTimer;
  late final AnimationController _headerFadeController;
  late final AnimationController _actionsPopController;
  late final AnimationController _descriptionPopController;
  late final Animation<double> _headerTitleOpacity;
  late final Animation<double> _headerMetaOpacity;
  late final Animation<double> _headerSelectorOpacity;
  late final Animation<double> _actionsOpacity;
  late final Animation<double> _actionsScale;
  late final Animation<double> _actionsTranslateY;

  double _backdropHeroHeight(Size screenSize) {
    final isLandscape = screenSize.width > screenSize.height;
    if (isLandscape) {
      return screenSize.height * 0.50;
    }
    final byHeight = screenSize.height * 0.38;
    final byWidth = screenSize.width / 1.36;
    return math.min(byHeight, byWidth).clamp(300.0, 560.0).toDouble();
  }

  bool _isPhonePortrait(Size screenSize) {
    return screenSize.width < screenSize.height &&
        screenSize.shortestSide < 600.0;
  }

  Alignment _backdropImageAlignment(Size screenSize) {
    if (_isPhonePortrait(screenSize)) {
      return const Alignment(0.0, -0.22);
    }
    return Alignment.topCenter;
  }

  double _backdropImageScale(Size screenSize) {
    if (_isPhonePortrait(screenSize)) {
      return 1.05;
    }
    return 1.0;
  }

  double _heroInfoBlockReservedHeight(
    Size screenSize, {
    required bool canPlay,
  }) {
    if (!canPlay) {
      return _isPhonePortrait(screenSize) ? 148.0 : 132.0;
    }
    if (_isPhonePortrait(screenSize)) {
      return 252.0;
    }
    return screenSize.width > screenSize.height ? 188.0 : 208.0;
  }

  Widget _asyncFadeSwitcher(Widget child, {required Object switchKey}) {
    return AnimatedSwitcher(
      duration: _asyncContentFadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey<Object>(switchKey), child: child),
    );
  }

  late final Animation<double> _resolutionOpacity;
  late final Animation<double> _resolutionScale;
  late final Animation<double> _resolutionTranslateY;
  late final Animation<double> _descriptionOpacity;
  late final Animation<double> _descriptionScale;
  late final Animation<double> _descriptionTranslateY;

  @override
  void initState() {
    super.initState();
    _currentItemGuid = widget.itemGuid;
    _headerFadeController = AnimationController(
      vsync: this,
      duration: _headerFadeDuration,
    );
    _actionsPopController = AnimationController(
      vsync: this,
      duration: _actionsPopDuration,
    );
    _descriptionPopController = AnimationController(
      vsync: this,
      duration: _descriptionPopDuration,
    );
    _headerTitleOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.0, 0.45, curve: Curves.linear),
    );
    _headerMetaOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.24, 0.78, curve: Curves.linear),
    );
    _headerSelectorOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.52, 1.0, curve: Curves.linear),
    );
    _actionsOpacity = CurvedAnimation(
      parent: _actionsPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.linear),
    );
    _actionsScale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(_actionsPopController);
    _actionsTranslateY = Tween<double>(
      begin: 10,
      end: 0,
    ).animate(_actionsPopController);
    _resolutionOpacity = CurvedAnimation(
      parent: _actionsPopController,
      curve: const Interval(0.25, 1.0, curve: Curves.linear),
    );
    _resolutionScale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _actionsPopController,
        curve: const Interval(0.25, 1.0, curve: Curves.linear),
      ),
    );
    _resolutionTranslateY = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(
        parent: _actionsPopController,
        curve: const Interval(0.25, 1.0, curve: Curves.linear),
      ),
    );
    final descriptionCurve = CurvedAnimation(
      parent: _descriptionPopController,
      curve: Curves.easeOutCubic,
    );
    _descriptionOpacity = CurvedAnimation(
      parent: _descriptionPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.linear),
    );
    _descriptionScale = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(descriptionCurve);
    _descriptionTranslateY = Tween<double>(
      begin: 10,
      end: 0,
    ).animate(descriptionCurve);
    _scrollController.addListener(_onScroll);
    _downloadTaskService.addListener(_handleDownloadTasksChanged);
    unawaited(_downloadTaskService.initialize());
    _load();
  }

  @override
  void dispose() {
    _topTip.dispose();
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    final warmedProvider = _warmedHeroImageProvider;
    if (warmedProvider != null) {
      unawaited(warmedProvider.evict());
      _warmedHeroImageProvider = null;
    }
    _headerFadeController.dispose();
    _actionsPopController.dispose();
    _descriptionPopController.dispose();
    _scrollController.removeListener(_onScroll);
    _downloadTaskService.removeListener(_handleDownloadTasksChanged);
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffsetNotifier.value).abs() > 0.5) {
      _scrollOffsetNotifier.value = offset;
    }
  }

  void _handleDownloadTasksChanged() {
    if (!mounted) return;
    setState(() {});
  }

  DownloadTaskRecord? _downloadedRecordForCurrentItem() {
    return _downloadTaskService.downloadedRecordForItem(_currentItemGuid);
  }

  StreamFileInfo? _localDownloadedFileInfo(DownloadTaskRecord? record) {
    if (record == null) return null;
    final path = record.filePath.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final stat = file.statSync();
      final modifiedAt = stat.modified.millisecondsSinceEpoch;
      return StreamFileInfo(
        mediaGuid: record.mediaGuid,
        path: path,
        fileName: record.fileName.trim().isEmpty
            ? file.uri.pathSegments.isEmpty
                  ? ''
                  : file.uri.pathSegments.last
            : record.fileName.trim(),
        size: stat.size,
        fileBirthTime: record.createdAtMs > 0 ? record.createdAtMs : modifiedAt,
        createTime: record.createdAtMs > 0 ? record.createdAtMs : modifiedAt,
        updateTime: record.updatedAtMs > 0 ? record.updatedAtMs : modifiedAt,
      );
    } catch (_) {
      return null;
    }
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

  int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _heroPathForItemMap(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString().trim().toLowerCase();
    final backdrops = (item['backdrops'] ?? '').toString().trim();
    final posters = (item['posters'] ?? '').toString().trim();
    final stillPath = (item['still_path'] ?? '').toString().trim();

    if (type == 'episode') {
      if (stillPath.isNotEmpty) return stillPath;
      if (backdrops.isNotEmpty) return backdrops;
      return posters;
    }
    if (backdrops.isNotEmpty) return backdrops;
    if (stillPath.isNotEmpty) return stillPath;
    return posters;
  }

  String _heroPathForPlayItem(PlayItem item) {
    final type = item.type.trim().toLowerCase();
    if (type == 'episode') {
      if (item.stillPath.isNotEmpty) return item.stillPath;
      if (item.backdrops.isNotEmpty) return item.backdrops;
      return item.posters;
    }
    if (item.backdrops.isNotEmpty) return item.backdrops;
    if (item.stillPath.isNotEmpty) return item.stillPath;
    return item.posters;
  }

  String _episodeHeroSubtitle(PlayItem item) {
    final itemType = item.type.trim().toLowerCase();
    if (itemType != 'episode') return '';

    final parts = <String>[];
    final tvTitle = item.tvTitle.trim();
    if (tvTitle.isNotEmpty) {
      parts.add(tvTitle);
    }

    if (item.seasonNumber == 0) {
      parts.add(_t('layout.subheading.season.special', '特别篇'));
    } else if (item.seasonNumber > 0) {
      parts.add(
        _t(
          'layout.subheading.season.number',
          '第 {number} 季',
          params: {'number': item.seasonNumber},
        ),
      );
    } else if (item.parentTitle.trim().isNotEmpty) {
      parts.add(item.parentTitle.trim());
    }

    if (item.episodeNumber > 0) {
      parts.add(
        _t(
          'layout.subheading.episode.number',
          '第 {number} 集',
          params: {'number': item.episodeNumber},
        ),
      );
    }

    return parts.join(' · ');
  }

  String _suggestedThemeNameBase(PlayItem item, String detailTitle) {
    final itemType = item.type.trim().toLowerCase();
    if (itemType == 'episode') {
      final seriesTitle = item.tvTitle.trim().isNotEmpty
          ? item.tvTitle.trim()
          : (item.parentTitle.trim().isNotEmpty
                ? item.parentTitle.trim()
                : detailTitle);
      return buildThemeSaveNameBase(
        title: detailTitle,
        seriesTitle: seriesTitle,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        isEpisode: true,
      );
    }
    return buildThemeSaveNameBase(title: detailTitle);
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

  Future<void> _load() async {
    unawaited(_ensureLocaleMapLoaded());
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _headerFadeController.reset();
    _actionsPopController.reset();
    _actionsPopController.value = 1.0;
    _descriptionPopController.reset();
    setState(() {
      _loading = true;
      _error = null;
      _descriptionVisible = false;
      _creditsVisible = false;
      _fileInfoVisible = false;
      _videoInfoVisible = false;
      _linkVisible = false;
      _deferredSectionLoadStarted = false;
      _heroAsyncSectionsResolved = false;
      _personCredits = const [];
      _streamOptions = const [];
      _streamTrackData = null;
      _selectedStreamIndex = null;
      _selectedSubtitleGuid = null;
      _selectedAudioGuid = null;
      _subtitleSelectorExpanded = false;
      _audioSelectorExpanded = false;
      _genresMapZhCn = const <int, String>{};
      _locateMapZhCn = const <String, String>{};
      _authorizedDirs = const <AuthorizedDirEntry>[];
    });

    try {
      final api = FeiniuApi(context.read<NasProvider>());
      // Phase 1: load only base play info for immediate first paint.
      final info = await _loadPlayInfo(api, _currentItemGuid);
      if (!mounted) return;
      setState(() {
        _currentItemGuid = info.item.guid.trim().isNotEmpty
            ? info.item.guid.trim()
            : _currentItemGuid;
        _data = info;
        _liked = info.item.isFavorite == 1;
        _watched = info.item.isWatched == 1;
        _imdbId = _extractInitialImdbId();
        _trimId = _extractInitialTrimId();
        _loading = false;
      });
      _warmupHeroImage(info);
      _startEntryAnimations();

      // Phase 2: load track-related data while header fade is running.
      unawaited(_loadPhase2(api: api, info: info));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'play detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  String _extractInitialImdbId() {
    final initial = widget.initialItemDetail;
    if (initial == null) return '';
    return PlayDetailDataLoader.extractImdbId(initial);
  }

  String _extractInitialTrimId() {
    final initial = widget.initialItemDetail;
    if (initial == null) return '';
    return PlayDetailDataLoader.extractTrimId(initial);
  }

  void _startEntryAnimations() {
    if (_playerRouteActive) return;
    _headerFadeController.value = 1.0;
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _deferredSectionTimer = Timer(_deferredSectionStartDelay, () {
      if (!mounted || _playerRouteActive) return;
      setState(() => _descriptionVisible = true);
      _descriptionPopController.forward(from: 0);
      unawaited(_loadDeferredSections());
    });
  }

  Future<void> _loadPhase2({
    required FeiniuApi api,
    required PlayInfoData info,
  }) async {
    await Future<void>.delayed(_phase2Delay);
    if (!mounted || _playerRouteActive) return;
    try {
      final trackData = await _loadStreamTrackData(api, _currentItemGuid);
      if (!mounted || _playerRouteActive) return;
      final streams = trackData.options;
      final initialIndex = streams.indexWhere(
        (e) => e.mediaGuid == info.mediaGuid,
      );
      final selectedIndex = initialIndex >= 0 ? initialIndex : null;
      final selectedMediaGuid =
          (selectedIndex != null &&
              selectedIndex >= 0 &&
              selectedIndex < streams.length)
          ? streams[selectedIndex].mediaGuid
          : '';
      final subtitleTracks = trackData.subtitlesForMedia(selectedMediaGuid);
      final audioTracks = trackData.audiosForMedia(selectedMediaGuid);

      setState(() {
        _streamTrackData = trackData;
        _streamOptions = streams;
        _selectedStreamIndex = selectedIndex;
        _selectedSubtitleGuid = PlayDetailTrackSelector.pickInitialSubtitleGuid(
          preferred: info.subtitleGuid,
          tracks: subtitleTracks,
        );
        _selectedAudioGuid = PlayDetailTrackSelector.pickInitialAudioGuid(
          preferred: info.audioGuid,
          tracks: audioTracks,
        );
      });

      final genresMap = await api
          .getTagGenresMap(lan: 'zh-CN')
          .catchError((_) => const <int, String>{});
      if (!mounted || _playerRouteActive) return;
      setState(() => _genresMapZhCn = genresMap);

      final locateMap = await api
          .getTagIso3166Map(lan: 'zh-CN')
          .catchError((_) => const <String, String>{});
      if (!mounted || _playerRouteActive) return;
      setState(() => _locateMapZhCn = locateMap);

      final languageMap = await api
          .getTagIso6392Map(lan: 'zh-CN')
          .catchError((_) => const <String, String>{});
      MediaLanguageMapper.mergeLanguageMap(languageMap);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load play detail locale maps',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      // Keep base UI alive even if track request fails.
    } finally {
      if (mounted && !_playerRouteActive && !_heroAsyncSectionsResolved) {
        setState(() => _heroAsyncSectionsResolved = true);
      }
    }
  }

  Future<void> _loadDeferredSections() async {
    if (_deferredSectionLoadStarted || !mounted || _playerRouteActive) return;
    _deferredSectionLoadStarted = true;
    final api = FeiniuApi(context.read<NasProvider>());

    try {
      final people = await _loadPersonCredits(api, _currentItemGuid)
          .then<List<PersonCredit>>((v) => v)
          .catchError((_) => const <PersonCredit>[]);
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() {
        _personCredits = people;
        _creditsVisible = people.isNotEmpty;
      });
    } catch (_) {}

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    if (_playerRouteActive) {
      _deferredSectionLoadStarted = false;
      return;
    }
    setState(() {
      _fileInfoVisible = true;
      _videoInfoVisible = true;
    });

    try {
      final dirs = await api
          .getAppAuthorizedDirs()
          .then<List<AuthorizedDirEntry>>((value) => value)
          .catchError((_) => const <AuthorizedDirEntry>[]);
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() => _authorizedDirs = dirs);
    } catch (_) {}

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    if (_playerRouteActive) {
      _deferredSectionLoadStarted = false;
      return;
    }
    try {
      final initialDetail = widget.initialItemDetail;
      var imdbId = initialDetail == null
          ? ''
          : PlayDetailDataLoader.extractImdbId(initialDetail);
      var trimId = initialDetail == null
          ? ''
          : PlayDetailDataLoader.extractTrimId(initialDetail);
      if (trimId.isEmpty) {
        trimId = _data?.item.trimId.trim() ?? '';
      }
      if (imdbId.isEmpty && trimId.isEmpty) {
        final detail = await _loadItemDetail(api, _currentItemGuid);
        if (!mounted) return;
        if (_playerRouteActive) {
          _deferredSectionLoadStarted = false;
          return;
        }
        imdbId = PlayDetailDataLoader.extractImdbId(detail);
        trimId = PlayDetailDataLoader.extractTrimId(detail);
      }
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() {
        _imdbId = imdbId;
        _trimId = trimId;
        _linkVisible = _imdbId.trim().isNotEmpty || _trimId.trim().isNotEmpty;
      });
    } catch (_) {}
  }

  void _warmupHeroImage(PlayInfoData info) {
    final provider = context.read<NasProvider>();
    final item = info.item;
    final heroPath = item.backdrops.isNotEmpty
        ? item.backdrops
        : (item.stillPath.isNotEmpty ? item.stillPath : item.posters);
    final urls = ApiUrlHelper.imageCandidates(
      provider.baseUrl,
      heroPath,
      width: 960,
    );
    if (urls.isEmpty) return;
    final media = MediaQuery.of(context);
    final dpr = media.devicePixelRatio.clamp(1.0, 2.0);
    final cacheWidth = (media.size.width * dpr)
        .round()
        .clamp(720, 1280)
        .toInt();
    final imageProvider = ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      NetworkImage(
        urls.first,
        headers: {
          'Authorization': provider.token,
          'Trim-MC-token': provider.token,
        },
      ),
    );
    _warmedHeroImageProvider = imageProvider;
    precacheImage(imageProvider, context).catchError((error, stackTrace) {
      debugPrint(
        '[IMG][PRECACHE][DETAIL] failed url=${urls.first} error=$error',
      );
    });
  }

  Future<PlayInfoData> _loadPlayInfo(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getPlayInfo(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<PlayInfoData>(
      bucket: 'play_info',
      key: itemGuid,
      loader: () => api.getPlayInfo(itemGuid),
    );
  }

  Future<StreamTrackData> _loadStreamTrackData(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getStreamTrackData(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<StreamTrackData>(
      bucket: 'stream_track',
      key: itemGuid,
      loader: () => api.getStreamTrackData(itemGuid),
    );
  }

  Future<List<PersonCredit>> _loadPersonCredits(
    FeiniuApi api,
    String itemGuid,
  ) {
    if (!_useRuntimeCache) {
      return api.getPersonList(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<List<PersonCredit>>(
      bucket: 'person_list',
      key: itemGuid,
      loader: () => api.getPersonList(itemGuid),
    );
  }

  Future<Map<String, dynamic>> _loadItemDetail(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getItemDetail(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<Map<String, dynamic>>(
      bucket: 'item_detail',
      key: itemGuid,
      loader: () => api.getItemDetail(itemGuid),
    );
  }

  StreamListOption? _currentStreamOption() {
    return PlayDetailTrackSelector.currentStreamOption(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
    );
  }

  List<SubtitleTrackOption> _currentSubtitleTracks() {
    return PlayDetailTrackSelector.subtitleTracksForCurrentMedia(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
      trackData: _streamTrackData,
    );
  }

  List<AudioTrackOption> _currentAudioTracks() {
    return PlayDetailTrackSelector.audioTracksForCurrentMedia(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
      trackData: _streamTrackData,
    );
  }

  String _currentAudioTypeForBadges() {
    return PlayDetailTrackSelector.currentAudioTypeForBadges(
      selectedAudioGuid: _selectedAudioGuid,
      audioTracks: _currentAudioTracks(),
      selectedOption: _currentStreamOption(),
    );
  }

  void _syncTrackSelectionForCurrentMedia() {
    final synced = PlayDetailTrackSelector.syncTrackSelectionForCurrentMedia(
      currentSubtitleGuid: _selectedSubtitleGuid,
      currentAudioGuid: _selectedAudioGuid,
      subtitleTracks: _currentSubtitleTracks(),
      audioTracks: _currentAudioTracks(),
    );
    _selectedSubtitleGuid = synced.subtitleGuid;
    _selectedAudioGuid = synced.audioGuid;
  }

  Future<void> _showSubtitleSheet(BuildContext sheetContext) async {
    final tracks = _currentSubtitleTracks();
    if (tracks.isEmpty) return;
    if (mounted) {
      setState(() => _subtitleSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showSubtitleSheet(
      sheetContext,
      subtitleTracks: tracks,
      selectedSubtitleGuid: _selectedSubtitleGuid,
    );
    if (mounted) {
      setState(() => _subtitleSelectorExpanded = false);
    }
    if (!mounted || result == null) return;
    setState(() {
      _selectedSubtitleGuid = result;
    });
  }

  Future<void> _showAudioSheet(BuildContext sheetContext) async {
    final tracks = _currentAudioTracks();
    if (tracks.length <= 1) return;
    if (mounted) {
      setState(() => _audioSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showAudioSheet(
      sheetContext,
      audioTracks: tracks,
      selectedAudioGuid: _selectedAudioGuid,
    );
    if (mounted) {
      setState(() => _audioSelectorExpanded = false);
    }
    if (!mounted || result == null) return;
    setState(() {
      _selectedAudioGuid = result;
    });
  }

  Future<void> _showMediaInfoDetail(BuildContext sheetContext) async {
    await PlayDetailSheetController.showMediaInfoDetail(
      sheetContext,
      streamOptions: _streamOptions,
      streamTrackData: _streamTrackData,
      selectedStreamIndex: _selectedStreamIndex,
      onVariantChanged: (index) {
        if (!mounted || index == _selectedStreamIndex) return;
        setState(() {
          _selectedStreamIndex = index;
          _syncTrackSelectionForCurrentMedia();
        });
      },
    );
  }

  Future<void> _openPlayer() async {
    final data = _data;
    if (data == null) return;

    final localRecord = _downloadedRecordForCurrentItem();
    if (localRecord != null) {
      await _openLocalPlayer(localRecord);
      return;
    }

    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final selectedOption = _currentStreamOption();
    final mediaGuid = selectedOption?.mediaGuid ?? data.mediaGuid;
    if (mediaGuid.trim().isEmpty) {
      _showTopTip(
        _t(
          'player.playbackError.playError',
          '播放异常: {error}',
          params: {'error': 'missing media guid'},
        ),
        context.appColors.danger,
      );
      return;
    }

    final streamUrl = api.getStreamUrl(mediaGuid);
    if (streamUrl.trim().isEmpty) {
      _showTopTip(
        _t(
          'player.playbackError.playError',
          '播放异常: {error}',
          params: {'error': 'missing stream url'},
        ),
        context.appColors.danger,
      );
      return;
    }

    late final PlaybackStreamData playbackStream;
    try {
      playbackStream = await api.getPlaybackStream(mediaGuid);
    } catch (error) {
      _showTopTip(
        _t(
          'player.playbackError.playError',
          '获取播放流失败: {error}',
          params: {'error': '$error'},
        ),
        context.appColors.danger,
      );
      return;
    }

    final effectiveDuration =
        (selectedOption != null && selectedOption.duration > 0)
        ? selectedOption.duration
        : data.item.duration;
    final sourceTs = data.ts > 0 ? data.ts : data.item.watchedTs;
    final effectiveTs = sourceTs.clamp(0, effectiveDuration);
    final playbackCompleted =
        effectiveDuration > 0 &&
        ((effectiveDuration - effectiveTs) <= 0 ||
            _watched ||
            data.item.isWatched == 1);
    final item = data.item;
    final title = formatPlayerTitleFromPlayItem(
      item,
      fallbackTitle: item.displayTitle,
    );

    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _selectedAudioGuid?.trim().isNotEmpty == true
          ? _selectedAudioGuid
          : data.audioGuid,
      audioTracks: playbackStream.audioStreams,
    );
    final playerSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: _currentSubtitleTracks(),
    );
    final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
      selectedSubtitleGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : data.subtitleGuid,
      subtitleTracks: playerSubtitleTracks,
    );
    final playbackVideoGuid =
        playbackStream.videoStream?.guid.trim().isNotEmpty == true
        ? playbackStream.videoStream!.guid.trim()
        : data.videoGuid.trim();
    final playbackResolution =
        playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
        ? playbackStream.videoStream!.resolutionType.trim()
        : selectedOption?.resolutionType ?? '';
    final playbackBitrate = playbackStream.videoStream?.bps ?? 0;
    final preferExternalSubtitle =
        selectedSubtitle != null &&
        (selectedSubtitle.isExternal == 1 ||
            selectedSubtitle.extraFile == 1 ||
            selectedSubtitle.guid.startsWith('local:'));
    final embeddedSubtitleTrackIndex =
        selectedSubtitle == null || preferExternalSubtitle
        ? null
        : (() {
            final embeddedTracks = playerSubtitleTracks
                .where((track) {
                  if (track.guid.trim().isEmpty) return false;
                  if (track.guid.startsWith('local:')) return false;
                  return track.isExternal != 1 && track.extraFile != 1;
                })
                .toList(growable: false);
            final ordinal = embeddedTracks.indexWhere(
              (track) => track.guid == selectedSubtitle.guid,
            );
            if (ordinal < 0) return null;
            return ordinal + 1;
          })();
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      _streamTrackData,
    );
    final selectedQuality = PlayerSourceController.preferredInitialQuality(
      mergedQualities,
    );
    final initialPlaybackVideoGuid =
        selectedQuality?.videoGuid.trim().isNotEmpty == true
        ? selectedQuality!.videoGuid.trim()
        : playbackVideoGuid;
    final initialPlaybackResolution =
        selectedQuality?.isDirectLink == true &&
            selectedQuality!.resolution.trim().isNotEmpty
        ? selectedQuality.resolution.trim()
        : playbackResolution;
    final initialPlaybackBitrate = selectedQuality?.isDirectLink == true
        ? selectedQuality!.bitrate
        : playbackBitrate;
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: streamUrl,
          mediaGuid: mediaGuid,
          videoGuid: initialPlaybackVideoGuid,
          playbackStream: playbackStream,
          quality: selectedQuality,
          selectedAudio: selectedAudio,
          startPosition: Duration(seconds: effectiveTs),
        );
    final playableSource = initialPlayback.playableSource;
    final resolvedStartPosition =
        !playableSource.reliableSeek && effectiveTs > 0
        ? Duration.zero
        : (playbackCompleted ? Duration.zero : Duration(seconds: effectiveTs));

    final source = MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: _currentItemGuid,
      seasonGuid: (widget.initialItemDetail?['parent_guid'] ?? '').toString(),
      posterPath: resolvePlayerArtworkPathForPlayItem(item),
      mediaGuid: initialPlayback.mediaGuid,
      mediaType: item.type,
      ancestorName: item.ancestorName,
      videoGuid: initialPlayback.videoGuid,
      directLinkQualityIndex: selectedQuality?.isDirectLink == true
          ? selectedQuality!.directLinkQualityIndex
          : null,
      videoWidth: playbackStream.videoStream?.width ?? 0,
      videoHeight: playbackStream.videoStream?.height ?? 0,
      proxySessionId: playableSource.proxySessionId,
      playLink: initialPlayback.playLink,
      url: playableSource.url,
      headers: playableSource.headers,
      title: title,
      seriesTitle: item.tvTitle.trim().isNotEmpty ? item.tvTitle.trim() : title,
      seasonNumber: item.seasonNumber,
      tmdbId: item.trimId,
      episodeNumber: item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      audioTrackGuid: selectedAudio?.guid ?? data.audioGuid,
      subtitleTrackGuid: selectedSubtitle?.guid ?? data.subtitleGuid,
      resolution: initialPlaybackResolution,
      bitrate: initialPlaybackBitrate,
      durationSeconds: effectiveDuration,
      videoCodecName: playbackStream.videoStream?.codecName ?? '',
      videoProfile: playbackStream.videoStream?.profile ?? '',
      colorSpace: playbackStream.videoStream?.colorSpace ?? '',
      colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
      colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
      bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
      preferExternalSubtitle: preferExternalSubtitle,
      forceNativeProxy: playableSource.forceNativeProxy,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      playbackMode: initialPlayback.playbackMode,
      playbackSpeed: 1.0,
      audioTracks: playbackStream.audioStreams,
      subtitleTracks: playerSubtitleTracks,
      qualities: mergedQualities,
    );

    await _launchPlayer(title: title, source: source, initialPlayInfo: data);
  }

  Future<void> _openLocalPlayer(DownloadTaskRecord record) async {
    final data = _data;
    if (data == null) return;
    if (record.filePath.trim().isEmpty) {
      _showTopTip('本地视频文件无效', context.appColors.warning);
      return;
    }

    final selectedOption = _currentStreamOption();
    final effectiveDuration =
        (selectedOption != null && selectedOption.duration > 0)
        ? selectedOption.duration
        : data.item.duration;
    final sourceTs = data.ts > 0 ? data.ts : data.item.watchedTs;
    final effectiveTs = sourceTs.clamp(0, effectiveDuration);
    final playbackCompleted =
        effectiveDuration > 0 &&
        ((effectiveDuration - effectiveTs) <= 0 ||
            _watched ||
            data.item.isWatched == 1);
    final startPosition = playbackCompleted
        ? Duration.zero
        : Duration(seconds: effectiveTs);
    final item = data.item;
    final title = formatPlayerTitleFromPlayItem(
      item,
      fallbackTitle: item.displayTitle,
    );
    final localVideo =
        _streamTrackData?.videoForMedia(record.mediaGuid) ??
        _streamTrackData?.videoForMedia(selectedOption?.mediaGuid ?? '') ??
        _streamTrackData?.videoForMedia(data.mediaGuid);
    final resolvedMediaGuid = record.mediaGuid.trim().isEmpty
        ? data.mediaGuid
        : record.mediaGuid;
    final localAudioTracks = _currentAudioTracks();
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _selectedAudioGuid?.trim().isNotEmpty == true
          ? _selectedAudioGuid
          : data.audioGuid,
      audioTracks: localAudioTracks,
    );
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      const <PlaybackQualityOption>[],
      _streamTrackData,
    );
    final source = MpvMediaSource.localFile(
      filePath: record.filePath,
      itemGuid: _currentItemGuid,
      seasonGuid: (widget.initialItemDetail?['parent_guid'] ?? '').toString(),
      posterPath: resolvePlayerArtworkPathForPlayItem(item),
      mediaGuid: resolvedMediaGuid,
      mediaType: item.type,
      ancestorName: item.ancestorName,
      videoGuid: localVideo?.guid.trim().isNotEmpty == true
          ? localVideo!.guid.trim()
          : data.videoGuid,
      title: title,
      seriesTitle: item.tvTitle.trim().isNotEmpty ? item.tvTitle.trim() : title,
      seasonNumber: item.seasonNumber,
      tmdbId: item.trimId,
      episodeNumber: item.episodeNumber,
      startPosition: startPosition,
      audioTrackGuid: selectedAudio?.guid ?? data.audioGuid,
      subtitleTrackGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : data.subtitleGuid,
      resolution: record.resolution,
      bitrate: 0,
      durationSeconds: effectiveDuration,
      videoWidth: localVideo?.width ?? 0,
      videoHeight: localVideo?.height ?? 0,
      videoCodecName: localVideo?.codecName ?? '',
      videoProfile: localVideo?.profile ?? '',
      colorSpace: localVideo?.colorSpace ?? '',
      colorTransfer: localVideo?.colorTransfer ?? '',
      colorPrimaries: localVideo?.colorPrimaries ?? '',
      bitDepth: localVideo?.bitDepth ?? 0,
      audioTracks: localAudioTracks,
      subtitleTracks: const <SubtitleTrackOption>[],
      qualities: mergedQualities,
      playbackSpeed: 1.0,
    );

    await _launchPlayer(title: title, source: source, initialPlayInfo: data);
  }

  Future<void> _launchPlayer({
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
  }) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    _playerRouteActive = true;
    _deferredSectionTimer?.cancel();
    final embeddedResult = await EmbeddedDetailLauncher.openFullscreenPlayer(
      context: context,
      title: title,
      source: source,
    );
    final result = embeddedResult.handled
        ? embeddedResult.data
        : await navigator.push(
            AppTransitions.playerRoute(
              MpvPlayerPage(
                title: title,
                source: source,
                initialPlayInfo: initialPlayInfo,
              ),
            ),
          );
    if (!mounted) return;
    _playerRouteActive = false;
    _restoreContentVisibilityAfterPlayerExit();
    if (!_deferredSectionLoadStarted &&
        (_personCredits.isEmpty ||
            _authorizedDirs.isEmpty ||
            (!_linkVisible && (_imdbId.isEmpty || _trimId.isEmpty)))) {
      unawaited(_loadDeferredSections());
    }
    final playerReturn = result is PlayDetailPlayerReturnData ? result : null;
    final nextItemGuid = switch (playerReturn) {
      PlayDetailPlayerReturnData(itemGuid: final String itemGuid)
          when itemGuid.trim().isNotEmpty =>
        itemGuid.trim(),
      _ => _currentItemGuid,
    };
    if (nextItemGuid != _currentItemGuid) {
      setState(() {
        _currentItemGuid = nextItemGuid;
      });
    }
    if (playerReturn?.refreshData != null) {
      _applyRefreshedDetailData(
        playerReturn!.refreshData!,
        currentTsSeconds: playerReturn.currentTsSeconds,
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshAfterPlayerExit());
    });
  }

  Future<void> _refreshAfterPlayerExit() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      _restoreContentVisibilityAfterPlayerExit();
      await _refreshAfterItemStateChange();
    } catch (error) {
      debugPrint('[PLAY_DETAIL] refresh after player failed error=$error');
    }
  }

  Future<void> _refreshAfterItemStateChange() async {
    final api = FeiniuApi(context.read<NasProvider>());
    final currentMediaGuid = _currentStreamOption()?.mediaGuid ?? '';
    final refreshed = await PlayDetailDataLoader(api)
        .refreshAfterItemStateChange(
          itemGuid: _currentItemGuid,
          currentMediaGuid: currentMediaGuid,
          currentSubtitleGuid: _selectedSubtitleGuid,
          currentAudioGuid: _selectedAudioGuid,
        );

    _applyRefreshedDetailData(refreshed);
  }

  void _applyRefreshedDetailData(
    PlayDetailRefreshData refreshed, {
    int? currentTsSeconds,
  }) {
    if (!mounted) return;
    setState(() {
      _currentItemGuid = refreshed.info.item.guid.trim().isNotEmpty
          ? refreshed.info.item.guid.trim()
          : _currentItemGuid;
      _data = currentTsSeconds == null
          ? refreshed.info
          : refreshed.info.copyWith(ts: currentTsSeconds);
      _streamTrackData = refreshed.streamTrackData;
      _streamOptions = refreshed.streamOptions;
      _selectedStreamIndex = refreshed.selectedStreamIndex;
      _selectedSubtitleGuid = refreshed.selectedSubtitleGuid;
      _selectedAudioGuid = refreshed.selectedAudioGuid;
      _heroAsyncSectionsResolved = true;
      _liked = refreshed.info.item.isFavorite == 1;
      _watched = refreshed.info.item.isWatched == 1;
      _imdbId = refreshed.imdbId;
      _trimId = refreshed.trimId;
    });
    _restoreContentVisibilityAfterPlayerExit();
  }

  void _restoreContentVisibilityAfterPlayerExit() {
    if (!mounted) return;
    if (!_descriptionVisible) {
      setState(() => _descriptionVisible = true);
    }
    if (_descriptionPopController.status != AnimationStatus.forward &&
        _descriptionPopController.value < 1.0) {
      _descriptionPopController.forward();
    }
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

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _toggleFavorite() async {
    final now = DateTime.now();
    if (_favoriteUpdating ||
        now.difference(_lastFavoriteTapAt) < _favoriteTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后再试'),
        context.appColors.warning,
      );
      return;
    }
    _lastFavoriteTapAt = now;
    _favoriteUpdating = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await PlayDetailItemActions(
        api,
        localeMap: _localeMap,
      ).toggleFavorite(itemGuid: _currentItemGuid, currentLiked: _liked);
      if (!mounted) return;
      setState(() => _liked = result.state);
      _showTopTip(
        result.message,
        result.state ? context.appColors.success : context.appColors.textMuted,
      );
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle favorite',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      _showTopTip(
        _liked
            ? _t('common.actions.favorite.unfavoriteFailed', '取消收藏失败')
            : _t('common.actions.favorite.favoriteFailed', '收藏失败'),
        context.appColors.danger,
      );
    } finally {
      _favoriteUpdating = false;
    }
  }

  Future<void> _toggleWatched() async {
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后再试'),
        context.appColors.warning,
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await PlayDetailItemActions(
        api,
        localeMap: _localeMap,
      ).toggleWatched(itemGuid: _currentItemGuid, currentWatched: _watched);
      if (!mounted) return;
      setState(() => _watched = result.state);
      _showTopTip(
        result.message,
        result.state ? context.appColors.success : context.appColors.textMuted,
      );
      if (result.needRefresh) {
        await _refreshAfterItemStateChange();
      }
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle watched',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      _showTopTip(
        _watched
            ? _t('common.actions.watched.markedAsUnwatchedFailed', '标记为未观看失败')
            : _t('common.actions.watched.markedAsWatchedFailed', '标记为已观看失败'),
        context.appColors.danger,
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  void _handleDownloadTap() {
    final item = _data?.item;
    final itemGuid = _currentItemGuid.trim();
    if (item == null || itemGuid.isEmpty) {
      _showTopTip(
        _t('common.actions.download.unavailable', '暂无可下载资源'),
        context.appColors.warning,
      );
      return;
    }
    final subtitleTracks = _currentSubtitleTracks();
    final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
      selectedSubtitleGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : _data?.subtitleGuid,
      subtitleTracks: subtitleTracks,
    );
    unawaited(
      _downloadSheetController.show(
        context,
        itemGuid: itemGuid,
        item: item,
        selectedSubtitleTrack: selectedSubtitle,
        parentGuid:
            (widget.initialItemDetail?['parent_guid'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
            ? (widget.initialItemDetail?['parent_guid'] ?? '').toString().trim()
            : (_data?.parentGuid.trim() ?? ''),
        previewUrls: ApiUrlHelper.imageCandidates(
          context.read<NasProvider>().baseUrl,
          _heroPathForPlayItem(item),
          width: 720,
        ),
        localeMap: _localeMap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<AppThemeProvider>();
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    var dynamicThemeKey = _currentItemGuid.trim().isNotEmpty
        ? _currentItemGuid
        : widget.itemGuid;
    var dynamicThemeImageUrl = '';
    if (_loading) {
      final initial = widget.initialItemDetail;
      if (initial != null) {
        final rawItem = initial['item'];
        final item = rawItem is Map<String, dynamic> ? rawItem : initial;
        final urls = ApiUrlHelper.imageCandidates(
          nasProvider.baseUrl,
          _heroPathForItemMap(item),
          width: 360,
        );
        if (urls.isNotEmpty) {
          dynamicThemeImageUrl = urls.first;
        }
      }
    } else if (_data != null) {
      final urls = ApiUrlHelper.imageCandidates(
        nasProvider.baseUrl,
        _heroPathForPlayItem(_data!.item),
        width: 360,
      );
      if (urls.isNotEmpty) {
        dynamicThemeImageUrl = urls.first;
      }
    }

    final dynamicThemeIntensity = themeProvider.dynamicThemeIntensity;
    return DynamicPageThemeScope(
      pageKey: dynamicThemeKey,
      imageUrl: dynamicThemeImageUrl,
      token: nasProvider.token,
      enabled: themeProvider.dynamicThemeEnabled,
      syncGlobalTheme: dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
        inPlayerPaneHost: inPlayerPaneHost,
        isPane: _isPane,
      ),
      intensity: dynamicThemeIntensity,
      builder: (context, ambientTint) {
        final colors = context.appColors;
        if (_loading) {
          final initial = widget.initialItemDetail;
          if (initial == null) {
            return Scaffold(
              backgroundColor: colors.backgroundBase,
              body: const SizedBox.shrink(),
            );
          }
          final provider = context.read<NasProvider>();
          final media = MediaQuery.of(context);
          final backdropRequestWidth =
              (_isPane
                      ? media.size.width * media.devicePixelRatio * 1.2
                      : 1200.0)
                  .clamp(720.0, 1200.0)
                  .round();
          final logoRequestWidth =
              (_isPane ? media.size.width * media.devicePixelRatio : 1200.0)
                  .clamp(480.0, 1200.0)
                  .round();
          final rawItem = initial['item'];
          final item = rawItem is Map<String, dynamic> ? rawItem : initial;
          final heroPath = _heroPathForItemMap(item);
          final heroUrls = ApiUrlHelper.imageCandidates(
            provider.baseUrl,
            heroPath,
            width: backdropRequestWidth,
          );
          final title = formatPlayerTitle(
            seriesTitle: (item['tv_title'] ?? '').toString().trim().isNotEmpty
                ? (item['tv_title'] ?? '').toString()
                : (item['display_title'] ?? item['title'] ?? '').toString(),
            episodeTitle: (item['title'] ?? '').toString(),
            seasonNumber: _asInt(item['season_number']),
            episodeNumber: _asInt(item['episode_number']),
            fallbackTitle: (item['display_title'] ?? item['title'] ?? '')
                .toString(),
          );
          final logoUrls = ApiUrlHelper.imageCandidates(
            provider.baseUrl,
            (item['logos'] ?? '').toString(),
            width: logoRequestWidth,
          );
          final episodeHeroSubtitle =
              ((item['type'] ?? '').toString().trim().toLowerCase() ==
                  'episode')
              ? [
                  if ((item['tv_title'] ?? '').toString().trim().isNotEmpty)
                    (item['tv_title'] ?? '').toString().trim(),
                  if (_asInt(item['season_number']) == 0)
                    _t('layout.subheading.season.special', '特别篇')
                  else if (_asInt(item['season_number']) > 0)
                    _t(
                      'layout.subheading.season.number',
                      '第 {number} 季',
                      params: {'number': _asInt(item['season_number'])},
                    ),
                  if (_asInt(item['episode_number']) > 0)
                    _t(
                      'layout.subheading.episode.number',
                      '第 {number} 集',
                      params: {'number': _asInt(item['episode_number'])},
                    ),
                ].join(' · ')
              : '';
          final posterHeight = _backdropHeroHeight(media.size);
          final imageAlignment = _backdropImageAlignment(media.size);
          final imageScale = _backdropImageScale(media.size);
          final layout = DetailLayoutSolver.solve(
            screenSize: media.size,
            safePadding: media.padding,
            posterHeight: posterHeight,
          );
          return Scaffold(
            backgroundColor: DetailTokens.pageBackground,
            body: Stack(
              fit: StackFit.expand,
              children: [
                ImmersiveDetailBackground(
                  urls: heroUrls,
                  token: provider.token,
                  scrollOffset: 0,
                  posterHeight: posterHeight,
                  imageScale: imageScale,
                  imageFit: BoxFit.cover,
                  imageAlignment: imageAlignment,
                  parallaxFactor: 1.0,
                  overlayOpacity: 0.62,
                  ambientTintOverride: ambientTint,
                ),
                CustomScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: DetailHeroOverlay(
                        height: layout.infoStart,
                        title: title,
                        subtitle: episodeHeroSubtitle,
                        titleFontSize: 28,
                        bottomInset: 20,
                        useSoftGradient: true,
                        titleChild:
                            logoUrls.isNotEmpty &&
                                (item['type'] ?? '')
                                        .toString()
                                        .trim()
                                        .toLowerCase() !=
                                    'episode'
                            ? DetailHeroLogoTitle(
                                urls: logoUrls,
                                token: provider.token,
                                fallbackTitle: title,
                                maxHeight: 112,
                                maxWidth:
                                    media.size.width -
                                    (DetailTokens.screenHorizontalPadding * 2),
                                fallbackFontSize: 28,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        if (_error != null || _data == null) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            appBar: _isPane
                ? null
                : AppBar(backgroundColor: colors.backgroundBase),
            body: AppErrorState(
              error: _error!,
              localeMap: _localeMap,
              onRetry: _load,
            ),
          );
        }

        final provider = context.read<NasProvider>();
        final data = _data!;
        final item = data.item;
        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final backdropRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio * 1.2 : 1200.0)
                .clamp(720.0, 1200.0)
                .round();
        final logoRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio : 1200.0)
                .clamp(480.0, 1200.0)
                .round();

        final posterHeight = _backdropHeroHeight(screenSize);
        final imageAlignment = _backdropImageAlignment(screenSize);
        final imageScale = _backdropImageScale(screenSize);
        final layout = DetailLayoutSolver.solve(
          screenSize: screenSize,
          safePadding: media.padding,
          posterHeight: posterHeight,
        );

        final collapseRange =
            (layout.infoStart - media.padding.top - kToolbarHeight).clamp(
              1.0,
              layout.infoStart,
            );
        final heroPath = _heroPathForPlayItem(item);
        final heroUrls = ApiUrlHelper.imageCandidates(
          provider.baseUrl,
          heroPath,
          width: backdropRequestWidth,
        );

        final selectedOption =
            (_selectedStreamIndex != null &&
                _selectedStreamIndex! >= 0 &&
                _selectedStreamIndex! < _streamOptions.length)
            ? _streamOptions[_selectedStreamIndex!]
            : null;

        final effectiveDuration =
            (selectedOption != null && selectedOption.duration > 0)
            ? selectedOption.duration
            : item.duration;
        final sourceTs = data.ts > 0 ? data.ts : item.watchedTs;
        final effectiveTs = sourceTs.clamp(0, effectiveDuration);
        final remainSeconds = (effectiveDuration - effectiveTs).clamp(
          0,
          effectiveDuration,
        );
        final playbackCompleted =
            effectiveDuration > 0 &&
            (remainSeconds <= 0 || _watched || item.isWatched == 1);
        final showProgress = effectiveTs > 0 && remainSeconds > 0;

        final resolvedPlayText = playbackCompleted
            ? _t('player.play.replay', '重新播放')
            : effectiveTs > 0
            ? _t('player.play.continuePlay', '继续播放')
            : _t('player.play.play', '播放');
        final metaLineA = PlayDetailFormatters.metaLineA(
          item,
          genreMap: _genresMapZhCn,
          locateMap: _locateMapZhCn,
        );
        final metaLineB = [
          PlayDetailFormatters.formatDuration(effectiveDuration),
          item.ancestorName,
        ].where((e) => e.isNotEmpty).join(' / ');

        final resolutionOptions = _streamOptions
            .map((e) => e.label)
            .where((e) => e.trim().isNotEmpty)
            .toList();
        final showResolutionSelector = resolutionOptions.length > 1;

        final itemType = item.type.trim().toLowerCase();
        final detailTitle =
            (itemType == 'episode' && item.title.trim().isNotEmpty)
            ? item.title.trim()
            : item.displayTitle;
        final heroInfoBlockReservedHeight = _heroInfoBlockReservedHeight(
          screenSize,
          canPlay: item.canPlay == 1,
        );
        final reserveHeroInfoBlockHeight = !_heroAsyncSectionsResolved;
        final logoUrls = ApiUrlHelper.imageCandidates(
          provider.baseUrl,
          item.logos,
          width: logoRequestWidth,
        );
        final episodeHeroSubtitle = _episodeHeroSubtitle(item);

        String? selectedKey;
        if (_selectedStreamIndex != null &&
            _selectedStreamIndex! >= 0 &&
            _selectedStreamIndex! < resolutionOptions.length) {
          selectedKey =
              '${_selectedStreamIndex!}:${resolutionOptions[_selectedStreamIndex!]}';
        }

        final capabilityLabels = () {
          if (selectedOption != null) {
            return <String>[
                  selectedOption.resolutionType,
                  selectedOption.colorRangeType,
                  _currentAudioTypeForBadges(),
                ]
                .map(CapabilityBadgeMapper.normalize)
                .where((e) => e.isNotEmpty)
                .toList();
          }
          return <String>[
                ...item.resolutions,
                ...item.colorRanges,
                ...item.audioTypes,
              ]
              .map(CapabilityBadgeMapper.normalize)
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
        }();
        final subtitleTracks = _currentSubtitleTracks();
        final audioTracks = _currentAudioTracks();
        final showSubtitleArrow = subtitleTracks.isNotEmpty;
        final showAudioArrow = audioTracks.length > 1;
        final subtitleLabel =
            PlayDetailTrackSelector.subtitleLabelForCurrentMedia(
              selectedSubtitleGuid: _selectedSubtitleGuid,
              subtitleTracks: subtitleTracks,
              localeMap: _localeMap,
            );
        final audioLabel = PlayDetailTrackSelector.audioLabelForCurrentMedia(
          selectedAudioGuid: _selectedAudioGuid,
          audioTracks: audioTracks,
          selectedOption: selectedOption,
          localeMap: _localeMap,
        );

        final currentMediaGuid = _currentStreamOption()?.mediaGuid ?? '';
        final localDownloadRecord = _downloadedRecordForCurrentItem();
        final localDownloadedFile = _localDownloadedFileInfo(
          localDownloadRecord,
        );
        final currentFile =
            localDownloadedFile ??
            ((currentMediaGuid.isNotEmpty)
                ? _streamTrackData?.fileForMedia(currentMediaGuid)
                : null);
        final currentVideo = (currentMediaGuid.isNotEmpty)
            ? _streamTrackData?.videoForMedia(currentMediaGuid)
            : null;
        final currentAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
          selectedAudioGuid: _selectedAudioGuid,
          audioTracks: audioTracks,
        );
        final currentSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
          selectedSubtitleGuid: _selectedSubtitleGuid,
          subtitleTracks: subtitleTracks,
        );
        final creditItems = _personCredits
            .map(
              (e) => CreditPersonItem(
                personGuid: e.personGuid,
                name: e.displayName,
                subtitle: e.displaySubTitle,
                imageUrls: ApiUrlHelper.personImageCandidates(
                  provider.baseUrl,
                  e.profilePath,
                  width: 320,
                ),
              ),
            )
            .toList();

        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffsetNotifier,
                builder: (context, offset, _) {
                  return ImmersiveDetailBackground(
                    urls: heroUrls,
                    token: provider.token,
                    scrollOffset: offset,
                    posterHeight: posterHeight,
                    imageScale: imageScale,
                    imageFit: BoxFit.cover,
                    imageAlignment: imageAlignment,
                    parallaxFactor: 1.0,
                    overlayOpacity: 0.62,
                    ambientTintOverride: ambientTint,
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
                    child: FadeTransition(
                      opacity: _headerTitleOpacity,
                      child: DetailHeroOverlay(
                        height: layout.infoStart,
                        title: detailTitle,
                        subtitle: episodeHeroSubtitle,
                        titleFontSize: itemType == 'episode' ? 28 : null,
                        bottomInset: itemType == 'episode' ? 20 : 36,
                        useSoftGradient: true,
                        titleChild: itemType != 'episode' && logoUrls.isNotEmpty
                            ? DetailHeroLogoTitle(
                                urls: logoUrls,
                                token: provider.token,
                                fallbackTitle: detailTitle,
                                maxHeight: 112,
                                maxWidth:
                                    screenSize.width -
                                    (DetailTokens.screenHorizontalPadding * 2),
                              )
                            : null,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      color: colors.backgroundBase,
                      padding: const EdgeInsets.fromLTRB(
                        DetailTokens.screenHorizontalPadding,
                        8,
                        DetailTokens.screenHorizontalPadding,
                        18,
                      ),
                      child: AnimatedSize(
                        duration: _asyncContentFadeDuration,
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: reserveHeroInfoBlockHeight
                                ? heroInfoBlockReservedHeight
                                : 0.0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FadeTransition(
                                opacity: _headerMetaOpacity,
                                child: _asyncFadeSwitcher(
                                  DetailMetaLines(
                                    metaLineA: metaLineA,
                                    metaLineB: metaLineB,
                                  ),
                                  switchKey: 'meta:$metaLineA|$metaLineB',
                                ),
                              ),
                              const SizedBox(height: 8),
                              FadeTransition(
                                opacity: _headerSelectorOpacity,
                                child: _asyncFadeSwitcher(
                                  DetailSelectorRow(
                                    subtitleLabel: subtitleLabel,
                                    audioLabel: audioLabel,
                                    capabilityLabels: capabilityLabels,
                                    showSubtitleArrow: showSubtitleArrow,
                                    showAudioArrow: showAudioArrow,
                                    subtitleExpanded: _subtitleSelectorExpanded,
                                    audioExpanded: _audioSelectorExpanded,
                                    onSubtitleTap: showSubtitleArrow
                                        ? () => _showSubtitleSheet(context)
                                        : null,
                                    onAudioTap: showAudioArrow
                                        ? () => _showAudioSheet(context)
                                        : null,
                                  ),
                                  switchKey:
                                      'selector:$subtitleLabel|$audioLabel|${capabilityLabels.join(",")}',
                                ),
                              ),
                              const SizedBox(height: 16),
                              AnimatedBuilder(
                                animation: _actionsPopController,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: _actionsOpacity.value,
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        _actionsTranslateY.value,
                                      ),
                                      child: Transform.scale(
                                        scale: _actionsScale.value,
                                        alignment: Alignment.topCenter,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: AnimatedBuilder(
                                  animation: _downloadTaskService,
                                  builder: (context, _) {
                                    final downloaded =
                                        _downloadedRecordForCurrentItem() !=
                                        null;
                                    return PlayActionBar(
                                      progress: PlayDetailFormatters.progress(
                                        effectiveDuration,
                                        effectiveTs,
                                      ),
                                      remainText:
                                          PlayDetailFormatters.remainText(
                                            effectiveDuration,
                                            effectiveTs,
                                          ),
                                      showProgress: showProgress,
                                      primaryText: resolvedPlayText,
                                      primaryEnabled: item.canPlay == 1,
                                      liked: _liked,
                                      watched: _watched,
                                      downloaded: downloaded,
                                      onPrimaryTap: _openPlayer,
                                      onLikeTap: _toggleFavorite,
                                      onDownloadTap: _handleDownloadTap,
                                      onWatchedTap: _toggleWatched,
                                    );
                                  },
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _actionsPopController,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: showResolutionSelector
                                        ? _resolutionOpacity.value
                                        : 1.0,
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        showResolutionSelector
                                            ? _resolutionTranslateY.value
                                            : 0,
                                      ),
                                      child: Transform.scale(
                                        scale: showResolutionSelector
                                            ? _resolutionScale.value
                                            : 1.0,
                                        alignment: Alignment.topCenter,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: _asyncFadeSwitcher(
                                  showResolutionSelector
                                      ? DetailResolutionSection(
                                          options: resolutionOptions,
                                          selected: selectedKey,
                                          onSelected: (index) {
                                            setState(() {
                                              _selectedStreamIndex = index;
                                              _syncTrackSelectionForCurrentMedia();
                                            });
                                          },
                                        )
                                      : const SizedBox.shrink(),
                                  switchKey:
                                      'resolution:${showResolutionSelector ? resolutionOptions.join(",") : "empty"}|$selectedKey',
                                ),
                              ),
                              if (item.playError.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _t(
                                    'player.playbackError.playError',
                                    '播放异常: {error}',
                                    params: {'error': item.playError},
                                  ),
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: _descriptionPopController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _descriptionVisible
                              ? _descriptionOpacity.value
                              : 0,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              _descriptionVisible
                                  ? _descriptionTranslateY.value
                                  : 10,
                            ),
                            child: Transform.scale(
                              scale: _descriptionVisible
                                  ? _descriptionScale.value
                                  : 0.97,
                              alignment: Alignment.topCenter,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        color: colors.backgroundBase,
                        padding: EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          media.padding.bottom + 18,
                        ),
                        child: DetailDescriptionSection(
                          text: item.overview,
                          onMoreTap: () {
                            LongTextOverlayPage.show(
                              context,
                              title: detailTitle,
                              sectionTitle: _t(
                                'layout.details.overview.overview',
                                '简介',
                              ),
                              content: item.overview,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_creditsVisible && creditItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        color: colors.backgroundBase,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          20,
                        ),
                        child: CreditsSection(
                          title: _t('layout.details.castAndCrew.title', '演职人员'),
                          items: creditItems,
                          token: provider.token,
                          onTap: _openCreditPerson,
                        ),
                      ),
                    ),
                  if (_fileInfoVisible)
                    SliverToBoxAdapter(
                      child: Container(
                        color: colors.backgroundBase,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          20,
                        ),
                        child: FileInfoSection(
                          file: currentFile,
                          authorizedDirs: _authorizedDirs,
                          title: _t('layout.details.fileInfo.title', '文件信息'),
                          locationLabel: _t(
                            'layout.details.fileInfo.location',
                            '文件位置',
                          ),
                          sizeLabel: _t('layout.details.fileInfo.size', '文件大小'),
                          createdAtLabel: _t(
                            'layout.details.fileInfo.createdAt',
                            '文件创建日期',
                          ),
                          addedAtLabel: _t(
                            'layout.details.fileInfo.addedAt',
                            '添加日期',
                          ),
                          toggleToFriendlyLabel: _t(
                            'layout.details.fileInfo.convert',
                            '转换',
                          ),
                          toggleToRawLabel: '/vol',
                        ),
                      ),
                    ),
                  if (_videoInfoVisible)
                    SliverToBoxAdapter(
                      child: Container(
                        color: colors.backgroundBase,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          20,
                        ),
                        child: VideoInfoSection(
                          video: currentVideo,
                          audio: currentAudio,
                          subtitle: currentSubtitle,
                          onViewAll: () => _showMediaInfoDetail(context),
                        ),
                      ),
                    ),
                  if (_linkVisible &&
                      (_imdbId.trim().isNotEmpty || _trimId.trim().isNotEmpty))
                    SliverToBoxAdapter(
                      child: Container(
                        color: colors.backgroundBase,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          24,
                        ),
                        child: LinkSection(
                          imdbId: _imdbId,
                          tmdbId: _trimId,
                          onImdbTap: _openImdb,
                          onTmdbTap: _openTmdb,
                        ),
                      ),
                    ),
                ],
              ),
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffsetNotifier,
                builder: (context, offset, _) {
                  final collapseT = (offset / collapseRange).clamp(0.0, 1.0);
                  final centerTitleOpacity = ((collapseT - 0.84) / 0.12).clamp(
                    0.0,
                    1.0,
                  );
                  return DetailFloatingTopBar(
                    onBack: () => unawaited(
                      EmbeddedDetailLauncher.closeHostOrPop(context),
                    ),
                    onMore: () => unawaited(
                      showDetailMoreActionsSheet(
                        context,
                        pageKey: dynamicThemeKey,
                        pageTitle: detailTitle,
                        suggestedThemeName: context
                            .read<AppThemeProvider>()
                            .nextSavedThemeNameFromBase(
                              _suggestedThemeNameBase(item, detailTitle),
                            ),
                        clearRuntimeBroadcastToMain: !inPlayerPaneHost,
                      ),
                    ),
                    title: detailTitle,
                    titleOpacity: centerTitleOpacity,
                    showBack: !_isPane,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
