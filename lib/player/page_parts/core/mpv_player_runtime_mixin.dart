part of '../../mpv_player_page.dart';

const Duration _serverManagedPlayLinkCheckCooldown = Duration(seconds: 12);
const Duration _serverSessionRecoveryCooldown = Duration(seconds: 8);
const Duration _initialSourceLoadSettleDelay = Duration(milliseconds: 160);

class _ChapterSkipSegment extends PlayerChapterSkipSegment {
  const _ChapterSkipSegment({
    required super.kind,
    required super.chapterIndex,
    required super.label,
    required super.start,
    required super.end,
  });
}

extension _MpvPlayerRuntimeMixin on _MpvPlayerPageState {
  static const int _systemPlaybackSessionMinRequestIntervalMs = 900;
  static const int _systemPlaybackSessionStartupWarmupMs = 1500;
  static const int _runtimeTrackAutoRefreshWarmupMs = 1800;
  static const int _externalSubtitleAutoApplyWarmupMs = 450;
  static const int _runtimeTrackRefreshMinRequestIntervalMs = 600;
  static const double _subtitleStyleEpsilon = 0.0001;

  double _effectiveSubtitlePositionFactor() {
    return _subtitlePositionFactor.clamp(0.0, 1.0).toDouble();
  }

  double _effectiveSubtitleDelaySeconds() {
    final normalized = _subtitleDelaySeconds.clamp(-10.0, 10.0).toDouble();
    return double.parse(normalized.toStringAsFixed(1));
  }

  double _effectiveSubtitleScale() {
    final factor = _subtitleScaleFactor.clamp(0.0, 1.0).toDouble();
    return _subtitleScaleMin +
        ((_subtitleScaleMax - _subtitleScaleMin) * factor);
  }

  int _effectiveSubtitleMpvPosition() {
    return ((1 - _effectiveSubtitlePositionFactor()) * 100)
        .round()
        .clamp(0, 100)
        .toInt();
  }

  Future<void> _syncEffectiveSubtitleDelay({bool force = false}) async {
    final nextDelay = _effectiveSubtitleDelaySeconds();
    if (!force &&
        _lastAppliedSubtitleDelaySeconds != null &&
        (_lastAppliedSubtitleDelaySeconds! - nextDelay).abs() <
            _subtitleStyleEpsilon) {
      return;
    }
    _lastAppliedSubtitleDelaySeconds = nextDelay;
    await _controller.setSubtitleDelay(nextDelay);
  }

  Future<void> _syncEffectiveSubtitleScale({bool force = false}) async {
    final nextScale = _effectiveSubtitleScale();
    if (!force &&
        _lastAppliedSubtitleScale != null &&
        (_lastAppliedSubtitleScale! - nextScale).abs() <
            _subtitleStyleEpsilon) {
      return;
    }
    _lastAppliedSubtitleScale = nextScale;
    await _controller.setSubtitleScale(nextScale);
  }

  Future<void> _syncEffectiveSubtitlePosition({bool force = false}) async {
    final nextPosition = _effectiveSubtitleMpvPosition();
    if (!force && _lastAppliedEffectiveSubtitlePosition == nextPosition) {
      return;
    }
    _lastAppliedEffectiveSubtitlePosition = nextPosition;
    await _controller.setSubtitlePosition(nextPosition);
  }

  Future<void> _syncEffectiveSubtitleStyle({bool force = false}) async {
    await _syncEffectiveSubtitleDelay(force: force);
    await _syncEffectiveSubtitleScale(force: force);
    await _syncEffectiveSubtitlePosition(force: force);
  }

  void _invalidateAppliedSubtitleStyle() {
    _lastAppliedSubtitleDelaySeconds = null;
    _lastAppliedSubtitleScale = null;
    _lastAppliedEffectiveSubtitlePosition = null;
  }

  PlayInfoData? _playStatsInitialInfoForSource(MpvMediaSource source) {
    final info = widget.initialPlayInfo;
    if (info == null) return null;
    final sourceItemGuid = source.itemGuid.trim();
    final infoItemGuid = info.item.guid.trim();
    if (sourceItemGuid.isEmpty || infoItemGuid.isEmpty) {
      return null;
    }
    return sourceItemGuid == infoItemGuid ? info : null;
  }

  PlayStatsAnimeIdentity _playStatsAnimeIdentity({
    required PlayInfoData? info,
    required MpvMediaSource source,
    required String fallbackTitle,
  }) {
    final item = info?.item;
    return PlayStatsIdentityResolver.resolveAnimeIdentity(
      seriesGuid: source.seriesGuid.trim(),
      grandGuid: info?.grandGuid.trim() ?? '',
      trimId: item?.trimId ?? source.tmdbId,
      tvTitle: item?.tvTitle ?? '',
      seriesTitle: source.seriesTitle,
      fallbackTitle: fallbackTitle,
    );
  }

  String _playStatsSeasonTitle({
    required PlayInfoData? info,
    required MpvMediaSource source,
    required String animeTitle,
  }) {
    final item = info?.item;
    if (item?.parentTitle.trim().isNotEmpty == true) {
      return item!.parentTitle.trim();
    }
    final seasonNumber = item?.seasonNumber ?? source.seasonNumber;
    if (seasonNumber > 0) {
      return AppLocalizations.of(
        context,
      ).playerEpisodeSeasonTemplate(seasonNumber.toString());
    }
    if ((item?.episodeNumber ?? source.episodeNumber) > 0) {
      return AppLocalizations.of(context).playerEpisodeSpecialSeason;
    }
    return animeTitle;
  }

  int _playStatsYearFromItem(PlayItem? item) {
    final rawValue = <String>[
      item?.releaseDate ?? '',
      item?.airDate ?? '',
    ].firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    final match = RegExp(r'(\d{4})').firstMatch(rawValue);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  List<String> _playStatsCountryCodesFromItem(PlayItem? item) {
    if (item == null || item.productionCountries.isEmpty) {
      return const <String>[];
    }
    return item.productionCountries
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<int> _playStatsGenreIdsFromItem(PlayItem? item) {
    if (item == null || item.genres.isEmpty) {
      return const <int>[];
    }
    return item.genres
        .where((value) => value > 0)
        .toSet()
        .toList(growable: false);
  }

  bool _playStatsCountsTowardCompletion(
    PlayInfoData? info,
    MpvMediaSource source,
  ) {
    final type =
        (info?.type.isNotEmpty == true
                ? info!.type
                : (info?.item.type.isNotEmpty == true
                      ? info!.item.type
                      : (_currentMediaType.trim().isNotEmpty
                            ? _currentMediaType
                            : source.mediaType)))
            .trim()
            .toLowerCase();
    final episodeNumber = info?.item.episodeNumber ?? _currentEpisodeNumber;
    return type == 'episode' && episodeNumber > 0;
  }

  PlayStatsVideoMeta _buildPlayStatsVideoMeta({
    required MpvMediaSource source,
    PlayInfoData? info,
    int? mediaDurationMs,
  }) {
    final currentInfo = info ?? _playStatsCurrentInfo;
    final item = currentInfo?.item;
    final videoId =
        (_currentItemGuid.trim().isNotEmpty
                ? _currentItemGuid.trim()
                : source.itemGuid.trim())
            .trim();
    final title = _currentTitle.trim().isNotEmpty
        ? _currentTitle.trim()
        : source.title.trim();
    final animeIdentity = _playStatsAnimeIdentity(
      info: currentInfo,
      source: source,
      fallbackTitle: title,
    );
    final seasonTitle = _playStatsSeasonTitle(
      info: currentInfo,
      source: source,
      animeTitle: animeIdentity.animeTitle,
    );
    final effectiveDurationMs =
        mediaDurationMs ??
        (() {
          final effectiveDuration = _effectiveDuration().inMilliseconds;
          if (effectiveDuration > 0) return effectiveDuration;
          if (_durationSeconds > 0) return _durationSeconds * 1000;
          return source.durationSeconds > 0 ? source.durationSeconds * 1000 : 0;
        })();
    final countryCodes = _playStatsCountryCodesFromItem(item);
    final country = countryCodes.isEmpty ? '' : countryCodes.first;
    return PlayStatsVideoMeta(
      videoId: videoId,
      animeId: animeIdentity.animeId,
      seasonId: currentInfo?.parentGuid.trim().isNotEmpty == true
          ? currentInfo!.parentGuid.trim()
          : (_currentSeasonGuid.trim().isNotEmpty
                ? _currentSeasonGuid.trim()
                : source.seasonGuid.trim()),
      title: title,
      animeTitle: animeIdentity.animeTitle,
      seasonTitle: seasonTitle,
      videoKind:
          (currentInfo?.type.isNotEmpty == true
                  ? currentInfo!.type
                  : (item?.type.isNotEmpty == true
                        ? item!.type
                        : (_currentMediaType.trim().isNotEmpty
                              ? _currentMediaType
                              : source.mediaType)))
              .trim(),
      countsTowardCompletion: _playStatsCountsTowardCompletion(
        currentInfo,
        source,
      ),
      country: country,
      countryCodes: countryCodes,
      genreIds: _playStatsGenreIdsFromItem(item),
      year: _playStatsYearFromItem(item),
      mediaDurationMs: effectiveDurationMs,
      credits: const <PlayStatsCredit>[],
    );
  }

  Future<void> _startPlayStatsSession({
    required PlayStartSource startSource,
    PlayInfoData? info,
    MpvMediaSource? source,
    int? startPositionMs,
  }) async {
    final effectiveSource = source ?? widget.source;
    if (effectiveSource.externalLocalSource) return;
    final existingInfo = _playStatsCurrentInfo;
    final currentInfo =
        info ??
        (existingInfo != null &&
                existingInfo.item.guid.trim() == effectiveSource.itemGuid.trim()
            ? existingInfo
            : null);
    final meta = _buildPlayStatsVideoMeta(
      source: effectiveSource,
      info: currentInfo,
    );
    if (meta.videoId.isEmpty) return;
    if (_playStatsCurrentVideoId == meta.videoId) {
      return;
    }
    _playStatsCurrentInfo = currentInfo;
    _playStatsCurrentVideoId = meta.videoId;
    await _playStatsSessionController.startPlayback(
      PlayStatsStartContext(
        startSource: startSource,
        meta: meta,
        startPositionMs:
            (startPositionMs ?? effectiveSource.startPosition.inMilliseconds)
                .clamp(0, 1 << 31),
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _finishPlayStatsSession(String reason) async {
    final videoId = _playStatsCurrentVideoId;
    _playStatsCurrentVideoId = '';
    if (videoId.isEmpty) return;
    await _playStatsSessionController.finishPlayback(reason: reason);
    final provider =
        _nasProvider ?? (mounted ? context.read<NasProvider>() : null);
    if (provider != null) {
      PlayStatsService.instance.metadataBackfillService.schedule(
        provider: provider,
        preferredVideoIds: <String>[videoId],
      );
    }
  }

  Future<void> _seekWithStats(
    Duration target, {
    required bool userInitiated,
  }) async {
    final fromMs =
        (_uiController.draggingPosition ?? _controller.value.value.position)
            .inMilliseconds;
    final toMs = target.inMilliseconds.clamp(0, 1 << 31);
    _playStatsSessionController.recordSeek(
      fromMs: fromMs < 0 ? 0 : fromMs,
      toMs: toMs,
      userInitiated: userInitiated,
    );
    await _controller.seek(Duration(milliseconds: toMs));
  }

  OpEdSegment? _playStatsSegmentFromChapter(PlayerChapterSkipSegment? segment) {
    if (segment == null) return null;
    return OpEdSegment(
      isIntro: segment.isIntro,
      startMs: segment.start.inMilliseconds,
      endMs: segment.end.inMilliseconds,
    );
  }

  void _syncPlayStatsOpEdSegments() {
    _playStatsSessionController.markOpEdDetected(
      intro: _playStatsSegmentFromChapter(_inferredIntroSkip),
      outro: _playStatsSegmentFromChapter(_inferredOutroSkip),
    );
  }

  void _hydrateFromSource(MpvMediaSource source) {
    final previousSeriesGuid = _currentSeriesGuid.trim();
    final previousSourceWasDownloaded = _currentSourceIsDownloadedFile;
    final nextSeriesGuid = source.seriesGuid.trim();
    final normalizedSourceUrl = source.url.trim().toLowerCase();
    final nextSourceIsDownloaded =
        source.isDownloadedFile ||
        source.externalLocalSource ||
        normalizedSourceUrl.startsWith('file:') ||
        normalizedSourceUrl.startsWith('content:');
    if (previousSeriesGuid != nextSeriesGuid ||
        previousSourceWasDownloaded != nextSourceIsDownloaded) {
      _invalidateEpisodePickerSeasonCache(clearCurrentItems: true);
    }
    _chapterRetryTimer?.cancel();
    _centerPopupTimer?.cancel();
    _uiController.resetForSourceChange();
    _dismissedChapterSkipKeys.clear();
    _completedChapterSkipKeys.clear();
    _loadNonceSeed = _sessionController.hydrateFromSource(
      source: source,
      completionController: _completionController,
      currentLoadNonceSeed: _loadNonceSeed,
    );
    _currentSubtitleGuid = _normalizedSubtitleGuid();
    _subtitleController.resetForSourceChange(
      pendingSelectionRefresh: (_normalizedSubtitleGuid() ?? '')
          .trim()
          .isNotEmpty,
    );
    for (final entry in source.localSubtitleFiles.entries) {
      _subtitleController.cacheLocalSubtitleFile(
        guid: entry.key,
        path: entry.value,
      );
    }
    _currentResolution = source.resolution;
    _currentBitrate = source.bitrate;
    _durationSeconds = source.durationSeconds;
    _currentPosterPath = source.posterPath.trim();
    _chapterMediaGuid = '';
    _chapters = const <MpvChapterItem>[];
    _resetAbLoopForSourceChange();
    unawaited(_loadBookmarksForCurrentMedia());
    _introOutroConfigGuid = '';
    _introOutroConfigLoaded = false;
    _introChapterIndex = null;
    _outroChapterIndex = null;
    _officialIntroDurationSeconds = 0;
    _officialOutroDurationSeconds = 0;
    _primeIntroOutroConfigFromInitialPlayInfo(source);
    _playStatsCurrentInfo = _playStatsInitialInfoForSource(source);
    _inferredIntroSkip = null;
    _inferredOutroSkip = null;
    _uiController.activeChapterSkipPrompt = null;
    _uiController.centerPopupMessage = null;
    _skipPromptCountdownSeconds = 0;
    _introOutroSkipInFlight = false;
    _pendingReloadAutoplayRefresh = false;
    _prefetchedReturnDetailData = null;
    _prefetchedReturnDetailItemGuid = '';
    _prefetchedReturnDetailMediaGuid = '';
    _prefetchedReturnDetailAudioGuid = null;
    _prefetchedReturnDetailSubtitleGuid = null;
    _returnDetailPrefetchGeneration = 0;
    _setResumePromptVisibility(
      _shouldShowResumePrompt(
        startPosition: _resumeStartPosition,
        durationSeconds: source.durationSeconds,
      ),
    );
    _syncDanmakuMediaContext(triggerAutoLoad: _danmakuController.ready);
    _runtimeTrackSnapshotInFlight = false;
    _runtimeTrackSnapshotLoaded = false;
    _runtimeTrackSnapshotLoadNonce = 0;
    _runtimeTrackSnapshotStatus = '';
    _runtimeTrackAutoRefreshReadyAtMs = 0;
    _runtimeTrackAutoRefreshLoadNonce = 0;
    _cacheDownloadAvailable = false;
    _cacheDownloadCheckInFlight = false;
    _cacheDownloadImportInFlight = false;
    _cacheCompletionTipShown = false;
    _cacheDownloadConsumedForSource = false;
    _cacheDownloadCheckToken = 0;
    _armSystemPlaybackSessionWarmup();
    if (!source.externalLocalSource) {
      _scheduleEpisodePickerPrefetch();
    }
  }

  void _armSystemPlaybackSessionWarmup() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _systemPlaybackSessionWarmupUntilMs =
        nowMs + _systemPlaybackSessionStartupWarmupMs;
    _lastSystemPlaybackSessionRequestMs = 0;
    _lastSystemPlaybackSessionRequestKey = '';
    _lastSystemPlaybackSessionPayload = null;
  }

  void _primeIntroOutroConfigFromInitialPlayInfo(MpvMediaSource source) {
    final initialPlayInfo = widget.initialPlayInfo;
    if (initialPlayInfo == null) return;
    final sourceItemGuid = source.itemGuid.trim();
    final initialItemGuid = initialPlayInfo.item.guid.trim();
    if (sourceItemGuid.isEmpty ||
        initialItemGuid.isEmpty ||
        sourceItemGuid != initialItemGuid) {
      return;
    }
    final config = initialPlayInfo.playConfig;
    _introOutroConfigGuid = _resolveIntroOutroConfigGuid(initialPlayInfo);
    _officialIntroDurationSeconds =
        _normalizedIntroOutroSkipValue(config?.skipOpening) ?? 0;
    _officialOutroDurationSeconds =
        _normalizedIntroOutroSkipValue(config?.skipEnding) ?? 0;
    _introOutroConfigLoaded = true;
  }

  bool _isLocalRuntimeTrackSource() {
    return _externalLocalSource ||
        _localRuntimeTrackController.isLocalPlaybackUrl(_currentUrl);
  }

  bool _shouldRefreshRuntimeTracks(MpvPlayerValue value, {bool force = false}) {
    if (!force &&
        (_uiController.pendingLoadingTransition ||
            _uiController.qualitySwitchLoading ||
            _uiController.awaitingVisualPlaybackStart)) {
      return false;
    }
    if (!force && !_isRuntimeTrackAutoRefreshReady(value)) {
      return false;
    }
    if (!force &&
        (!_runtimeTrackSnapshotLoaded ||
            _runtimeTrackSnapshotLoadNonce != value.loadNonce)) {
      return _isLocalRuntimeTrackSource();
    }
    return _localRuntimeTrackController.shouldRefresh(
      isLocalPlayback: _isLocalRuntimeTrackSource(),
      value: value,
      currentSubtitleGuid: _currentSubtitleGuid,
      pendingSubtitleSelectionRefresh: _pendingSubtitleSelectionRefresh,
      pendingExternalSubtitlePath: _pendingExternalSubtitlePath,
      lastSnapshotLoadNonce: _runtimeTrackSnapshotLoadNonce,
      lastSnapshotPhase: _runtimeTrackSnapshotStatus,
      force: force,
    );
  }

  bool _isRuntimeTrackAutoRefreshReady(MpvPlayerValue value) {
    if (!_isLocalRuntimeTrackSource()) {
      return false;
    }
    if (!value.ready || !value.nativeLibLoaded) {
      return false;
    }
    final phase = value.playbackPhase;
    final stablePlaybackActive =
        phase == MpvPlaybackPhase.playing && value.isPlaybackAdvancing;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_runtimeTrackAutoRefreshLoadNonce != value.loadNonce) {
      _runtimeTrackAutoRefreshLoadNonce = value.loadNonce;
      _runtimeTrackAutoRefreshReadyAtMs = 0;
    }
    if (_runtimeTrackAutoRefreshReadyAtMs <= 0) {
      if (!stablePlaybackActive) {
        return false;
      }
      _runtimeTrackAutoRefreshReadyAtMs =
          nowMs + _runtimeTrackAutoRefreshWarmupMs;
      return false;
    }
    return nowMs >= _runtimeTrackAutoRefreshReadyAtMs;
  }

  bool _isExternalSubtitleAutoApplyReady(MpvPlayerValue value) {
    final pendingPath = _pendingExternalSubtitlePath;
    if (pendingPath == null || pendingPath.trim().isEmpty) {
      _externalSubtitleAutoApplyReadyAtMs = 0;
      return false;
    }
    if (!value.ready || !value.nativeLibLoaded) {
      return false;
    }
    final phase = value.playbackPhase;
    final stablePlaybackActive =
        phase == MpvPlaybackPhase.playing && value.isPlaybackAdvancing;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_externalSubtitleAutoApplyLoadNonce != value.loadNonce) {
      _externalSubtitleAutoApplyLoadNonce = value.loadNonce;
      _externalSubtitleAutoApplyReadyAtMs = 0;
    }
    if (_externalSubtitleAutoApplyReadyAtMs <= 0) {
      if (!stablePlaybackActive) {
        return false;
      }
      _externalSubtitleAutoApplyReadyAtMs =
          nowMs + _externalSubtitleAutoApplyWarmupMs;
      return false;
    }
    return nowMs >= _externalSubtitleAutoApplyReadyAtMs;
  }

  Future<bool> _refreshRuntimeTracks({bool force = false}) async {
    final value = _controller.value.value;
    if (!_shouldRefreshRuntimeTracks(value, force: force)) {
      return _runtimeTrackSnapshotLoaded;
    }
    if (_runtimeTrackSnapshotInFlight) {
      return _runtimeTrackSnapshotLoaded;
    }
    _runtimeTrackSnapshotInFlight = true;
    try {
      final snapshot = await _controller.getTrackSnapshot();
      if (!mounted) return false;
      final result = _localRuntimeTrackController.applySnapshot(
        snapshot: snapshot,
        currentAudioTracks: _audioTracks,
        currentSubtitleTracks: _subtitleTracks,
        currentAudioGuid: _currentAudioGuid,
        currentSubtitleGuid: _currentSubtitleGuid,
      );
      _updatePlayerState(() {
        _audioTracks = result.audioTracks;
        _subtitleTracks = result.subtitleTracks;
        _currentAudioGuid = result.selectedAudioGuid;
        _currentSubtitleGuid = result.selectedSubtitleGuid;
        _runtimeTrackSnapshotLoaded = true;
        _runtimeTrackSnapshotLoadNonce = value.loadNonce;
        _runtimeTrackSnapshotStatus = value.playbackPhase.name;
      });
      return true;
    } finally {
      _runtimeTrackSnapshotInFlight = false;
    }
  }

  bool _shouldRequestRuntimeTrackRefresh(MpvPlayerValue value) {
    if (!_isLocalRuntimeTrackSource()) {
      return false;
    }
    if (!_shouldRefreshRuntimeTracks(value)) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final requestKey =
        '${value.loadNonce}|${value.playbackPhase.name}|'
        '${(_currentSubtitleGuid ?? '').trim()}|'
        '${_pendingSubtitleSelectionRefresh ? 1 : 0}';
    if (requestKey == _lastRuntimeTrackRefreshRequestKey &&
        nowMs - _lastRuntimeTrackRefreshRequestMs <
            _runtimeTrackRefreshMinRequestIntervalMs) {
      return false;
    }
    _lastRuntimeTrackRefreshRequestKey = requestKey;
    _lastRuntimeTrackRefreshRequestMs = nowMs;
    return true;
  }

  bool _shouldRequestSystemPlaybackSessionSync(MpvPlayerValue value) {
    if (!Platform.isAndroid || _exitInProgress) {
      return false;
    }
    if (_uiTransientOverlayVisible) {
      return false;
    }
    if (_uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _systemPlaybackSessionWarmupUntilMs) {
      return false;
    }
    final positionBucket = _displayPosition(value).inMilliseconds ~/ 1000;
    final requestKey = <Object?>[
      _currentItemGuid,
      value.loadNonce,
      value.ready,
      value.nativeLibLoaded,
      value.playbackPhase.name,
      value.error ?? '',
      value.listenVideoModeEnabled,
      value.nativeProxySessionId ?? '',
      _playbackSpeed.toStringAsFixed(3),
      _currentTitle,
      _currentSeriesTitle,
      _currentMediaType,
      _currentSeasonNumber,
      _currentEpisodeNumber,
      positionBucket,
    ].join('|');
    if (requestKey == _lastSystemPlaybackSessionRequestKey &&
        nowMs - _lastSystemPlaybackSessionRequestMs <
            _systemPlaybackSessionMinRequestIntervalMs) {
      return false;
    }
    _lastSystemPlaybackSessionRequestKey = requestKey;
    _lastSystemPlaybackSessionRequestMs = nowMs;
    return true;
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  PlayerSourceSnapshot _currentSourceSnapshot() {
    return _sessionController.buildSourceSnapshot(
      serverFallbackSubtitleGuids: _serverFallbackSubtitleGuids,
    );
  }

  Duration _displayPosition(MpvPlayerValue value) {
    return _uiController.draggingPosition ??
        _gestureController.displayPosition(value.position);
  }

  Duration _effectiveDuration() {
    final value = _controller.value.value;
    final metadataDuration = _durationSeconds > 0
        ? Duration(seconds: _durationSeconds)
        : Duration.zero;
    if (metadataDuration <= Duration.zero) {
      return value.duration;
    }
    if (value.duration <= Duration.zero) {
      return metadataDuration;
    }
    final delta = (value.duration - metadataDuration).abs();
    if ((!value.ready || !value.nativeLibLoaded) &&
        delta >= const Duration(seconds: 2)) {
      return metadataDuration;
    }
    if (value.duration < metadataDuration &&
        delta >= const Duration(seconds: 2)) {
      return metadataDuration;
    }
    return value.duration;
  }

  bool _shouldApplyPendingExternalSubtitlePath(String pendingPath) {
    final normalizedPath = pendingPath.trim();
    if (normalizedPath.isEmpty) return false;
    final selectedGuid = (_currentSubtitleGuid ?? '').trim();
    if (selectedGuid.isEmpty) return false;
    final selectedTrack = _findSubtitleTrack(selectedGuid);
    if (!_subtitleShouldUseExternalFile(selectedTrack)) {
      return false;
    }
    final expectedPath = _subtitleFileByGuid[selectedGuid]?.trim() ?? '';
    if (expectedPath.isEmpty) {
      return true;
    }
    return expectedPath == normalizedPath;
  }

  Duration _completionReferenceDuration(MpvPlayerValue value) {
    final runtimeDuration = value.duration;
    final metadataDuration = _durationSeconds > 0
        ? Duration(seconds: _durationSeconds)
        : Duration.zero;
    if (runtimeDuration > Duration.zero) {
      return runtimeDuration >= metadataDuration
          ? runtimeDuration
          : metadataDuration;
    }
    if (_currentSourceIsDownloadedFile) {
      return Duration.zero;
    }
    return metadataDuration;
  }

  bool _hasPlayedLongEnoughForAutoPlay(Duration displayPosition) {
    return displayPosition >=
        _MpvPlayerPageState._autoPlayPromptMinimumProgress;
  }

  Future<void> _loadInitialPlayerPreferences() async {
    final preferences = await _runtimePreferencesStore.load();
    final mpvBundle = await _mpvSettingsStore.loadBundle();
    final savedPicturePresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.picture,
    );
    final savedAudioPresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.audio,
    );
    final pictureInPictureSupported =
        await PlayerHostBridge.isPictureInPictureSupported();
    final parallelWindowSupported =
        await EmbeddedDetailLauncher.canOpenEmbeddedDetail();
    final parallelWindowSettings = parallelWindowSupported
        ? await ParallelWindowSettingsBridge.load()
        : null;
    if (!mounted) {
      _settingsController.applyRuntimePreferences(preferences);
      _subtitleController.subtitleDelaySeconds =
          preferences.subtitleDelaySeconds;
      _subtitleController.subtitlePositionFactor =
          preferences.subtitlePositionFactor;
      _subtitleController.subtitleScaleFactor = preferences.subtitleScaleFactor;
      _mpvSettings = mpvBundle.settings;
      _videoAdjustments = mpvBundle.videoAdjustments;
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
      _pictureInPictureSupported = pictureInPictureSupported;
      _parallelWindowSupported = parallelWindowSupported;
      _parallelWindowEnabled =
          parallelWindowSupported && (parallelWindowSettings?.enabled ?? false);
      _performanceOverlayOffsetNotifier.value =
          preferences.performanceOverlayOffset;
      _initialPlayerPreferencesLoaded = true;
      return;
    }
    _updatePlayerState(() {
      _settingsController.applyRuntimePreferences(preferences);
      _subtitleController.subtitleDelaySeconds =
          preferences.subtitleDelaySeconds;
      _subtitleController.subtitlePositionFactor =
          preferences.subtitlePositionFactor;
      _subtitleController.subtitleScaleFactor = preferences.subtitleScaleFactor;
      _mpvSettings = mpvBundle.settings;
      _videoAdjustments = mpvBundle.videoAdjustments;
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
      _pictureInPictureSupported = pictureInPictureSupported;
      _parallelWindowSupported = parallelWindowSupported;
      _parallelWindowEnabled =
          parallelWindowSupported && (parallelWindowSettings?.enabled ?? false);
      _performanceOverlayOffsetNotifier.value =
          preferences.performanceOverlayOffset;
    });
    _syncPerformanceOverlayPolling();
    _recomputeChapterSkipSegments();
    await _controller.setDecoderMode(_decoderMode);
    await _controller.setDisplayAspectRatioMode(_displayAspectRatioMode);
    await _controller.setVideoAdjustments(_videoAdjustments);
    await _controller.setMpvAdvancedSettings(
      _effectiveMpvSettings(mpvBundle.settings),
    );
    _initialPlayerPreferencesLoaded = true;
    _tryStartInitialSourceLoad();
  }

  Future<void> _refreshSavedMpvPresets() async {
    final savedPicturePresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.picture,
    );
    final savedAudioPresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.audio,
    );
    if (!mounted) {
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
      return;
    }
    _updatePlayerState(() {
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
    });
  }

  Future<void> _syncMpvPresetStateFromStore() async {
    final bundle = await _mpvSettingsStore.loadBundle();
    final savedPicturePresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.picture,
    );
    final savedAudioPresets = await _mpvSettingsStore.loadSavedPresets(
      SavedMpvPresetKind.audio,
    );
    if (!mounted) {
      _mpvSettings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
      return;
    }
    _updatePlayerState(() {
      _mpvSettings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      _savedMpvPicturePresets = savedPicturePresets;
      _savedMpvAudioPresets = savedAudioPresets;
    });
  }

  Future<void> _applyStoredMpvBundle(MpvSettingsBundle bundle) async {
    if (!mounted) {
      _mpvSettings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      return;
    }
    _updatePlayerState(() {
      _mpvSettings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
    });
    await _controller.setVideoAdjustments(bundle.videoAdjustments);
    _prepareSubtitleSelectionForPlayerReconfigure();
    await _controller.setMpvAdvancedSettings(
      _effectiveMpvSettings(bundle.settings),
    );
    _scheduleDeferredSubtitleSelectionRefresh();
  }

  Future<void> _setAutoPlayEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._autoPlayPrefKey,
      enabled,
    );
    if (!mounted) return;
    _updatePlayerState(() => _autoPlayEnabled = enabled);
    if (!enabled) {
      _invalidateNextEpisodePreload();
    }
  }

  Future<void> _setNextEpisodePreloadEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._nextEpisodePreloadPrefKey,
      enabled,
    );
    if (!mounted) {
      _nextEpisodePreloadEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _nextEpisodePreloadEnabled = enabled);
    if (!enabled) {
      _invalidateNextEpisodePreload();
    }
  }

  Future<void> _setAutoRotateEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._autoRotatePrefKey,
      enabled,
    );
    if (!mounted) return;
    _updatePlayerState(() => _autoRotateEnabled = enabled);
  }

  Future<void> _setExtremePlaybackEnabled(
    bool enabled, {
    bool reloadCurrentPlayback = false,
  }) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._extremePlaybackPrefKey,
      enabled,
    );
    if (!mounted) {
      _extremePlaybackEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _extremePlaybackEnabled = enabled);
    await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
    if (!reloadCurrentPlayback) return;
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      _displayPosition(_controller.value.value),
      targetPaused:
          _controller.value.value.playbackPhase != MpvPlaybackPhase.playing,
    );
    await _reloadCurrentSource(
      forcePlay:
          _controller.value.value.playbackPhase == MpvPlaybackPhase.playing,
    );
  }

  Map<String, String> _effectiveMpvSettings([Map<String, String>? base]) {
    final effective = Map<String, String>.from(base ?? _mpvSettings);
    final extremeActive =
        _extremePlaybackEnabled &&
        _isExtremePlaybackApplicableForCurrentSource();
    if (!extremeActive) return effective;
    effective[_MpvPlayerPageState._mpvSettingCacheProfile] = 'low_latency';
    effective[_MpvPlayerPageState._mpvSettingCacheSizeMb] = 'auto';
    return effective;
  }

  Future<void> _setPerformanceOverlayEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._performanceOverlayPrefKey,
      enabled,
    );
    if (!mounted) {
      _performanceOverlayEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _performanceOverlayEnabled = enabled);
    _syncPerformanceOverlayPolling();
  }

  Future<void> _setFpsOverlayEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._fpsOverlayPrefKey,
      enabled,
    );
    if (!mounted) {
      _fpsOverlayEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _fpsOverlayEnabled = enabled);
  }

  Future<void> _persistPerformanceOverlayOffset(Offset offset) async {
    await _runtimePreferencesStore.persistPerformanceOverlayOffset(offset);
  }

  Future<void> _setDecoderModePreference(String mode) async {
    final normalized = mode == _MpvPlayerPageState._decoderModeSoftware
        ? _MpvPlayerPageState._decoderModeSoftware
        : _MpvPlayerPageState._decoderModeHardware;
    await _runtimePreferencesStore.setString(
      _MpvPlayerPageState._decoderModePrefKey,
      normalized,
    );
    _decoderMode = normalized;
    _prepareSubtitleSelectionForPlayerReconfigure();
    await _controller.setDecoderMode(normalized);
    _scheduleDeferredSubtitleSelectionRefresh();
  }

  Future<void> _setDisplayAspectRatioPreference(String mode) async {
    await _runtimePreferencesStore.setString(
      _MpvPlayerPageState._displayAspectRatioPrefKey,
      mode,
    );
    _displayAspectRatioMode = mode;
    _prepareSubtitleSelectionForPlayerReconfigure();
    await _controller.setDisplayAspectRatioMode(mode);
    _scheduleDeferredSubtitleSelectionRefresh();
  }

  Future<void> _setMpvAdvancedSetting(String key, String value) async {
    if (!_MpvPlayerPageState._defaultMpvSettings.containsKey(key)) return;
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await _runtimePreferencesStore.setString(
      '${_MpvPlayerPageState._mpvSettingPrefPrefix}$key',
      normalized,
    );
    if (!mounted) {
      _mpvSettings = <String, String>{..._mpvSettings, key: normalized};
      return;
    }
    _updatePlayerState(() {
      _mpvSettings = <String, String>{..._mpvSettings, key: normalized};
    });
    _prepareSubtitleSelectionForPlayerReconfigure();
    await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
    _scheduleDeferredSubtitleSelectionRefresh();
  }

  Future<void> _setMpvAdvancedSettingsPatch(
    Map<String, String> patch, {
    bool applyToPlayer = true,
  }) async {
    if (patch.isEmpty) return;
    final next = Map<String, String>.from(_mpvSettings);
    var changed = false;
    for (final entry in patch.entries) {
      if (!_MpvPlayerPageState._defaultMpvSettings.containsKey(entry.key)) {
        continue;
      }
      final normalized = entry.value.trim();
      if (normalized.isEmpty) continue;
      if (next[entry.key] == normalized) continue;
      next[entry.key] = normalized;
      changed = true;
    }
    if (!changed) return;
    for (final entry in patch.entries) {
      if (!_MpvPlayerPageState._defaultMpvSettings.containsKey(entry.key)) {
        continue;
      }
      final normalized = entry.value.trim();
      if (normalized.isEmpty) continue;
      await _runtimePreferencesStore.setString(
        '${_MpvPlayerPageState._mpvSettingPrefPrefix}${entry.key}',
        normalized,
      );
    }
    if (!mounted) {
      _mpvSettings = next;
      return;
    }
    _updatePlayerState(() => _mpvSettings = next);
    if (applyToPlayer) {
      _prepareSubtitleSelectionForPlayerReconfigure();
      await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
      _scheduleDeferredSubtitleSelectionRefresh();
    }
  }

  Future<void> _applyAutomaticFilterFallbackSettings() async {
    final patch = <String, String>{
      _MpvPlayerPageState._mpvSettingDeband: 'off',
      _MpvPlayerPageState._mpvSettingSharpen: 'off',
      _MpvPlayerPageState._mpvSettingDenoise: 'off',
      _MpvPlayerPageState._mpvSettingFrameInterpolation: 'off',
      if (_mpvSettings[_MpvPlayerPageState._mpvSettingScaleProfile] ==
          'quality')
        _MpvPlayerPageState._mpvSettingScaleProfile: 'balanced',
    };
    await _setMpvAdvancedSettingsPatch(patch);
  }

  void _prepareSubtitleSelectionForPlayerReconfigure() {
    if ((_currentSubtitleGuid ?? '').trim().isEmpty) return;
    _subtitleStatusTipSuppressedUntil = DateTime.now().add(
      const Duration(seconds: 5),
    );
    _pendingSubtitleSelectionRefresh = true;
    _pendingExternalSubtitlePath = null;
  }

  void _scheduleDeferredSubtitleSelectionRefresh() {
    if ((_currentSubtitleGuid ?? '').trim().isEmpty) {
      _deferredSubtitleSelectionTimer?.cancel();
      _deferredSubtitleSelectionTimer = null;
      return;
    }
    _deferredSubtitleSelectionTimer?.cancel();
    _deferredSubtitleSelectionTimer = Timer(
      const Duration(milliseconds: 450),
      () {
        _deferredSubtitleSelectionTimer = null;
        if (!mounted || _exitInProgress) {
          return;
        }
        final value = _controller.value.value;
        if (!value.nativeLibLoaded || !value.ready) {
          _scheduleDeferredSubtitleSelectionRefresh();
          return;
        }
        unawaited(_refreshSubtitleSelectionIfNeeded());
      },
    );
  }

  Future<void> _loadIntroOutroConfigForItem(String itemGuid) async {
    if (_externalLocalSource) return;
    final normalizedItemGuid = itemGuid.trim();
    if (normalizedItemGuid.isEmpty) return;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final info = await api.getPlayInfo(normalizedItemGuid);
      if (!mounted || _currentItemGuid != normalizedItemGuid) return;
      final config = info.playConfig;
      final resolvedConfigGuid = _resolveIntroOutroConfigGuid(info);
      final skipOpening =
          _normalizedIntroOutroSkipValue(config?.skipOpening) ?? 0;
      final skipEnding =
          _normalizedIntroOutroSkipValue(config?.skipEnding) ?? 0;
      _updatePlayerState(() {
        _introOutroConfigGuid = resolvedConfigGuid;
        _officialIntroDurationSeconds = skipOpening;
        _officialOutroDurationSeconds = skipEnding;
      });
    } catch (_) {}
  }

  Future<void> _syncIntroOutroConfigToServer({bool? enabled}) async {
    if (_externalLocalSource) return;
    final configGuid = _resolvedIntroOutroConfigGuid();
    if (configGuid.isEmpty) return;
    final api = FeiniuApi(context.read<NasProvider>());
    final shouldEnable = enabled ?? _introOutroEnabled;
    final skipOpening = shouldEnable ? _officialIntroDurationSeconds : null;
    final skipEnding = shouldEnable ? _officialOutroDurationSeconds : null;
    await api.setPlayConfigByItem(
      itemGuid: configGuid,
      skipOpening: skipOpening,
      skipEnding: skipEnding,
    );
  }

  Future<void> _markCurrentItemWatched() async {}

  String _resolvedIntroOutroConfigGuid() {
    final explicit = _introOutroConfigGuid.trim();
    if (explicit.isNotEmpty) return explicit;
    return _currentItemGuid.trim();
  }

  String _resolveIntroOutroConfigGuid(PlayInfoData info) {
    final configGuid = info.playConfig?.guid.trim() ?? '';
    if (configGuid.isNotEmpty) return configGuid;
    final parentGuid = info.parentGuid.trim();
    if (parentGuid.isNotEmpty) return parentGuid;
    return _currentItemGuid.trim();
  }

  int? _normalizedIntroOutroSkipValue(int? value) {
    if (value == null) return null;
    if (value < 0) return null;
    return value;
  }

  Future<void> _persistIntroOutroPreferences({bool? enabled}) async {
    final effectiveSourceMode = enabled == false
        ? _MpvPlayerPageState._introOutroSourceModeOff
        : _introOutroSourceMode;
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._introOutroEnabledPrefKey,
      effectiveSourceMode != _MpvPlayerPageState._introOutroSourceModeOff,
    );
    await _runtimePreferencesStore.setString(
      _MpvPlayerPageState._introOutroSourceModePrefKey,
      effectiveSourceMode,
    );
    await _runtimePreferencesStore.setString(
      _MpvPlayerPageState._introOutroChapterModePrefKey,
      _chapterSkipMode,
    );
    await _runtimePreferencesStore.setInt(
      _MpvPlayerPageState._introOutroIntroMaxPrefKey,
      _introDurationSeconds.clamp(60, 240),
    );
    await _runtimePreferencesStore.setInt(
      _MpvPlayerPageState._introOutroOutroMaxPrefKey,
      _outroDurationSeconds.clamp(60, 240),
    );
  }

  String _decoderModeLabel([String? mode]) {
    final normalized =
        (mode ?? _decoderMode) == _MpvPlayerPageState._decoderModeSoftware
        ? _MpvPlayerPageState._decoderModeSoftware
        : _MpvPlayerPageState._decoderModeHardware;
    return normalized == _MpvPlayerPageState._decoderModeSoftware
        ? AppLocalizations.of(context).playerSoftwareDecoderTitle
        : AppLocalizations.of(context).playerHardwareDecoderTitle;
  }

  String _displayAspectRatioLabel([String? mode]) {
    switch (mode ?? _displayAspectRatioMode) {
      case _MpvPlayerPageState._displayAspectRatioFill:
        return AppLocalizations.of(context).playerAspectFill;
      case _MpvPlayerPageState._displayAspectRatio4x3:
        return '4:3';
      case _MpvPlayerPageState._displayAspectRatio16x9:
        return '16:9';
      case _MpvPlayerPageState._displayAspectRatio21x9:
        return '21:9';
      default:
        return AppLocalizations.of(context).playerAspectFit;
    }
  }

  Future<void> _setDisplayAspectRatioMode(String mode) async {
    await _setDisplayAspectRatioPreference(mode);
    if (!mounted) return;
    _updatePlayerState(() => _displayAspectRatioMode = mode);
  }

  void _handlePlatformViewCreated(int viewId, {required String backend}) {
    _updatePlayerState(() {
      _platformViewAttached = true;
      // Keep the active PlatformView backend stable for the rest of this
      // player session. Rebuilding the PlatformView to flip texture/surface
      // while mpv is already attached pauses playback and can strand resume.
      _lockedPlatformViewBackend = MpvVideoOutputBackend.normalize(backend);
      _lastDanmakuOcclusionConfigSignature = '';
    });
    _controller.attach(viewId);
    _syncPerformanceOverlayPolling();
    unawaited(_syncDanmakuDynamicOcclusionConfig());
    _queueNativeDanmakuRendererSync(immediate: true);
    unawaited(_syncNativeDanmakuOcclusionState());
    _tryStartInitialSourceLoad();
  }

  void _tryStartInitialSourceLoad() {
    if (!mounted) return;
    if (_initialSourceLoadTimer != null) return;
    if (!_platformViewAttached ||
        !_initialPlayerPreferencesLoaded ||
        !_initialDanmakuPreferencesLoaded ||
        !_initialFrameReady) {
      return;
    }
    if (_initialSourceLoadStarted) return;
    _initialSourceLoadTimer = Timer(_initialSourceLoadSettleDelay, () {
      _initialSourceLoadTimer = null;
      if (!mounted ||
          _exitInProgress ||
          _initialSourceLoadStarted ||
          !_platformViewAttached ||
          !_initialPlayerPreferencesLoaded ||
          !_initialDanmakuPreferencesLoaded ||
          !_initialFrameReady) {
        return;
      }
      _initialSourceLoadStarted = true;
      _replacePlayerSource(widget.source);
    });
  }

  void _resetSourceLoadTransitionState() {
    _videoLoadingOverlayTimer?.cancel();
    _videoLoadingOverlayTimer = null;
    _invalidateAppliedSubtitleStyle();
    _uiController.resetSourceLoadTransitionState();
  }

  Future<void> _prepareAndReloadSource(
    MpvMediaSource source, {
    required bool paused,
    required Duration visualStartPosition,
    required bool targetPaused,
    String? statusText,
  }) async {
    final effectiveSource = source.copyWith(startPaused: paused);
    _markAwaitingVisualPlaybackStart(
      visualStartPosition,
      targetPaused: targetPaused,
    );
    _controller.prepareForSourceLoad(
      effectiveSource,
      paused: paused,
      statusText:
          statusText ?? AppLocalizations.of(context).playerPreparingPlayback,
    );
    await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
    await _controller.reload(effectiveSource);
  }

  void _replacePlayerSource(MpvMediaSource incomingSource) {
    final source = incomingSource.loadNonce > 0
        ? incomingSource
        : incomingSource.copyWith(loadNonce: _issueNextLoadNonce());
    _invalidateNextEpisodePreload();
    _speedDialVisible = false;
    _resetSourceLoadTransitionState();
    _hydrateFromSource(source);
    unawaited(_prefetchCurrentSubtitleFileIfNeeded());
    unawaited(
      _startPlayStatsSession(
        startSource: widget.startSource,
        info: _playStatsInitialInfoForSource(source),
        source: source,
        startPositionMs: source.startPosition.inMilliseconds,
      ),
    );
    _clearPlaybackCompletionState();
    _pendingReloadAutoplayRefresh = true;
    unawaited(
      _prepareAndReloadSource(
        source,
        paused: false,
        visualStartPosition: source.startPosition,
        targetPaused: false,
        statusText: AppLocalizations.of(context).playerPreparingPlayback,
      ),
    );
    unawaited(_refreshPlayerStateAfterSourceReplace());
    if ((_currentSubtitleGuid ?? '').trim().isNotEmpty) {
      if (_isLocalRuntimeTrackSource()) {
        _pendingSubtitleSelectionRefresh = true;
      } else {
        unawaited(_applySubtitleSelection());
      }
    }
  }

  Future<void> _refreshPlayerStateAfterSourceReplace() async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted || _exitInProgress) return;
    await _controller.refreshState();
    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (!mounted || _exitInProgress) return;
    await _controller.refreshState();
  }

  void _handlePlayerValueChanged() {
    final value = _controller.value.value;
    final now = DateTime.now();
    _activeProxySessionId = value.nativeProxySessionId;
    _activeCacheResourceKey = value.cacheResourceKey;
    final listenModeChanged =
        _listenVideoModeEnabled != value.listenVideoModeEnabled;
    _listenVideoModeEnabled = value.listenVideoModeEnabled;
    final currentStatusText = value.statusText.trim();
    final statusReaction = _runtimeController.consumeStatusText(
      currentStatusText: currentStatusText,
      now: DateTime.now(),
      subtitleStatusTipSuppressedUntil: _subtitleStatusTipSuppressedUntil,
      autoFilterFallbackStatusText:
          _MpvPlayerPageState._autoFilterFallbackStatusText,
    );
    _gestureController.acknowledgeSeekPosition(value.position);
    _playStatsSessionController.updateProgress(
      positionMs: value.position.inMilliseconds,
      mediaDurationMs: _effectiveDuration().inMilliseconds,
      paused: !value.isPlaybackAdvancing,
      now: now,
      playbackCompleted:
          _playbackCompleted || value.playbackPhase == MpvPlaybackPhase.ended,
    );
    _syncVisualPlaybackStartState(value);
    _refreshAutoplayAfterReloadIfNeeded(value);
    _syncVideoLoadingOverlayVisibility(value);
    _syncWeakNetworkSuggestion(value);
    if (value.nativeLibLoaded && value.ready) {
      unawaited(_syncEffectiveSubtitleStyle());
    }
    if (statusReaction.showAutoFilterFallbackTip) {
      _showStatusMessage(
        AppLocalizations.of(context).playerAutoFilterFallbackApplied,
        hideAfter: const Duration(seconds: 2),
      );
      unawaited(_applyAutomaticFilterFallbackSettings());
    }
    if (statusReaction.clearSubtitleStatusTipSuppression) {
      _subtitleStatusTipSuppressedUntil = null;
    } else if (statusReaction.showSubtitleStatusTopTip) {
      _showSubtitleStatusTopTip();
    }
    _syncPerformanceOverlayPolling();
    _handleAbLoopRuntime(value);
    if (_shouldRequestRuntimeTrackRefresh(value)) {
      unawaited(_refreshRuntimeTracks());
    }
    if (_shouldRequestSystemPlaybackSessionSync(value)) {
      unawaited(_startOrUpdateSystemPlaybackSession());
    }
    final effectiveDuration = _effectiveDuration();
    _syncCacheDownloadability(value, effectiveDuration);
    final displayPosition = _displayPosition(value);
    final completionDuration = _completionReferenceDuration(value);
    final transitionPlaybackState =
        _uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart;
    _completionController.setAutoPlayCountdownPaused(
      value.playbackPhase != MpvPlaybackPhase.playing &&
          value.playbackPhase != MpvPlaybackPhase.ended,
    );
    _completionController.settlePlaybackCompletionSuppression(
      value: value,
      effectiveDuration: completionDuration,
      displayPosition: displayPosition,
    );
    final remaining = completionDuration - displayPosition;
    if (_autoPlayEnabled &&
        !_completionController.autoPlayPromptVisible &&
        !_completionController.autoPlayPromptSuppressed &&
        !_playbackCompleted &&
        !_completionActionInFlight &&
        !transitionPlaybackState &&
        !_completionController.suppressPlaybackCompletionUntilReady &&
        _hasPlayedLongEnoughForAutoPlay(displayPosition) &&
        completionDuration > Duration.zero &&
        remaining > Duration.zero &&
        remaining <= _completionController.autoPlayPromptWindow) {
      unawaited(_maybeStartAutoPlayPromptNearEnd());
    }
    if (transitionPlaybackState ||
        _completionController.suppressPlaybackCompletionUntilReady) {
      // A reload emits transient end-file/playback-ended states for the old source.
      // Ignore completion UI until the new source is visually stable again.
    } else if (_completionController.consumePauseAfterReady(value)) {
      unawaited(_pauseForAutoPlayPromptIfNeeded());
    } else if (!_completionController.autoPlayPromptVisible &&
        !_playbackCompleted &&
        !_completionActionInFlight &&
        _completionController.isPlaybackCompleted(
          value: value,
          effectiveDuration: completionDuration,
          displayPosition: displayPosition,
        )) {
      unawaited(_handlePlaybackCompleted());
    }
    final pausedLike = value.playbackPhase == MpvPlaybackPhase.paused;
    final pausedChanged = pausedLike != _uiController.wasPaused;
    _uiController.wasPaused = pausedLike;
    if (transitionPlaybackState) {
      if (value.playbackPhase == MpvPlaybackPhase.playing &&
          _uiController.draggingPosition == null) {
        _scheduleControlsAutoHide();
      }
    } else if (pausedLike && pausedChanged) {
      final suppressReveal = _uiController.suppressControlsRevealOnNextPause;
      _uiController.suppressControlsRevealOnNextPause = false;
      if (!suppressReveal) {
        _showControls();
      }
    } else if (value.playbackPhase == MpvPlaybackPhase.playing &&
        pausedChanged) {
      _uiController.suppressControlsRevealOnNextPause = false;
      if (_uiController.draggingPosition == null) {
        _scheduleControlsAutoHide();
      }
    }
    if (listenModeChanged && mounted) {
      _updatePlayerState(() {});
    }
    final pendingPath = _pendingExternalSubtitlePath;
    _loadChaptersIfNeeded(value);
    _handleChapterSkipRuntime(value);
    final subtitleSelectionReady =
        !_isLocalRuntimeTrackSource() || _isRuntimeTrackAutoRefreshReady(value);
    if (_pendingSubtitleSelectionRefresh &&
        value.nativeLibLoaded &&
        value.ready &&
        subtitleSelectionReady &&
        pendingPath == null) {
      unawaited(_refreshSubtitleSelectionIfNeeded());
    }
    if (pendingPath == null || !value.nativeLibLoaded || !value.ready) {
      return;
    }
    if (!_isExternalSubtitleAutoApplyReady(value)) {
      return;
    }
    _pendingExternalSubtitlePath = null;
    if (!_shouldApplyPendingExternalSubtitlePath(pendingPath)) {
      return;
    }
    unawaited(_controller.setExternalSubtitleFile(pendingPath));
  }

  void _syncWeakNetworkSuggestion(MpvPlayerValue value) {
    final currentSuggestion = _uiController.weakNetworkSuggestion;
    if (_externalLocalSource || _currentSourceIsDownloadedFile) {
      if (currentSuggestion != null) {
        _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      }
      return;
    }

    final transitionInFlight =
        _uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart ||
        _uiController.qualitySwitchLoading;
    final eta = value.estimatedResumeWait;
    if (transitionInFlight ||
        value.playbackPhase != MpvPlaybackPhase.buffering ||
        eta == null ||
        eta < const Duration(seconds: 8)) {
      if (currentSuggestion != null) {
        _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      }
      return;
    }

    final currentQuality = _currentDisplayedQualityOption();
    if (currentQuality == null) {
      if (currentSuggestion != null) {
        _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      }
      return;
    }

    final suppressionKey = _weakNetworkSuggestionSuppressionKey(currentQuality);
    if (_uiController.isWeakNetworkSuggestionSuppressed(suppressionKey)) {
      if (currentSuggestion != null) {
        _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      }
      return;
    }

    final recommendation = recommendWeakNetworkQuality(
      qualities: _displayQualityOptionsForCurrentMode(),
      currentQuality: currentQuality,
      networkSpeedBytesPerSecond: value.networkSpeedBytesPerSecond,
    );
    if (recommendation == null ||
        !isMeaningfulWeakNetworkDowngrade(
          currentQuality: currentQuality,
          recommendedQuality: recommendation.quality,
        )) {
      if (currentSuggestion != null) {
        _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      }
      return;
    }

    final nextSuggestion = PlayerWeakNetworkSuggestion(
      suppressionKey: suppressionKey,
      targetQualityId: _qualityId(recommendation.quality),
      title: AppLocalizations.of(context).playerWeakNetworkSuggestionTitle(
        _qualityDisplayLabel(recommendation.quality),
      ),
      subtitle: buildWeakNetworkBufferingDetails(
        networkSpeedBytesPerSecond: value.networkSpeedBytesPerSecond,
        estimatedResumeWait: eta,
      ),
    );
    if (_sameWeakNetworkSuggestion(currentSuggestion, nextSuggestion)) {
      return;
    }
    _updatePlayerState(
      () => _uiController.showWeakNetworkSuggestion(nextSuggestion),
    );
  }

  PlaybackQualityOption? _currentDisplayedQualityOption() {
    final selectedId = _selectedQualityId();
    if (selectedId.isEmpty) {
      return null;
    }
    for (final quality in _displayQualityOptionsForCurrentMode()) {
      if (_qualityId(quality) == selectedId) {
        return quality;
      }
    }
    return null;
  }

  String _weakNetworkSuggestionSuppressionKey(
    PlaybackQualityOption currentQuality,
  ) {
    return <String>[
      _currentItemGuid.trim(),
      _currentMediaGuid.trim().isNotEmpty
          ? _currentMediaGuid.trim()
          : currentQuality.mediaGuid.trim(),
      _currentVideoGuid.trim().isNotEmpty
          ? _currentVideoGuid.trim()
          : currentQuality.videoGuid.trim(),
      _currentResolution.trim().isNotEmpty
          ? _currentResolution.trim()
          : _qualityLabel(currentQuality),
      (_currentBitrate > 0 ? _currentBitrate : currentQuality.bitrate)
          .toString(),
      (_currentDirectLinkQualityIndex ??
              currentQuality.directLinkQualityIndex ??
              '')
          .toString(),
    ].join('|');
  }

  bool _sameWeakNetworkSuggestion(
    PlayerWeakNetworkSuggestion? left,
    PlayerWeakNetworkSuggestion? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return left.suppressionKey == right.suppressionKey &&
        left.targetQualityId == right.targetQualityId &&
        left.title == right.title &&
        left.subtitle == right.subtitle;
  }

  void _dismissWeakNetworkSuggestion() {
    final suggestion = _uiController.weakNetworkSuggestion;
    if (suggestion == null) {
      return;
    }
    _updatePlayerState(
      () => _uiController.suppressWeakNetworkSuggestion(
        suggestion.suppressionKey,
      ),
    );
  }

  Future<void> _applyWeakNetworkSuggestion() async {
    final suggestion = _uiController.weakNetworkSuggestion;
    if (suggestion == null) {
      return;
    }
    final targetQuality = _displayQualityOptionsForCurrentMode()
        .cast<PlaybackQualityOption?>()
        .firstWhere(
          (quality) =>
              quality != null &&
              _qualityId(quality) == suggestion.targetQualityId,
          orElse: () => null,
        );
    if (targetQuality == null) {
      _updatePlayerState(() => _uiController.clearWeakNetworkSuggestion());
      _showTransientMessage(
        AppLocalizations.of(context).playerQualityRecommendedExpired,
      );
      return;
    }
    _updatePlayerState(() {
      _uiController.clearWeakNetworkSuggestionSuppression();
      _uiController.clearWeakNetworkSuggestion();
    });
    await _switchQuality(
      targetQuality,
      loadingMessage: AppLocalizations.of(
        context,
      ).playerWeakNetworkSwitching(_qualityDisplayLabel(targetQuality)),
    );
  }

  void _handleOverlayControllersChanged() {
    if (!mounted) return;
    _updatePlayerState(() {});
  }

  bool _shouldCheckServerManagedPlayLink(MpvPlayerValue value) {
    if (_exitInProgress ||
        _playbackCompleted ||
        _completionActionInFlight ||
        _serverSessionRecoveryInFlight ||
        _serverManagedPlayLinkCheckInFlight) {
      return false;
    }
    if (!_playbackMode.isServerManaged) return false;
    if ((_currentPlayLink ?? '').trim().isEmpty) return false;
    if (!value.ready ||
        !value.nativeLibLoaded ||
        value.playbackPhase != MpvPlaybackPhase.playing) {
      return false;
    }
    if (_uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart) {
      return false;
    }
    final remaining =
        _completionReferenceDuration(value) - _displayPosition(value);
    if (remaining > Duration.zero && remaining <= const Duration(seconds: 20)) {
      return false;
    }
    final lastCheckAt = _lastServerManagedPlayLinkCheckAt;
    if (lastCheckAt != null &&
        DateTime.now().difference(lastCheckAt) <
            _serverManagedPlayLinkCheckCooldown) {
      return false;
    }
    return value.playbackPhase != MpvPlaybackPhase.ended;
  }

  Future<bool> _checkServerSessionExpired([FeiniuApi? api]) async {
    if (!_playbackMode.isServerManaged || !mounted || _exitInProgress) {
      return false;
    }
    final playLink = (_currentPlayLink ?? '').trim();
    if (playLink.isEmpty) return false;
    try {
      final effectiveApi = api ?? FeiniuApi(context.read<NasProvider>());
      return await effectiveApi.checkPlayLinkExpired(playLink) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkServerManagedPlayLinkIfNeeded({
    required MpvPlayerValue value,
    FeiniuApi? api,
  }) async {
    if (!_shouldCheckServerManagedPlayLink(value)) {
      return;
    }
    _serverManagedPlayLinkCheckInFlight = true;
    _lastServerManagedPlayLinkCheckAt = DateTime.now();
    try {
      if (!await _checkServerSessionExpired(api)) {
        return;
      }
      if (!mounted || _exitInProgress) return;
      final latestValue = _controller.value.value;
      await _refreshServerManagedSession(
        startPosition: _displayPosition(latestValue),
        pausedAfterReload:
            latestValue.playbackPhase != MpvPlaybackPhase.playing,
        background: latestValue.playbackPhase == MpvPlaybackPhase.playing,
      );
    } finally {
      _serverManagedPlayLinkCheckInFlight = false;
    }
  }

  Future<bool> _ensureServerSessionPlaybackReadyBeforeResume() async {
    if (!_playbackMode.isServerManaged) return false;
    if (_serverSessionRecoveryInFlight || _serverManagedPlayLinkCheckInFlight) {
      return true;
    }
    final api = FeiniuApi(context.read<NasProvider>());
    if (await _checkServerSessionExpired(api)) {
      final value = _controller.value.value;
      await _refreshServerManagedSession(
        startPosition: _displayPosition(value),
        pausedAfterReload: false,
        background: false,
      );
      return true;
    }
    return false;
  }

  Future<void> _refreshServerManagedSession({
    required Duration startPosition,
    required bool pausedAfterReload,
    required bool background,
  }) async {
    if (!mounted || _exitInProgress || !_playbackMode.isServerManaged) return;
    final playLink = (_currentPlayLink ?? '').trim();
    if (playLink.isEmpty || _serverSessionRecoveryInFlight) return;
    final now = DateTime.now();
    final lastRecoveryAt = _lastServerSessionRecoveryAt;
    if (lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < _serverSessionRecoveryCooldown) {
      return;
    }

    _serverSessionRecoveryInFlight = true;
    _lastServerSessionRecoveryAt = now;
    final currentPosition = startPosition;
    final proactive = background;

    final l10n = AppLocalizations.of(context);
    final recoveryMessage = proactive
        ? l10n.playerRefreshingPlaybackSession
        : l10n.playerPlaybackSessionExpiredRecovering;
    final failureMessagePrefix = proactive
        ? l10n.playerRefreshPlaybackSessionFailed
        : l10n.playerRecoverPlaybackSessionFailed;

    _uiController.pendingLoadingTransition = true;
    _showSubtitleSwitchMessage(recoveryMessage);
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: pausedAfterReload,
      background: background,
    );

    try {
      await _reloadServerPlaySession(
        startPosition: currentPosition,
        pausedAfterReload: pausedAfterReload,
      );
    } catch (error) {
      _cancelPendingLoadingTransition();
      _showTransientMessage(
        l10n.playerGenericError(failureMessagePrefix, '$error'),
      );
    } finally {
      _serverSessionRecoveryInFlight = false;
    }
  }

  void _setResumePromptVisibility(bool visible) {
    _overlayState.setResumePromptVisible(visible);
    if (!mounted) return;
    if (visible) {
      _showControls();
      return;
    }
    if (!_completionController.autoPlayPromptVisible && !_playbackCompleted) {
      _scheduleControlsAutoHide();
    }
  }

  void _refreshAutoplayAfterReloadIfNeeded(MpvPlayerValue value) {
    if (!_pendingReloadAutoplayRefresh) return;
    if (_uiController.pendingTransitionTargetPaused) {
      _pendingReloadAutoplayRefresh = false;
      return;
    }
    if ((value.error?.trim().isNotEmpty ?? false)) {
      _pendingReloadAutoplayRefresh = false;
      return;
    }
    if (!value.ready || !value.nativeLibLoaded) return;
    if (value.playbackPhase == MpvPlaybackPhase.paused) {
      _pendingReloadAutoplayRefresh = false;
      unawaited(_controller.play());
      return;
    }
    final transitionPlaybackState =
        _uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart;
    if (!transitionPlaybackState && !value.isTransientLoadingPhase) {
      _pendingReloadAutoplayRefresh = false;
    }
  }

  void _showSubtitleStatusTopTip() {
    // Keep subtitle switching silent. The loading overlay shown during manual
    // subtitle operations is enough feedback, and the extra top tips feel noisy.
  }

  Future<void> _refreshSubtitleSelectionIfNeeded() async {
    if (_subtitleSelectionRefreshInFlight) return;
    _subtitleSelectionRefreshInFlight = true;
    var applied = false;
    try {
      applied = await _applySubtitleSelection();
    } finally {
      if (mounted) {
        _pendingSubtitleSelectionRefresh =
            !applied && (_currentSubtitleGuid ?? '').trim().isNotEmpty;
      }
      _subtitleSelectionRefreshInFlight = false;
    }
  }

  void _loadChaptersIfNeeded([MpvPlayerValue? currentValue]) {
    final value = currentValue ?? _controller.value.value;
    if (!value.ready || !value.nativeLibLoaded) return;
    if (_uiController.chapterLoading) return;
    if (_chapterMediaGuid == _currentMediaGuid && _chapters.isNotEmpty) return;
    final mediaGuid = _currentMediaGuid;
    _uiController.chapterLoading = true;
    unawaited(() async {
      try {
        final chapters = await _controller.getChapters();
        if (!mounted) return;
        if (_currentMediaGuid != mediaGuid) {
          _uiController.chapterLoading = false;
          _loadChaptersIfNeeded();
          return;
        }
        if (chapters.isEmpty) {
          _uiController.chapterLoading = false;
          _scheduleChapterRetry(mediaGuid);
          return;
        }
        _chapterRetryTimer?.cancel();
        _updatePlayerState(() {
          _uiController.chapterLoading = false;
          _uiController.chapterRetryAttempt = 0;
          _chapterMediaGuid = mediaGuid;
          _chapters = chapters;
          _recomputeChapterSkipSegments();
        });
      } catch (_) {
        _uiController.chapterLoading = false;
        _scheduleChapterRetry(mediaGuid);
      }
    }());
  }

  void _scheduleChapterRetry(String mediaGuid) {
    _chapterRetryTimer?.cancel();
    if (_currentMediaGuid != mediaGuid) {
      _uiController.chapterRetryAttempt = 0;
      return;
    }
    if (_uiController.chapterRetryAttempt >= 2) {
      _uiController.chapterRetryAttempt = 0;
      return;
    }
    _uiController.chapterRetryAttempt += 1;
    _chapterRetryTimer = Timer(const Duration(milliseconds: 900), () {
      _chapterRetryTimer = null;
      if (!mounted ||
          _currentMediaGuid != mediaGuid ||
          _uiController.chapterLoading) {
        return;
      }
      _loadChaptersIfNeeded();
    });
  }

  void _recomputeChapterSkipSegments() {
    final duration = _effectiveDuration();
    if (_chapters.isEmpty || duration <= Duration.zero) {
      _inferredIntroSkip = null;
      _inferredOutroSkip = null;
      _syncPlayStatsOpEdSegments();
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
      return;
    }

    final intro = _inferChapterSkipSegment(
      intro: true,
      chapters: _chapters,
      duration: duration,
      maxSegmentSeconds: _introDurationSeconds,
    );
    final outro = _inferChapterSkipSegment(
      intro: false,
      chapters: _chapters,
      duration: duration,
      maxSegmentSeconds: _outroDurationSeconds,
    );
    if (_chapterSkipMode == _MpvPlayerPageState._chapterSkipModeAuto) {
      _introChapterIndex = intro?.chapterIndex;
      _outroChapterIndex = outro?.chapterIndex;
    }
    _inferredIntroSkip = intro;
    _inferredOutroSkip = outro;
    _syncPlayStatsOpEdSegments();
    final active = _uiController.activeChapterSkipPrompt;
    if (active != null &&
        intro?.key != active.key &&
        outro?.key != active.key) {
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
    }
  }

  _ChapterSkipSegment? _inferChapterSkipSegment({
    required bool intro,
    required List<MpvChapterItem> chapters,
    required Duration duration,
    required int maxSegmentSeconds,
  }) {
    if (chapters.length < 2 || duration <= Duration.zero) return null;
    const minSegment = Duration(seconds: 45);
    final maxSegment = Duration(seconds: maxSegmentSeconds.clamp(60, 240));
    _ChapterSkipSegment? best;
    int? bestScore;

    // 这里不是只看章节名命中，而是把“位置、时长、章节顺序、关键字”一起打分。
    // 这样即使源站章节名不规范，也还能大致推断出最像片头/片尾的区间。
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final start = chapter.time;
      final end = index + 1 < chapters.length
          ? chapters[index + 1].time
          : duration;
      final segmentDuration = end - start;
      if (segmentDuration < minSegment || segmentDuration > maxSegment) {
        continue;
      }
      final startFromHead = start.inSeconds;
      final startFromTail = (duration - start).inSeconds;
      final nearExpectedSide = intro
          ? startFromHead <= 360
          : startFromTail <= 420;
      if (!nearExpectedSide) {
        continue;
      }

      final lowerTitle = chapter.title.trim().toLowerCase();
      var score = 0;
      if (intro) {
        score += (360 - startFromHead).clamp(0, 360);
        if (index <= 1) {
          score += 180 - (index * 40);
        }
        if (_matchesIntroKeyword(lowerTitle)) {
          score += 500;
        }
      } else {
        score += (420 - startFromTail).clamp(0, 420);
        if (index >= chapters.length - 2) {
          score += 160;
        }
        if (_matchesOutroKeyword(lowerTitle)) {
          score += 500;
        }
      }
      final durationBias = (maxSegment.inSeconds - segmentDuration.inSeconds)
          .abs();
      score += (240 - durationBias).clamp(0, 240);

      if (bestScore == null || score > bestScore) {
        bestScore = score;
        best = _ChapterSkipSegment(
          kind: intro ? 'intro' : 'outro',
          chapterIndex: chapter.index,
          label: _chapterLabel(chapter),
          start: start,
          end: end > duration ? duration : end,
        );
      }
    }

    return best;
  }

  _ChapterSkipSegment? _chapterSegmentByIndex({
    required bool intro,
    required int? chapterIndex,
    required Duration duration,
  }) {
    if (chapterIndex == null ||
        _chapters.isEmpty ||
        duration <= Duration.zero) {
      return null;
    }
    for (var index = 0; index < _chapters.length; index++) {
      final chapter = _chapters[index];
      if (chapter.index != chapterIndex) continue;
      final end = index + 1 < _chapters.length
          ? _chapters[index + 1].time
          : duration;
      return _ChapterSkipSegment(
        kind: intro ? 'intro' : 'outro',
        chapterIndex: chapter.index,
        label: _chapterLabel(chapter),
        start: chapter.time,
        end: end > duration ? duration : end,
      );
    }
    return null;
  }

  List<_ChapterSkipSegment?> _activeSkipSegmentsForRuntime(Duration duration) {
    switch (_introOutroSourceMode) {
      case _MpvPlayerPageState._introOutroSourceModeOfficial:
        final introEnd = Duration(seconds: _officialIntroDurationSeconds);
        final introTrigger = Duration(
          seconds: introEnd.inSeconds.clamp(
            0,
            _MpvPlayerPageState._introOutroReminderLeadSeconds,
          ),
        );
        final outroStart =
            duration - Duration(seconds: _officialOutroDurationSeconds);
        final intro = _officialIntroDurationSeconds > 0
            ? _ChapterSkipSegment(
                kind: 'intro',
                chapterIndex: -1,
                label: 'Official intro',
                start: introTrigger,
                end: introEnd > duration ? duration : introEnd,
              )
            : null;
        final outro = _officialOutroDurationSeconds > 0 && outroStart < duration
            ? _ChapterSkipSegment(
                kind: 'outro',
                chapterIndex: -2,
                label: 'Official outro',
                start: outroStart.isNegative ? Duration.zero : outroStart,
                end: duration,
              )
            : null;
        return <_ChapterSkipSegment?>[intro, outro];
      case _MpvPlayerPageState._introOutroSourceModeChapter:
        if (_chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual) {
          return <_ChapterSkipSegment?>[
            _chapterSegmentByIndex(
              intro: true,
              chapterIndex: _introChapterIndex,
              duration: duration,
            ),
            _chapterSegmentByIndex(
              intro: false,
              chapterIndex: _outroChapterIndex,
              duration: duration,
            ),
          ];
        }
        return <_ChapterSkipSegment?>[_inferredIntroSkip, _inferredOutroSkip];
      default:
        return const <_ChapterSkipSegment?>[null, null];
    }
  }

  bool _matchesIntroKeyword(String title) {
    if (title.isEmpty) return false;
    return title.contains('op') ||
        title.contains('opening credits') ||
        title.contains('opening sequence') ||
        title.contains('op theme') ||
        title.contains('opening theme');
  }

  bool _matchesOutroKeyword(String title) {
    if (title.isEmpty) return false;
    return title.contains('ed') ||
        title.contains('ending credits') ||
        title.contains('outro') ||
        title.contains('ending theme') ||
        title.contains('credits');
  }

  void _handleChapterSkipRuntime(MpvPlayerValue value) {
    if (!_supportsIntroOutroUi ||
        !_introOutroEnabled ||
        _introOutroSourceMode == _MpvPlayerPageState._introOutroSourceModeOff ||
        !value.ready ||
        value.playbackPhase != MpvPlaybackPhase.playing) {
      return;
    }
    final position = value.position;
    final duration = _effectiveDuration();
    final segments = _activeSkipSegmentsForRuntime(duration);

    if (_uiController.activeChapterSkipPrompt != null) {
      _syncActiveChapterSkipPrompt(position);
    }

    for (final segment in segments) {
      if (segment == null) continue;
      if (_completedChapterSkipKeys.contains(segment.key) ||
          _dismissedChapterSkipKeys.contains(segment.key)) {
        continue;
      }
      if (position >= segment.end) {
        _completedChapterSkipKeys.add(segment.key);
        continue;
      }
      final leadStart =
          segment.start -
          const Duration(
            seconds: _MpvPlayerPageState._introOutroReminderLeadSeconds,
          );
      final effectiveLeadStart = leadStart.isNegative
          ? Duration.zero
          : leadStart;
      // 片头如果从 0 秒开始，就没有“提前几秒弹提示”的空间，
      // 这里允许它在播放进入片段后立即出现一次提示。
      if (position < effectiveLeadStart || position >= segment.start) {
        if (segment.start == Duration.zero &&
            position < segment.end &&
            !_completedChapterSkipKeys.contains(segment.key) &&
            !_dismissedChapterSkipKeys.contains(segment.key) &&
            _uiController.activeChapterSkipPrompt?.key != segment.key) {
          _showChapterSkipPrompt(segment, currentPosition: position);
          break;
        }
        continue;
      }
      if (_uiController.activeChapterSkipPrompt?.key == segment.key) {
        break;
      }
      _showChapterSkipPrompt(segment, currentPosition: position);
      break;
    }
  }

  void _showChapterSkipPrompt(
    _ChapterSkipSegment segment, {
    required Duration currentPosition,
  }) {
    if (!_supportsIntroOutroUi) {
      return;
    }
    final countdown = segment.start <= Duration.zero
        ? _MpvPlayerPageState._introOutroReminderLeadSeconds
        : (segment.start - currentPosition).inSeconds.ceil().clamp(
            1,
            _MpvPlayerPageState._introOutroReminderLeadSeconds,
          );
    if (!mounted) {
      _uiController.activeChapterSkipPrompt = segment;
      _skipPromptCountdownSeconds = countdown;
      return;
    }
    _updatePlayerState(() {
      _uiController.activeChapterSkipPrompt = segment;
      _skipPromptCountdownSeconds = countdown;
    });
  }

  void _syncActiveChapterSkipPrompt(Duration currentPosition) {
    final prompt = _uiController.activeChapterSkipPrompt;
    if (prompt == null) return;
    final leadStart =
        prompt.start -
        const Duration(
          seconds: _MpvPlayerPageState._introOutroReminderLeadSeconds,
        );
    if (_dismissedChapterSkipKeys.contains(prompt.key) ||
        _completedChapterSkipKeys.contains(prompt.key)) {
      _clearActiveChapterSkipPrompt();
      return;
    }
    if (currentPosition < leadStart) {
      _clearActiveChapterSkipPrompt();
      return;
    }
    if (currentPosition >= prompt.end) {
      _completedChapterSkipKeys.add(prompt.key);
      _clearActiveChapterSkipPrompt();
      return;
    }
    final remaining = (prompt.start - currentPosition).inSeconds.ceil();
    if (remaining <= 0) {
      _clearActiveChapterSkipPrompt();
      unawaited(_performChapterSkip(prompt));
      return;
    }
    if (remaining == _skipPromptCountdownSeconds) {
      return;
    }
    if (!mounted) {
      _skipPromptCountdownSeconds = remaining;
      return;
    }
    _updatePlayerState(() => _skipPromptCountdownSeconds = remaining);
  }

  Future<void> _performChapterSkip(PlayerChapterSkipSegment segment) async {
    if (_introOutroSkipInFlight ||
        _completedChapterSkipKeys.contains(segment.key)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    _introOutroSkipInFlight = true;
    try {
      _completedChapterSkipKeys.add(segment.key);
      final target = segment.end > Duration.zero ? segment.end : segment.start;
      _playStatsSessionController.recordOpEdSkip(intro: segment.isIntro);
      await _seekWithStats(target, userInitiated: false);
      if (mounted) {
        _showStatusMessage(
          segment.isIntro ? l10n.playerIntroSkipped : l10n.playerOutroSkipped,
          hideAfter: const Duration(milliseconds: 1500),
        );
      }
    } finally {
      _introOutroSkipInFlight = false;
    }
  }

  void _dismissCurrentChapterSkipPrompt() {
    final prompt = _uiController.activeChapterSkipPrompt;
    if (prompt == null) return;
    _playStatsSessionController.recordOpEdDismiss(intro: prompt.isIntro);
    _dismissedChapterSkipKeys.add(prompt.key);
    _clearActiveChapterSkipPrompt();
    _showStatusMessage(
      AppLocalizations.of(context).playerChapterSkipPromptDismissed,
    );
  }

  void _clearActiveChapterSkipPrompt() {
    if (!mounted) {
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
      return;
    }
    _updatePlayerState(() {
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
    });
  }

  void _showCenterPopupMessage(String message, {Duration? hideAfter}) {
    _centerPopupTimer?.cancel();
    if (!mounted) {
      _uiController.centerPopupMessage = null;
      _uiController.statusMessage = message;
      return;
    }
    _updatePlayerState(() => _uiController.centerPopupMessage = null);
    _showStatusMessage(
      message,
      hideAfter: hideAfter ?? const Duration(seconds: 2),
    );
  }

  void _syncCacheDownloadability(
    MpvPlayerValue value,
    Duration effectiveDuration,
  ) {
    if (!_canImportCurrentPlaybackCache()) {
      if (_cacheDownloadAvailable || _cacheCompletionTipShown) {
        _updatePlayerState(() {
          _cacheDownloadAvailable = false;
          _cacheCompletionTipShown = false;
        });
      }
      return;
    }
    if (_cacheDownloadAvailable || _cacheDownloadCheckInFlight) {
      return;
    }
    if (!value.ready ||
        !value.nativeLibLoaded ||
        effectiveDuration <= Duration.zero) {
      return;
    }
    final bufferedPosition = value.bufferedPosition;
    if (bufferedPosition <= Duration.zero) return;
    if (bufferedPosition + const Duration(seconds: 2) < effectiveDuration) {
      return;
    }
    unawaited(_refreshCacheDownloadability(showCompletionTipWhenReady: true));
  }

  bool _canImportCurrentPlaybackCache() {
    if (_externalLocalSource) return false;
    if (_cacheDownloadConsumedForSource) return false;
    if (_currentSourceIsDownloadedFile) return false;
    final normalizedUrl = _currentUrl.trim().toLowerCase();
    if (normalizedUrl.startsWith('file:')) return false;
    return _currentItemGuid.trim().isNotEmpty &&
        _currentMediaGuid.trim().isNotEmpty &&
        _currentVideoGuid.trim().isNotEmpty;
  }

  Future<void> _refreshCacheDownloadability({
    bool showCompletionTipWhenReady = false,
    bool force = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (!_canImportCurrentPlaybackCache()) {
      if (_cacheDownloadAvailable || _cacheCompletionTipShown) {
        _updatePlayerState(() {
          _cacheDownloadAvailable = false;
          _cacheCompletionTipShown = false;
        });
      }
      return;
    }
    if (_cacheDownloadCheckInFlight && !force) return;
    final checkToken = ++_cacheDownloadCheckToken;
    _cacheDownloadCheckInFlight = true;
    final identity = CachedMediaSourceIdentity(
      itemGuid: _currentItemGuid.trim(),
      mediaGuid: _currentMediaGuid.trim(),
      videoGuid: _currentVideoGuid.trim(),
      resourceKey: (_activeCacheResourceKey ?? '').trim(),
    );
    try {
      final result = await StorageManagementService.instance
          .canPromoteCachedMedia(identity);
      if (!mounted || checkToken != _cacheDownloadCheckToken) return;
      final available = result.found && result.downloadable;
      _updatePlayerState(() {
        _cacheDownloadAvailable = available;
        if (!available) {
          _cacheCompletionTipShown = false;
        } else if (showCompletionTipWhenReady && !_cacheCompletionTipShown) {
          _cacheCompletionTipShown = true;
        }
      });
      if (available && showCompletionTipWhenReady && _cacheCompletionTipShown) {
        _showCenterPopupMessage(l10n.playerCacheFullyAvailable);
      }
    } catch (_) {
      if (!mounted || checkToken != _cacheDownloadCheckToken) return;
      _updatePlayerState(() => _cacheDownloadAvailable = false);
    } finally {
      if (mounted && checkToken == _cacheDownloadCheckToken) {
        _updatePlayerState(() => _cacheDownloadCheckInFlight = false);
      } else {
        _cacheDownloadCheckInFlight = false;
      }
    }
  }

  Future<void> _importCurrentPlaybackCacheToDownload() async {
    if (_cacheDownloadImportInFlight) return;
    final l10n = AppLocalizations.of(context);
    await _refreshCacheDownloadability(force: true);
    if (!mounted) return;
    if (!_cacheDownloadAvailable) {
      _showTopTip(
        l10n.playerCacheNotReadyForDownload,
        context.appColors.warning,
      );
      return;
    }
    _updatePlayerState(() => _cacheDownloadImportInFlight = true);
    try {
      final nasProvider = context.read<NasProvider>();
      final provider = nasProvider.isConfigured ? nasProvider : null;
      final result = await DownloadTaskService.instance.importCachedMedia(
        provider: provider,
        identity: CachedMediaSourceIdentity(
          itemGuid: _currentItemGuid.trim(),
          mediaGuid: _currentMediaGuid.trim(),
          videoGuid: _currentVideoGuid.trim(),
          resourceKey: (_activeCacheResourceKey ?? '').trim(),
        ),
        resolution: _currentResolution.trim(),
        title: _currentTitle.trim().isNotEmpty
            ? _currentTitle.trim()
            : l10n.playerCurrentVideo,
        groupId: _currentDownloadGroupId(),
        groupTitle: _currentDownloadGroupTitle(),
        durationText: _formatDuration(_effectiveDuration()),
        posterUrls: _resolveSystemPlaybackArtworkUrls(),
        groupPosterUrls: _resolveSystemPlaybackArtworkUrls(),
        subtitleTrack: _currentSubtitleTrack(),
        subtitleFilePath:
            _subtitleFileByGuid[_currentSubtitleTrack()?.guid.trim() ?? ''],
      );
      if (!mounted) return;
      if (result == null) {
        _showTopTip(l10n.playerCacheImportFailed, context.appColors.warning);
        return;
      }
      switch (result.state) {
        case DownloadStartState.importedFromCache:
          _updatePlayerState(() {
            _cacheDownloadAvailable = false;
            _cacheDownloadConsumedForSource = true;
          });
          _showTopTip(
            l10n.playerCacheImportedToDownload,
            context.appColors.success,
          );
          break;
        case DownloadStartState.downloaded:
          _updatePlayerState(() {
            _cacheDownloadAvailable = false;
            _cacheDownloadConsumedForSource = true;
          });
          _showTopTip(
            l10n.playerAlreadyInDownloadList,
            context.appColors.success,
          );
          break;
        case DownloadStartState.downloading:
        case DownloadStartState.started:
          _showTopTip(
            l10n.playerAddingToDownloadList,
            context.appColors.accent,
          );
          break;
      }
    } catch (_) {
      if (!mounted) return;
      _showTopTip(l10n.playerCacheImportFailed, context.appColors.warning);
    } finally {
      if (mounted) {
        _updatePlayerState(() => _cacheDownloadImportInFlight = false);
      } else {
        _cacheDownloadImportInFlight = false;
      }
    }
  }

  String _currentDownloadGroupId() {
    final seasonGuid = _currentSeasonGuid.trim();
    if (seasonGuid.isNotEmpty) return seasonGuid;
    final itemGuid = _currentItemGuid.trim();
    if (itemGuid.isNotEmpty) return itemGuid;
    return _currentMediaGuid.trim();
  }

  String _currentDownloadGroupTitle() {
    final seriesTitle = _currentSeriesTitle.trim();
    if (seriesTitle.isNotEmpty && _currentSeasonNumber > 0) {
      return '$seriesTitle ${AppLocalizations.of(context).playerEpisodeSeasonTemplate(_currentSeasonNumber.toString())}';
    }
    if (seriesTitle.isNotEmpty) return seriesTitle;
    final title = _currentTitle.trim();
    if (title.isNotEmpty) return title;
    return AppLocalizations.of(context).playerCurrentVideo;
  }

  void _showStatusMessage(String message, {Duration? hideAfter}) {
    _statusMessageTimer?.cancel();
    if (!mounted) return;
    _updatePlayerState(() => _uiController.statusMessage = message);
    if (hideAfter == null || hideAfter <= Duration.zero) {
      return;
    }
    _statusMessageTimer = Timer(hideAfter, () {
      if (!mounted) return;
      _updatePlayerState(() => _uiController.statusMessage = null);
    });
  }

  String _chapterLabel(MpvChapterItem chapter) {
    final title = chapter.title.trim();
    return title.isNotEmpty ? title : 'Chapter ${chapter.index + 1}';
  }

  void _showControls() {
    if (!mounted) return;
    if (_playbackSettingsDrawerVisible) return;
    _overlayState.showControls();
    unawaited(_syncEffectiveSubtitlePosition());
    _scheduleControlsAutoHide();
  }

  bool _isLandscapeViewport() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    return view.physicalSize.width > view.physicalSize.height;
  }

  Future<void> _applySystemUiForOrientation(
    bool landscape, {
    bool force = false,
  }) async {
    if (widget.parallelLayoutMode == 'split') {
      await _setPlayerImmersiveMode(false);
      if (!mounted) return;
      final immersiveStatusBar = context
          .read<ParallelWindowSettingsProvider>()
          .immersiveStatusBar;
      return _setSystemUiModeIfNeeded(
        immersiveStatusBar
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
        force: force && immersiveStatusBar && landscape,
      );
    }
    await _setPlayerImmersiveMode(true);
    return _setSystemUiModeIfNeeded(SystemUiMode.immersiveSticky, force: force);
  }

  Future<void> _setSystemUiModeIfNeeded(
    SystemUiMode mode, {
    bool force = false,
  }) async {
    if (!force && _lastAppliedSystemUiMode == mode) {
      return;
    }
    _lastAppliedSystemUiMode = mode;
    try {
      await SystemChrome.setEnabledSystemUIMode(mode);
    } catch (_) {
      if (_lastAppliedSystemUiMode == mode) {
        _lastAppliedSystemUiMode = null;
      }
    }
  }

  Future<void> _setPlayerOrientationMode(String mode) async {
    if (!Platform.isAndroid) return;
    try {
      await _MpvPlayerPageState._systemChannel.invokeMethod<void>(
        'setPlayerOrientation',
        <String, String>{'mode': mode},
      );
    } catch (_) {}
  }

  Future<void> _setPlayerImmersiveMode(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (_lastAppliedPlayerImmersiveMode == enabled) {
      return;
    }
    _lastAppliedPlayerImmersiveMode = enabled;
    try {
      await _MpvPlayerPageState._systemChannel.invokeMethod<void>(
        'setPlayerImmersiveMode',
        <String, bool>{'enabled': enabled},
      );
    } catch (_) {
      if (_lastAppliedPlayerImmersiveMode == enabled) {
        _lastAppliedPlayerImmersiveMode = null;
      }
    }
  }

  Future<void> _togglePlayerOrientation() async {
    final l10n = AppLocalizations.of(context);
    final systemMultiWindowActive =
        await PlayerHostBridge.isSystemMultiWindowActive();
    if (widget.parallelLayoutToggleEnabled && !systemMultiWindowActive) {
      final currentPosition =
          _uiController.draggingPosition ?? _controller.value.value.position;
      final source = _buildCurrentSource(
        startPosition: currentPosition,
        loadNonce: _issueNextLoadNonce(),
      );
      final targetMode = widget.parallelLayoutMode == 'split'
          ? 'fullscreen'
          : 'split';
      final onParallelLayoutModeChanged = widget.onParallelLayoutModeChanged;
      if (onParallelLayoutModeChanged != null) {
        onParallelLayoutModeChanged(targetMode);
        return;
      }
      final switched = await PlayerHostBridge.switchPlayerLayoutMode(
        title: _currentTitle,
        source: source.toMap(),
        initialPlayInfo: widget.initialPlayInfo,
        startSource: widget.startSource,
        targetMode: targetMode,
        result: _buildPlayerReturnData(),
      );
      if (switched) {
        return;
      }
      _showCenterPopupMessage(l10n.playerLayoutSwitchFailed);
      return;
    }
    final switchToLandscape = !_isLandscapeViewport();
    _updatePlayerState(_uiController.beginOrientationChange);
    _resumeAfterLifecyclePause = false;
    await _setPlayerOrientationMode(
      switchToLandscape ? 'landscape' : 'portrait',
    );
    await _applySystemUiForOrientation(switchToLandscape, force: true);
    if (!mounted) return;
    _showControls();
  }

  Future<void> _lockPlayerUi() async {
    if (_playerUiLocked) return;
    _hideSpeedDialOverlay(restoreAutoHide: false);
    for (var index = 0; index < 6; index += 1) {
      final dismissed = await _dismissActiveTransientUi();
      if (!dismissed) {
        break;
      }
    }
    if (!mounted) {
      _playerUiLocked = true;
      return;
    }
    _updatePlayerState(() {
      _playerUiLocked = true;
    });
    _showControls();
    _showCenterPopupMessage(
      AppLocalizations.of(context).playerUiLocked,
      hideAfter: const Duration(seconds: 1),
    );
  }

  Future<void> _unlockPlayerUi() async {
    if (!_playerUiLocked) return;
    if (!mounted) {
      _playerUiLocked = false;
      return;
    }
    _updatePlayerState(() {
      _playerUiLocked = false;
    });
    _showCenterPopupMessage(
      AppLocalizations.of(context).playerUiUnlocked,
      hideAfter: const Duration(seconds: 1),
    );
    _showControls();
  }

  void _startPlayerSystemStatusTicker() {
    _playerSystemStatusTimer?.cancel();
    unawaited(_refreshPlayerSystemStatus());
    _playerSystemStatusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshPlayerSystemStatus()),
    );
  }

  String _formatPlayerSystemClock(DateTime now) {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _refreshPlayerSystemStatus() async {
    final nextTimeLabel = _formatPlayerSystemClock(DateTime.now());
    var nextNetworkType = _playerSystemNetworkType;
    var nextBatteryLevel = _playerSystemBatteryLevel;
    var nextCharging = _playerSystemCharging;
    if (Platform.isAndroid) {
      try {
        final raw = await _MpvPlayerPageState._systemChannel
            .invokeMapMethod<String, dynamic>('getPlayerStatusSnapshot');
        if (raw != null) {
          nextNetworkType = (raw['networkType'] ?? 'unknown').toString().trim();
          final rawBatteryLevel = raw['batteryLevel'];
          nextBatteryLevel = switch (rawBatteryLevel) {
            int value => value,
            num value => value.toInt(),
            _ => int.tryParse('$rawBatteryLevel'),
          };
          nextCharging = raw['charging'] == true;
        }
      } catch (_) {}
    }
    if (!mounted) {
      _playerSystemTimeLabel = nextTimeLabel;
      _playerSystemNetworkType = nextNetworkType;
      _playerSystemBatteryLevel = nextBatteryLevel;
      _playerSystemCharging = nextCharging;
      return;
    }
    final changed =
        _playerSystemTimeLabel != nextTimeLabel ||
        _playerSystemNetworkType != nextNetworkType ||
        _playerSystemBatteryLevel != nextBatteryLevel ||
        _playerSystemCharging != nextCharging;
    if (!changed) return;
    _updatePlayerState(() {
      _playerSystemTimeLabel = nextTimeLabel;
      _playerSystemNetworkType = nextNetworkType;
      _playerSystemBatteryLevel = nextBatteryLevel;
      _playerSystemCharging = nextCharging;
    });
  }

  void _toggleControls() {
    if (!mounted) return;
    if (_controlsVisible) {
      _hideControlsAnimated();
      return;
    }
    _showControls();
  }

  void _hideControlsAnimated() {
    _controlsTimer?.cancel();
    final hadVisibleControls = _controlsVisible || _controlsAnimatingOut;
    if (!hadVisibleControls) return;
    _overlayState.hideImmediately();
    unawaited(_syncEffectiveSubtitlePosition());
  }

  void _hideControlsImmediately() {
    _controlsTimer?.cancel();
    final hadVisibleControls = _controlsVisible || _controlsAnimatingOut;
    if (!hadVisibleControls) return;
    _overlayState.hideImmediately();
    unawaited(_syncEffectiveSubtitlePosition());
  }

  void _scheduleControlsAutoHide() {
    _controlsTimer?.cancel();
    final value = _controller.value.value;
    if (!value.ready) return;
    if (_completionController.autoPlayPromptVisible ||
        _playbackCompleted ||
        _speedDialVisible) {
      _overlayState.cancelAutoHide();
      return;
    }
    _overlayState.scheduleAutoHide(
      ready: value.ready,
      gestureSeekActive: _gestureSeekActive,
      onTimeout: _hideControlsAnimated,
    );
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _hideControlsAnimated();
    });
  }

  Future<void> _submitPlaybackRecord({bool force = false}) async {
    if (_externalLocalSource) return;
    if (_currentItemGuid.isEmpty ||
        _currentMediaGuid.isEmpty ||
        _currentVideoGuid.isEmpty) {
      return;
    }
    final value = _controller.value.value;
    final ts = value.position.inSeconds;
    final duration = _durationSeconds > 0
        ? _durationSeconds
        : value.duration.inSeconds;
    if (duration <= 0) return;
    if (!force && ts <= 0) return;
    if (!force && ts == _uiController.lastRecordedSecond) return;
    _uiController.lastRecordedSecond = ts;
    final nasProvider = _nasProvider;
    if (nasProvider == null) return;
    try {
      final api = FeiniuApi(nasProvider);
      await api.recordPlayback(
        itemGuid: _currentItemGuid,
        mediaGuid: _currentMediaGuid,
        videoGuid: _currentVideoGuid,
        audioGuid: _normalizedAudioGuid(),
        subtitleGuid: _normalizedSubtitleGuid(),
        resolution: _currentResolution,
        bitrate: _currentBitrate,
        ts: ts.clamp(0, duration),
        duration: duration,
        playLink: _currentPlayLink,
      );
      if (!force) {
        await _checkServerManagedPlayLinkIfNeeded(value: value, api: api);
      }
    } catch (error, stackTrace) {
      debugPrint('[MPV][RECORD] report failed error=$error');
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'record playback',
          source: 'mpv_player_runtime',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid mediaGuid=$_currentMediaGuid',
        ),
      );
    }
  }

  Future<void> _submitPlaybackRecordAndFlushStats() async {
    try {
      await _submitPlaybackRecord();
    } finally {
      await _flushPlayStatsSnapshot('periodic');
    }
  }

  Future<void> _flushPlayStatsSnapshot(String reason) async {
    if (_externalLocalSource) return;
    if (_playStatsCurrentVideoId.isEmpty) return;
    try {
      await _playStatsSessionController.flushPlayback(reason: reason);
    } catch (error, stackTrace) {
      debugPrint('[MPV][PLAY_STATS] flush failed error=$error');
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'flush play stats snapshot',
          source: 'mpv_player_runtime',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          level: AppLogLevel.warning,
          details: 'videoId=$_playStatsCurrentVideoId reason=$reason',
        ),
      );
    }
  }

  Future<void> _togglePlayback({bool revealControls = true}) async {
    final l10n = AppLocalizations.of(context);
    if (revealControls) {
      _showControls();
    }
    final value = _controller.value.value;
    final suppressPauseReveal =
        !revealControls && value.playbackPhase == MpvPlaybackPhase.playing;
    if (suppressPauseReveal) {
      _uiController.suppressControlsRevealOnNextPause = true;
    }
    if (value.playbackPhase == MpvPlaybackPhase.paused &&
        await _ensureServerSessionPlaybackReadyBeforeResume()) {
      if (suppressPauseReveal) {
        _uiController.suppressControlsRevealOnNextPause = false;
      }
      return;
    }
    if (value.playbackPhase == MpvPlaybackPhase.paused &&
        _shouldReloadSourceBeforeResume()) {
      _showSubtitleSwitchMessage(l10n.playerReloadRequiredRecovering);
      _uiController.pendingLoadingTransition = true;
      _markAwaitingVisualPlaybackStart(
        _displayPosition(value),
        targetPaused: false,
      );
      await _reloadCurrentSource(forcePlay: true);
      return;
    }
    try {
      await _controller.togglePlayback();
    } catch (_) {
      if (suppressPauseReveal) {
        _uiController.suppressControlsRevealOnNextPause = false;
      }
      rethrow;
    }
  }

  bool _shouldReloadSourceBeforeResume() {
    return false;
  }

  Future<void> _reloadCurrentSource({bool forcePlay = false}) async {
    final currentPosition =
        _uiController.draggingPosition ?? _controller.value.value.position;
    _prepareSubtitleSelectionForPlayerReconfigure();
    final source = _buildCurrentSource(
      startPosition: currentPosition,
      loadNonce: _issueNextLoadNonce(),
    );
    final paused = forcePlay
        ? false
        : _controller.value.value.playbackPhase != MpvPlaybackPhase.playing;
    await _prepareAndReloadSource(
      source,
      paused: paused,
      visualStartPosition: source.startPosition,
      targetPaused:
          !forcePlay &&
          _controller.value.value.playbackPhase != MpvPlaybackPhase.playing,
    );
    _scheduleDeferredSubtitleSelectionRefresh();
  }

  void _showTransientMessage(String message) {
    if (!mounted) return;
    _showTopTip(message, _transientMessageColor(message));
  }

  Color _transientMessageColor(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return context.appColors.warning;
    }
    final dangerHints = <String>[
      'failed',
      'failure',
      'error',
      'unsupported',
      'missing',
      AppLocalizations.of(context).playerErrorHintFailed,
      AppLocalizations.of(context).playerErrorHintError,
      AppLocalizations.of(context).playerErrorHintUnavailable,
      AppLocalizations.of(context).playerErrorHintMissing,
      AppLocalizations.of(context).playerErrorHintNone,
      AppLocalizations.of(context).playerErrorHintNotLoaded,
      AppLocalizations.of(context).playerErrorHintNotExtracted,
    ];
    for (final hint in dangerHints) {
      if (normalized.contains(hint)) {
        return context.appColors.danger;
      }
    }
    return context.appColors.warning;
  }

  void _showTopTip(String message, Color color, {bool revealControls = false}) {
    if (!mounted) return;
    if (revealControls) {
      _showControls();
    }
    _topTip.show(context, message: message, color: color);
  }

  PlayDetailPlayerReturnData _buildPlayerReturnData() {
    final currentValue = _controller.value.value;
    final currentTsSeconds = _displayPosition(currentValue).inSeconds;
    final matchingRefreshData = _hasFreshPrefetchedReturnDetailData()
        ? _prefetchedReturnDetailData
        : null;
    return PlayDetailPlayerReturnData(
      itemGuid: _currentItemGuid,
      currentTsSeconds: currentTsSeconds < 0 ? 0 : currentTsSeconds,
      refreshData: matchingRefreshData,
      parentItemGuid: _currentSeasonGuid.trim().isEmpty
          ? null
          : _currentSeasonGuid.trim(),
      canPopToParent: _currentSeasonGuid.trim().isNotEmpty,
    );
  }

  Future<void> _closePlayer() async {
    if (_exitInProgress) return;
    if (mounted) {
      _updatePlayerState(() => _exitInProgress = true);
    } else {
      _exitInProgress = true;
    }
    await _finishPlayStatsSession('close');
    await _stopSystemPlaybackSession();
    await _flushPlaybackRecordOnExit();
    final returnData = _buildPlayerReturnData();
    if (!mounted) return;
    final closeRequested = widget.onCloseRequested;
    if (closeRequested != null) {
      await closeRequested(returnData);
      return;
    }
    Navigator.of(context).pop(returnData);
  }

  Future<void> _flushPlaybackRecordOnExit() async {
    if (_exitPlaybackRecordQueued) return;
    _exitPlaybackRecordQueued = true;
    await _submitPlaybackRecord(force: true);
  }

  bool _hasFreshPrefetchedReturnDetailData() {
    final itemGuid = _currentItemGuid.trim();
    if (itemGuid.isEmpty || itemGuid == widget.source.itemGuid.trim()) {
      return false;
    }
    if (_prefetchedReturnDetailData == null) return false;
    if (_prefetchedReturnDetailItemGuid != itemGuid) return false;
    if (_prefetchedReturnDetailMediaGuid != _currentMediaGuid.trim()) {
      return false;
    }
    if ((_prefetchedReturnDetailAudioGuid ?? '').trim() !=
        (_currentAudioGuid ?? '').trim()) {
      return false;
    }
    if ((_prefetchedReturnDetailSubtitleGuid ?? '').trim() !=
        (_currentSubtitleGuid ?? '').trim()) {
      return false;
    }
    return true;
  }

  void _invalidateReturnDetailPrefetch() {
    _returnDetailPrefetchGeneration++;
    _prefetchedReturnDetailData = null;
    _prefetchedReturnDetailItemGuid = '';
    _prefetchedReturnDetailMediaGuid = '';
    _prefetchedReturnDetailAudioGuid = null;
    _prefetchedReturnDetailSubtitleGuid = null;
  }

  Future<void> _prefetchReturnDetailDataIfNeeded() async {
    if (_externalLocalSource) {
      _invalidateReturnDetailPrefetch();
      return;
    }
    final itemGuid = _currentItemGuid.trim();
    final sourceItemGuid = widget.source.itemGuid.trim();
    if (itemGuid.isEmpty || itemGuid == sourceItemGuid) {
      _invalidateReturnDetailPrefetch();
      return;
    }
    final mediaGuid = _currentMediaGuid.trim();
    if (mediaGuid.isEmpty) return;
    final audioGuid = (_currentAudioGuid ?? '').trim();
    final subtitleGuid = (_currentSubtitleGuid ?? '').trim();
    if (_prefetchedReturnDetailData != null &&
        _prefetchedReturnDetailItemGuid == itemGuid &&
        _prefetchedReturnDetailMediaGuid == mediaGuid &&
        (_prefetchedReturnDetailAudioGuid ?? '').trim() == audioGuid &&
        (_prefetchedReturnDetailSubtitleGuid ?? '').trim() == subtitleGuid) {
      return;
    }
    final generation = ++_returnDetailPrefetchGeneration;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final refreshed = await PlayDetailDataLoader(api)
          .refreshAfterItemStateChange(
            itemGuid: itemGuid,
            currentMediaGuid: mediaGuid,
            currentSubtitleGuid: subtitleGuid.isEmpty ? null : subtitleGuid,
            currentAudioGuid: audioGuid.isEmpty ? null : audioGuid,
          );
      if (!mounted || generation != _returnDetailPrefetchGeneration) return;
      if (_currentItemGuid.trim() != itemGuid ||
          _currentMediaGuid.trim() != mediaGuid) {
        return;
      }
      _prefetchedReturnDetailData = refreshed;
      _prefetchedReturnDetailItemGuid = itemGuid;
      _prefetchedReturnDetailMediaGuid = mediaGuid;
      _prefetchedReturnDetailAudioGuid = audioGuid;
      _prefetchedReturnDetailSubtitleGuid = subtitleGuid;
    } catch (_) {
      if (generation != _returnDetailPrefetchGeneration) return;
      _prefetchedReturnDetailData = null;
      _prefetchedReturnDetailItemGuid = '';
      _prefetchedReturnDetailMediaGuid = '';
      _prefetchedReturnDetailAudioGuid = null;
      _prefetchedReturnDetailSubtitleGuid = null;
    }
  }

  void _syncPerformanceOverlayPolling() {
    final wantsPolling = _runtimeController.wantsPerformanceOverlayPolling(
      performanceOverlayEnabled: _performanceOverlayEnabled,
      playerReady: _controller.value.value.nativeLibLoaded,
    );
    if (!wantsPolling) {
      _performanceOverlayTimer?.cancel();
      _performanceOverlayTimer = null;
      final currentStats = _performanceOverlayStatsNotifier.value;
      final hasStats =
          currentStats.cpuUsagePercent != null ||
          currentStats.appMemoryUsedBytes != null ||
          currentStats.systemMemoryTotalBytes != null;
      if (hasStats) {
        _performanceOverlayStatsNotifier.value =
            MpvPerformanceOverlayStats.empty;
      }
      return;
    }
    if (_performanceOverlayTimer != null) {
      return;
    }
    unawaited(_refreshPerformanceOverlayStats());
    _performanceOverlayTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_refreshPerformanceOverlayStats()),
    );
  }

  Future<void> _refreshPerformanceOverlayStats() async {
    if (!mounted) return;
    if (!_runtimeController.wantsPerformanceOverlayPolling(
      performanceOverlayEnabled: _performanceOverlayEnabled,
      playerReady: _controller.value.value.nativeLibLoaded,
    )) {
      return;
    }
    final stats = await _controller.getPerformanceOverlayStats();
    if (!mounted) return;
    if (_runtimeController.samePerformanceOverlayStats(
      _performanceOverlayStatsNotifier.value,
      stats,
    )) {
      return;
    }
    _performanceOverlayStatsNotifier.value = stats;
  }
}
