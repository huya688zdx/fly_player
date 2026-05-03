import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mpv_player_controller.dart';

/// 管理完播判断、自动连播提示与其过渡状态。
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

  /// 根据自动连播倒计时窗口构造控制器。
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

  /// 判断恢复进度是否已经落在媒体结尾之后。
  bool isProgressFullyWatched({
    required Duration startPosition,
    required int durationSeconds,
  }) {
    if (durationSeconds <= 0) return false;
    return startPosition.inSeconds >= durationSeconds;
  }

  /// 将超出媒体时长的恢复进度归一化为起始位置。
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

  /// 根据播放器状态与当前位置判断本次播放是否已完播。
  bool isPlaybackCompleted({
    required MpvPlayerValue value,
    required Duration effectiveDuration,
    required Duration displayPosition,
  }) {
    if (!value.ready || !value.nativeLibLoaded) return false;
    if (effectiveDuration <= Duration.zero) return false;
    if (value.playbackPhase == MpvPlaybackPhase.ended) {
      return true;
    }

    final remaining = effectiveDuration - displayPosition;
    if (remaining <= const Duration(seconds: 1)) {
      return true;
    }

    final threshold = effectiveDuration - const Duration(milliseconds: 900);
    return value.playbackPhase == MpvPlaybackPhase.paused &&
        displayPosition >= threshold;
  }

  /// 消费一次“播放器就绪后立即暂停”的请求。
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

  /// 请求在播放器就绪后暂停，以便展示自动连播提示。
  void requestPauseAfterReadyForAutoPlayPrompt() {
    if (_pauseAfterReadyForAutoPlayPrompt) return;
    _pauseAfterReadyForAutoPlayPrompt = true;
    notifyListeners();
  }

  /// 取消自动连播提示并重置倒计时状态。
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

  /// 显示自动连播提示并启动倒计时。
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

  /// 暂停或恢复自动连播倒计时。
  void setAutoPlayCountdownPaused(bool paused) {
    _autoPlayCountdownPaused = paused;
  }

  /// 标记完播后的跳转流程已经开始。
  void markTransitionInFlight({required bool hasNextEpisode}) {
    _playbackCompleted = false;
    _completionHasNextEpisode = hasNextEpisode;
    _completionActionInFlight = true;
    notifyListeners();
  }

  /// 开始抑制完播判断，通常用于源切换过渡期。
  void beginPlaybackCompletionSuppression() {
    _suppressPlaybackCompletionUntilReady = true;
  }

  /// 清除完播判断抑制标记。
  void clearPlaybackCompletionSuppression() {
    _suppressPlaybackCompletionUntilReady = false;
  }

  /// 在播放器恢复稳定后自动结束完播抑制状态。
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

  /// 结束完播后的跳转中状态。
  void finishTransitionInFlight() {
    if (!_completionActionInFlight) return;
    _completionActionInFlight = false;
    notifyListeners();
  }

  /// 标记本次播放已完成。
  void markPlaybackCompleted({required bool hasNextEpisode}) {
    _playbackCompleted = true;
    _completionActionInFlight = false;
    _completionHasNextEpisode = hasNextEpisode;
    notifyListeners();
  }

  /// 在当前条目生命周期内抑制自动连播提示。
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

  /// 清空完播控制器的全部运行态。
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
