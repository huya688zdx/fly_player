import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/player/controllers/mpv_player_controller.dart';
import 'package:fly_player/player/controllers/playback_loading_state.dart';

void main() {
  PlaybackLoadingState resolve({
    MpvPlayerValue? value,
    PlaybackLoadingFlags flags = PlaybackLoadingFlags.none,
    bool initialSourceLoadStarted = true,
    bool exiting = false,
    bool playbackCompleted = false,
    bool completionActionInFlight = false,
    bool hasVisibleError = false,
  }) {
    return PlaybackLoadingState.resolve(
      value: value ?? const MpvPlayerValue.initial(),
      flags: flags,
      initialSourceLoadStarted: initialSourceLoadStarted,
      exiting: exiting,
      playbackCompleted: playbackCompleted,
      completionActionInFlight: completionActionInFlight,
      hasVisibleError: hasVisibleError,
    );
  }

  MpvPlayerValue valueWith({
    required MpvPlaybackPhase phase,
    bool ready = true,
    bool nativeLibLoaded = true,
  }) {
    return const MpvPlayerValue.initial().copyWith(
      playbackPhase: phase,
      ready: ready,
      nativeLibLoaded: nativeLibLoaded,
    );
  }

  group('PlaybackLoadingState.resolve', () {
    test('stable playback yields idle', () {
      final state = resolve(value: valueWith(phase: MpvPlaybackPhase.playing));
      expect(state.kind, PlaybackLoadingKind.none);
      expect(state.isLoading, isFalse);
      expect(state.showsFullScreenOverlay, isFalse);
      expect(state.showsPlayButtonSpinner, isFalse);
    });

    test('exiting / completed short-circuits to idle', () {
      expect(
        resolve(
          value: valueWith(phase: MpvPlaybackPhase.buffering),
          exiting: true,
        ).kind,
        PlaybackLoadingKind.none,
      );
      expect(
        resolve(
          value: valueWith(phase: MpvPlaybackPhase.buffering),
          playbackCompleted: true,
        ).kind,
        PlaybackLoadingKind.none,
      );
      expect(
        resolve(
          value: valueWith(phase: MpvPlaybackPhase.buffering),
          completionActionInFlight: true,
        ).kind,
        PlaybackLoadingKind.none,
      );
    });

    test('before initial source load → preparingSource', () {
      final state = resolve(initialSourceLoadStarted: false);
      expect(state.kind, PlaybackLoadingKind.preparingSource);
      expect(state.showsFullScreenOverlay, isTrue);
    });

    test('track switch has highest priority and shows overlay', () {
      final state = resolve(
        value: valueWith(phase: MpvPlaybackPhase.playing),
        flags: const PlaybackLoadingFlags(switchingTrack: true),
      );
      expect(state.kind, PlaybackLoadingKind.switchingTrack);
      expect(state.showsFullScreenOverlay, isTrue);
      expect(state.showsPlayButtonSpinner, isTrue);
    });

    test('buffering maps to buffering and shows overlay', () {
      final state = resolve(
        value: valueWith(phase: MpvPlaybackPhase.buffering),
      );
      expect(state.kind, PlaybackLoadingKind.buffering);
      expect(state.showsFullScreenOverlay, isTrue);
    });

    test(
      'seeking spins the play button but never shows full-screen overlay',
      () {
        final state = resolve(
          value: valueWith(phase: MpvPlaybackPhase.seeking),
        );
        expect(state.kind, PlaybackLoadingKind.seeking);
        expect(state.showsPlayButtonSpinner, isTrue);
        expect(
          state.showsFullScreenOverlay,
          isFalse,
          reason: 'seeking must not flash a full-screen scrim',
        );
      },
    );

    test('pending foreground transition → preparingSource', () {
      final state = resolve(
        value: valueWith(phase: MpvPlaybackPhase.playing),
        flags: const PlaybackLoadingFlags(pendingTransition: true),
      );
      expect(state.kind, PlaybackLoadingKind.preparingSource);
      expect(state.showsFullScreenOverlay, isTrue);
    });

    test('background transition stays invisible even while loading', () {
      final state = resolve(
        value: valueWith(phase: MpvPlaybackPhase.playing),
        flags: const PlaybackLoadingFlags(
          awaitingVisualStart: true,
          backgroundTransition: true,
        ),
      );
      expect(state.background, isTrue);
      expect(state.isForegroundLoading, isFalse);
      expect(state.showsFullScreenOverlay, isFalse);
      expect(state.showsPlayButtonSpinner, isFalse);
    });

    test('visible error suppresses loading (after source started)', () {
      final state = resolve(
        value: valueWith(phase: MpvPlaybackPhase.buffering),
        hasVisibleError: true,
      );
      expect(state.kind, PlaybackLoadingKind.none);
    });

    test('kernel not ready → preparingSource', () {
      final state = resolve(
        value: valueWith(
          phase: MpvPlaybackPhase.playing,
          ready: false,
          nativeLibLoaded: false,
        ),
      );
      expect(state.kind, PlaybackLoadingKind.preparingSource);
    });

    test('targetPaused flows through to state', () {
      final state = resolve(
        flags: const PlaybackLoadingFlags(
          pendingTransition: true,
          targetPaused: true,
        ),
      );
      expect(state.targetPaused, isTrue);
    });

    test('equality collapses identical states for cheap notifier diffing', () {
      const a = PlaybackLoadingState(kind: PlaybackLoadingKind.buffering);
      const b = PlaybackLoadingState(kind: PlaybackLoadingKind.buffering);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
