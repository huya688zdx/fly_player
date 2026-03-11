import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../controllers/play_detail_item_actions.dart';
import '../controllers/play_detail_sheet_controller.dart';
import '../models/authorized_dir_entry.dart';
import '../models/playback_stream.dart';
import '../models/play_info.dart';
import '../models/person_credit.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import 'long_text_overlay_page.dart';
import '../player/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../player/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../ui/capability_badge_mapper.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_layout_solver.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/media_language_mapper.dart';
import '../utils/media_locale_store.dart';
import '../utils/play_detail_formatters.dart';
import '../utils/play_detail_track_selector.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_hero_overlay.dart';
import '../widgets/detail/detail_meta_lines.dart';
import '../widgets/detail/detail_selector_row.dart';
import '../widgets/detail/detail_resolution_section.dart';
import '../widgets/detail/file_info_section.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/play_action_bar.dart';
import '../widgets/detail/video_info_section.dart';
import '../screens/person_detail_screen.dart';

class PlayDetailPage extends StatefulWidget {
  final String itemGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;

  const PlayDetailPage({
    super.key,
    required this.itemGuid,
    this.heroTag,
    this.initialItemDetail,
  });

  @override
  State<PlayDetailPage> createState() => _PlayDetailPageState();
}

class _PlayDetailPageState extends State<PlayDetailPage>
    with TickerProviderStateMixin {
  static const Duration _headerFadeDuration = Duration(milliseconds: 360);
  static const Duration _actionsPopDuration = Duration(milliseconds: 300);
  static const Duration _descriptionPopDuration = Duration(milliseconds: 320);
  static const Duration _phase2Delay = Duration(milliseconds: 120);
  static const Duration _deferredSectionStartDelay = Duration(
    milliseconds: 160,
  );
  static const Duration _deferredSectionStepDelay = Duration(milliseconds: 140);
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  static const Duration _favoriteTapCooldown = Duration(milliseconds: 900);
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);

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
  bool _subtitleSelectorExpanded = false;
  bool _audioSelectorExpanded = false;
  bool _deferredSectionLoadStarted = false;
  bool _playerRouteActive = false;
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
    _load();
  }

  @override
  void dispose() {
    _topTip.dispose();
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _headerFadeController.dispose();
    _actionsPopController.dispose();
    _descriptionPopController.dispose();
    _scrollController.removeListener(_onScroll);
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
      if (posters.isNotEmpty) return posters;
      if (stillPath.isNotEmpty) return stillPath;
      return backdrops;
    }
    if (backdrops.isNotEmpty) return backdrops;
    if (stillPath.isNotEmpty) return stillPath;
    return posters;
  }

  String _heroPathForPlayItem(PlayItem item) {
    final type = item.type.trim().toLowerCase();
    if (type == 'episode') {
      if (item.posters.isNotEmpty) return item.posters;
      if (item.stillPath.isNotEmpty) return item.stillPath;
      return item.backdrops;
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
      final info = await api.getPlayInfo(_currentItemGuid);
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
    _headerFadeController.forward(from: 0);
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _deferredSectionTimer = Timer(
      _headerFadeDuration + _actionsPopDuration + _deferredSectionStartDelay,
      () {
        if (!mounted || _playerRouteActive) return;
        setState(() => _descriptionVisible = true);
        _descriptionPopController.forward(from: 0);
        unawaited(_loadDeferredSections());
      },
    );
  }

  Future<void> _loadPhase2({
    required FeiniuApi api,
    required PlayInfoData info,
  }) async {
    await Future<void>.delayed(_phase2Delay);
    if (!mounted || _playerRouteActive) return;
    try {
      final results = await Future.wait<dynamic>([
        api.getStreamTrackData(_currentItemGuid),
        api
            .getTagGenresMap(lan: 'zh-CN')
            .catchError((_) => const <int, String>{}),
        api
            .getTagIso3166Map(lan: 'zh-CN')
            .catchError((_) => const <String, String>{}),
        api
            .getTagIso6392Map(lan: 'zh-CN')
            .catchError((_) => const <String, String>{}),
      ]);
      if (!mounted || _playerRouteActive) return;
      final trackData = results[0] as StreamTrackData;
      final genresMap = results[1] as Map<int, String>;
      final locateMap = results[2] as Map<String, String>;
      final languageMap = results[3] as Map<String, String>;
      MediaLanguageMapper.mergeLanguageMap(languageMap);
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
        _genresMapZhCn = genresMap;
        _locateMapZhCn = locateMap;
      });
    } catch (_) {
      // Keep base UI alive even if track request fails.
    }
  }

  Future<void> _loadDeferredSections() async {
    if (_deferredSectionLoadStarted || !mounted || _playerRouteActive) return;
    _deferredSectionLoadStarted = true;
    final api = FeiniuApi(context.read<NasProvider>());

    try {
      final people = await api
          .getPersonList(_currentItemGuid)
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
      final detail = await api.getItemDetail(_currentItemGuid);
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      final imdbId = PlayDetailDataLoader.extractImdbId(detail);
      setState(() {
        _imdbId = imdbId;
        _trimId = PlayDetailDataLoader.extractTrimId(detail);
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
      width: 1200,
    );
    if (urls.isEmpty) return;
    precacheImage(
      NetworkImage(
        urls.first,
        headers: {
          'Authorization': provider.token,
          'Trim-MC-token': provider.token,
        },
      ),
      context,
    ).catchError((error, stackTrace) {
      debugPrint(
        '[IMG][PRECACHE][DETAIL] failed url=${urls.first} error=$error',
      );
    });
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

  Future<void> _showSubtitleSheet() async {
    final tracks = _currentSubtitleTracks();
    if (tracks.isEmpty) return;
    if (mounted) {
      setState(() => _subtitleSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showSubtitleSheet(
      context,
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

  Future<void> _showAudioSheet() async {
    final tracks = _currentAudioTracks();
    if (tracks.length <= 1) return;
    if (mounted) {
      setState(() => _audioSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showAudioSheet(
      context,
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

  Future<void> _showMediaInfoDetail() async {
    await PlayDetailSheetController.showMediaInfoDetail(
      context,
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

    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final selectedOption = _currentStreamOption();
    final mediaGuid = selectedOption?.mediaGuid ?? data.mediaGuid;
    if (mediaGuid.trim().isEmpty) {
      _showTopTip(
        _t(
          'player.playbackError.playError',
          '鎾斁寮傚父: {error}',
          params: {'error': 'missing media guid'},
        ),
        const Color(0xFFD64545),
      );
      return;
    }

    final streamUrl = api.getStreamUrl(mediaGuid);
    if (streamUrl.trim().isEmpty) {
      _showTopTip(
        _t(
          'player.playbackError.playError',
          '鎾斁寮傚父: {error}',
          params: {'error': 'missing stream url'},
        ),
        const Color(0xFFD64545),
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
          '閹绢厽鏂佸鍌氱埗: {error}',
          params: {'error': '$error'},
        ),
        const Color(0xFFD64545),
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
    final title =
        (item.type.trim().toLowerCase() == 'episode' &&
            item.title.trim().isNotEmpty)
        ? item.title.trim()
        : item.displayTitle;

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
    final preferExternalSubtitle = selectedSubtitle?.isExternal == 1;
    PlaybackQualityOption? selectedQuality;
    for (final quality in playbackStream.qualities) {
      if (quality.mediaGuid == mediaGuid &&
          (quality.videoGuid.isEmpty ||
              quality.videoGuid == playbackVideoGuid)) {
        selectedQuality = quality;
        break;
      }
    }
    selectedQuality ??= playbackStream.qualities
        .cast<PlaybackQualityOption?>()
        .firstWhere(
          (quality) =>
              quality != null &&
              quality.mediaGuid == mediaGuid &&
              quality.resolution.trim().isNotEmpty &&
              quality.resolution.trim() == playbackResolution,
          orElse: () => null,
        );
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: streamUrl,
          mediaGuid: mediaGuid,
          videoGuid: playbackVideoGuid,
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
      itemGuid: _currentItemGuid,
      seasonGuid: (widget.initialItemDetail?['parent_guid'] ?? '').toString(),
      mediaGuid: initialPlayback.mediaGuid,
      videoGuid: initialPlayback.videoGuid,
      videoWidth: playbackStream.videoStream?.width ?? 0,
      videoHeight: playbackStream.videoStream?.height ?? 0,
      proxySessionId: playableSource.proxySessionId,
      playLink: initialPlayback.playLink,
      url: playableSource.url,
      headers: playableSource.headers,
      title: title,
      episodeNumber: item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: preferExternalSubtitle
          ? null
          : selectedSubtitle?.index,
      audioTrackGuid: selectedAudio?.guid ?? data.audioGuid,
      subtitleTrackGuid: selectedSubtitle?.guid ?? data.subtitleGuid,
      resolution: playbackResolution,
      bitrate: playbackBitrate,
      durationSeconds: effectiveDuration,
      videoCodecName: playbackStream.videoStream?.codecName ?? '',
      videoProfile: playbackStream.videoStream?.profile ?? '',
      colorSpace: playbackStream.videoStream?.colorSpace ?? '',
      colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
      colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
      bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
      preferExternalSubtitle: preferExternalSubtitle,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      serverPlaybackManaged: initialPlayback.serverPlaybackManaged,
      playbackSpeed: 1.0,
      audioTracks: playbackStream.audioStreams,
      subtitleTracks: playerSubtitleTracks,
      qualities: playbackStream.qualities,
    );

    if (!mounted) return;
    _playerRouteActive = true;
    _deferredSectionTimer?.cancel();
    final result = await Navigator.of(context).push(
      AppTransitions.playerRoute(
        MpvPlayerPage(title: title, source: source),
      ),
    );
    if (!mounted) return;
    _playerRouteActive = false;
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
      _liked = refreshed.info.item.isFavorite == 1;
      _watched = refreshed.info.item.isWatched == 1;
      _imdbId = refreshed.imdbId;
      _trimId = refreshed.trimId;
    });
  }

  Future<void> _openImdb() async {
    final result = await ImdbLauncher.openExternal(_imdbId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          _t('layout.details.castAndCrew.imdb', '暂无 IMDB 链接'),
          const Color(0xFFB8860B),
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          _t('layout.details.castAndCrew.imdbOpenFailed', '无法打开 IMDB 链接'),
          const Color(0xFFD64545),
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip('暂无 TMDB 链接', const Color(0xFFB8860B));
      case ImdbLaunchResult.failed:
        _showTopTip('无法打开 TMDB 链接', const Color(0xFFD64545));
    }
  }

  void _openCreditPerson(CreditPersonItem person) {
    final guid = person.personGuid.trim();
    if (guid.isEmpty) return;
    Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        PersonDetailScreen(personGuid: guid, initialName: person.name),
      ),
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
        const Color(0xFFB8860B),
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
        result.state ? const Color(0xFF19A35B) : const Color(0xFF3B4A5E),
      );
    } catch (_) {
      _showTopTip(
        _liked
            ? _t('common.actions.favorite.unfavoriteFailed', '取消收藏失败')
            : _t('common.actions.favorite.favoriteFailed', '收藏失败'),
        const Color(0xFFD64545),
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
        const Color(0xFFB8860B),
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
        result.state ? const Color(0xFF19A35B) : const Color(0xFF3B4A5E),
      );
      if (result.needRefresh) {
        await _refreshAfterItemStateChange();
      }
    } catch (_) {
      _showTopTip(
        _watched
            ? _t('common.actions.watched.markedAsUnwatchedFailed', '标记为未观看失败')
            : _t('common.actions.watched.markedAsWatchedFailed', '标记为已观看失败'),
        const Color(0xFFD64545),
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final initial = widget.initialItemDetail;
      if (initial == null) {
        return const Scaffold(
          backgroundColor: DetailTokens.pageBackground,
          body: SizedBox.shrink(),
        );
      }
      final provider = context.read<NasProvider>();
      final rawItem = initial['item'];
      final item = rawItem is Map<String, dynamic> ? rawItem : initial;
      final heroPath = _heroPathForItemMap(item);
      final heroUrls = ApiUrlHelper.imageCandidates(
        provider.baseUrl,
        heroPath,
        width: 1200,
      );
      final title = ((item['type'] ?? '').toString().toLowerCase() == 'episode')
          ? ((item['title'] ?? '').toString())
          : (((item['tv_title'] ?? '').toString().trim().isNotEmpty)
                ? (item['tv_title'] ?? '').toString()
                : (item['title'] ?? '').toString());
      final episodeHeroSubtitle =
          ((item['type'] ?? '').toString().trim().toLowerCase() == 'episode')
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
      final media = MediaQuery.of(context);
      final posterHeight = media.size.height * 0.50;
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
              parallaxFactor: 1.0,
              overlayOpacity: 0.62,
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
        backgroundColor: DetailTokens.pageBackground,
        appBar: AppBar(backgroundColor: DetailTokens.pageBackground),
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

    final posterHeight = screenSize.height * 0.50;
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
      width: 1200,
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
    final detailTitle = (itemType == 'episode' && item.title.trim().isNotEmpty)
        ? item.title.trim()
        : item.displayTitle;
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
    final subtitleLabel = PlayDetailTrackSelector.subtitleLabelForCurrentMedia(
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
    final currentFile = (currentMediaGuid.isNotEmpty)
        ? _streamTrackData?.fileForMedia(currentMediaGuid)
        : null;
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
      backgroundColor: DetailTokens.pageBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _scrollOffsetNotifier,
            builder: (context, offset, _) {
              final useHero =
                  widget.heroTag != null &&
                  widget.heroTag!.isNotEmpty &&
                  itemType != 'episode';
              final background = ImmersiveDetailBackground(
                urls: heroUrls,
                token: provider.token,
                scrollOffset: offset,
                posterHeight: posterHeight,
                parallaxFactor: 1.0,
                overlayOpacity: 0.62,
              );
              if (!useHero) {
                return background;
              }
              return Hero(tag: widget.heroTag!, child: background);
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
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: DetailTokens.pageBackground,
                  padding: const EdgeInsets.fromLTRB(
                    DetailTokens.screenHorizontalPadding,
                    8,
                    DetailTokens.screenHorizontalPadding,
                    18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeTransition(
                        opacity: _headerMetaOpacity,
                        child: DetailMetaLines(
                          metaLineA: metaLineA,
                          metaLineB: metaLineB,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeTransition(
                        opacity: _headerSelectorOpacity,
                        child: DetailSelectorRow(
                          subtitleLabel: subtitleLabel,
                          audioLabel: audioLabel,
                          capabilityLabels: capabilityLabels,
                          showSubtitleArrow: showSubtitleArrow,
                          showAudioArrow: showAudioArrow,
                          subtitleExpanded: _subtitleSelectorExpanded,
                          audioExpanded: _audioSelectorExpanded,
                          onSubtitleTap: showSubtitleArrow
                              ? _showSubtitleSheet
                              : null,
                          onAudioTap: showAudioArrow ? _showAudioSheet : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: _actionsPopController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _actionsOpacity.value,
                            child: Transform.translate(
                              offset: Offset(0, _actionsTranslateY.value),
                              child: Transform.scale(
                                scale: _actionsScale.value,
                                alignment: Alignment.topCenter,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: PlayActionBar(
                          progress: PlayDetailFormatters.progress(
                            effectiveDuration,
                            effectiveTs,
                          ),
                          remainText: PlayDetailFormatters.remainText(
                            effectiveDuration,
                            effectiveTs,
                          ),
                          showProgress: showProgress,
                          primaryText: resolvedPlayText,
                          primaryEnabled: item.canPlay == 1,
                          liked: _liked,
                          watched: _watched,
                          onPrimaryTap: _openPlayer,
                          onLikeTap: _toggleFavorite,
                          onWatchedTap: _toggleWatched,
                        ),
                      ),
                      if (showResolutionSelector)
                        AnimatedBuilder(
                          animation: _actionsPopController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _resolutionOpacity.value,
                              child: Transform.translate(
                                offset: Offset(0, _resolutionTranslateY.value),
                                child: Transform.scale(
                                  scale: _resolutionScale.value,
                                  alignment: Alignment.topCenter,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: DetailResolutionSection(
                            options: resolutionOptions,
                            selected: selectedKey,
                            onSelected: (index) {
                              setState(() {
                                _selectedStreamIndex = index;
                                _syncTrackSelectionForCurrentMedia();
                              });
                            },
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
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ],
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
                    color: DetailTokens.pageBackground,
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
                    color: DetailTokens.pageBackground,
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
                    color: DetailTokens.pageBackground,
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
                    color: DetailTokens.pageBackground,
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
                      onViewAll: _showMediaInfoDetail,
                    ),
                  ),
                ),
              if (_linkVisible &&
                  (_imdbId.trim().isNotEmpty || _trimId.trim().isNotEmpty))
                SliverToBoxAdapter(
                  child: Container(
                    color: DetailTokens.pageBackground,
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
                onBack: () => Navigator.of(context).maybePop(),
                onMore: () {},
                title: detailTitle,
                titleOpacity: centerTitleOpacity,
              );
            },
          ),
        ],
      ),
    );
  }
}
