part of 'mpv_player_page.dart';

class _ChapterSkipSegment {
  final String kind;
  final int chapterIndex;
  final String label;
  final Duration start;
  final Duration end;

  const _ChapterSkipSegment({
    required this.kind,
    required this.chapterIndex,
    required this.label,
    required this.start,
    required this.end,
  });

  String get key => '$kind:$chapterIndex:${start.inMilliseconds}:${end.inMilliseconds}';

  bool get isIntro => kind == 'intro';
}

extension _MpvPlayerRuntimeMixin on _MpvPlayerPageState {
  void _hydrateFromSource(MpvMediaSource source) {
    _chapterRetryTimer?.cancel();
    _centerPopupTimer?.cancel();
    _serverFallbackSubtitleGuids.clear();
    _subtitleFailureNoticeShownGuids.clear();
    _dismissedChapterSkipKeys.clear();
    _completedChapterSkipKeys.clear();
    _currentItemGuid = source.itemGuid;
    _currentTitle = source.title;
    _currentSeasonGuid = source.seasonGuid;
    _currentEpisodeNumber = source.episodeNumber;
    _currentMediaGuid = source.mediaGuid;
    _subtitleSourceMediaGuid = source.mediaGuid;
    _currentVideoGuid = source.videoGuid;
    _currentVideoWidth = source.videoWidth;
    _currentVideoHeight = source.videoHeight;
    _currentVideoCodecName = source.videoCodecName;
    _currentVideoProfile = source.videoProfile;
    _currentColorSpace = source.colorSpace;
    _currentColorTransfer = source.colorTransfer;
    _currentColorPrimaries = source.colorPrimaries;
    _currentBitDepth = source.bitDepth;
    _activeProxySessionId = source.proxySessionId;
    _activeSubtitleProxySessionId = null;
    _currentPlayLink = source.playLink;
    _currentUrl = source.url;
    _currentHeaders = Map<String, String>.from(source.headers);
    _currentReliableSeek = source.reliableSeek;
    _currentSeekProbeSummary = source.seekProbeSummary;
    _currentAudioGuid = source.audioTrackGuid;
    _currentSubtitleGuid = source.subtitleTrackGuid;
    _currentResolution = source.resolution;
    _currentBitrate = source.bitrate;
    _durationSeconds = source.durationSeconds;
    _chapterMediaGuid = '';
    _chapters = const <MpvChapterItem>[];
    _chapterLoading = false;
    _serverPlaybackManaged = source.serverPlaybackManaged;
    _resumeStartPosition = _completionController.normalizedStartPosition(
      startPosition: source.startPosition,
      durationSeconds: source.durationSeconds,
    );
    _playbackSpeed = source.playbackSpeed;
    _introOutroConfigGuid = '';
    _introOutroConfigLoaded = false;
    _introChapterIndex = null;
    _outroChapterIndex = null;
    _officialIntroDurationSeconds = 0;
    _officialOutroDurationSeconds = 0;
    _inferredIntroSkip = null;
    _inferredOutroSkip = null;
    _activeChapterSkipPrompt = null;
    _centerPopupMessage = null;
    _skipPromptCountdownSeconds = 0;
    _introOutroSkipInFlight = false;
    _audioTracks = List<AudioTrackOption>.from(source.audioTracks);
    _subtitleTracks = List<SubtitleTrackOption>.from(source.subtitleTracks);
    _qualities = List<PlaybackQualityOption>.from(source.qualities);
    _overlayState.setResumePromptVisible(
      _shouldShowResumePrompt(
        startPosition: _resumeStartPosition,
        durationSeconds: source.durationSeconds,
      ),
    );
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  PlayerSourceSnapshot _currentSourceSnapshot() {
    return PlayerSourceSnapshot(
      itemGuid: _currentItemGuid,
      mediaGuid: _currentMediaGuid,
      subtitleSourceMediaGuid: _subtitleSourceMediaGuid,
      videoGuid: _currentVideoGuid,
      audioGuid: _currentAudioGuid,
      subtitleGuid: _currentSubtitleGuid,
      resolution: _currentResolution,
      bitrate: _currentBitrate,
      videoWidth: _currentVideoWidth,
      videoHeight: _currentVideoHeight,
      currentHeaders: _currentHeaders,
      activeProxySessionId: _activeProxySessionId,
      activeSubtitleProxySessionId: _activeSubtitleProxySessionId,
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      qualities: _qualities,
      serverPlaybackManaged: _serverPlaybackManaged,
      serverFallbackSubtitleGuids: _serverFallbackSubtitleGuids,
    );
  }

  Duration _displayPosition(MpvPlayerValue value) {
    return _draggingPosition ??
        _gestureController.displayPosition(value.position);
  }

  Duration _effectiveDuration() {
    final value = _controller.value.value;
    return value.duration > Duration.zero
        ? value.duration
        : Duration(seconds: _durationSeconds);
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      const <String, dynamic>{},
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _loadAutoPlayPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_MpvPlayerPageState._autoPlayPrefKey) ?? true;
    if (!mounted) {
      _autoPlayEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _autoPlayEnabled = enabled);
  }

  Future<void> _setAutoPlayEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_MpvPlayerPageState._autoPlayPrefKey, enabled);
    if (!mounted) return;
    _updatePlayerState(() => _autoPlayEnabled = enabled);
  }

  Future<void> _loadAutoRotatePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(_MpvPlayerPageState._autoRotatePrefKey) ?? true;
    if (!mounted) {
      _autoRotateEnabled = enabled;
      return;
    }
    _updatePlayerState(() => _autoRotateEnabled = enabled);
  }

  Future<void> _setAutoRotateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_MpvPlayerPageState._autoRotatePrefKey, enabled);
    if (!mounted) return;
    _updatePlayerState(() => _autoRotateEnabled = enabled);
  }

  Future<void> _loadDecoderModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final mode =
        prefs.getString(_MpvPlayerPageState._decoderModePrefKey) ??
        _MpvPlayerPageState._decoderModeHardware;
    _decoderMode = mode == _MpvPlayerPageState._decoderModeSoftware
        ? _MpvPlayerPageState._decoderModeSoftware
        : _MpvPlayerPageState._decoderModeHardware;
  }

  Future<void> _setDecoderModePreference(String mode) async {
    final normalized = mode == _MpvPlayerPageState._decoderModeSoftware
        ? _MpvPlayerPageState._decoderModeSoftware
        : _MpvPlayerPageState._decoderModeHardware;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_MpvPlayerPageState._decoderModePrefKey, normalized);
    _decoderMode = normalized;
    await _controller.setDecoderMode(normalized);
  }

  Future<void> _loadDisplayAspectRatioPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _displayAspectRatioMode =
        prefs.getString(_MpvPlayerPageState._displayAspectRatioPrefKey) ??
        _MpvPlayerPageState._displayAspectRatioFit;
  }

  Future<void> _setDisplayAspectRatioPreference(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_MpvPlayerPageState._displayAspectRatioPrefKey, mode);
    _displayAspectRatioMode = mode;
    await _controller.setDisplayAspectRatioMode(mode);
  }

  Future<void> _loadIntroOutroConfigForItem(String itemGuid) async {
    final normalizedItemGuid = itemGuid.trim();
    if (normalizedItemGuid.isEmpty) return;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final info = await api.getPlayInfo(normalizedItemGuid);
      if (!mounted || _currentItemGuid != normalizedItemGuid) return;
      final config = info.playConfig;
      final resolvedConfigGuid = _resolveIntroOutroConfigGuid(info);
      final skipOpening = _normalizedIntroOutroSkipValue(config?.skipOpening) ?? 0;
      final skipEnding = _normalizedIntroOutroSkipValue(config?.skipEnding) ?? 0;
      _updatePlayerState(() {
        _introOutroConfigGuid = resolvedConfigGuid;
        _officialIntroDurationSeconds = skipOpening;
        _officialOutroDurationSeconds = skipEnding;
      });
    } catch (_) {}
  }

  Future<void> _syncIntroOutroConfigToServer({bool? enabled}) async {
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

  bool _isIntroOutroConfigEnabled({
    required int? skipOpening,
    required int? skipEnding,
  }) {
    if (skipOpening == null && skipEnding == null) return false;
    return !(skipOpening == 0 && skipEnding == 0);
  }

  Future<void> _loadIntroOutroPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(_MpvPlayerPageState._introOutroEnabledPrefKey) ?? false;
    final sourceMode =
        prefs.getString(_MpvPlayerPageState._introOutroSourceModePrefKey) ??
        _MpvPlayerPageState._introOutroSourceModeOff;
    final chapterMode =
        prefs.getString(_MpvPlayerPageState._introOutroChapterModePrefKey) ??
        _MpvPlayerPageState._chapterSkipModeAuto;
    final introMax =
        prefs.getInt(_MpvPlayerPageState._introOutroIntroMaxPrefKey) ?? 180;
    final outroMax =
        prefs.getInt(_MpvPlayerPageState._introOutroOutroMaxPrefKey) ?? 180;
    final normalizedSourceMode = enabled
        ? _normalizeIntroOutroSourceMode(sourceMode)
        : _MpvPlayerPageState._introOutroSourceModeOff;
    final normalizedChapterMode = _normalizeChapterSkipMode(chapterMode);
    if (!mounted) {
      _introOutroEnabled = normalizedSourceMode !=
          _MpvPlayerPageState._introOutroSourceModeOff;
      _introOutroSourceMode = normalizedSourceMode;
      _chapterSkipMode = normalizedChapterMode;
      _introOutroMode = normalizedChapterMode;
      _introDurationSeconds = introMax.clamp(60, 240);
      _outroDurationSeconds = outroMax.clamp(60, 240);
      _introOutroConfigLoaded = true;
      return;
    }
    _updatePlayerState(() {
      _introOutroEnabled = normalizedSourceMode !=
          _MpvPlayerPageState._introOutroSourceModeOff;
      _introOutroSourceMode = normalizedSourceMode;
      _chapterSkipMode = normalizedChapterMode;
      _introOutroMode = normalizedChapterMode;
      _introDurationSeconds = introMax.clamp(60, 240);
      _outroDurationSeconds = outroMax.clamp(60, 240);
      _introOutroConfigLoaded = true;
    });
    _recomputeChapterSkipSegments();
  }

  Future<void> _persistIntroOutroPreferences({bool? enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveSourceMode = enabled == false
        ? _MpvPlayerPageState._introOutroSourceModeOff
        : _introOutroSourceMode;
    await prefs.setBool(
      _MpvPlayerPageState._introOutroEnabledPrefKey,
      effectiveSourceMode != _MpvPlayerPageState._introOutroSourceModeOff,
    );
    await prefs.setString(
      _MpvPlayerPageState._introOutroSourceModePrefKey,
      effectiveSourceMode,
    );
    await prefs.setString(
      _MpvPlayerPageState._introOutroChapterModePrefKey,
      _chapterSkipMode,
    );
    await prefs.setInt(
      _MpvPlayerPageState._introOutroIntroMaxPrefKey,
      _introDurationSeconds.clamp(60, 240),
    );
    await prefs.setInt(
      _MpvPlayerPageState._introOutroOutroMaxPrefKey,
      _outroDurationSeconds.clamp(60, 240),
    );
  }

  String _normalizeIntroOutroSourceMode(String? value) {
    switch (value) {
      case _MpvPlayerPageState._introOutroSourceModeOfficial:
      case _MpvPlayerPageState._introOutroSourceModeChapter:
      case _MpvPlayerPageState._introOutroSourceModeOff:
        return value!;
      default:
        return _MpvPlayerPageState._introOutroSourceModeOff;
    }
  }

  String _normalizeChapterSkipMode(String? value) {
    switch (value) {
      case _MpvPlayerPageState._chapterSkipModeManual:
      case _MpvPlayerPageState._chapterSkipModeAuto:
        return value!;
      default:
        return _MpvPlayerPageState._chapterSkipModeAuto;
    }
  }

  String _decoderModeLabel([String? mode]) {
    final normalized =
        (mode ?? _decoderMode) == _MpvPlayerPageState._decoderModeSoftware
        ? _MpvPlayerPageState._decoderModeSoftware
        : _MpvPlayerPageState._decoderModeHardware;
    return normalized == _MpvPlayerPageState._decoderModeSoftware
        ? '软解码'
        : '硬解码';
  }

  String _displayAspectRatioLabel([String? mode]) {
    switch (mode ?? _displayAspectRatioMode) {
      case _MpvPlayerPageState._displayAspectRatioFill:
        return '填充';
      case _MpvPlayerPageState._displayAspectRatio4x3:
        return '4:3';
      case _MpvPlayerPageState._displayAspectRatio16x9:
        return '16:9';
      case _MpvPlayerPageState._displayAspectRatio21x9:
        return '21:9';
      default:
        return '适应';
    }
  }

  Future<void> _setDisplayAspectRatioMode(String mode) async {
    await _setDisplayAspectRatioPreference(mode);
    if (!mounted) return;
    _updatePlayerState(() => _displayAspectRatioMode = mode);
  }

  void _handlePlatformViewCreated(int viewId) {
    _controller.attach(viewId);
    unawaited(_controller.setDecoderMode(_decoderMode));
    unawaited(_controller.setDisplayAspectRatioMode(_displayAspectRatioMode));
    final source = _buildCurrentSource(startPosition: _resumeStartPosition);
    _controller.prepareForSourceLoad(
      source,
      paused: _controller.value.value.paused,
    );
    unawaited(_controller.reload(source));
    if (_currentSubtitleTrack()?.isExternal == 1) {
      unawaited(_applySubtitleSelection());
    }
  }

  void _handlePlayerValueChanged() {
    final value = _controller.value.value;
    _gestureController.acknowledgeSeekPosition(value.position);
    _syncVideoLoadingOverlayVisibility(value);
    final pausedChanged = value.paused != _wasPaused;
    _wasPaused = value.paused;
    if (value.paused && pausedChanged) {
      _showControls();
    } else if (!value.paused && _draggingPosition == null) {
      _scheduleControlsAutoHide();
    }
    final pendingPath = _pendingExternalSubtitlePath;
    _loadChaptersIfNeeded(value);
    _handleChapterSkipRuntime(value);
    if (pendingPath == null || !value.nativeLibLoaded || !value.ready) {
      return;
    }
    _pendingExternalSubtitlePath = null;
    unawaited(_controller.setExternalSubtitleFile(pendingPath));
  }

  void _loadChaptersIfNeeded([MpvPlayerValue? currentValue]) {
    final value = currentValue ?? _controller.value.value;
    if (!value.ready || !value.nativeLibLoaded) return;
    if (_chapterLoading) return;
    if (_chapterMediaGuid == _currentMediaGuid && _chapters.isNotEmpty) return;
    final mediaGuid = _currentMediaGuid;
    _chapterLoading = true;
    unawaited(() async {
      try {
        final chapters = await _controller.getChapters();
        debugPrint(
          'chapter-debug flutter media=$_currentMediaGuid count=${chapters.length} '
          'times=${chapters.map((chapter) => '${chapter.index}:${chapter.time.inMilliseconds}').join(',')}',
        );
        if (!mounted) return;
        if (_currentMediaGuid != mediaGuid) {
          _chapterLoading = false;
          _loadChaptersIfNeeded();
          return;
        }
        if (chapters.isEmpty) {
          _chapterLoading = false;
          _scheduleChapterRetry(mediaGuid);
          return;
        }
        _chapterRetryTimer?.cancel();
        setState(() {
          _chapterLoading = false;
          _chapterMediaGuid = mediaGuid;
          _chapters = chapters;
          _recomputeChapterSkipSegments();
        });
      } catch (_) {
        _chapterLoading = false;
        _scheduleChapterRetry(mediaGuid);
      }
    }());
  }

  void _scheduleChapterRetry(String mediaGuid) {
    _chapterRetryTimer?.cancel();
    _chapterRetryTimer = Timer(const Duration(milliseconds: 900), () {
      _chapterRetryTimer = null;
      if (!mounted || _currentMediaGuid != mediaGuid || _chapterLoading) {
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
      _activeChapterSkipPrompt = null;
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
    final active = _activeChapterSkipPrompt;
    if (active != null &&
        intro?.key != active.key &&
        outro?.key != active.key) {
      _activeChapterSkipPrompt = null;
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
    final minSegment = const Duration(seconds: 45);
    final maxSegment = Duration(seconds: maxSegmentSeconds.clamp(60, 240));
    _ChapterSkipSegment? best;
    int? bestScore;

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
    if (chapterIndex == null || _chapters.isEmpty || duration <= Duration.zero) {
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
        final outroStart = duration - Duration(seconds: _officialOutroDurationSeconds);
        final intro = _officialIntroDurationSeconds > 0
            ? _ChapterSkipSegment(
                kind: 'intro',
                chapterIndex: -1,
                label: '官方片头',
                start: introTrigger,
                end: introEnd > duration ? duration : introEnd,
              )
            : null;
        final outro = _officialOutroDurationSeconds > 0 &&
                outroStart < duration
            ? _ChapterSkipSegment(
                kind: 'outro',
                chapterIndex: -2,
                label: '官方片尾',
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
        title.contains('opening') ||
        title.contains('片头') ||
        title.contains('op主题') ||
        title.contains('opening theme');
  }

  bool _matchesOutroKeyword(String title) {
    if (title.isEmpty) return false;
    return title.contains('ed') ||
        title.contains('ending') ||
        title.contains('片尾') ||
        title.contains('ending theme') ||
        title.contains('credits');
  }

  void _handleChapterSkipRuntime(MpvPlayerValue value) {
    if (!_introOutroEnabled ||
        _introOutroSourceMode == _MpvPlayerPageState._introOutroSourceModeOff ||
        !value.ready ||
        value.paused) {
      return;
    }
    final position = value.position;
    final duration = _effectiveDuration();
    final segments = _activeSkipSegmentsForRuntime(duration);

    if (_activeChapterSkipPrompt != null) {
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
      final leadStart = segment.start -
          Duration(seconds: _MpvPlayerPageState._introOutroReminderLeadSeconds);
      final effectiveLeadStart =
          leadStart.isNegative ? Duration.zero : leadStart;
      if (position < effectiveLeadStart || position >= segment.start) {
        if (segment.start == Duration.zero &&
            position < segment.end &&
            !_completedChapterSkipKeys.contains(segment.key) &&
            !_dismissedChapterSkipKeys.contains(segment.key) &&
            _activeChapterSkipPrompt?.key != segment.key) {
          _showChapterSkipPrompt(segment, currentPosition: position);
          break;
        }
        continue;
      }
      if (_activeChapterSkipPrompt?.key == segment.key) {
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
    final countdown = segment.start <= Duration.zero
        ? _MpvPlayerPageState._introOutroReminderLeadSeconds
        : (segment.start - currentPosition).inSeconds.ceil().clamp(
            1,
            _MpvPlayerPageState._introOutroReminderLeadSeconds,
          );
    if (!mounted) {
      _activeChapterSkipPrompt = segment;
      _skipPromptCountdownSeconds = countdown;
      return;
    }
    setState(() {
      _activeChapterSkipPrompt = segment;
      _skipPromptCountdownSeconds = countdown;
    });
  }

  void _syncActiveChapterSkipPrompt(Duration currentPosition) {
    final prompt = _activeChapterSkipPrompt;
    if (prompt == null) return;
    final leadStart = prompt.start -
        Duration(seconds: _MpvPlayerPageState._introOutroReminderLeadSeconds);
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
    setState(() => _skipPromptCountdownSeconds = remaining);
  }

  Future<void> _performChapterSkip(_ChapterSkipSegment segment) async {
    if (_introOutroSkipInFlight || _completedChapterSkipKeys.contains(segment.key)) {
      return;
    }
    _introOutroSkipInFlight = true;
    try {
      _completedChapterSkipKeys.add(segment.key);
      final target = segment.end > Duration.zero ? segment.end : segment.start;
      await _controller.seek(target);
      if (mounted) {
        _showCenterPopupMessage(
          segment.isIntro ? '已为您跳过片头' : '已为您跳过片尾',
          hideAfter: const Duration(milliseconds: 1500),
        );
      }
    } finally {
      _introOutroSkipInFlight = false;
    }
  }

  void _dismissCurrentChapterSkipPrompt() {
    final prompt = _activeChapterSkipPrompt;
    if (prompt == null) return;
    _dismissedChapterSkipKeys.add(prompt.key);
    _clearActiveChapterSkipPrompt();
    _showCenterPopupMessage('本次跳过已关闭，如果需要关闭跳过 OPED 功能，请在设置关闭');
  }

  void _clearActiveChapterSkipPrompt() {
    if (!mounted) {
      _activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
      return;
    }
    setState(() {
      _activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
    });
  }

  void _showCenterPopupMessage(String message, {Duration? hideAfter}) {
    _centerPopupTimer?.cancel();
    final duration = hideAfter ?? const Duration(seconds: 2);
    if (!mounted) {
      _centerPopupMessage = message;
      return;
    }
    setState(() => _centerPopupMessage = message);
    _centerPopupTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _centerPopupMessage = null);
    });
  }

  void _showStatusMessage(String message, {Duration? hideAfter}) {
    _statusMessageTimer?.cancel();
    if (!mounted) return;
    setState(() => _statusMessage = message);
    if (hideAfter == null || hideAfter <= Duration.zero) {
      return;
    }
    _statusMessageTimer = Timer(hideAfter, () {
      if (!mounted) return;
      setState(() => _statusMessage = null);
    });
  }

  String _chapterLabel(MpvChapterItem chapter) {
    final title = chapter.title.trim();
    return title.isNotEmpty ? title : '第${chapter.index + 1}章';
  }

  Future<void> _seekToChapter(MpvChapterItem chapter, Duration duration) async {
    if (duration <= Duration.zero) return;
    final target = chapter.time > duration ? duration : chapter.time;
    _showControls();
    _showStatusMessage(
      '正在切换到 ${_chapterLabel(chapter)}...',
      hideAfter: const Duration(milliseconds: 900),
    );
    await _controller.seek(target);
    if (!mounted) return;
    _showControls();
  }

  void _showControls() {
    if (!mounted) return;
    _overlayState.showControls();
    if (!_controlsVisible || _controlsAnimatingOut) {
      setState(() {
        _controlsVisible = true;
        _controlsAnimatingOut = false;
      });
    }
    unawaited(
      _applySystemUiForOrientation(
        _isLandscapeViewport(),
        controlsVisible: true,
      ),
    );
    _scheduleControlsAutoHide();
  }

  bool _isLandscapeViewport() {
    final media = MediaQuery.maybeOf(context);
    if (media != null) {
      return media.orientation == Orientation.landscape;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    return view.physicalSize.width > view.physicalSize.height;
  }

  Future<void> _applySystemUiForOrientation(
    bool landscape, {
    bool? controlsVisible,
  }) {
    final showSystemBars = controlsVisible ?? _controlsVisible;
    return SystemChrome.setEnabledSystemUIMode(
      showSystemBars ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
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

  Future<void> _togglePlayerOrientation() async {
    final switchToLandscape = !_isLandscapeViewport();
    setState(() {
      _orientationChangeInProgress = true;
      _orientationTransitionMaskVisible = true;
    });
    _resumeAfterLifecyclePause = false;
    await _setPlayerOrientationMode(
      switchToLandscape ? 'landscape' : 'portrait',
    );
    await _applySystemUiForOrientation(switchToLandscape);
    if (!mounted) return;
    _showControls();
  }

  void _updatePlayerState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _syncVideoLoadingOverlayVisibility();
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
    _overlayState.beginHide();
    if (!_controlsVisible && !_controlsAnimatingOut) return;
    setState(() {
      _controlsVisible = false;
      _controlsAnimatingOut = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (!mounted || _controlsVisible) return;
      _overlayState.finishHide();
      setState(() => _controlsAnimatingOut = false);
      unawaited(
        _applySystemUiForOrientation(
          _isLandscapeViewport(),
          controlsVisible: false,
        ),
      );
    });
  }

  void _hideControlsImmediately() {
    _controlsTimer?.cancel();
    _overlayState.hideImmediately();
    if (!_controlsVisible && !_controlsAnimatingOut) return;
    setState(() {
      _controlsVisible = false;
      _controlsAnimatingOut = false;
    });
  }

  void _scheduleControlsAutoHide() {
    _controlsTimer?.cancel();
    final value = _controller.value.value;
    if (!value.ready) return;
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
    if (!force && ts == _lastRecordedSecond) return;
    _lastRecordedSecond = ts;
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
      );
    } catch (error) {
      debugPrint('[MPV][RECORD] report failed error=$error');
    }
  }

  Future<void> _togglePlayback() async {
    _showControls();
    await _controller.togglePlayback();
  }

  Future<void> _reloadCurrentSource() async {
    _showControls();
    final currentPosition =
        _draggingPosition ?? _controller.value.value.position;
    final source = _buildCurrentSource(startPosition: currentPosition);
    _controller.prepareForSourceLoad(
      source,
      paused: _controller.value.value.paused,
    );
    await _controller.reload(source);
  }

  void _showTransientMessage(String message) {
    if (!mounted) return;
    _showControls();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
