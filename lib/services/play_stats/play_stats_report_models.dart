import '../../l10n/generated/app_localizations.dart';
import 'play_stats_models.dart';

/// 定义播放统计报表支持的时间范围。
enum PlayStatsRange { days7, days30, days90, days180, days365, all }

/// 为统计范围提供展示与换算辅助。
extension PlayStatsRangeX on PlayStatsRange {
  /// 返回对应范围的天数；全部范围返回 `null`。
  int? get dayCount => switch (this) {
    PlayStatsRange.days7 => 7,
    PlayStatsRange.days30 => 30,
    PlayStatsRange.days90 => 90,
    PlayStatsRange.days180 => 180,
    PlayStatsRange.days365 => 365,
    PlayStatsRange.all => null,
  };

  /// 返回用于界面展示的范围标签。
  String label(AppLocalizations l10n) => switch (this) {
    PlayStatsRange.days7 => l10n.playStatsRangeDays7,
    PlayStatsRange.days30 => l10n.playStatsRangeDays30,
    PlayStatsRange.days90 => l10n.playStatsRangeDays90,
    PlayStatsRange.days180 => l10n.playStatsRangeDays180,
    PlayStatsRange.days365 => l10n.playStatsRangeDays365,
    PlayStatsRange.all => l10n.playStatsRangeAll,
  };
}

/// 表示统计报表顶部概览区所需的数据。
class PlayStatsOverview {
  final int totalPlayedMs;
  final int totalClickCount;
  final int totalViewCount;
  final int totalCompletedVideoCount;
  final int totalCompletedSeasonCount;
  final int activeDays;
  final double metadataCoverage;
  final String insight;

  /// 根据概览统计字段构造对象。
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

/// 表示趋势图中的单个时间点。
class PlayStatsTrendPoint {
  final DateTime date;
  final int playedMs;
  final int viewCount;

  /// 根据趋势统计字段构造对象。
  const PlayStatsTrendPoint({
    required this.date,
    required this.playedMs,
    required this.viewCount,
  });
}

/// 表示热力图中的单个格子统计结果。
class PlayStatsHeatmapCell {
  final int weekday;
  final int hour;
  final int playedMs;
  final int sessionCount;

  /// 根据热力图统计字段构造对象。
  const PlayStatsHeatmapCell({
    required this.weekday,
    required this.hour,
    required this.playedMs,
    required this.sessionCount,
  });
}

/// 表示分布图中的单个桶位数据。
class PlayStatsDistributionBucket {
  final String id;
  final String label;
  final int value;
  final double share;

  /// 根据分布桶字段构造对象。
  const PlayStatsDistributionBucket({
    required this.id,
    required this.label,
    required this.value,
    required this.share,
  });
}

/// 表示片头或片尾行为的汇总统计。
class PlayStatsOpEdSummary {
  final int detectedCount;
  final int skippedCount;
  final int watchedCount;
  final int totalPlayedMs;

  /// 根据片头片尾汇总字段构造对象。
  const PlayStatsOpEdSummary({
    required this.detectedCount,
    required this.skippedCount,
    required this.watchedCount,
    required this.totalPlayedMs,
  });
}

/// 表示播放行为层面的综合统计。
class PlayStatsBehaviorSummary {
  final int totalSessions;
  final int completedSessions;
  final double completionRate;
  final int forwardSeekCount;
  final int backwardSeekCount;
  final List<PlayStatsDistributionBucket> startSourceBuckets;
  final PlayStatsOpEdSummary intro;
  final PlayStatsOpEdSummary outro;

  /// 根据行为统计字段构造对象。
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

/// 表示与用户观看行为关联度较高的演职员。
class PlayStatsAffinityPerson {
  final String personId;
  final String name;
  final String role;
  final String job;
  final int watchedMs;
  final int appearanceCount;

  /// 根据亲和人物统计字段构造对象。
  const PlayStatsAffinityPerson({
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
    required this.watchedMs,
    required this.appearanceCount,
  });
}

/// 表示报表中的高频观看番剧项。
class PlayStatsTopAnime {
  final String animeId;
  final String videoId;
  final String videoKind;
  final String title;
  final int playedMs;
  final int viewCount;
  final int sessionCount;
  final int lastPlayedAtMs;

  /// 根据番剧排行字段构造对象。
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

/// 表示报表中的高频观看视频项。
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

  /// 根据视频排行字段构造对象。
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

/// 表示继续观看列表中的单个候选项。
class PlayStatsContinueWatchingItem {
  final String videoId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final int lastPlayedAtMs;
  final double progress;
  final int lastPositionMs;
  final int mediaDurationMs;

  /// 根据继续观看字段构造对象。
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

/// 表示完整的播放统计报表快照。
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

  /// 根据报表各区域数据构造对象。
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

  /// 判断当前报表是否缺少足够的数据用于展示。
  bool get isEmpty =>
      overview.totalPlayedMs <= 0 &&
      overview.totalViewCount <= 0 &&
      behavior.totalSessions <= 0 &&
      recentHistory.isEmpty;
}
