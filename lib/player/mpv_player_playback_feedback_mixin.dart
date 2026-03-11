part of 'mpv_player_page.dart';

const Set<String> _loadingStatusTexts = <String>{
  'preparing player',
  'preparing playback',
  'preparing video renderer',
  'waiting for video surface',
  'waiting for playback source',
  'source loaded',
};
const Duration _videoLoadingOverlayShowDelay = Duration(milliseconds: 260);

extension _MpvPlayerPlaybackFeedbackMixin on _MpvPlayerPageState {
  String _videoLoadingOverlayMessage(MpvPlayerValue value) {
    final switchMessage = _subtitleSwitchMessage?.trim() ?? '';
    if (_qualitySwitchLoading && switchMessage.isNotEmpty) {
      return switchMessage;
    }
    final status = value.statusText.trim().toLowerCase();
    if (status == 'waiting for playback source') {
      return '\u6b63\u5728\u51c6\u5907\u64ad\u653e\u6e90...';
    }
    if (status == 'waiting for video surface' ||
        status == 'preparing video renderer') {
      return '\u6b63\u5728\u51c6\u5907\u753b\u9762...';
    }
    return '\u89c6\u9891\u52a0\u8f7d\u4e2d...';
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
    if (_controller.value.value.paused) {
      await _showAutoPlayPrompt();
      return;
    }
    await _controller.pause();
    if (!mounted) return;
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

    if (_autoPlayEnabled && nextEpisode != null) {
      _completionController.markTransitionInFlight(
        hasNextEpisode: hasNextEpisode,
      );
      _completionController.beginPlaybackCompletionSuppression();
      try {
        await _switchToEpisode(nextEpisode, fromAutoPlay: true);
        if (_currentItemGuid != nextEpisode.guid) {
          _completionController.clearPlaybackCompletionSuppression();
        }
      } finally {
        if (mounted) {
          _completionController.finishTransitionInFlight();
        }
      }
      return;
    }

    _overlayState.showControls();
    _overlayState.cancelAutoHide();
    _completionController.markPlaybackCompleted(hasNextEpisode: hasNextEpisode);
  }

  Future<void> _replayCompletedItem() async {
    _clearPlaybackCompletionState();
    _overlayState.showControls();
    _overlayState.setResumePromptVisible(false);
    _gestureController.resetSeekTracking();
    await _controller.seek(Duration.zero);
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
    if (_qualitySwitchLoading) {
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
    if (!value.ready || !value.nativeLibLoaded) {
      return true;
    }
    return _loadingStatusTexts.contains(value.statusText.trim().toLowerCase());
  }

  bool _shouldShowVideoLoadingOverlay(MpvPlayerValue value) {
    return _videoLoadingOverlayVisible;
  }

  void _syncVideoLoadingOverlayVisibility([MpvPlayerValue? currentValue]) {
    final value = currentValue ?? _controller.value.value;
    final wantsOverlay = _wantsVideoLoadingOverlay(value);
    if (!wantsOverlay) {
      _videoLoadingOverlayTimer?.cancel();
      _videoLoadingOverlayTimer = null;
      if (_videoLoadingOverlayVisible && mounted) {
        setState(() => _videoLoadingOverlayVisible = false);
      } else {
        _videoLoadingOverlayVisible = false;
      }
      return;
    }
    if (_videoLoadingOverlayVisible || _videoLoadingOverlayTimer != null) {
      return;
    }
    _videoLoadingOverlayTimer = Timer(_videoLoadingOverlayShowDelay, () {
      _videoLoadingOverlayTimer = null;
      if (!mounted) return;
      if (!_wantsVideoLoadingOverlay(_controller.value.value)) return;
      setState(() => _videoLoadingOverlayVisible = true);
    });
  }
}
