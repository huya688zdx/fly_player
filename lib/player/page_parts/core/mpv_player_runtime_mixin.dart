part of mpv_player_page;

class _ChapterSkipSegment extends PlayerChapterSkipSegment {
  const _ChapterSkipSegment({
    required String kind,
    required int chapterIndex,
    required String label,
    required Duration start,
    required Duration end,
  }) : super(
         kind: kind,
         chapterIndex: chapterIndex,
         label: label,
         start: start,
         end: end,
       );
}

extension _MpvPlayerRuntimeMixin on _MpvPlayerPageState {
  void _hydrateFromSource(MpvMediaSource source) {
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
    _subtitleController.resetForSourceChange(
      pendingSelectionRefresh: (_currentSubtitleGuid ?? '').trim().isNotEmpty,
    );
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
    _overlayState.setResumePromptVisible(
      _shouldShowResumePrompt(
        startPosition: _resumeStartPosition,
        durationSeconds: source.durationSeconds,
      ),
    );
    _syncDanmakuMediaContext();
    unawaited(
      _startOrUpdateSystemPlaybackSession(forceStart: true, force: true),
    );
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

  Future<void> _loadInitialPlayerPreferences() async {
    final preferences = await _runtimePreferencesStore.load();
    if (!mounted) {
      _settingsController.applyRuntimePreferences(preferences);
      _performanceOverlayOffsetNotifier.value =
          preferences.performanceOverlayOffset;
      return;
    }
    _updatePlayerState(() {
      _settingsController.applyRuntimePreferences(preferences);
      _performanceOverlayOffsetNotifier.value =
          preferences.performanceOverlayOffset;
    });
    _syncPerformanceOverlayPolling();
    _recomputeChapterSkipSegments();
    await _controller.setMpvAdvancedSettings(
      _effectiveMpvSettings(preferences.mpvSettings),
    );
  }

  Future<void> _setAutoPlayEnabled(bool enabled) async {
    await _runtimePreferencesStore.setBool(
      _MpvPlayerPageState._autoPlayPrefKey,
      enabled,
    );
    if (!mounted) return;
    _updatePlayerState(() => _autoPlayEnabled = enabled);
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
      targetPaused: _controller.value.value.paused,
    );
    await _reloadCurrentSource(forcePlay: !_controller.value.value.paused);
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
    _syncPerformanceOverlayPolling();
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

  Future<void> _setMpvAdvancedSettingsPreset(
    Map<String, String> presetSettings,
  ) async {
    final next = Map<String, String>.from(
      _MpvPlayerPageState._defaultMpvSettings,
    );
    for (final entry in presetSettings.entries) {
      if (!_MpvPlayerPageState._defaultMpvSettings.containsKey(entry.key)) {
        continue;
      }
      final normalized = entry.value.trim();
      if (normalized.isEmpty) continue;
      next[entry.key] = normalized;
    }
    for (final entry in next.entries) {
      await _runtimePreferencesStore.setString(
        '${_MpvPlayerPageState._mpvSettingPrefPrefix}${entry.key}',
        entry.value,
      );
    }
    if (!mounted) {
      _mpvSettings = next;
      return;
    }
    _updatePlayerState(() => _mpvSettings = next);
    _prepareSubtitleSelectionForPlayerReconfigure();
    await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
    _scheduleDeferredSubtitleSelectionRefresh();
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
        ? '软件解码'
        : '硬件解码';
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
    unawaited(_controller.setMpvAdvancedSettings(_effectiveMpvSettings()));
    _syncPerformanceOverlayPolling();
    _replacePlayerSource(widget.source);
  }

  void _resetSourceLoadTransitionState() {
    _videoLoadingOverlayTimer?.cancel();
    _videoLoadingOverlayTimer = null;
    _uiController.resetSourceLoadTransitionState();
  }

  Future<void> _prepareAndReloadSource(
    MpvMediaSource source, {
    required bool paused,
    required Duration visualStartPosition,
    required bool targetPaused,
    String? statusText,
  }) async {
    _markAwaitingVisualPlaybackStart(
      visualStartPosition,
      targetPaused: targetPaused,
    );
    _controller.prepareForSourceLoad(
      source,
      paused: paused,
      statusText: statusText ?? 'Preparing player',
    );
    await _controller.setMpvAdvancedSettings(_effectiveMpvSettings());
    await _controller.reload(source);
  }

  void _replacePlayerSource(MpvMediaSource incomingSource) {
    final source = incomingSource.loadNonce > 0
        ? incomingSource
        : incomingSource.copyWith(loadNonce: _issueNextLoadNonce());
    _resetSourceLoadTransitionState();
    _hydrateFromSource(source);
    _clearPlaybackCompletionState();
    _pendingReloadAutoplayRefresh = true;
    _overlayState.setResumePromptVisible(false);
    unawaited(
      _prepareAndReloadSource(
        source,
        paused: false,
        visualStartPosition: source.startPosition,
        targetPaused: false,
        statusText: '正在准备播放',
      ),
    );
    unawaited(_refreshPlayerStateAfterSourceReplace());
    if (_subtitleShouldUseExternalFile(_currentSubtitleTrack())) {
      unawaited(_applySubtitleSelection());
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
    final currentStatusText = value.statusText.trim();
    final statusReaction = _runtimeController.consumeStatusText(
      currentStatusText: currentStatusText,
      now: DateTime.now(),
      subtitleStatusTipSuppressedUntil: _subtitleStatusTipSuppressedUntil,
      autoFilterFallbackStatusText:
          _MpvPlayerPageState._autoFilterFallbackStatusText,
    );
    _gestureController.acknowledgeSeekPosition(value.position);
    _syncVisualPlaybackStartState(value);
    _refreshAutoplayAfterReloadIfNeeded(value);
    _syncVideoLoadingOverlayVisibility(value);
    if (statusReaction.showAutoFilterFallbackTip) {
      _showStatusMessage(
        '\u68c0\u6d4b\u5230\u5e27\u7387\u4e0d\u7a33\u5b9a\uff0c\u5df2\u81ea\u52a8\u5173\u95ed\u6ee4\u955c',
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
    unawaited(_startOrUpdateSystemPlaybackSession());
    final pausedChanged = value.paused != _uiController.wasPaused;
    _uiController.wasPaused = value.paused;
    final transitionPlaybackState =
        _uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart;
    if (transitionPlaybackState) {
      if (!value.paused && _uiController.draggingPosition == null) {
        _scheduleControlsAutoHide();
      }
    } else if (value.paused && pausedChanged) {
      _showControls();
    } else if (!value.paused && pausedChanged) {
      if (_uiController.draggingPosition == null) {
        _scheduleControlsAutoHide();
      }
    } else if (!value.paused && _uiController.draggingPosition == null) {
      _scheduleControlsAutoHide();
    }
    final pendingPath = _pendingExternalSubtitlePath;
    _loadChaptersIfNeeded(value);
    _handleChapterSkipRuntime(value);
    if (_pendingSubtitleSelectionRefresh &&
        value.nativeLibLoaded &&
        value.ready &&
        pendingPath == null) {
      unawaited(_refreshSubtitleSelectionIfNeeded());
    }
    if (pendingPath == null || !value.nativeLibLoaded || !value.ready) {
      return;
    }
    _pendingExternalSubtitlePath = null;
    unawaited(_controller.setExternalSubtitleFile(pendingPath));
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
    if (value.paused) {
      _pendingReloadAutoplayRefresh = false;
      unawaited(_controller.play());
      return;
    }
    final status = value.statusText.trim().toLowerCase();
    final transitionPlaybackState =
        _uiController.pendingLoadingTransition ||
        _uiController.qualitySwitchLoading ||
        _uiController.awaitingVisualPlaybackStart;
    if (!transitionPlaybackState && !_loadingStatusTexts.contains(status)) {
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
        setState(() {
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
        value.paused) {
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
          Duration(seconds: _MpvPlayerPageState._introOutroReminderLeadSeconds);
      final effectiveLeadStart = leadStart.isNegative
          ? Duration.zero
          : leadStart;
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
    setState(() {
      _uiController.activeChapterSkipPrompt = segment;
      _skipPromptCountdownSeconds = countdown;
    });
  }

  void _syncActiveChapterSkipPrompt(Duration currentPosition) {
    final prompt = _uiController.activeChapterSkipPrompt;
    if (prompt == null) return;
    final leadStart =
        prompt.start -
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

  Future<void> _performChapterSkip(PlayerChapterSkipSegment segment) async {
    if (_introOutroSkipInFlight ||
        _completedChapterSkipKeys.contains(segment.key)) {
      return;
    }
    _introOutroSkipInFlight = true;
    try {
      _completedChapterSkipKeys.add(segment.key);
      final target = segment.end > Duration.zero ? segment.end : segment.start;
      await _controller.seek(target);
      if (mounted) {
        _showCenterPopupMessage(
          segment.isIntro ? '已跳过片头' : '已跳过片尾',
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
    _dismissedChapterSkipKeys.add(prompt.key);
    _clearActiveChapterSkipPrompt();
    _showCenterPopupMessage(
      '本次播放已忽略跳过提示，如需关闭可在设置中禁用片头片尾跳过。',
    );
  }

  void _clearActiveChapterSkipPrompt() {
    if (!mounted) {
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
      return;
    }
    setState(() {
      _uiController.activeChapterSkipPrompt = null;
      _skipPromptCountdownSeconds = 0;
    });
  }

  void _showCenterPopupMessage(String message, {Duration? hideAfter}) {
    _centerPopupTimer?.cancel();
    final duration = hideAfter ?? const Duration(seconds: 2);
    if (!mounted) {
      _uiController.centerPopupMessage = message;
      return;
    }
    setState(() => _uiController.centerPopupMessage = message);
    _centerPopupTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _uiController.centerPopupMessage = null);
    });
  }

  void _showStatusMessage(String message, {Duration? hideAfter}) {
    _statusMessageTimer?.cancel();
    if (!mounted) return;
    setState(() => _uiController.statusMessage = message);
    if (hideAfter == null || hideAfter <= Duration.zero) {
      return;
    }
    _statusMessageTimer = Timer(hideAfter, () {
      if (!mounted) return;
      setState(() => _uiController.statusMessage = null);
    });
  }

  String _chapterLabel(MpvChapterItem chapter) {
    final title = chapter.title.trim();
    return title.isNotEmpty ? title : 'Chapter ${chapter.index + 1}';
  }

  Future<void> _seekToChapter(MpvChapterItem chapter, Duration duration) async {
    if (duration <= Duration.zero) return;
    final target = chapter.time > duration ? duration : chapter.time;
    _showControls();
    _showStatusMessage(
      '正在跳转到第 ${_chapterLabel(chapter)} 章...',
      hideAfter: const Duration(milliseconds: 900),
    );
    await _controller.seek(target);
    if (!mounted) return;
    _showControls();
  }

  void _showControls() {
    if (!mounted) return;
    if (_playbackSettingsDrawerVisible) return;
    final changed = _overlayState.showControls();
    if (changed) {
      setState(() {});
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
    if (widget.parallelLayoutMode == 'split') {
      final immersiveStatusBar =
          context.read<ParallelWindowSettingsProvider>().immersiveStatusBar;
      return _setSystemUiModeIfNeeded(
        immersiveStatusBar
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      );
    }
    final showSystemBars = controlsVisible ?? _controlsVisible;
    return _setSystemUiModeIfNeeded(
      showSystemBars ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
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

  Future<void> _togglePlayerOrientation() async {
    if (widget.parallelLayoutToggleEnabled) {
      final currentPosition =
          _uiController.draggingPosition ?? _controller.value.value.position;
      final source = _buildCurrentSource(
        startPosition: currentPosition,
        loadNonce: _issueNextLoadNonce(),
      );
      final targetMode = widget.parallelLayoutMode == 'split'
          ? 'fullscreen'
          : 'split';
      final switched = await PlayerHostBridge.switchPlayerLayoutMode(
        title: _currentTitle,
        source: source.toMap(),
        targetMode: targetMode,
        result: _buildPlayerReturnData(),
      );
      if (switched) {
        widget.onParallelLayoutModeChanged?.call(targetMode);
        return;
      }
      _showCenterPopupMessage('切换播放布局失败');
      return;
    }
    final switchToLandscape = !_isLandscapeViewport();
    setState(_uiController.beginOrientationChange);
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
    final hadVisibleControls = _controlsVisible || _controlsAnimatingOut;
    if (!hadVisibleControls) return;
    _overlayState.hideImmediately();
    unawaited(
      _applySystemUiForOrientation(
        _isLandscapeViewport(),
        controlsVisible: false,
      ),
    );
    setState(() {});
  }

  void _hideControlsImmediately() {
    _controlsTimer?.cancel();
    final hadVisibleControls = _controlsVisible || _controlsAnimatingOut;
    if (!hadVisibleControls) return;
    _overlayState.hideImmediately();
    setState(() {});
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
      );
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

  Future<void> _togglePlayback() async {
    _showControls();
    final value = _controller.value.value;
    if (value.paused && _shouldReloadSourceBeforeResume()) {
      _showSubtitleSwitchMessage('当前播放需要重新加载，正在为您恢复播放，请稍候...');
      _uiController.pendingLoadingTransition = true;
      _markAwaitingVisualPlaybackStart(
        _displayPosition(value),
        targetPaused: false,
      );
      await _reloadCurrentSource(forcePlay: true);
      return;
    }
    await _controller.togglePlayback();
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
    final paused = forcePlay ? false : _controller.value.value.paused;
    await _prepareAndReloadSource(
      source,
      paused: paused,
      visualStartPosition: source.startPosition,
      targetPaused: !forcePlay && _controller.value.value.paused,
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
    const dangerHints = <String>[
      'failed',
      'failure',
      'error',
      'unsupported',
      'missing',
      '失败',
      '错误',
      '不可',
      '缺少',
      '暂无',
      '未加载',
      '未提取',
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
    final returnData = _buildPlayerReturnData();
    unawaited(_flushPlaybackRecordOnExit());
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
      fpsOverlayEnabled: _fpsOverlayEnabled,
      playerReady: _controller.value.value.nativeLibLoaded,
    );
    if (!wantsPolling) {
      _performanceOverlayTimer?.cancel();
      _performanceOverlayTimer = null;
      final currentStats = _performanceOverlayStatsNotifier.value;
      final hasStats =
          currentStats.cpuUsagePercent != null ||
          currentStats.gpuUsagePercent != null ||
          currentStats.estimatedVfFps != null ||
          currentStats.containerFps != null ||
          currentStats.displayFps != null;
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
      fpsOverlayEnabled: _fpsOverlayEnabled,
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
