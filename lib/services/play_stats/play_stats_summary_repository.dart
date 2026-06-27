import 'package:sqflite/sqflite.dart';

import '../../l10n/generated/app_localizations.dart';
import 'play_stats_database.dart';
import 'play_stats_mappers.dart';
import 'play_stats_models.dart';
import 'play_stats_report_aggregator.dart';
import 'play_stats_report_models.dart';
import 'play_stats_summary_models.dart';

/// 定义播放统计报表与首页数据的读取接口。
abstract class PlayStatsSummaryRepository {
  /// 按指定时间范围加载完整报表快照。
  Future<PlayStatsReportSnapshot> loadReportSnapshot({
    required AppLocalizations l10n,
    required PlayStatsRange range,
    int topLimit = 8,
  });

  /// 加载统计首页所需的核心面板数据。
  Future<PlayStatsDashboard> loadDashboard({
    int topVideoLimit = 10,
    int topAnimeLimit = 10,
    int recentHistoryLimit = 20,
  });

  /// 加载调试视图所需的完整统计树快照。
  Future<PlayStatsDebugSnapshot> loadDebugSnapshot();

  /// 返回最近播放历史列表。
  Future<List<PlayHistoryRecord>> loadRecentHistory({int limit = 50});

  /// 返回播放时长最高的视频列表。
  Future<List<VideoStatsRecord>> loadTopVideosByPlayedMs({int limit = 20});

  /// 返回播放时长最高的番剧列表。
  Future<List<AnimeStatsRecord>> loadTopAnimesByPlayedMs({int limit = 20});
}

/// 基于 `sqflite` 的播放统计汇总查询实现。
class SqflitePlayStatsSummaryRepository implements PlayStatsSummaryRepository {
  final PlayStatsDatabase _database;
  final PlayStatsReportAggregator _reportAggregator;

  /// 根据数据库与报表聚合器依赖构造仓储。
  const SqflitePlayStatsSummaryRepository(
    this._database, {
    PlayStatsReportAggregator reportAggregator =
        const PlayStatsReportAggregator(),
  }) : _reportAggregator = reportAggregator;

  @override
  Future<PlayStatsReportSnapshot> loadReportSnapshot({
    required AppLocalizations l10n,
    required PlayStatsRange range,
    int topLimit = 8,
  }) async {
    final db = await _database.rawDatabase;
    final historyRows = await db.query(
      'play_history',
      where: _rangeWhereClause(range),
      whereArgs: _rangeWhereArgs(range),
      orderBy: 'started_at_ms DESC',
    );
    final histories = historyRows
        .map((row) => PlayStatsSqlMapper.playHistoryFromMap(row))
        .toList(growable: false);
    final videoIds = histories
        .map((item) => item.videoId.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final videoRows = await _queryRowsByIds(
      db,
      table: 'video_stats',
      idColumn: 'video_id',
      ids: videoIds,
      orderBy: 'last_played_at_ms DESC, total_played_ms DESC',
    );
    final videos = videoRows
        .map((row) => PlayStatsSqlMapper.videoStatsFromMap(row))
        .toList(growable: false);
    final seasonRows = await db.query(
      'season_stats',
      orderBy: 'last_played_at_ms DESC, title COLLATE NOCASE ASC',
    );
    final seasons = seasonRows
        .map((row) => PlayStatsSqlMapper.seasonStatsFromMap(row))
        .toList(growable: false);
    return _reportAggregator.buildSnapshot(
      l10n: l10n,
      range: range,
      histories: histories,
      videos: videos,
      seasons: seasons,
      topLimit: topLimit,
    );
  }

  @override
  Future<PlayStatsDashboard> loadDashboard({
    int topVideoLimit = 10,
    int topAnimeLimit = 10,
    int recentHistoryLimit = 20,
  }) async {
    final db = await _database.rawDatabase;
    final totalsRows = await db.rawQuery('''
SELECT
  COALESCE(SUM(total_played_ms), 0) AS total_played_ms,
  COALESCE(SUM(click_count), 0) AS total_click_count,
  COALESCE(SUM(view_count), 0) AS total_view_count,
  COALESCE(SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END), 0) AS total_completed_video_count
FROM video_stats
''');
    final seasonRows = await db.rawQuery('''
SELECT COALESCE(SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END), 0) AS total_completed_season_count
FROM season_stats
''');
    final totalsMap = totalsRows.isEmpty
        ? const <String, Object?>{}
        : totalsRows.first;
    final seasonMap = seasonRows.isEmpty
        ? const <String, Object?>{}
        : seasonRows.first;
    final totals = PlayStatsTotals(
      totalPlayedMs: _intValue(totalsMap['total_played_ms']),
      totalClickCount: _intValue(totalsMap['total_click_count']),
      totalViewCount: _intValue(totalsMap['total_view_count']),
      totalCompletedVideoCount: _intValue(
        totalsMap['total_completed_video_count'],
      ),
      totalCompletedSeasonCount: _intValue(
        seasonMap['total_completed_season_count'],
      ),
    );
    final results = await Future.wait(<Future<Object>>[
      loadTopVideosByPlayedMs(limit: topVideoLimit),
      loadTopAnimesByPlayedMs(limit: topAnimeLimit),
      loadRecentHistory(limit: recentHistoryLimit),
    ]);
    return PlayStatsDashboard(
      totals: totals,
      topVideos: results[0] as List<VideoStatsRecord>,
      topAnimes: results[1] as List<AnimeStatsRecord>,
      recentHistory: results[2] as List<PlayHistoryRecord>,
    );
  }

  @override
  Future<PlayStatsDebugSnapshot> loadDebugSnapshot() async {
    final db = await _database.rawDatabase;
    final totals = await _loadTotalsFromDb(db);
    final animeRows = await db.query(
      'anime_stats',
      orderBy: 'last_played_at_ms DESC, total_played_ms DESC',
    );
    final seasonRows = await db.query(
      'season_stats',
      orderBy: 'last_played_at_ms DESC, title COLLATE NOCASE ASC',
    );
    final videoRows = await db.query(
      'video_stats',
      orderBy: 'last_played_at_ms DESC, total_played_ms DESC',
    );
    final historyRows = await db.query(
      'play_history',
      orderBy: 'started_at_ms DESC',
    );

    final animes = animeRows
        .map((row) => PlayStatsSqlMapper.animeStatsFromMap(row))
        .toList(growable: false);
    final seasons = seasonRows
        .map((row) => PlayStatsSqlMapper.seasonStatsFromMap(row))
        .toList(growable: false);
    final videos = videoRows
        .map((row) => PlayStatsSqlMapper.videoStatsFromMap(row))
        .toList(growable: false);
    final history = historyRows
        .map((row) => PlayStatsSqlMapper.playHistoryFromMap(row))
        .toList(growable: false);

    final historyByVideoId = <String, List<PlayHistoryRecord>>{};
    for (final record in history) {
      final key = record.videoId.trim();
      if (key.isEmpty) {
        continue;
      }
      historyByVideoId
          .putIfAbsent(key, () => <PlayHistoryRecord>[])
          .add(record);
    }

    final movieNodes = videos
        .where(_isMovieVideo)
        .map(
          (video) => PlayStatsDebugVideoNode(
            video: video,
            history:
                historyByVideoId[video.videoId.trim()] ??
                const <PlayHistoryRecord>[],
          ),
        )
        .toList(growable: false);

    final videosByAnimeId = <String, List<VideoStatsRecord>>{};
    final videosBySeasonId = <String, List<VideoStatsRecord>>{};
    for (final video in videos) {
      if (_isMovieVideo(video)) {
        continue;
      }
      final animeId = video.animeId.trim();
      if (animeId.isNotEmpty) {
        videosByAnimeId
            .putIfAbsent(animeId, () => <VideoStatsRecord>[])
            .add(video);
      }
      final seasonId = video.seasonId.trim();
      if (seasonId.isNotEmpty) {
        videosBySeasonId
            .putIfAbsent(seasonId, () => <VideoStatsRecord>[])
            .add(video);
      }
    }

    final seasonsByAnimeId = <String, List<SeasonStatsRecord>>{};
    for (final season in seasons) {
      final animeId = season.animeId.trim();
      if (animeId.isEmpty) {
        continue;
      }
      seasonsByAnimeId
          .putIfAbsent(animeId, () => <SeasonStatsRecord>[])
          .add(season);
    }

    final animeNodes = <PlayStatsDebugAnimeNode>[];
    final consumedAnimeIds = <String>{};
    final consumedSeasonIds = <String>{};
    final consumedVideoIds = movieNodes
        .map((node) => node.video.videoId.trim())
        .where((videoId) => videoId.isNotEmpty)
        .toSet();

    for (final anime in animes) {
      final animeId = anime.animeId.trim();
      final seasonNodes = <PlayStatsDebugSeasonNode>[];
      final seasonList =
          seasonsByAnimeId[animeId] ?? const <SeasonStatsRecord>[];
      final seasonIdsForAnime = seasonList
          .map((season) => season.seasonId.trim())
          .where((seasonId) => seasonId.isNotEmpty)
          .toSet();
      for (final season in seasonList) {
        final seasonId = season.seasonId.trim();
        consumedSeasonIds.add(seasonId);
        final seasonVideos =
            (videosBySeasonId[seasonId] ?? const <VideoStatsRecord>[])
                .map(
                  (video) => PlayStatsDebugVideoNode(
                    video: video,
                    history:
                        historyByVideoId[video.videoId.trim()] ??
                        const <PlayHistoryRecord>[],
                  ),
                )
                .toList(growable: false);
        for (final node in seasonVideos) {
          consumedVideoIds.add(node.video.videoId.trim());
        }
        seasonNodes.add(
          PlayStatsDebugSeasonNode(season: season, videos: seasonVideos),
        );
      }

      final ungroupedVideos =
          (videosByAnimeId[animeId] ?? const <VideoStatsRecord>[])
              .where(
                (video) =>
                    video.seasonId.trim().isEmpty ||
                    !seasonIdsForAnime.contains(video.seasonId.trim()),
              )
              .map(
                (video) => PlayStatsDebugVideoNode(
                  video: video,
                  history:
                      historyByVideoId[video.videoId.trim()] ??
                      const <PlayHistoryRecord>[],
                ),
              )
              .toList(growable: false);
      for (final node in ungroupedVideos) {
        consumedVideoIds.add(node.video.videoId.trim());
      }

      if (seasonNodes.isEmpty && ungroupedVideos.isEmpty) {
        continue;
      }

      consumedAnimeIds.add(animeId);
      animeNodes.add(
        PlayStatsDebugAnimeNode(
          anime: anime,
          seasons: seasonNodes,
          ungroupedVideos: ungroupedVideos,
        ),
      );
    }

    final fallbackAnimeIds = <String>{
      ...videosByAnimeId.keys,
      ...seasonsByAnimeId.keys,
    }.where((animeId) => animeId.trim().isNotEmpty).toList(growable: false);
    for (final animeId in fallbackAnimeIds) {
      if (consumedAnimeIds.contains(animeId)) {
        continue;
      }
      final seasonList =
          seasonsByAnimeId[animeId] ?? const <SeasonStatsRecord>[];
      final seasonIdsForAnime = seasonList
          .map((season) => season.seasonId.trim())
          .where((seasonId) => seasonId.isNotEmpty)
          .toSet();
      final seasonNodes = <PlayStatsDebugSeasonNode>[];
      for (final season in seasonList) {
        final seasonId = season.seasonId.trim();
        consumedSeasonIds.add(seasonId);
        final seasonVideos =
            (videosBySeasonId[seasonId] ?? const <VideoStatsRecord>[])
                .map(
                  (video) => PlayStatsDebugVideoNode(
                    video: video,
                    history:
                        historyByVideoId[video.videoId.trim()] ??
                        const <PlayHistoryRecord>[],
                  ),
                )
                .toList(growable: false);
        for (final node in seasonVideos) {
          consumedVideoIds.add(node.video.videoId.trim());
        }
        seasonNodes.add(
          PlayStatsDebugSeasonNode(season: season, videos: seasonVideos),
        );
      }
      final animeVideos =
          videosByAnimeId[animeId] ?? const <VideoStatsRecord>[];
      final ungroupedVideos = animeVideos
          .where(
            (video) =>
                video.seasonId.trim().isEmpty ||
                !seasonIdsForAnime.contains(video.seasonId.trim()),
          )
          .map(
            (video) => PlayStatsDebugVideoNode(
              video: video,
              history:
                  historyByVideoId[video.videoId.trim()] ??
                  const <PlayHistoryRecord>[],
            ),
          )
          .toList(growable: false);
      for (final node in ungroupedVideos) {
        consumedVideoIds.add(node.video.videoId.trim());
      }
      final fallbackTitle = animeVideos
          .map((video) => video.animeTitle.trim())
          .firstWhere((title) => title.isNotEmpty, orElse: () => animeId);
      animeNodes.add(
        PlayStatsDebugAnimeNode(
          anime: AnimeStatsRecord(
            animeId: animeId,
            title: fallbackTitle,
            clickCount: 0,
            viewCount: 0,
            totalPlayedMs: animeVideos.fold<int>(
              0,
              (sum, video) => sum + video.totalPlayedMs,
            ),
            forwardSeekCount: 0,
            backwardSeekCount: 0,
            watchedEpisodeCount: animeVideos
                .where(
                  (video) =>
                      video.countsTowardCompletion && video.viewCount > 0,
                )
                .length,
            completedEpisodeCount: animeVideos
                .where(
                  (video) => video.countsTowardCompletion && video.completed,
                )
                .length,
            completedSeasonCount: seasonList
                .where((season) => season.isCompleted)
                .length,
            lastPlayedAtMs: animeVideos.fold<int>(
              0,
              (latest, video) =>
                  latest > video.lastPlayedAtMs ? latest : video.lastPlayedAtMs,
            ),
          ),
          seasons: seasonNodes,
          ungroupedVideos: ungroupedVideos,
        ),
      );
    }

    final orphanSeasonNodes = <PlayStatsDebugSeasonNode>[];
    for (final season in seasons) {
      final seasonId = season.seasonId.trim();
      if (consumedSeasonIds.contains(seasonId)) {
        continue;
      }
      final seasonVideos =
          (videosBySeasonId[seasonId] ?? const <VideoStatsRecord>[])
              .map(
                (video) => PlayStatsDebugVideoNode(
                  video: video,
                  history:
                      historyByVideoId[video.videoId.trim()] ??
                      const <PlayHistoryRecord>[],
                ),
              )
              .toList(growable: false);
      for (final node in seasonVideos) {
        consumedVideoIds.add(node.video.videoId.trim());
      }
      orphanSeasonNodes.add(
        PlayStatsDebugSeasonNode(season: season, videos: seasonVideos),
      );
    }
    if (orphanSeasonNodes.isNotEmpty) {
      animeNodes.add(
        PlayStatsDebugAnimeNode(
          anime: const AnimeStatsRecord(
            animeId: '__orphan_anime__',
            title: '未匹配番剧',
            clickCount: 0,
            viewCount: 0,
            totalPlayedMs: 0,
            forwardSeekCount: 0,
            backwardSeekCount: 0,
            watchedEpisodeCount: 0,
            completedEpisodeCount: 0,
            completedSeasonCount: 0,
            lastPlayedAtMs: 0,
          ),
          seasons: orphanSeasonNodes,
        ),
      );
    }

    final orphanVideos = videos
        .where((video) => !consumedVideoIds.contains(video.videoId.trim()))
        .map(
          (video) => PlayStatsDebugVideoNode(
            video: video,
            history:
                historyByVideoId[video.videoId.trim()] ??
                const <PlayHistoryRecord>[],
          ),
        )
        .toList(growable: false);

    final unlinkedHistory = history
        .where((record) => !consumedVideoIds.contains(record.videoId.trim()))
        .toList(growable: false);

    return PlayStatsDebugSnapshot(
      totals: totals,
      animes: animeNodes,
      movies: movieNodes,
      orphanVideos: orphanVideos,
      unlinkedHistory: unlinkedHistory,
    );
  }

  @override
  Future<List<PlayHistoryRecord>> loadRecentHistory({int limit = 50}) async {
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
  Future<List<VideoStatsRecord>> loadTopVideosByPlayedMs({
    int limit = 20,
  }) async {
    final db = await _database.rawDatabase;
    final rows = await db.query(
      'video_stats',
      orderBy: 'total_played_ms DESC, last_played_at_ms DESC',
      limit: limit,
    );
    return rows
        .map((row) => PlayStatsSqlMapper.videoStatsFromMap(row))
        .toList(growable: false);
  }

  @override
  Future<List<AnimeStatsRecord>> loadTopAnimesByPlayedMs({
    int limit = 20,
  }) async {
    final db = await _database.rawDatabase;
    final rows = await db.query(
      'anime_stats',
      orderBy: 'total_played_ms DESC, last_played_at_ms DESC',
      limit: limit,
    );
    return rows
        .map((row) => PlayStatsSqlMapper.animeStatsFromMap(row))
        .toList(growable: false);
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  Future<PlayStatsTotals> _loadTotalsFromDb(Database db) async {
    final totalsRows = await db.rawQuery('''
SELECT
  COALESCE(SUM(total_played_ms), 0) AS total_played_ms,
  COALESCE(SUM(click_count), 0) AS total_click_count,
  COALESCE(SUM(view_count), 0) AS total_view_count,
  COALESCE(SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END), 0) AS total_completed_video_count
FROM video_stats
''');
    final seasonRows = await db.rawQuery('''
SELECT COALESCE(SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END), 0) AS total_completed_season_count
FROM season_stats
''');
    final totalsMap = totalsRows.isEmpty
        ? const <String, Object?>{}
        : totalsRows.first;
    final seasonMap = seasonRows.isEmpty
        ? const <String, Object?>{}
        : seasonRows.first;
    return PlayStatsTotals(
      totalPlayedMs: _intValue(totalsMap['total_played_ms']),
      totalClickCount: _intValue(totalsMap['total_click_count']),
      totalViewCount: _intValue(totalsMap['total_view_count']),
      totalCompletedVideoCount: _intValue(
        totalsMap['total_completed_video_count'],
      ),
      totalCompletedSeasonCount: _intValue(
        seasonMap['total_completed_season_count'],
      ),
    );
  }

  bool _isMovieVideo(VideoStatsRecord video) {
    return video.videoKind.trim().toLowerCase() == 'movie';
  }

  String? _rangeWhereClause(PlayStatsRange range) {
    if (range == PlayStatsRange.all) {
      return null;
    }
    return 'started_at_ms >= ?';
  }

  List<Object?>? _rangeWhereArgs(PlayStatsRange range) {
    if (range == PlayStatsRange.all) {
      return null;
    }
    final days = range.dayCount ?? 0;
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final start = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return <Object?>[start.millisecondsSinceEpoch];
  }

  Future<List<Map<String, Object?>>> _queryRowsByIds(
    Database db, {
    required String table,
    required String idColumn,
    required List<String> ids,
    required String orderBy,
  }) async {
    if (ids.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    const chunkSize = 300;
    final rows = <Map<String, Object?>>[];
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final chunk = ids.skip(offset).take(chunkSize).toList(growable: false);
      final placeholders = List<String>.filled(chunk.length, '?').join(', ');
      final result = await db.query(
        table,
        where: '$idColumn IN ($placeholders)',
        whereArgs: chunk,
        orderBy: orderBy,
      );
      rows.addAll(result);
    }
    return rows;
  }
}
