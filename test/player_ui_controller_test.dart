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
        ..allowPlaybackProgressTransitionCompletion = true
        ..videoLoadingOverlayVisible = true
        ..weakNetworkSuggestionSuppressionKey = 'item|1080p'
        ..weakNetworkSuggestion = const PlayerWeakNetworkSuggestion(
          suppressionKey: 'item|1080p',
          targetQualityId: '720p',
          title: 'Network slow',
          subtitle: 'Current speed 1 MB/s',
        )
        ..visualPlaybackStartAnchorPosition = const Duration(seconds: 5);

      controller.resetSourceLoadTransitionState();

      expect(controller.pendingLoadingTransition, isFalse);
      expect(controller.pendingTransitionTargetPaused, isFalse);
      expect(controller.qualitySwitchLoading, isFalse);
      expect(controller.awaitingVisualPlaybackStart, isFalse);
      expect(controller.allowPlaybackProgressTransitionCompletion, isFalse);
      expect(controller.videoLoadingOverlayVisible, isFalse);
      expect(controller.weakNetworkSuggestion, isNull);
      expect(controller.weakNetworkSuggestionSuppressionKey, 'item|1080p');
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
      expect(controller.pendingLoadingTransition, isTrue);
      expect(controller.allowPlaybackProgressTransitionCompletion, isFalse);
    });

    test(
      'markAwaitingVisualPlaybackStart keeps background transitions silent',
      () {
        final controller = PlayerUiController();

        controller.markAwaitingVisualPlaybackStart(
          const Duration(seconds: 3),
          targetPaused: false,
          background: true,
        );

        expect(controller.awaitingVisualPlaybackStart, isTrue);
        expect(controller.backgroundLoadingTransition, isTrue);
        expect(controller.pendingLoadingTransition, isFalse);
      },
    );

    test('resetForSourceChange clears weak network suggestion suppression', () {
      final controller = PlayerUiController()
        ..weakNetworkSuggestionSuppressionKey = 'item|1080p'
        ..weakNetworkSuggestion = const PlayerWeakNetworkSuggestion(
          suppressionKey: 'item|1080p',
          targetQualityId: '720p',
          title: 'Network slow',
          subtitle: 'Current speed 1 MB/s',
        );

      controller.resetForSourceChange();

      expect(controller.weakNetworkSuggestion, isNull);
      expect(controller.weakNetworkSuggestionSuppressionKey, isNull);
    });
  });
}
