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

class PlayerUiController {
  bool orientationChangeInProgress = false;
  bool orientationTransitionMaskVisible = false;
  bool qualitySwitchLoading = false;
  bool pendingLoadingTransition = false;
  bool videoLoadingOverlayVisible = false;
  bool awaitingVisualPlaybackStart = false;
  bool pendingTransitionTargetPaused = false;
  bool wasPaused = true;
  bool chapterLoading = false;
  int chapterRetryAttempt = 0;
  int lastRecordedSecond = -1;
  Duration? draggingPosition;
  bool timelineInteractionActive = false;
  PlayerChapterSkipSegment? activeChapterSkipPrompt;
  String? centerPopupMessage;
  String? statusMessage;
  String? subtitleSwitchMessage;
  Duration visualPlaybackStartAnchorPosition = Duration.zero;

  void resetForSourceChange() {
    draggingPosition = null;
    timelineInteractionActive = false;
    chapterLoading = false;
    chapterRetryAttempt = 0;
    activeChapterSkipPrompt = null;
    centerPopupMessage = null;
  }

  void resetSourceLoadTransitionState() {
    pendingLoadingTransition = false;
    pendingTransitionTargetPaused = false;
    qualitySwitchLoading = false;
    awaitingVisualPlaybackStart = false;
    videoLoadingOverlayVisible = false;
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
  }) {
    awaitingVisualPlaybackStart = true;
    pendingTransitionTargetPaused = targetPaused;
    visualPlaybackStartAnchorPosition = anchorPosition.isNegative
        ? Duration.zero
        : anchorPosition;
  }
}
