import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/controllers/play_stats_session_controller.dart';
import 'package:fly_player/services/play_stats/play_stats.dart';

void main() {
  test('counts views using episode 20% and movie 10% thresholds', () async {
    final repository = _FakePlayStatsRepository();
    final controller = DefaultPlayStatsSessionController(
      repository: repository,
    );
    final startedAt = DateTime(2026, 3, 24, 20);

    await _playSession(
      controller: controller,
      meta: _meta(videoId: 'episode-1', videoKind: 'episode'),
      startedAt: startedAt,
      watchedMs: 19000,
      durationMs: 100000,
    );
    await _playSession(
      controller: controller,
      meta: _meta(videoId: 'episode-2', videoKind: 'episode'),
      startedAt: startedAt.add(const Duration(minutes: 1)),
      watchedMs: 20000,
      durationMs: 100000,
    );
    await _playSession(
      controller: controller,
      meta: _meta(videoId: 'movie-1', videoKind: 'movie'),
      startedAt: startedAt.add(const Duration(minutes: 2)),
      watchedMs: 10000,
      durationMs: 100000,
    );

    expect(repository.sessions, hasLength(3));
    expect(repository.sessions[0].history.countedAsView, isFalse);
    expect(repository.sessions[1].history.countedAsView, isTrue);
    expect(repository.sessions[2].history.countedAsView, isTrue);
  });

  test('periodic flush and finish update the same play history', () async {
    final repository = _FakePlayStatsRepository();
    final controller = DefaultPlayStatsSessionController(
      repository: repository,
    );
    final startedAt = DateTime(2026, 3, 24, 20);
    final meta = _meta(videoId: 'episode-1', videoKind: 'episode');

    await controller.startPlayback(
      PlayStatsStartContext(
        startSource: PlayStartSource.manual,
        meta: meta,
        startPositionMs: 0,
        startedAtMs: startedAt.millisecondsSinceEpoch,
      ),
    );
    controller.updateProgress(
      positionMs: 0,
      mediaDurationMs: 100000,
      paused: false,
      now: startedAt,
      playbackCompleted: false,
    );
    for (var position = 1000; position <= 5000; position += 1000) {
      controller.updateProgress(
        positionMs: position,
        mediaDurationMs: 100000,
        paused: false,
        now: startedAt.add(Duration(milliseconds: position)),
        playbackCompleted: false,
      );
    }

    await controller.flushPlayback(reason: 'periodic');

    for (var position = 6000; position <= 10000; position += 1000) {
      controller.updateProgress(
        positionMs: position,
        mediaDurationMs: 100000,
        paused: false,
        now: startedAt.add(Duration(milliseconds: position)),
        playbackCompleted: false,
      );
    }
    await controller.finishPlayback(reason: 'close');

    expect(repository.sessions, hasLength(2));
    expect(
      repository.sessions[0].history.historyId,
      repository.sessions[1].history.historyId,
    );
    expect(repository.sessions[0].finishReason, 'periodic');
    expect(repository.sessions[1].finishReason, 'close');
    expect(
      repository.sessions[1].history.watchedMs,
      greaterThan(repository.sessions[0].history.watchedMs),
    );
  });
}

Future<void> _playSession({
  required DefaultPlayStatsSessionController controller,
  required PlayStatsVideoMeta meta,
  required DateTime startedAt,
  required int watchedMs,
  required int durationMs,
}) async {
  await controller.startPlayback(
    PlayStatsStartContext(
      startSource: PlayStartSource.manual,
      meta: meta,
      startPositionMs: 0,
      startedAtMs: startedAt.millisecondsSinceEpoch,
    ),
  );
  controller.updateProgress(
    positionMs: 0,
    mediaDurationMs: durationMs,
    paused: false,
    now: startedAt,
    playbackCompleted: false,
  );
  for (var position = 1000; position <= watchedMs; position += 1000) {
    controller.updateProgress(
      positionMs: position,
      mediaDurationMs: durationMs,
      paused: false,
      now: startedAt.add(Duration(milliseconds: position)),
      playbackCompleted: false,
    );
  }
  await controller.finishPlayback(reason: 'test');
}

PlayStatsVideoMeta _meta({required String videoId, required String videoKind}) {
  return PlayStatsVideoMeta(
    videoId: videoId,
    animeId: 'anime-$videoId',
    seasonId: 'season-$videoId',
    title: 'Title $videoId',
    animeTitle: 'Anime $videoId',
    seasonTitle: 'Season $videoId',
    videoKind: videoKind,
    countsTowardCompletion: true,
    country: '',
    year: 2024,
    mediaDurationMs: 100000,
  );
}

class _FakePlayStatsRepository implements PlayStatsRepository {
  final List<FinalizedPlaySession> sessions = <FinalizedPlaySession>[];

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> persistFinalizedSession(FinalizedPlaySession session) async {
    sessions.add(session);
  }
}
