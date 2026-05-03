class PlayerChapterSkipSegment {
  final String kind;
  final int chapterIndex;
  final String label;
  final Duration start;
  final Duration end;

  const PlayerChapterSkipSegment({
    required this.kind,
    required this.chapterIndex,
    required this.label,
    required this.start,
    required this.end,
  });

  String get key =>
      '$kind:$chapterIndex:${start.inMilliseconds}:${end.inMilliseconds}';

  bool get isIntro => kind == 'intro';
}

class PlayerWeakNetworkSuggestion {
  final String suppressionKey;
  final String targetQualityId;
  final String title;
  final String subtitle;

  const PlayerWeakNetworkSuggestion({
    required this.suppressionKey,
    required this.targetQualityId,
    required this.title,
    required this.subtitle,
  });
}

class PlayerUiController {
  bool orientationChangeInProgress = false;
  bool orientationTransitionMaskVisible = false;
  bool qualitySwitchLoading = false;
  bool pendingLoadingTransition = false;
  bool backgroundLoadingTransition = false;
  bool videoLoadingOverlayVisible = false;
  bool awaitingVisualPlaybackStart = false;
  bool allowPlaybackProgressTransitionCompletion = false;
  bool pendingTransitionTargetPaused = false;
  bool wasPaused = true;
  bool suppressControlsRevealOnNextPause = false;
  bool chapterLoading = false;
  int chapterRetryAttempt = 0;
  int lastRecordedSecond = -1;
  Duration? draggingPosition;
  bool timelineInteractionActive = false;
  PlayerChapterSkipSegment? activeChapterSkipPrompt;
  String? centerPopupMessage;
  String? statusMessage;
  String? subtitleSwitchMessage;
  PlayerWeakNetworkSuggestion? weakNetworkSuggestion;
  String? weakNetworkSuggestionSuppressionKey;
  Duration visualPlaybackStartAnchorPosition = Duration.zero;

  void resetForSourceChange() {
    draggingPosition = null;
    timelineInteractionActive = false;
    chapterLoading = false;
    chapterRetryAttempt = 0;
    suppressControlsRevealOnNextPause = false;
    activeChapterSkipPrompt = null;
    centerPopupMessage = null;
    weakNetworkSuggestion = null;
    weakNetworkSuggestionSuppressionKey = null;
  }

  void resetSourceLoadTransitionState() {
    pendingLoadingTransition = false;
    backgroundLoadingTransition = false;
    pendingTransitionTargetPaused = false;
    suppressControlsRevealOnNextPause = false;
    qualitySwitchLoading = false;
    awaitingVisualPlaybackStart = false;
    allowPlaybackProgressTransitionCompletion = false;
    videoLoadingOverlayVisible = false;
    weakNetworkSuggestion = null;
    visualPlaybackStartAnchorPosition = Duration.zero;
  }

  void beginOrientationChange() {
    orientationChangeInProgress = true;
    orientationTransitionMaskVisible = true;
  }

  void finishOrientationChange() {
    orientationChangeInProgress = false;
    orientationTransitionMaskVisible = false;
  }

  void markAwaitingVisualPlaybackStart(
    Duration anchorPosition, {
    required bool targetPaused,
    bool background = false,
  }) {
    awaitingVisualPlaybackStart = true;
    allowPlaybackProgressTransitionCompletion = false;
    backgroundLoadingTransition = background;
    if (!background) {
      pendingLoadingTransition = true;
    }
    pendingTransitionTargetPaused = targetPaused;
    visualPlaybackStartAnchorPosition = anchorPosition.isNegative
        ? Duration.zero
        : anchorPosition;
  }

  void showWeakNetworkSuggestion(PlayerWeakNetworkSuggestion suggestion) {
    weakNetworkSuggestion = suggestion;
  }

  void clearWeakNetworkSuggestion() {
    weakNetworkSuggestion = null;
  }

  void suppressWeakNetworkSuggestion(String suppressionKey) {
    weakNetworkSuggestion = null;
    weakNetworkSuggestionSuppressionKey = suppressionKey;
  }

  void clearWeakNetworkSuggestionSuppression() {
    weakNetworkSuggestionSuppressionKey = null;
  }

  bool isWeakNetworkSuggestionSuppressed(String suppressionKey) {
    return weakNetworkSuggestionSuppressionKey == suppressionKey;
  }
}
