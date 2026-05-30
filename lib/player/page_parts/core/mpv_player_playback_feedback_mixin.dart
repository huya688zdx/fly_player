part of '../../mpv_player_page.dart';

const Duration _videoLoadingOverlayShowDelay = Duration(milliseconds: 260);

extension _MpvPlayerPlaybackFeedbackMixin on _MpvPlayerPageState {
  void _finishPendingLoadingTransition({
    Duration hideDelay = const Duration(milliseconds: 900),
  }) {
    final hadTransitionState =
        _uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart ||
        _uiController.qualitySwitchLoading ||
        _uiController.backgroundLoadingTransition;
    if (!hadTransitionState) {
      return;
    }
    _uiController.pendingLoadingTransition = false;
    _uiController.awaitingVisualPlaybackStart = false;
    _uiController.allowPlaybackProgressTransitionCompletion = false;
    _uiController.backgroundLoadingTransition = false;
    _uiController.pendingTransitionTargetPaused = false;
    if (mounted) {
      _updatePlayerState(() => _uiController.qualitySwitchLoading = false);
    } else {
      _uiController.qualitySwitchLoading = false;
    }
    _completionController.clearPlaybackCompletionSuppression();
    _hideSubtitleSwitchMessage(delay: hideDelay);
  }

  void _cancelPendingLoadingTransition({
    Duration hideDelay = const Duration(milliseconds: 900),
  }) {
    _uiController.awaitingVisualPlaybackStart = false;
    _uiController.allowPlaybackProgressTransitionCompletion = false;
    _uiController.backgroundLoadingTransition = false;
    _uiController.pendingTransitionTargetPaused = false;
    _finishPendingLoadingTransition(hideDelay: hideDelay);
  }

  void _markAwaitingVisualPlaybackStart(
    Duration anchorPosition, {
    required bool targetPaused,
    bool background = false,
  }) {
    _completionController.beginPlaybackCompletionSuppression();
    _uiController.markAwaitingVisualPlaybackStart(
      anchorPosition,
      targetPaused: targetPaused,
      background: background,
    );
    _syncVideoLoadingOverlayVisibility();
  }

  void _enablePlaybackProgressTransitionCompletion({
    required bool targetPaused,
  }) {
    if (targetPaused) return;
    _uiController.allowPlaybackProgressTransitionCompletion = true;
  }

  void _syncVisualPlaybackStartState(MpvPlayerValue value) {
    if (!_uiController.awaitingVisualPlaybackStart) {
      return;
    }
    final hasVisibleError =
        (value.error?.trim().isNotEmpty ?? false) &&
        !_shouldSuppressPlayerStatusUi(value);
    if (hasVisibleError) {
      _uiController.awaitingVisualPlaybackStart = false;
      _finishPendingLoadingTransition();
      return;
    }
    if (value.visualPlaybackReady && value.ready && value.nativeLibLoaded) {
      _uiController.awaitingVisualPlaybackStart = false;
      _finishPendingLoadingTransition(
        hideDelay: const Duration(milliseconds: 220),
      );
      return;
    }
    if (_uiController.pendingTransitionTargetPaused) {
      if (value.ready &&
          value.nativeLibLoaded &&
          (value.paused ||
              value.playbackPhase == MpvPlaybackPhase.paused ||
              !value.isTransientLoadingPhase)) {
        _uiController.awaitingVisualPlaybackStart = false;
        _finishPendingLoadingTransition();
      }
      return;
    }
    final playbackProgressedAfterSwitch =
        _uiController.allowPlaybackProgressTransitionCompletion &&
        value.ready &&
        value.nativeLibLoaded &&
        !value.paused &&
        value.position >=
            _uiController.visualPlaybackStartAnchorPosition +
                _MpvPlayerPageState._videoLoadingPlaybackProgressTolerance;
    if (playbackProgressedAfterSwitch) {
      _uiController.awaitingVisualPlaybackStart = false;
      _finishPendingLoadingTransition(
        hideDelay: const Duration(milliseconds: 220),
      );
      return;
    }
  }

  String _videoLoadingOverlayMessage(MpvPlayerValue value) {
    final l10n = AppLocalizations.of(context);
    final switchMessage = _uiController.subtitleSwitchMessage?.trim() ?? '';
    if (_uiController.qualitySwitchLoading && switchMessage.isNotEmpty) {
      return switchMessage;
    }
    if (!_initialSourceLoadStarted) {
      if (!_initialPlayerPreferencesLoaded ||
          !_initialDanmakuPreferencesLoaded) {
        return l10n.playerLoadingPreparingEnvironment;
      }
      if (!_platformViewAttached) {
        return l10n.playerLoadingInitializingPlayer;
      }
      return l10n.playerLoadingPreparingSource;
    }
    if (value.playbackPhase == MpvPlaybackPhase.buffering) {
      return l10n.playerLoadingBuffering;
    }
    final status = value.statusText.trim().toLowerCase();
    if (value.playbackPhase == MpvPlaybackPhase.seeking) {
      return l10n.playerLoadingSeeking;
    }
    if (status == 'waiting for playback source') {
      return l10n.playerLoadingPreparingSource;
    }
    if (status == 'opening source' || status == 'source loaded') {
      return l10n.playerLoadingOpeningSource;
    }
    if (status == 'waiting for video surface' ||
        status == 'preparing video renderer') {
      return l10n.playerLoadingPreparingVideo;
    }
    return l10n.playerLoadingVideo;
  }

  String? _videoLoadingOverlaySecondaryMessage(MpvPlayerValue value) {
    if (_currentSourceIsDownloadedFile || _externalLocalSource) {
      return null;
    }
    final sourceUrl =
        (_currentUrl.trim().isNotEmpty ? _currentUrl : widget.source.url)
            .trim()
            .toLowerCase();
    final remoteHttpSource =
        sourceUrl.startsWith('http://') || sourceUrl.startsWith('https://');
    if (!remoteHttpSource) {
      return null;
    }
    if (value.playbackPhase != MpvPlaybackPhase.buffering &&
        !value.isTransientLoadingPhase &&
        !_uiController.awaitingVisualPlaybackStart &&
        !_uiController.qualitySwitchLoading) {
      return null;
    }
    return buildWeakNetworkBufferingDetails(
      networkSpeedBytesPerSecond: value.networkSpeedBytesPerSecond,
      estimatedResumeWait: value.playbackPhase == MpvPlaybackPhase.buffering
          ? value.estimatedResumeWait
          : null,
    );
  }

  bool _shouldShowResumePrompt({
    required Duration startPosition,
    required int durationSeconds,
  }) {
    if (startPosition <= Duration.zero) return false;
    if (durationSeconds <= 0) return true;
    return startPosition.inSeconds < durationSeconds;
  }

  Future<void> _showAutoPlayPrompt() async {
    final nextEpisode = await _nextEpisodeOrNull();
    if (!mounted) return;
    if (nextEpisode == null) {
      _overlayState.showControls();
      _overlayState.cancelAutoHide();
      _completionController.markPlaybackCompleted(hasNextEpisode: false);
      return;
    }

    _overlayState.showControls();
    _overlayState.cancelAutoHide();
    _completionController.beginAutoPlayPrompt(
      hasNextEpisode: true,
      onTimeout: () {
        if (!mounted) return;
        unawaited(_skipToNextEpisodeFromPrompt());
      },
    );
    unawaited(_preloadNextEpisodeIfNeeded(nextEpisode));
    final value = _controller.value.value;
    _completionController.setAutoPlayCountdownPaused(
      value.playbackPhase != MpvPlaybackPhase.playing &&
          value.playbackPhase != MpvPlaybackPhase.ended,
    );
  }

  Future<void> _maybeStartAutoPlayPromptNearEnd() async {
    if (_autoPlayPromptRequestInFlight ||
        _completionController.autoPlayPromptVisible ||
        _completionController.autoPlayPromptSuppressed ||
        _playbackCompleted ||
        _completionActionInFlight) {
      return;
    }
    _autoPlayPromptRequestInFlight = true;
    try {
      final nextEpisode = await _nextEpisodeOrNull();
      if (!mounted || nextEpisode == null) {
        return;
      }
      _overlayState.showControls();
      _overlayState.cancelAutoHide();
      _completionController.beginAutoPlayPrompt(
        hasNextEpisode: true,
        onTimeout: () {
          if (!mounted) return;
          unawaited(_skipToNextEpisodeFromPrompt());
        },
      );
      unawaited(_preloadNextEpisodeIfNeeded(nextEpisode));
      final value = _controller.value.value;
      _completionController.setAutoPlayCountdownPaused(
        value.playbackPhase != MpvPlaybackPhase.playing &&
            value.playbackPhase != MpvPlaybackPhase.ended,
      );
    } finally {
      _autoPlayPromptRequestInFlight = false;
    }
  }

  Future<void> _skipToNextEpisodeFromPrompt() async {
    final nextEpisode = await _nextEpisodeOrNull();
    _completionController.cancelAutoPlayPrompt();
    if (nextEpisode == null) {
      if (!mounted) return;
      _completionController.markPlaybackCompleted(hasNextEpisode: false);
      return;
    }
    await _switchToEpisode(nextEpisode, fromAutoPlay: true);
  }

  Future<void> _replayCurrentEpisodeFromPrompt() async {
    _completionController.cancelAutoPlayPrompt();
    await _replayCompletedItem();
  }

  Future<void> _pauseForAutoPlayPromptIfNeeded() async {
    await _showAutoPlayPrompt();
  }

  void _clearPlaybackCompletionState() {
    _completionController.clear();
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_completionActionInFlight) return;
    await _submitPlaybackRecord(force: true);
    await _markCurrentItemWatched();
    final nextEpisode = await _nextEpisodeOrNull();
    if (!mounted) return;
    final hasNextEpisode = nextEpisode != null;
    final hasPlayedLongEnoughForAutoPlay = _hasPlayedLongEnoughForAutoPlay(
      _displayPosition(_controller.value.value),
    );

    if (_autoPlayEnabled &&
        nextEpisode != null &&
        hasPlayedLongEnoughForAutoPlay &&
        !_completionController.autoPlayPromptSuppressed) {
      await _pauseForAutoPlayPromptIfNeeded();
      return;
    }

    if (_controller.value.value.playbackPhase == MpvPlaybackPhase.playing) {
      await _controller.pause();
      if (!mounted) return;
    }
    _overlayState.showControls();
    _overlayState.cancelAutoHide();
    _completionController.markPlaybackCompleted(hasNextEpisode: hasNextEpisode);
  }

  Future<void> _replayCompletedItem() async {
    _clearPlaybackCompletionState();
    _overlayState.showControls();
    _setResumePromptVisibility(false);
    _gestureController.resetSeekTracking();
    await _finishPlayStatsSession('replay_restart');
    await _startPlayStatsSession(
      startSource: PlayStartSource.replay,
      info: _playStatsCurrentInfo,
      source: _buildCurrentSource(
        startPosition: Duration.zero,
        loadNonce: _issueNextLoadNonce(),
      ),
      startPositionMs: 0,
    );
    await _seekWithStats(Duration.zero, userInitiated: false);
    await _controller.play();
    if (!mounted) return;
    _scheduleControlsAutoHide();
  }

  bool _shouldSuppressPlayerStatusUi(MpvPlayerValue value) {
    final status = value.statusText.trim().toLowerCase();
    final error = (value.error ?? '').trim().toLowerCase();
    if (error.isEmpty) return false;
    return error.contains('rejected seek') ||
        error.contains('mpv-android runtime rejected source') ||
        error.contains('mpv-android runtime rejected source loading') ||
        (status == 'playback paused' && error.contains('seek'));
  }

  bool _wantsVideoLoadingOverlay(MpvPlayerValue value) {
    if (_exitInProgress || _playbackCompleted || _completionActionInFlight) {
      return false;
    }
    if (_uiController.backgroundLoadingTransition &&
        (_uiController.pendingLoadingTransition ||
            _uiController.awaitingVisualPlaybackStart ||
            _uiController.qualitySwitchLoading)) {
      return false;
    }
    if (_uiController.qualitySwitchLoading) {
      return true;
    }
    if (!_initialSourceLoadStarted) {
      return true;
    }
    if (_shouldSuppressPlayerStatusUi(value)) {
      return true;
    }
    final hasVisibleError =
        (value.error?.trim().isNotEmpty ?? false) &&
        !_shouldSuppressPlayerStatusUi(value);
    if (hasVisibleError) {
      return false;
    }
    if (_uiController.awaitingVisualPlaybackStart) {
      return true;
    }
    if (value.playbackPhase == MpvPlaybackPhase.buffering) {
      return true;
    }
    if (!value.ready || !value.nativeLibLoaded) {
      return true;
    }
    return value.isTransientLoadingPhase;
  }

  bool _shouldForceVideoLoadingOverlay(MpvPlayerValue value) {
    if (_exitInProgress || _playbackCompleted || _completionActionInFlight) {
      return false;
    }
    if (_uiController.backgroundLoadingTransition) {
      return false;
    }
    if (!_initialSourceLoadStarted ||
        _uiController.qualitySwitchLoading ||
        _uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart) {
      return true;
    }
    if (value.paused || value.visualPlaybackReady) {
      return false;
    }
    return value.playbackPhase == MpvPlaybackPhase.preparing ||
        value.playbackPhase == MpvPlaybackPhase.buffering ||
        value.playbackPhase == MpvPlaybackPhase.seeking ||
        !value.ready ||
        !value.nativeLibLoaded;
  }

  bool _shouldShowVideoLoadingOverlay(MpvPlayerValue value) {
    return _uiController.videoLoadingOverlayVisible ||
        _shouldForceVideoLoadingOverlay(value);
  }

  void _syncVideoLoadingOverlayVisibility([MpvPlayerValue? currentValue]) {
    final value = currentValue ?? _controller.value.value;
    final wantsOverlay = _wantsVideoLoadingOverlay(value);
    if (!wantsOverlay) {
      _videoLoadingOverlayTimer?.cancel();
      _videoLoadingOverlayTimer = null;
      if (_uiController.videoLoadingOverlayVisible && mounted) {
        _updatePlayerState(
          () => _uiController.videoLoadingOverlayVisible = false,
        );
      } else {
        _uiController.videoLoadingOverlayVisible = false;
      }
      return;
    }
    final transitionWantsImmediateOverlay =
        _uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart ||
        _uiController.qualitySwitchLoading;
    if (_uiController.videoLoadingOverlayVisible) {
      return;
    }
    final showDelay = transitionWantsImmediateOverlay
        ? Duration.zero
        : _videoLoadingOverlayShowDelay;
    if (_videoLoadingOverlayTimer != null) {
      if (showDelay > Duration.zero) {
        return;
      }
      _videoLoadingOverlayTimer?.cancel();
      _videoLoadingOverlayTimer = null;
    }
    if (showDelay <= Duration.zero) {
      if (mounted) {
        _updatePlayerState(
          () => _uiController.videoLoadingOverlayVisible = true,
        );
      } else {
        _uiController.videoLoadingOverlayVisible = true;
      }
      return;
    }
    _videoLoadingOverlayTimer = Timer(showDelay, () {
      _videoLoadingOverlayTimer = null;
      if (!mounted) return;
      if (!_wantsVideoLoadingOverlay(_controller.value.value)) return;
      _updatePlayerState(() => _uiController.videoLoadingOverlayVisible = true);
    });
  }
}
