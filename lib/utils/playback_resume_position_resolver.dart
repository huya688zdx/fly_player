import 'package:flutter/foundation.dart';

import '../services/play_stats/play_stats.dart';

class ResolvedPlaybackResumePosition {
  final Duration position;
  final int effectiveDurationSeconds;
  final bool fromLocalDatabase;

  const ResolvedPlaybackResumePosition({
    required this.position,
    required this.effectiveDurationSeconds,
    required this.fromLocalDatabase,
  });
}

class PlaybackResumePositionResolver {
  const PlaybackResumePositionResolver._();

  static Future<ResolvedPlaybackResumePosition> resolve({
    required Iterable<String> videoIds,
    required int durationSeconds,
    int networkPositionSeconds = 0,
    bool networkPositionAvailable = false,
    bool networkCompleted = false,
    bool resetCompletedToBeginning = true,
    VideoStatsRepository? videoStatsRepository,
  }) async {
    final safeDurationSeconds = _nonNegative(durationSeconds);
    if (networkPositionAvailable) {
      return ResolvedPlaybackResumePosition(
        position: _normalizePosition(
          positionSeconds: networkPositionSeconds,
          durationSeconds: safeDurationSeconds,
          completed: networkCompleted,
          resetCompletedToBeginning: resetCompletedToBeginning,
        ),
        effectiveDurationSeconds: safeDurationSeconds,
        fromLocalDatabase: false,
      );
    }

    final local = await _loadLocalVideoStats(
      videoIds,
      videoStatsRepository ?? PlayStatsService.instance.videoStatsRepository,
    );
    if (local == null) {
      return ResolvedPlaybackResumePosition(
        position: Duration.zero,
        effectiveDurationSeconds: safeDurationSeconds,
        fromLocalDatabase: false,
      );
    }

    final localDurationSeconds = safeDurationSeconds > 0
        ? safeDurationSeconds
        : _durationSecondsFromStats(local);
    return ResolvedPlaybackResumePosition(
      position: _normalizePosition(
        positionSeconds: local.lastPositionMs ~/ 1000,
        durationSeconds: localDurationSeconds,
        completed: local.completed,
        resetCompletedToBeginning: resetCompletedToBeginning,
      ),
      effectiveDurationSeconds: localDurationSeconds,
      fromLocalDatabase: true,
    );
  }

  static Future<VideoStatsRecord?> _loadLocalVideoStats(
    Iterable<String> videoIds,
    VideoStatsRepository repository,
  ) async {
    final tried = <String>{};
    for (final rawVideoId in videoIds) {
      final videoId = rawVideoId.trim();
      if (videoId.isEmpty || !tried.add(videoId)) continue;
      try {
        final record = await repository.getByVideoId(videoId);
        if (record != null) return record;
      } catch (error, stackTrace) {
        debugPrint(
          'Failed to load local playback resume position for $videoId: '
          '$error\n$stackTrace',
        );
      }
    }
    return null;
  }

  static Duration _normalizePosition({
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
    required bool resetCompletedToBeginning,
  }) {
    if (resetCompletedToBeginning && completed) return Duration.zero;
    final safePositionSeconds = _nonNegative(positionSeconds);
    if (durationSeconds <= 0) {
      return Duration(seconds: safePositionSeconds);
    }
    final clamped = safePositionSeconds.clamp(0, durationSeconds).toInt();
    if (resetCompletedToBeginning && clamped >= durationSeconds) {
      return Duration.zero;
    }
    return Duration(seconds: clamped);
  }

  static int _durationSecondsFromStats(VideoStatsRecord record) {
    if (record.mediaDurationMs <= 0) return 0;
    return record.mediaDurationMs ~/ 1000;
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;
}
