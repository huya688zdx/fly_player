import 'play_stats_models.dart';

class PlayStatsTotals {
  final int totalPlayedMs;
  final int totalClickCount;
  final int totalViewCount;
  final int totalCompletedVideoCount;
  final int totalCompletedSeasonCount;

  const PlayStatsTotals({
    required this.totalPlayedMs,
    required this.totalClickCount,
    required this.totalViewCount,
    required this.totalCompletedVideoCount,
    required this.totalCompletedSeasonCount,
  });
}

class PlayStatsDashboard {
  final PlayStatsTotals totals;
  final List<VideoStatsRecord> topVideos;
  final List<AnimeStatsRecord> topAnimes;
  final List<PlayHistoryRecord> recentHistory;

  const PlayStatsDashboard({
    required this.totals,
    required this.topVideos,
    required this.topAnimes,
    required this.recentHistory,
  });
}

class PlayStatsDebugSnapshot {
  final PlayStatsTotals totals;
  final List<PlayStatsDebugAnimeNode> animes;
  final List<PlayStatsDebugVideoNode> movies;
  final List<PlayStatsDebugVideoNode> orphanVideos;
  final List<PlayHistoryRecord> unlinkedHistory;

  const PlayStatsDebugSnapshot({
    required this.totals,
    required this.animes,
    this.movies = const <PlayStatsDebugVideoNode>[],
    this.orphanVideos = const <PlayStatsDebugVideoNode>[],
    this.unlinkedHistory = const <PlayHistoryRecord>[],
  });
}

class PlayStatsDebugAnimeNode {
  final AnimeStatsRecord anime;
  final List<PlayStatsDebugSeasonNode> seasons;
  final List<PlayStatsDebugVideoNode> ungroupedVideos;

  const PlayStatsDebugAnimeNode({
    required this.anime,
    required this.seasons,
    this.ungroupedVideos = const <PlayStatsDebugVideoNode>[],
  });
}

class PlayStatsDebugSeasonNode {
  final SeasonStatsRecord? season;
  final List<PlayStatsDebugVideoNode> videos;

  const PlayStatsDebugSeasonNode({required this.season, required this.videos});
}

class PlayStatsDebugVideoNode {
  final VideoStatsRecord video;
  final List<PlayHistoryRecord> history;

  const PlayStatsDebugVideoNode({required this.video, required this.history});
}
