import '../../services/play_stats/play_stats_models.dart';
import '../../services/play_stats/play_stats_repositories.dart';

abstract class OpEdTracker {
  void setSegments({OpEdSegment? intro, OpEdSegment? outro});
  void onProgress({
    required int positionMs,
    required bool paused,
    required int mediaDurationMs,
  });
  void onSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  });
  void markSkip({required bool intro});
  void markDismiss({required bool intro});
  OpEdSnapshot snapshotAtFinish();
  void reset();
}

abstract class PlayStatsSessionController {
  Future<void> startPlayback(PlayStatsStartContext context);
  void updateMetadata(PlayStatsVideoMeta meta);
  void updateProgress({
    required int positionMs,
    required int mediaDurationMs,
    required bool paused,
    required DateTime now,
    required bool playbackCompleted,
  });
  void recordSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  });
  void markOpEdDetected({OpEdSegment? intro, OpEdSegment? outro});
  void recordOpEdSkip({required bool intro});
  void recordOpEdDismiss({required bool intro});
  Future<void> finishPlayback({required String reason});
}

class DefaultPlayStatsSessionController implements PlayStatsSessionController {
  static const int _maxContinuousProgressDeltaMs = 3000;
  static const int _completedAfterSeekThresholdMs = 3000;
  static const double _episodeViewThreshold = 0.2;
  static const double _movieViewThreshold = 0.1;

  final PlayStatsRepository _repository;
  final OpEdTracker _opEdTracker;

  _ActivePlayStatsSession? _currentSession;

  DefaultPlayStatsSessionController({
    required PlayStatsRepository repository,
    OpEdTracker? opEdTracker,
  }) : _repository = repository,
       _opEdTracker = opEdTracker ?? LocalOpEdTracker();

  @override
  Future<void> startPlayback(PlayStatsStartContext context) async {
    if (_currentSession != null) {
      await finishPlayback(reason: 'item_switch');
    }
    _opEdTracker.reset();
    _currentSession = _ActivePlayStatsSession.fromContext(context);
  }

  @override
  void updateMetadata(PlayStatsVideoMeta meta) {
    final session = _currentSession;
    if (session == null) return;
    if (session.meta.videoId != meta.videoId) return;
    session.meta = meta;
    if (meta.mediaDurationMs > 0) {
      session.mediaDurationMs = meta.mediaDurationMs;
    }
  }

  @override
  void updateProgress({
    required int positionMs,
    required int mediaDurationMs,
    required bool paused,
    required DateTime now,
    required bool playbackCompleted,
  }) {
    final session = _currentSession;
    if (session == null) return;
    final safePositionMs = positionMs < 0 ? 0 : positionMs;
    final safeDurationMs = mediaDurationMs > 0
        ? mediaDurationMs
        : session.mediaDurationMs;
    session.mediaDurationMs = safeDurationMs;
    session.currentPositionMs = safePositionMs;
    if (safePositionMs > session.maxPositionMs) {
      session.maxPositionMs = safePositionMs;
    }
    final progress = safeDurationMs > 0
        ? (safePositionMs / safeDurationMs).clamp(0.0, 1.0)
        : 0.0;
    if (progress > session.maxProgress) {
      session.maxProgress = progress;
    }
    if (playbackCompleted) {
      session.playbackCompletedObserved = true;
    }
    _opEdTracker.onProgress(
      positionMs: safePositionMs,
      paused: paused,
      mediaDurationMs: safeDurationMs,
    );
    final nowMs = now.millisecondsSinceEpoch;
    if (session.lastPositionMs == null || session.lastObservedAtMs == null) {
      session.lastPositionMs = safePositionMs;
      session.lastObservedAtMs = nowMs;
      return;
    }
    if (paused) {
      session.lastPositionMs = safePositionMs;
      session.lastObservedAtMs = nowMs;
      return;
    }
    if (session.seekJustHappened) {
      session.seekJustHappened = false;
      session.lastPositionMs = safePositionMs;
      session.lastObservedAtMs = nowMs;
      return;
    }
    final deltaPositionMs = safePositionMs - session.lastPositionMs!;
    if (deltaPositionMs > 0 &&
        deltaPositionMs <= _maxContinuousProgressDeltaMs) {
      session.watchedMs += deltaPositionMs;
      session.playedAfterLastSeekMs += deltaPositionMs;
    }
    session.lastPositionMs = safePositionMs;
    session.lastObservedAtMs = nowMs;
  }

  @override
  void recordSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  }) {
    final session = _currentSession;
    if (session == null || !userInitiated) {
      return;
    }
    if (toMs > fromMs) {
      session.forwardSeekCount += 1;
    } else if (toMs < fromMs) {
      session.backwardSeekCount += 1;
    } else {
      return;
    }
    final safeToMs = toMs < 0 ? 0 : toMs;
    session.currentPositionMs = safeToMs;
    if (safeToMs > session.maxPositionMs) {
      session.maxPositionMs = safeToMs;
    }
    if (session.mediaDurationMs > 0) {
      final seekProgress = (safeToMs / session.mediaDurationMs).clamp(0.0, 1.0);
      if (seekProgress > session.maxProgress) {
        session.maxProgress = seekProgress;
      }
    }
    session.seekJustHappened = true;
    session.playedAfterLastSeekMs = 0;
    _opEdTracker.onSeek(
      fromMs: fromMs,
      toMs: toMs,
      userInitiated: userInitiated,
    );
  }

  @override
  void markOpEdDetected({OpEdSegment? intro, OpEdSegment? outro}) {
    _opEdTracker.setSegments(intro: intro, outro: outro);
  }

  @override
  void recordOpEdSkip({required bool intro}) {
    _opEdTracker.markSkip(intro: intro);
  }

  @override
  void recordOpEdDismiss({required bool intro}) {
    _opEdTracker.markDismiss(intro: intro);
  }

  @override
  Future<void> finishPlayback({required String reason}) async {
    final session = _currentSession;
    if (session == null) return;
    _currentSession = null;
    final endedAtMs = DateTime.now().millisecondsSinceEpoch;
    final mediaDurationMs = session.mediaDurationMs < 0
        ? 0
        : session.mediaDurationMs;
    final countedAsView =
        mediaDurationMs > 0 &&
        session.watchedMs >=
            (mediaDurationMs * _viewThresholdFor(session.meta.videoKind));
    final countedAsCompleted = mediaDurationMs <= 0
        ? session.playbackCompletedObserved
        : session.maxProgress >= 0.8 &&
              (session.playedAfterLastSeekMs >=
                      _completedAfterSeekThresholdMs ||
                  session.playbackCompletedObserved);
    final opEdSnapshot = _opEdTracker.snapshotAtFinish();
    final history = PlayHistoryRecord(
      historyId: session.historyId,
      videoId: session.meta.videoId,
      animeId: session.meta.animeId,
      seasonId: session.meta.seasonId,
      title: session.meta.title,
      animeTitle: session.meta.animeTitle,
      seasonTitle: session.meta.seasonTitle,
      videoKind: session.meta.videoKind,
      countsTowardCompletion: session.meta.countsTowardCompletion,
      countryCodes: session.meta.countryCodes,
      genreIds: session.meta.genreIds,
      credits: session.meta.credits,
      startSource: session.startSource,
      startedAtMs: session.startedAtMs,
      endedAtMs: endedAtMs,
      mediaDurationMs: mediaDurationMs,
      watchedMs: session.watchedMs < 0 ? 0 : session.watchedMs,
      maxProgress: session.maxProgress.clamp(0.0, 1.0),
      maxPositionMs: session.maxPositionMs < 0 ? 0 : session.maxPositionMs,
      countedAsView: countedAsView,
      countedAsCompleted: countedAsCompleted,
      opDetected: opEdSnapshot.opDetected,
      edDetected: opEdSnapshot.edDetected,
      opSkipped: opEdSnapshot.opSkipped,
      edSkipped: opEdSnapshot.edSkipped,
      opNotSkipped: opEdSnapshot.opNotSkipped,
      edNotSkipped: opEdSnapshot.edNotSkipped,
      opPlayedMs: opEdSnapshot.opPlayedMs,
      edPlayedMs: opEdSnapshot.edPlayedMs,
      forwardSeekCount: session.forwardSeekCount,
      backwardSeekCount: session.backwardSeekCount,
    );
    final finalizedSession = FinalizedPlaySession(
      history: history,
      meta: session.meta,
      clickDelta: session.clickDelta,
      autoPlayDelta: session.autoPlayDelta,
      lastPositionMs: session.currentPositionMs < 0
          ? 0
          : session.currentPositionMs,
      finishReason: reason,
    );
    _opEdTracker.reset();
    await _repository.persistFinalizedSession(finalizedSession);
  }

  double _viewThresholdFor(String videoKind) {
    return videoKind.trim().toLowerCase() == 'movie'
        ? _movieViewThreshold
        : _episodeViewThreshold;
  }
}

class LocalOpEdTracker implements OpEdTracker {
  static const int _maxProgressDeltaMs = 3000;
  static const double _notSkippedThreshold = 0.8;

  _TrackedOpEdState? _intro;
  _TrackedOpEdState? _outro;
  int? _lastPositionMs;
  bool _seekJustHappened = false;

  @override
  void setSegments({OpEdSegment? intro, OpEdSegment? outro}) {
    _intro = intro == null ? null : _mergeSegmentState(_intro, intro);
    _outro = outro == null ? null : _mergeSegmentState(_outro, outro);
  }

  @override
  void onProgress({
    required int positionMs,
    required bool paused,
    required int mediaDurationMs,
  }) {
    final safePositionMs = positionMs < 0 ? 0 : positionMs;
    if (_lastPositionMs == null) {
      _lastPositionMs = safePositionMs;
      return;
    }
    if (paused || _seekJustHappened) {
      _seekJustHappened = false;
      _lastPositionMs = safePositionMs;
      return;
    }
    final deltaMs = safePositionMs - _lastPositionMs!;
    if (deltaMs > 0 && deltaMs <= _maxProgressDeltaMs) {
      _addOverlap(_intro, _lastPositionMs!, safePositionMs);
      _addOverlap(_outro, _lastPositionMs!, safePositionMs);
    }
    _lastPositionMs = safePositionMs;
  }

  @override
  void onSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  }) {
    if (!userInitiated) return;
    _seekJustHappened = true;
    _lastPositionMs = toMs;
  }

  @override
  void markSkip({required bool intro}) {
    final state = intro ? _intro : _outro;
    if (state == null) return;
    state.skipped = true;
  }

  @override
  void markDismiss({required bool intro}) {
    final state = intro ? _intro : _outro;
    if (state == null) return;
    state.dismissed = true;
  }

  @override
  OpEdSnapshot snapshotAtFinish() {
    final introNotSkipped = _resolveNotSkipped(_intro);
    final outroNotSkipped = _resolveNotSkipped(_outro);
    return OpEdSnapshot(
      opDetected: _intro != null,
      edDetected: _outro != null,
      opSkipped: _intro?.skipped ?? false,
      edSkipped: _outro?.skipped ?? false,
      opNotSkipped: introNotSkipped,
      edNotSkipped: outroNotSkipped,
      opPlayedMs: _intro?.playedMs ?? 0,
      edPlayedMs: _outro?.playedMs ?? 0,
    );
  }

  @override
  void reset() {
    _intro = null;
    _outro = null;
    _lastPositionMs = null;
    _seekJustHappened = false;
  }

  _TrackedOpEdState? _mergeSegmentState(
    _TrackedOpEdState? current,
    OpEdSegment? next,
  ) {
    if (next == null) return current;
    if (current != null &&
        current.segment.isIntro == next.isIntro &&
        current.segment.startMs == next.startMs &&
        current.segment.endMs == next.endMs) {
      return current;
    }
    return _TrackedOpEdState(segment: next);
  }

  void _addOverlap(_TrackedOpEdState? state, int fromMs, int toMs) {
    if (state == null || state.skipped) return;
    final overlapStart = fromMs > state.segment.startMs
        ? fromMs
        : state.segment.startMs;
    final overlapEnd = toMs < state.segment.endMs ? toMs : state.segment.endMs;
    if (overlapEnd <= overlapStart) return;
    state.playedMs += overlapEnd - overlapStart;
  }

  bool _resolveNotSkipped(_TrackedOpEdState? state) {
    if (state == null || state.skipped) return false;
    final durationMs = state.segment.durationMs;
    if (durationMs <= 0) return false;
    return state.playedMs >= (durationMs * _notSkippedThreshold);
  }
}

class _TrackedOpEdState {
  final OpEdSegment segment;
  bool skipped = false;
  bool dismissed = false;
  int playedMs = 0;

  _TrackedOpEdState({required this.segment});
}

class _ActivePlayStatsSession {
  final String historyId;
  PlayStatsVideoMeta meta;
  final PlayStartSource startSource;
  final int startedAtMs;
  final int clickDelta;
  final int autoPlayDelta;
  int mediaDurationMs;
  int watchedMs = 0;
  double maxProgress;
  int maxPositionMs;
  int currentPositionMs;
  int forwardSeekCount = 0;
  int backwardSeekCount = 0;
  int playedAfterLastSeekMs = 0;
  bool playbackCompletedObserved = false;
  bool seekJustHappened = false;
  int? lastPositionMs;
  int? lastObservedAtMs;

  _ActivePlayStatsSession({
    required this.historyId,
    required this.meta,
    required this.startSource,
    required this.startedAtMs,
    required this.clickDelta,
    required this.autoPlayDelta,
    required this.mediaDurationMs,
    required this.maxPositionMs,
    required this.currentPositionMs,
    required this.maxProgress,
    this.lastPositionMs,
    this.lastObservedAtMs,
  });

  factory _ActivePlayStatsSession.fromContext(PlayStatsStartContext context) {
    final nowId = DateTime.now().microsecondsSinceEpoch;
    final clickDelta =
        context.startSource == PlayStartSource.manual ||
            context.startSource == PlayStartSource.manualSwitch
        ? 1
        : 0;
    final autoPlayDelta = context.startSource == PlayStartSource.autoNext
        ? 1
        : 0;
    final mediaDurationMs = context.meta.mediaDurationMs > 0
        ? context.meta.mediaDurationMs
        : 0;
    final startPositionMs = context.startPositionMs < 0
        ? 0
        : context.startPositionMs;
    final maxProgress = mediaDurationMs > 0
        ? (startPositionMs / mediaDurationMs).clamp(0.0, 1.0)
        : 0.0;
    return _ActivePlayStatsSession(
      historyId: 'history_$nowId',
      meta: context.meta,
      startSource: context.startSource,
      startedAtMs: context.startedAtMs,
      clickDelta: clickDelta,
      autoPlayDelta: autoPlayDelta,
      mediaDurationMs: mediaDurationMs,
      maxPositionMs: startPositionMs,
      currentPositionMs: startPositionMs,
      maxProgress: maxProgress,
      lastPositionMs: startPositionMs,
      lastObservedAtMs: context.startedAtMs,
    );
  }
}
