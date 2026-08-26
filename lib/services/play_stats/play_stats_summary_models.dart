import 'play_stats_models.dart';

/// 表示统计首页顶部的核心汇总指标。
class PlayStatsTotals {
  final int totalPlayedMs;
  final int totalClickCount;
  final int totalViewCount;
  final int totalCompletedVideoCount;
  final int totalCompletedSeasonCount;

  /// 根据汇总指标字段构造对象。
  const PlayStatsTotals({
    required this.totalPlayedMs,
    required this.totalClickCount,
    required this.totalViewCount,
    required this.totalCompletedVideoCount,
    required this.totalCompletedSeasonCount,
  });
}

/// 表示统计首页所需的核心数据集合。
class PlayStatsDashboard {
  final PlayStatsTotals totals;
  final List<VideoStatsRecord> topVideos;
  final List<AnimeStatsRecord> topAnimes;
  final List<PlayHistoryRecord> recentHistory;

  /// 根据首页各区块数据构造对象。
  const PlayStatsDashboard({
    required this.totals,
    required this.topVideos,
    required this.topAnimes,
    required this.recentHistory,
  });
}

/// 表示调试视图使用的完整统计树快照。
class PlayStatsDebugSnapshot {
  final PlayStatsTotals totals;
  final List<PlayStatsDebugAnimeNode> animes;
  final List<PlayStatsDebugVideoNode> movies;
  final List<PlayStatsDebugVideoNode> orphanVideos;
  final List<PlayHistoryRecord> unlinkedHistory;

  /// 根据调试视图各区块数据构造对象。
  const PlayStatsDebugSnapshot({
    required this.totals,
    required this.animes,
    this.movies = const <PlayStatsDebugVideoNode>[],
    this.orphanVideos = const <PlayStatsDebugVideoNode>[],
    this.unlinkedHistory = const <PlayHistoryRecord>[],
  });
}

/// 表示调试树中的番剧节点。
class PlayStatsDebugAnimeNode {
  final AnimeStatsRecord anime;
  final List<PlayStatsDebugSeasonNode> seasons;
  final List<PlayStatsDebugVideoNode> ungroupedVideos;

  /// 根据番剧节点字段构造对象。
  const PlayStatsDebugAnimeNode({
    required this.anime,
    required this.seasons,
    this.ungroupedVideos = const <PlayStatsDebugVideoNode>[],
  });
}

/// 表示调试树中的季度节点。
class PlayStatsDebugSeasonNode {
  final SeasonStatsRecord? season;
  final List<PlayStatsDebugVideoNode> videos;

  /// 根据季度节点字段构造对象。
  const PlayStatsDebugSeasonNode({required this.season, required this.videos});
}

/// 表示调试树中的视频节点。
class PlayStatsDebugVideoNode {
  final VideoStatsRecord video;
  final List<PlayHistoryRecord> history;

  /// 根据视频节点字段构造对象。
  const PlayStatsDebugVideoNode({required this.video, required this.history});
}
