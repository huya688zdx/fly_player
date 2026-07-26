import 'dart:isolate';
import 'dart:ui';

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
  Future<PlayStatsDebugSnapshot> loadDebugSnapshot({AppLocalizations? l10n});

  /// 返回最近播放历史列表。
  Future<List<PlayHistoryRecord>> loadRecentHistory({int limit = 50});

  /// 返回播放时长最高的视频列表。
  Future<List<VideoStatsRecord>> loadTopVideosByPlayedMs({int limit = 20});

  /// 返回播放时长最高的番剧列表。
  Future<List<AnimeStatsRecord>> loadTopAnimesByPlayedMs({int limit = 20});
}

/// 承载报表快照计算所需的全部原始数据，字段均可跨 isolate 传递。
class PlayStatsReportSnapshotRequest {
  final AppLocalizations l10n;
  final PlayStatsRange range;
  final int topLimit;
  final PlayStatsReportAggregator aggregator;
  final List<Map<String, Object?>> historyRows;
  final List<Map<String, Object?>> videoRows;
  final List<Map<String, Object?>> seasonRows;

  /// 根据数据库原始行与聚合参数构造请求。
  const PlayStatsReportSnapshotRequest({
    required this.l10n,
    required this.range,
    required this.topLimit,
    required this.aggregator,
    required this.historyRows,
    required this.videoRows,
    required this.seasonRows,
  });
}

/// 将数据库原始行映射为记录并聚合为报表快照。
///
/// 写成不依赖任何实例状态的顶层纯函数，便于整体丢到后台 isolate 执行：
/// 行映射里的三列 JSON 解码与聚合器的多轮遍历都不再占用 UI isolate。
PlayStatsReportSnapshot buildPlayStatsReportSnapshot(
  PlayStatsReportSnapshotRequest request,
) {
  final histories = request.historyRows
      .map(PlayStatsSqlMapper.playHistoryFromMap)
      .toList(growable: false);
  final videos = request.videoRows
      .map(PlayStatsSqlMapper.videoStatsFromMap)
      .toList(growable: false);
  final seasons = request.seasonRows
      .map(PlayStatsSqlMapper.seasonStatsFromMap)
      .toList(growable: false);
  return request.aggregator.buildSnapshot(
    l10n: request.l10n,
    range: request.range,
    histories: histories,
    videos: videos,
    seasons: seasons,
    topLimit: request.topLimit,
  );
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
    // 同一次快照内只算一次范围起点，历史表与季度表共用同一条时间线。
    final rangeStartMs = _rangeStartMs(range);
    final historyRows = await db.query(
      'play_history',
      where: rangeStartMs == null ? null : 'started_at_ms >= ?',
      whereArgs: rangeStartMs == null ? null : <Object?>[rangeStartMs],
      orderBy: 'started_at_ms DESC',
    );
    final videoIds = <String>{};
    for (final row in historyRows) {
      final videoId = (row['video_id']?.toString() ?? '').trim();
      if (videoId.isNotEmpty) {
        videoIds.add(videoId);
      }
    }
    final videoRows = await _queryRowsByIds(
      db,
      table: 'video_stats',
      idColumn: 'video_id',
      ids: videoIds.toList(growable: false),
      orderBy: 'last_played_at_ms DESC, total_played_ms DESC',
    );
    // 季度表只有"已完结且落在范围内"的行会影响快照（仅参与完结季度计数），
    // 其余行聚合器一律丢弃，所以直接在 SQL 侧收敛掉整表搬运与 NOCASE 排序。
    final seasonRows = await db.query(
      'season_stats',
      where: rangeStartMs == null
          ? 'is_completed = 1'
          : 'is_completed = 1 AND last_played_at_ms >= ?',
      whereArgs: rangeStartMs == null ? null : <Object?>[rangeStartMs],
    );
    final request = PlayStatsReportSnapshotRequest(
      l10n: l10n,
      range: range,
      topLimit: topLimit,
      aggregator: _reportAggregator,
      historyRows: _toPlainRows(historyRows),
      videoRows: _toPlainRows(videoRows),
      seasonRows: _toPlainRows(seasonRows),
    );
    // 行映射与聚合整体丢到后台 isolate，UI isolate 只负责搬运原始行。
    return Isolate.run(() => buildPlayStatsReportSnapshot(request));
  }

  /// 把 sqflite 返回的行视图复制成普通 Map，确保可安全跨 isolate 传递。
  List<Map<String, Object?>> _toPlainRows(List<Map<String, Object?>> rows) {
    return List<Map<String, Object?>>.generate(
      rows.length,
      (index) => Map<String, Object?>.of(rows[index]),
      growable: false,
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
  Future<PlayStatsDebugSnapshot> loadDebugSnapshot({
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? lookupAppLocalizations(const Locale('zh', 'CN'));
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
          anime: AnimeStatsRecord(
            animeId: '__orphan_anime__',
            title: strings.playStatsDebugUnmatchedAnime,
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

  /// 返回统计范围的起始毫秒时间戳；全部范围返回 `null` 表示不加时间过滤。
  int? _rangeStartMs(PlayStatsRange range) {
    if (range == PlayStatsRange.all) {
      return null;
    }
    final days = range.dayCount ?? 0;
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final start = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return start.millisecondsSinceEpoch;
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
