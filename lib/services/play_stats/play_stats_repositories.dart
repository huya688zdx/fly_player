import 'package:sqflite/sqflite.dart';

import 'play_stats_database.dart';
import 'play_stats_mappers.dart';
import 'play_stats_models.dart';

abstract class PlayHistoryStore {
  Future<void> insert(PlayHistoryRecord record, {DatabaseExecutor? executor});
  Future<List<PlayHistoryRecord>> listRecent({int limit = 50});
  Future<List<PlayHistoryRecord>> listByAnime(
    String animeId, {
    int limit = 100,
  });
}

abstract class VideoStatsRepository {
  Future<VideoStatsRecord?> getByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  });
  Future<List<String>> listMetadataBackfillCandidateIds({
    int limit = 20,
    DatabaseExecutor? executor,
  });
  Future<void> upsert(VideoStatsRecord record, {DatabaseExecutor? executor});
  Future<int> countSeasonMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });
  Future<int> countSeasonWatchedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });
  Future<int> countSeasonCompletedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });
  Future<int> countAnimeWatchedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  });
  Future<int> countAnimeCompletedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  });
}

abstract class VideoCreditStatsRepository {
  Future<void> replaceForVideo(
    String videoId,
    List<VideoCreditRecord> records, {
    DatabaseExecutor? executor,
  });

  Future<List<VideoCreditRecord>> listByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  });
}

abstract class AnimeStatsRepository {
  Future<AnimeStatsRecord?> getByAnimeId(
    String animeId, {
    DatabaseExecutor? executor,
  });
  Future<void> upsert(AnimeStatsRecord record, {DatabaseExecutor? executor});
}

abstract class SeasonStatsRepository {
  Future<SeasonStatsRecord?> getBySeasonId(
    String seasonId, {
    DatabaseExecutor? executor,
  });
  Future<void> upsert(SeasonStatsRecord record, {DatabaseExecutor? executor});
  Future<int> countCompletedSeasonsByAnime(
    String animeId, {
    DatabaseExecutor? executor,
  });
}

abstract class PlayStatsRepository {
  Future<void> persistFinalizedSession(FinalizedPlaySession session);
  Future<void> clearAll();
}

class SqflitePlayHistoryStore implements PlayHistoryStore {
  final PlayStatsDatabase _database;

  const SqflitePlayHistoryStore(this._database);

  @override
  Future<void> insert(
    PlayHistoryRecord record, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    await db.insert(
      'play_history',
      PlayStatsSqlMapper.playHistoryToMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<PlayHistoryRecord>> listRecent({int limit = 50}) async {
    final db = await _database.rawDatabase;
    final rows = await db.query(
      'play_history',
      orderBy: 'started_at_ms DESC',
      limit: limit,
    );
    return rows
        .map((row) => PlayStatsSqlMapper.playHistoryFromMap(row))
        .toList(growable: false);
  }

  @override
  Future<List<PlayHistoryRecord>> listByAnime(
    String animeId, {
    int limit = 100,
  }) async {
    final db = await _database.rawDatabase;
    final rows = await db.query(
      'play_history',
      where: 'anime_id = ?',
      whereArgs: <Object?>[animeId],
      orderBy: 'started_at_ms DESC',
      limit: limit,
    );
    return rows
        .map((row) => PlayStatsSqlMapper.playHistoryFromMap(row))
        .toList(growable: false);
  }
}

class SqfliteVideoStatsRepository implements VideoStatsRepository {
  final PlayStatsDatabase _database;

  const SqfliteVideoStatsRepository(this._database);

  @override
  Future<VideoStatsRecord?> getByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'video_stats',
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlayStatsSqlMapper.videoStatsFromMap(rows.first);
  }

  @override
  Future<List<String>> listMetadataBackfillCandidateIds({
    int limit = 20,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'video_stats',
      columns: const <String>['video_id'],
      where: 'metadata_enriched = 0',
      orderBy: 'last_played_at_ms DESC, total_played_ms DESC',
      limit: limit,
    );
    return rows
        .map((row) => PlayStatsSqlMapper.stringValue(row['video_id']).trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> upsert(
    VideoStatsRecord record, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    await db.insert(
      'video_stats',
      PlayStatsSqlMapper.videoStatsToMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> countSeasonMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) {
    return _count(
      'SELECT COUNT(*) FROM video_stats WHERE season_id = ? AND counts_toward_completion = 1',
      <Object?>[seasonId],
      executor: executor,
    );
  }

  @override
  Future<int> countSeasonWatchedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) {
    return _count(
      'SELECT COUNT(*) FROM video_stats WHERE season_id = ? AND counts_toward_completion = 1 AND view_count > 0',
      <Object?>[seasonId],
      executor: executor,
    );
  }

  @override
  Future<int> countSeasonCompletedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  }) {
    return _count(
      'SELECT COUNT(*) FROM video_stats WHERE season_id = ? AND counts_toward_completion = 1 AND completed = 1',
      <Object?>[seasonId],
      executor: executor,
    );
  }

  @override
  Future<int> countAnimeWatchedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  }) {
    return _count(
      'SELECT COUNT(*) FROM video_stats WHERE anime_id = ? AND counts_toward_completion = 1 AND view_count > 0',
      <Object?>[animeId],
      executor: executor,
    );
  }

  @override
  Future<int> countAnimeCompletedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  }) {
    return _count(
      'SELECT COUNT(*) FROM video_stats WHERE anime_id = ? AND counts_toward_completion = 1 AND completed = 1',
      <Object?>[animeId],
      executor: executor,
    );
  }

  Future<int> _count(
    String sql,
    List<Object?> args, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.rawQuery(sql, args);
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}

class SqfliteVideoCreditStatsRepository implements VideoCreditStatsRepository {
  final PlayStatsDatabase _database;

  const SqfliteVideoCreditStatsRepository(this._database);

  @override
  Future<void> replaceForVideo(
    String videoId,
    List<VideoCreditRecord> records, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    await db.delete(
      'video_credit_stats',
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
    );
    for (final record in records) {
      await db.insert(
        'video_credit_stats',
        PlayStatsSqlMapper.videoCreditToMap(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<List<VideoCreditRecord>> listByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'video_credit_stats',
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
      orderBy: 'credit_order ASC, rowid ASC',
    );
    return rows
        .map((row) => PlayStatsSqlMapper.videoCreditFromMap(row))
        .toList(growable: false);
  }
}

class SqfliteAnimeStatsRepository implements AnimeStatsRepository {
  final PlayStatsDatabase _database;

  const SqfliteAnimeStatsRepository(this._database);

  @override
  Future<AnimeStatsRecord?> getByAnimeId(
    String animeId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'anime_stats',
      where: 'anime_id = ?',
      whereArgs: <Object?>[animeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlayStatsSqlMapper.animeStatsFromMap(rows.first);
  }

  @override
  Future<void> upsert(
    AnimeStatsRecord record, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    await db.insert(
      'anime_stats',
      PlayStatsSqlMapper.animeStatsToMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class SqfliteSeasonStatsRepository implements SeasonStatsRepository {
  final PlayStatsDatabase _database;

  const SqfliteSeasonStatsRepository(this._database);

  @override
  Future<SeasonStatsRecord?> getBySeasonId(
    String seasonId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'season_stats',
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlayStatsSqlMapper.seasonStatsFromMap(rows.first);
  }

  @override
  Future<void> upsert(
    SeasonStatsRecord record, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    await db.insert(
      'season_stats',
      PlayStatsSqlMapper.seasonStatsToMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> countCompletedSeasonsByAnime(
    String animeId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) FROM season_stats WHERE anime_id = ? AND is_completed = 1',
      <Object?>[animeId],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
