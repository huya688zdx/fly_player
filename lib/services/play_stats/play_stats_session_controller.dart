import '../../services/play_stats/play_stats_models.dart';
import '../../services/play_stats/play_stats_repositories.dart';

/// 定义片头片尾播放行为跟踪器的最小接口。
abstract class OpEdTracker {
  /// 设置当前播放条目识别出的片头与片尾区间。
  void setSegments({OpEdSegment? intro, OpEdSegment? outro});

  /// 在播放进度推进时同步片头片尾的观看状态。
  void onProgress({
    required int positionMs,
    required bool paused,
    required int mediaDurationMs,
  });

  /// 在用户执行拖动后同步片头片尾统计状态。
  void onSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  });

  /// 记录一次片头或片尾被主动跳过的行为。
  void markSkip({required bool intro});

  /// 记录一次片头或片尾提示被用户忽略的行为。
  void markDismiss({required bool intro});

  /// 生成当前会话结束时的片头片尾统计快照。
  OpEdSnapshot snapshotAtFinish();

  /// 重置跟踪器内部状态。
  void reset();
}

/// 定义单次播放会话统计控制器的统一接口。
abstract class PlayStatsSessionController {
  /// 启动一段新的播放统计会话。
  Future<void> startPlayback(PlayStatsStartContext context);

  /// 更新当前会话的媒体元数据。
  void updateMetadata(PlayStatsVideoMeta meta);

  /// 写入一次播放进度采样。
  void updateProgress({
    required int positionMs,
    required int mediaDurationMs,
    required bool paused,
    required DateTime now,
    required bool playbackCompleted,
  });

  /// 记录一次用户触发的拖动行为。
  void recordSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  });

  /// 提交本次会话识别出的片头与片尾区间。
  void markOpEdDetected({OpEdSegment? intro, OpEdSegment? outro});

  /// 记录一次片头或片尾跳过行为。
  void recordOpEdSkip({required bool intro});

  /// 记录一次片头或片尾忽略行为。
  void recordOpEdDismiss({required bool intro});

  /// 将当前会话状态持久化，但不结束会话。
  Future<void> flushPlayback({required String reason});

  /// 结束当前会话并持久化最终统计结果。
  Future<void> finishPlayback({required String reason});
}

/// 默认的本地播放统计会话控制器实现。
class DefaultPlayStatsSessionController implements PlayStatsSessionController {
  static const int _maxContinuousProgressDeltaMs = 3000;
  static const int _completedAfterSeekThresholdMs = 3000;
  static const double _episodeViewThreshold = 0.2;
  static const double _movieViewThreshold = 0.1;

  final PlayStatsRepository _repository;
  final OpEdTracker _opEdTracker;

  _ActivePlayStatsSession? _currentSession;
  Future<void> _persistQueue = Future<void>.value();

  /// 根据仓储实现与可选片头片尾跟踪器构造控制器。
  DefaultPlayStatsSessionController({
    required PlayStatsRepository repository,
    OpEdTracker? opEdTracker,
  }) : _repository = repository,
       _opEdTracker = opEdTracker ?? LocalOpEdTracker();

  /// 见 [PlayStatsSessionController.startPlayback]。
  @override
  Future<void> startPlayback(PlayStatsStartContext context) async {
    if (_currentSession != null) {
      await finishPlayback(reason: 'item_switch');
    }
    _opEdTracker.reset();
    _currentSession = _ActivePlayStatsSession.fromContext(context);
  }

  /// 见 [PlayStatsSessionController.updateMetadata]。
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

  /// 见 [PlayStatsSessionController.updateProgress]。
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

  /// 见 [PlayStatsSessionController.recordSeek]。
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

  /// 见 [PlayStatsSessionController.markOpEdDetected]。
  @override
  void markOpEdDetected({OpEdSegment? intro, OpEdSegment? outro}) {
    _opEdTracker.setSegments(intro: intro, outro: outro);
  }

  /// 见 [PlayStatsSessionController.recordOpEdSkip]。
  @override
  void recordOpEdSkip({required bool intro}) {
    _opEdTracker.markSkip(intro: intro);
  }

  /// 见 [PlayStatsSessionController.recordOpEdDismiss]。
  @override
  void recordOpEdDismiss({required bool intro}) {
    _opEdTracker.markDismiss(intro: intro);
  }

  /// 见 [PlayStatsSessionController.flushPlayback]。
  @override
  Future<void> flushPlayback({required String reason}) async {
    final session = _currentSession;
    if (session == null) return;
    await _enqueuePersist(_buildFinalizedSession(session, reason: reason));
  }

  /// 见 [PlayStatsSessionController.finishPlayback]。
  @override
  Future<void> finishPlayback({required String reason}) async {
    final session = _currentSession;
    if (session == null) return;
    _currentSession = null;
    final finalizedSession = _buildFinalizedSession(session, reason: reason);
    _opEdTracker.reset();
    await _enqueuePersist(finalizedSession);
  }

  FinalizedPlaySession _buildFinalizedSession(
    _ActivePlayStatsSession session, {
    required String reason,
  }) {
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
    return finalizedSession;
  }

  Future<void> _enqueuePersist(FinalizedPlaySession session) {
    Future<void> persist() => _repository.persistFinalizedSession(session);
    final next = _persistQueue.then<void>(
      (_) => persist(),
      onError: (_, __) => persist(),
    );
    _persistQueue = next.catchError((_) {});
    return next;
  }

  double _viewThresholdFor(String videoKind) {
    return videoKind.trim().toLowerCase() == 'movie'
        ? _movieViewThreshold
        : _episodeViewThreshold;
  }
}

/// 在本地会话中统计片头片尾观看行为的默认实现。
class LocalOpEdTracker implements OpEdTracker {
  static const int _maxProgressDeltaMs = 3000;
  static const double _notSkippedThreshold = 0.8;

  _TrackedOpEdState? _intro;
  _TrackedOpEdState? _outro;
  int? _lastPositionMs;
  bool _seekJustHappened = false;

  /// 见 [OpEdTracker.setSegments]。
  @override
  void setSegments({OpEdSegment? intro, OpEdSegment? outro}) {
    _intro = intro == null ? null : _mergeSegmentState(_intro, intro);
    _outro = outro == null ? null : _mergeSegmentState(_outro, outro);
  }

  /// 见 [OpEdTracker.onProgress]。
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

  /// 见 [OpEdTracker.onSeek]。
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

  /// 见 [OpEdTracker.markSkip]。
  @override
  void markSkip({required bool intro}) {
    final state = intro ? _intro : _outro;
    if (state == null) return;
    state.skipped = true;
  }

  /// 见 [OpEdTracker.markDismiss]。
  @override
  void markDismiss({required bool intro}) {
    final state = intro ? _intro : _outro;
    if (state == null) return;
    state.dismissed = true;
  }

  /// 见 [OpEdTracker.snapshotAtFinish]。
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

  /// 见 [OpEdTracker.reset]。
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
