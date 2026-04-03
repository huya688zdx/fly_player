import 'play_stats_models.dart';

enum PlayStatsRange { days7, days30, days90, days180, days365, all }

extension PlayStatsRangeX on PlayStatsRange {
  int? get dayCount => switch (this) {
    PlayStatsRange.days7 => 7,
    PlayStatsRange.days30 => 30,
    PlayStatsRange.days90 => 90,
    PlayStatsRange.days180 => 180,
    PlayStatsRange.days365 => 365,
    PlayStatsRange.all => null,
  };

  String get label => switch (this) {
    PlayStatsRange.days7 => '7天',
    PlayStatsRange.days30 => '30天',
    PlayStatsRange.days90 => '90天',
    PlayStatsRange.days180 => '半年',
    PlayStatsRange.days365 => '一年',
    PlayStatsRange.all => '全部',
  };
}

class PlayStatsOverview {
  final int totalPlayedMs;
  final int totalClickCount;
  final int totalViewCount;
  final int totalCompletedVideoCount;
  final int totalCompletedSeasonCount;
  final int activeDays;
  final double metadataCoverage;
  final String insight;

  const PlayStatsOverview({
    required this.totalPlayedMs,
    required this.totalClickCount,
    required this.totalViewCount,
    required this.totalCompletedVideoCount,
    required this.totalCompletedSeasonCount,
    required this.activeDays,
    required this.metadataCoverage,
    required this.insight,
  });
}

class PlayStatsTrendPoint {
  final DateTime date;
  final int playedMs;
  final int viewCount;

  const PlayStatsTrendPoint({
    required this.date,
    required this.playedMs,
    required this.viewCount,
  });
}

class PlayStatsHeatmapCell {
  final int weekday;
  final int hour;
  final int playedMs;
  final int sessionCount;

  const PlayStatsHeatmapCell({
    required this.weekday,
    required this.hour,
    required this.playedMs,
    required this.sessionCount,
  });
}

class PlayStatsDistributionBucket {
  final String id;
  final String label;
  final int value;
  final double share;

  const PlayStatsDistributionBucket({
    required this.id,
    required this.label,
    required this.value,
    required this.share,
  });
}

class PlayStatsOpEdSummary {
  final int detectedCount;
  final int skippedCount;
  final int watchedCount;
  final int totalPlayedMs;

  const PlayStatsOpEdSummary({
    required this.detectedCount,
    required this.skippedCount,
    required this.watchedCount,
    required this.totalPlayedMs,
  });
}

class PlayStatsBehaviorSummary {
  final int totalSessions;
  final int completedSessions;
  final double completionRate;
  final int forwardSeekCount;
  final int backwardSeekCount;
  final List<PlayStatsDistributionBucket> startSourceBuckets;
  final PlayStatsOpEdSummary intro;
  final PlayStatsOpEdSummary outro;

  const PlayStatsBehaviorSummary({
    required this.totalSessions,
    required this.completedSessions,
    required this.completionRate,
    required this.forwardSeekCount,
    required this.backwardSeekCount,
    required this.startSourceBuckets,
    required this.intro,
    required this.outro,
  });
}

class PlayStatsAffinityPerson {
  final String personId;
  final String name;
  final String role;
  final String job;
  final int watchedMs;
  final int appearanceCount;

  const PlayStatsAffinityPerson({
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
    required this.watchedMs,
    required this.appearanceCount,
  });
}

class PlayStatsTopAnime {
  final String animeId;
  final String videoId;
  final String videoKind;
  final String title;
  final int playedMs;
  final int viewCount;
  final int sessionCount;
  final int lastPlayedAtMs;

  const PlayStatsTopAnime({
    required this.animeId,
    required this.videoId,
    required this.videoKind,
    required this.title,
    required this.playedMs,
    required this.viewCount,
    required this.sessionCount,
    required this.lastPlayedAtMs,
  });
}

class PlayStatsTopVideo {
  final String videoId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final String videoKind;
  final int playedMs;
  final int viewCount;
  final int sessionCount;
  final int lastPlayedAtMs;
  final double maxProgress;
  final bool completed;

  const PlayStatsTopVideo({
    required this.videoId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.videoKind,
    required this.playedMs,
    required this.viewCount,
    required this.sessionCount,
    required this.lastPlayedAtMs,
    required this.maxProgress,
    required this.completed,
  });
}

class PlayStatsContinueWatchingItem {
  final String videoId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final int lastPlayedAtMs;
  final double progress;
  final int lastPositionMs;
  final int mediaDurationMs;

  const PlayStatsContinueWatchingItem({
    required this.videoId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.lastPlayedAtMs,
    required this.progress,
    required this.lastPositionMs,
    required this.mediaDurationMs,
  });
}

class PlayStatsReportSnapshot {
  final PlayStatsRange range;
  final PlayStatsOverview overview;
  final List<PlayStatsTrendPoint> trends;
  final List<PlayStatsHeatmapCell> heatmap;
  final List<PlayStatsDistributionBucket> mediaTypeBuckets;
  final List<PlayStatsDistributionBucket> genreBuckets;
  final List<PlayStatsDistributionBucket> countryBuckets;
  final List<PlayStatsDistributionBucket> yearBuckets;
  final List<PlayStatsAffinityPerson> affinityPeople;
  final PlayStatsBehaviorSummary behavior;
  final List<PlayStatsTopAnime> topAnimes;
  final List<PlayStatsTopVideo> topVideos;
  final List<PlayHistoryRecord> recentHistory;
  final List<PlayStatsContinueWatchingItem> continueWatching;

  const PlayStatsReportSnapshot({
    required this.range,
    required this.overview,
    required this.trends,
    required this.heatmap,
    required this.mediaTypeBuckets,
    required this.genreBuckets,
    required this.countryBuckets,
    required this.yearBuckets,
    required this.affinityPeople,
    required this.behavior,
    required this.topAnimes,
    required this.topVideos,
    required this.recentHistory,
    required this.continueWatching,
  });

  bool get isEmpty =>
      overview.totalPlayedMs <= 0 &&
      overview.totalViewCount <= 0 &&
      behavior.totalSessions <= 0 &&
      recentHistory.isEmpty;
}
