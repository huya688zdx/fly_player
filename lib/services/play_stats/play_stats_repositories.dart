import 'package:sqflite/sqflite.dart';

import 'play_stats_database.dart';
import 'play_stats_mappers.dart';
import 'play_stats_models.dart';

/// 定义播放历史记录的持久化接口。
abstract class PlayHistoryStore {
  /// 按历史记录标识查询单条播放历史。
  Future<PlayHistoryRecord?> getByHistoryId(
    String historyId, {
    DatabaseExecutor? executor,
  });

  /// 写入一条播放历史记录。
  Future<void> insert(PlayHistoryRecord record, {DatabaseExecutor? executor});

  /// 按时间倒序返回最近播放历史。
  Future<List<PlayHistoryRecord>> listRecent({int limit = 50});

  /// 返回指定番剧下的播放历史列表。
  Future<List<PlayHistoryRecord>> listByAnime(
    String animeId, {
    int limit = 100,
  });
}

/// 定义视频维度统计记录的持久化接口。
abstract class VideoStatsRepository {
  /// 按视频标识查询统计记录。
  Future<VideoStatsRecord?> getByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  });

  /// 列出需要补全元数据的视频标识。
  Future<List<String>> listMetadataBackfillCandidateIds({
    int limit = 20,
    DatabaseExecutor? executor,
  });

  /// 插入或更新一条视频统计记录。
  Future<void> upsert(VideoStatsRecord record, {DatabaseExecutor? executor});

  /// 统计指定季度下纳入完播计算的视频数量。
  Future<int> countSeasonMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });

  /// 统计指定季度下已观看的视频数量。
  Future<int> countSeasonWatchedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });

  /// 统计指定季度下已完成的视频数量。
  Future<int> countSeasonCompletedMainVideos(
    String seasonId, {
    DatabaseExecutor? executor,
  });

  /// 统计指定番剧下已观看的视频数量。
  Future<int> countAnimeWatchedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  });

  /// 统计指定番剧下已完成的视频数量。
  Future<int> countAnimeCompletedMainVideos(
    String animeId, {
    DatabaseExecutor? executor,
  });
}

/// 定义视频演职员统计记录的持久化接口。
abstract class VideoCreditStatsRepository {
  /// 使用给定列表替换指定视频的全部演职员记录。
  Future<void> replaceForVideo(
    String videoId,
    List<VideoCreditRecord> records, {
    DatabaseExecutor? executor,
  });

  /// 返回指定视频的演职员统计记录列表。
  Future<List<VideoCreditRecord>> listByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  });
}

/// 定义番剧维度统计记录的持久化接口。
abstract class AnimeStatsRepository {
  /// 按番剧标识查询统计记录。
  Future<AnimeStatsRecord?> getByAnimeId(
    String animeId, {
    DatabaseExecutor? executor,
  });

  /// 插入或更新一条番剧统计记录。
  Future<void> upsert(AnimeStatsRecord record, {DatabaseExecutor? executor});
}

/// 定义季度维度统计记录的持久化接口。
abstract class SeasonStatsRepository {
  /// 按季度标识查询统计记录。
  Future<SeasonStatsRecord?> getBySeasonId(
    String seasonId, {
    DatabaseExecutor? executor,
  });

  /// 插入或更新一条季度统计记录。
  Future<void> upsert(SeasonStatsRecord record, {DatabaseExecutor? executor});

  /// 统计指定番剧下已完成的季度数量。
  Future<int> countCompletedSeasonsByAnime(
    String animeId, {
    DatabaseExecutor? executor,
  });
}

/// 定义播放统计聚合写入入口的统一接口。
abstract class PlayStatsRepository {
  /// 持久化一次已经收口的播放会话结果。
  Future<void> persistFinalizedSession(FinalizedPlaySession session);

  /// 清空全部播放统计数据。
  Future<void> clearAll();
}

/// 基于 `sqflite` 的播放历史存储实现。
class SqflitePlayHistoryStore implements PlayHistoryStore {
  final PlayStatsDatabase _database;

  /// 根据数据库依赖构造播放历史存储。
  const SqflitePlayHistoryStore(this._database);

  @override
  Future<PlayHistoryRecord?> getByHistoryId(
    String historyId, {
    DatabaseExecutor? executor,
  }) async {
    final normalized = historyId.trim();
    if (normalized.isEmpty) return null;
    final db = executor ?? await _database.rawDatabase;
    final rows = await db.query(
      'play_history',
      where: 'history_id = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlayStatsSqlMapper.playHistoryFromMap(rows.first);
  }

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

/// 基于 `sqflite` 的视频统计仓储实现。
class SqfliteVideoStatsRepository implements VideoStatsRepository {
  final PlayStatsDatabase _database;

  /// 根据数据库依赖构造视频统计仓储。
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

/// 基于 `sqflite` 的视频演职员统计仓储实现。
class SqfliteVideoCreditStatsRepository implements VideoCreditStatsRepository {
  final PlayStatsDatabase _database;

  /// 根据数据库依赖构造演职员统计仓储。
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

/// 基于 `sqflite` 的番剧统计仓储实现。
class SqfliteAnimeStatsRepository implements AnimeStatsRepository {
  final PlayStatsDatabase _database;

  /// 根据数据库依赖构造番剧统计仓储。
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

/// 基于 `sqflite` 的季度统计仓储实现。
class SqfliteSeasonStatsRepository implements SeasonStatsRepository {
  final PlayStatsDatabase _database;

  /// 根据数据库依赖构造季度统计仓储。
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
