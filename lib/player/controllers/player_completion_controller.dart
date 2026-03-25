import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mpv_player_controller.dart';

class PlayerCompletionController extends ChangeNotifier {
  final Duration autoPlayCountdownDuration;

  Timer? _autoPlayCountdownTimer;
  bool _autoPlayPromptVisible = false;
  bool _pauseAfterReadyForAutoPlayPrompt = false;
  bool _playbackCompleted = false;
  bool _completionActionInFlight = false;
  bool _completionHasNextEpisode = false;
  bool _suppressPlaybackCompletionUntilReady = false;
  bool _autoPlayPromptSuppressed = false;
  bool _autoPlayCountdownPaused = false;
  late int _autoPlayCountdownSeconds;

  PlayerCompletionController({
    this.autoPlayCountdownDuration = const Duration(seconds: 5),
  }) {
    _autoPlayCountdownSeconds = autoPlayCountdownDuration.inSeconds;
  }

  bool get autoPlayPromptVisible => _autoPlayPromptVisible;
  bool get playbackCompleted => _playbackCompleted;
  bool get completionActionInFlight => _completionActionInFlight;
  bool get completionHasNextEpisode => _completionHasNextEpisode;
  bool get suppressPlaybackCompletionUntilReady =>
      _suppressPlaybackCompletionUntilReady;
  bool get autoPlayPromptSuppressed => _autoPlayPromptSuppressed;
  Duration get autoPlayPromptWindow => autoPlayCountdownDuration;
  int get autoPlayCountdownSeconds => _autoPlayCountdownSeconds;

  bool isProgressFullyWatched({
    required Duration startPosition,
    required int durationSeconds,
  }) {
    if (durationSeconds <= 0) return false;
    return startPosition.inSeconds >= durationSeconds;
  }

  Duration normalizedStartPosition({
    required Duration startPosition,
    required int durationSeconds,
  }) {
    if (isProgressFullyWatched(
      startPosition: startPosition,
      durationSeconds: durationSeconds,
    )) {
      return Duration.zero;
    }
    return startPosition;
  }

  bool isPlaybackCompleted({
    required MpvPlayerValue value,
    required Duration effectiveDuration,
    required Duration displayPosition,
  }) {
    if (!value.ready || !value.nativeLibLoaded) return false;
    final statusText = value.statusText.trim().toLowerCase();
    if (effectiveDuration <= Duration.zero) return false;

    final remaining = effectiveDuration - displayPosition;
    if (remaining <= const Duration(seconds: 1)) {
      return true;
    }

    final threshold = effectiveDuration - const Duration(milliseconds: 900);
    if (statusText == 'playback ended') {
      return displayPosition >= threshold;
    }
    return value.paused && displayPosition >= threshold;
  }

  bool consumePauseAfterReady(MpvPlayerValue value) {
    if (!_pauseAfterReadyForAutoPlayPrompt ||
        !value.ready ||
        !value.nativeLibLoaded) {
      return false;
    }
    _pauseAfterReadyForAutoPlayPrompt = false;
    notifyListeners();
    return true;
  }

  void requestPauseAfterReadyForAutoPlayPrompt() {
    if (_pauseAfterReadyForAutoPlayPrompt) return;
    _pauseAfterReadyForAutoPlayPrompt = true;
    notifyListeners();
  }

  void cancelAutoPlayPrompt({bool notify = true}) {
    _autoPlayCountdownTimer?.cancel();
    _autoPlayCountdownTimer = null;
    final changed = _autoPlayPromptVisible || _pauseAfterReadyForAutoPlayPrompt;
    _autoPlayPromptVisible = false;
    _pauseAfterReadyForAutoPlayPrompt = false;
    _autoPlayCountdownPaused = false;
    _autoPlayCountdownSeconds = autoPlayCountdownDuration.inSeconds;
    if (notify && changed) {
      notifyListeners();
    }
  }

  void beginAutoPlayPrompt({
    required bool hasNextEpisode,
    required VoidCallback onTimeout,
  }) {
    _autoPlayCountdownTimer?.cancel();
    _playbackCompleted = false;
    _completionActionInFlight = false;
    _completionHasNextEpisode = hasNextEpisode;
    _autoPlayPromptSuppressed = false;
    _autoPlayPromptVisible = true;
    _autoPlayCountdownPaused = false;
    _autoPlayCountdownSeconds = autoPlayCountdownDuration.inSeconds;
    notifyListeners();

    _autoPlayCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!_autoPlayPromptVisible) {
        timer.cancel();
        return;
      }
      if (_autoPlayCountdownPaused) {
        return;
      }
      if (_autoPlayCountdownSeconds <= 1) {
        timer.cancel();
        onTimeout();
        return;
      }
      _autoPlayCountdownSeconds -= 1;
      notifyListeners();
    });
  }

  void setAutoPlayCountdownPaused(bool paused) {
    _autoPlayCountdownPaused = paused;
  }

  void markTransitionInFlight({required bool hasNextEpisode}) {
    _playbackCompleted = false;
    _completionHasNextEpisode = hasNextEpisode;
    _completionActionInFlight = true;
    notifyListeners();
  }

  void beginPlaybackCompletionSuppression() {
    _suppressPlaybackCompletionUntilReady = true;
  }

  void clearPlaybackCompletionSuppression() {
    _suppressPlaybackCompletionUntilReady = false;
  }

  void settlePlaybackCompletionSuppression({
    required MpvPlayerValue value,
    required Duration effectiveDuration,
    required Duration displayPosition,
  }) {
    if (!_suppressPlaybackCompletionUntilReady ||
        !value.ready ||
        !value.nativeLibLoaded) {
      return;
    }
    if (isPlaybackCompleted(
      value: value,
      effectiveDuration: effectiveDuration,
      displayPosition: displayPosition,
    )) {
      return;
    }
    _suppressPlaybackCompletionUntilReady = false;
  }

  void finishTransitionInFlight() {
    if (!_completionActionInFlight) return;
    _completionActionInFlight = false;
    notifyListeners();
  }

  void markPlaybackCompleted({required bool hasNextEpisode}) {
    _playbackCompleted = true;
    _completionActionInFlight = false;
    _completionHasNextEpisode = hasNextEpisode;
    notifyListeners();
  }

  void suppressAutoPlayPromptForCurrentItem() {
    _autoPlayCountdownTimer?.cancel();
    _autoPlayCountdownTimer = null;
    final changed =
        _autoPlayPromptVisible ||
        _pauseAfterReadyForAutoPlayPrompt ||
        !_autoPlayPromptSuppressed;
    _autoPlayPromptVisible = false;
    _pauseAfterReadyForAutoPlayPrompt = false;
    _autoPlayPromptSuppressed = true;
    _autoPlayCountdownPaused = false;
    _autoPlayCountdownSeconds = autoPlayCountdownDuration.inSeconds;
    if (changed) {
      notifyListeners();
    }
  }

  void clear() {
    _autoPlayCountdownTimer?.cancel();
    _autoPlayCountdownTimer = null;
    final changed =
        _autoPlayPromptVisible ||
        _pauseAfterReadyForAutoPlayPrompt ||
        _playbackCompleted ||
        _completionActionInFlight ||
        _completionHasNextEpisode ||
        _autoPlayPromptSuppressed ||
        _autoPlayCountdownSeconds != autoPlayCountdownDuration.inSeconds;
    _autoPlayPromptVisible = false;
    _pauseAfterReadyForAutoPlayPrompt = false;
    _playbackCompleted = false;
    _completionActionInFlight = false;
    _completionHasNextEpisode = false;
    _suppressPlaybackCompletionUntilReady = false;
    _autoPlayPromptSuppressed = false;
    _autoPlayCountdownPaused = false;
    _autoPlayCountdownSeconds = autoPlayCountdownDuration.inSeconds;
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autoPlayCountdownTimer?.cancel();
    super.dispose();
  }
}
