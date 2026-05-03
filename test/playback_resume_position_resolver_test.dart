import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:fly_player/services/play_stats/play_stats.dart';
import 'package:fly_player/utils/playback_resume_position_resolver.dart';

void main() {
  test('uses network progress before local database progress', () async {
    final repository = _FakeVideoStatsRepository(<String, VideoStatsRecord>{
      'episode-1': _stats(videoId: 'episode-1', lastPositionMs: 90000),
    });

    final resolved = await PlaybackResumePositionResolver.resolve(
      videoIds: const <String>['episode-1'],
      durationSeconds: 120,
      networkPositionSeconds: 30,
      networkPositionAvailable: true,
      videoStatsRepository: repository,
    );

    expect(resolved.position, const Duration(seconds: 30));
    expect(resolved.effectiveDurationSeconds, 120);
    expect(resolved.fromLocalDatabase, isFalse);
  });

  test(
    'falls back to local database progress when network is unavailable',
    () async {
      final repository = _FakeVideoStatsRepository(<String, VideoStatsRecord>{
        'episode-1': _stats(videoId: 'episode-1', lastPositionMs: 90000),
      });

      final resolved = await PlaybackResumePositionResolver.resolve(
        videoIds: const <String>['episode-1'],
        durationSeconds: 120,
        networkPositionAvailable: false,
        videoStatsRepository: repository,
      );

      expect(resolved.position, const Duration(seconds: 90));
      expect(resolved.effectiveDurationSeconds, 120);
      expect(resolved.fromLocalDatabase, isTrue);
    },
  );

  test('uses database duration and resets completed local records', () async {
    final repository = _FakeVideoStatsRepository(<String, VideoStatsRecord>{
      'episode-1': _stats(
        videoId: 'episode-1',
        lastPositionMs: 110000,
        mediaDurationMs: 120000,
        completed: true,
      ),
    });

    final resolved = await PlaybackResumePositionResolver.resolve(
      videoIds: const <String>['episode-1'],
      durationSeconds: 0,
      networkPositionAvailable: false,
      videoStatsRepository: repository,
    );

    expect(resolved.position, Duration.zero);
    expect(resolved.effectiveDurationSeconds, 120);
    expect(resolved.fromLocalDatabase, isTrue);
  });
}

VideoStatsRecord _stats({
  required String videoId,
  required int lastPositionMs,
  int mediaDurationMs = 0,
  bool completed = false,
}) {
  return VideoStatsRecord(
    videoId: videoId,
    animeId: 'anime-$videoId',
    seasonId: 'season-$videoId',
    title: 'Title $videoId',
    animeTitle: 'Anime $videoId',
    seasonTitle: 'Season $videoId',
    videoKind: 'episode',
    countsTowardCompletion: true,
    country: '',
    year: 2024,
    mediaDurationMs: mediaDurationMs,
    clickCount: 0,
    autoPlayCount: 0,
    viewCount: 0,
    totalPlayedMs: 0,
    maxProgress: 0,
    lastProgress: 0,
    lastPositionMs: lastPositionMs,
    completed: completed,
    metadataEnriched: false,
    lastPlayedAtMs: 0,
    credits: const <PlayStatsCredit>[],
  );
}

class _FakeVideoStatsRepository implements VideoStatsRepository {
  final Map<String, VideoStatsRecord> records;

  const _FakeVideoStatsRepository(this.records);

  @override
  Future<VideoStatsRecord?> getByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  }) async {
    return records[videoId.trim()];
  }

  @override
  Future<List<String>> listMetadataBackfillCandidateIds({
    int limit = 20,
    DatabaseExecutor? executor,
  }) async {
    return const <String>[];
  }

  @override
  Future<void> upsert(
    VideoStatsRecord record, {
    DatabaseExecutor? executor,
  }) async {}

  @override
  Future<int> countSeasonMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) async {
    return 0;
  }

  @override
  Future<int> countSeasonWatchedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) async {
    return 0;
  }

  @override
  Future<int> countSeasonCompletedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) async {
    return 0;
  }

  @override
  Future<int> countAnimeWatchedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  }) async {
    return 0;
  }

  @override
  Future<int> countAnimeCompletedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  }) async {
    return 0;
  }
}
