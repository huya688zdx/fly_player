import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/player/controllers/player_ui_controller.dart';

void main() {
  group('PlayerUiController', () {
    test('resetForSourceChange clears transient timeline and prompt state', () {
      final controller = PlayerUiController()
        ..draggingPosition = const Duration(seconds: 12)
        ..timelineInteractionActive = true
        ..chapterLoading = true
        ..chapterRetryAttempt = 2
        ..activeChapterSkipPrompt = const PlayerChapterSkipSegment(
          kind: 'intro',
          chapterIndex: 0,
          label: 'Intro',
          start: Duration.zero,
          end: Duration(seconds: 90),
        )
        ..centerPopupMessage = 'message';

      controller.resetForSourceChange();

      expect(controller.draggingPosition, isNull);
      expect(controller.timelineInteractionActive, isFalse);
      expect(controller.chapterLoading, isFalse);
      expect(controller.chapterRetryAttempt, 0);
      expect(controller.activeChapterSkipPrompt, isNull);
      expect(controller.centerPopupMessage, isNull);
    });

    test('resetSourceLoadTransitionState clears loading transition flags', () {
      final controller = PlayerUiController()
        ..pendingLoadingTransition = true
        ..pendingTransitionTargetPaused = true
        ..qualitySwitchLoading = true
        ..awaitingVisualPlaybackStart = true
        ..videoLoadingOverlayVisible = true
        ..visualPlaybackStartAnchorPosition = const Duration(seconds: 5);

      controller.resetSourceLoadTransitionState();

      expect(controller.pendingLoadingTransition, isFalse);
      expect(controller.pendingTransitionTargetPaused, isFalse);
      expect(controller.qualitySwitchLoading, isFalse);
      expect(controller.awaitingVisualPlaybackStart, isFalse);
      expect(controller.videoLoadingOverlayVisible, isFalse);
      expect(
        controller.visualPlaybackStartAnchorPosition,
        equals(Duration.zero),
      );
    });

    test('markAwaitingVisualPlaybackStart normalizes negative anchor', () {
      final controller = PlayerUiController();

      controller.markAwaitingVisualPlaybackStart(
        const Duration(seconds: -1),
        targetPaused: true,
      );

      expect(controller.awaitingVisualPlaybackStart, isTrue);
      expect(controller.pendingTransitionTargetPaused, isTrue);
      expect(
        controller.visualPlaybackStartAnchorPosition,
        equals(Duration.zero),
      );
    });
  });
}
