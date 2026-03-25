import 'dart:math' as math;

import 'play_stats_models.dart';
import 'play_stats_report_models.dart';

class PlayStatsReportAggregator {
  const PlayStatsReportAggregator();

  PlayStatsReportSnapshot buildSnapshot({
    required PlayStatsRange range,
    required List<PlayHistoryRecord> histories,
    required List<VideoStatsRecord> videos,
    required List<SeasonStatsRecord> seasons,
    int topLimit = 8,
  }) {
    final sortedHistory = histories.toList()
      ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    final videoById = <String, VideoStatsRecord>{
      for (final video in videos) video.videoId.trim(): video,
    };

    final overview = _buildOverview(
      range: range,
      histories: sortedHistory,
      videos: videos,
      seasons: seasons,
    );

    return PlayStatsReportSnapshot(
      range: range,
      overview: overview,
      trends: _buildTrends(range: range, histories: sortedHistory),
      heatmap: _buildHeatmap(sortedHistory),
      mediaTypeBuckets: _buildMediaTypeBuckets(sortedHistory),
      genreBuckets: _buildGenreBuckets(sortedHistory, topLimit: topLimit),
      countryBuckets: _buildCountryBuckets(sortedHistory, topLimit: topLimit),
      yearBuckets: _buildYearBuckets(
        histories: sortedHistory,
        videoById: videoById,
        topLimit: topLimit,
      ),
      affinityPeople: _buildAffinityPeople(sortedHistory, topLimit: topLimit),
      behavior: _buildBehavior(sortedHistory),
      topAnimes: _buildTopAnimes(sortedHistory, topLimit: topLimit),
      topVideos: _buildTopVideos(sortedHistory, topLimit: topLimit),
      recentHistory: sortedHistory.take(12).toList(growable: false),
      continueWatching: _buildContinueWatching(
        videos: videos,
        range: range,
        topLimit: topLimit,
      ),
    );
  }

  PlayStatsOverview _buildOverview({
    required PlayStatsRange range,
    required List<PlayHistoryRecord> histories,
    required List<VideoStatsRecord> videos,
    required List<SeasonStatsRecord> seasons,
  }) {
    final totalPlayedMs = histories.fold<int>(
      0,
      (sum, item) => sum + math.max(0, item.watchedMs),
    );
    final totalClickCount = histories
        .where(
          (item) =>
              item.startSource == PlayStartSource.manual ||
              item.startSource == PlayStartSource.manualSwitch,
        )
        .length;
    final totalViewCount = histories.where((item) => item.countedAsView).length;
    final completedVideos = histories
        .where(
          (item) => item.countedAsCompleted && item.videoId.trim().isNotEmpty,
        )
        .map((item) => item.videoId.trim())
        .toSet()
        .length;
    final completedSeasons = seasons
        .where(
          (season) =>
              season.isCompleted && _matchesRange(range, season.lastPlayedAtMs),
        )
        .map((season) => season.seasonId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
    final activeDays = histories
        .map(
          (item) =>
              _dateKey(DateTime.fromMillisecondsSinceEpoch(item.startedAtMs)),
        )
        .toSet()
        .length;
    final metadataCoverage = _metadataCoverage(videos);
    return PlayStatsOverview(
      totalPlayedMs: totalPlayedMs,
      totalClickCount: totalClickCount,
      totalViewCount: totalViewCount,
      totalCompletedVideoCount: completedVideos,
      totalCompletedSeasonCount: completedSeasons,
      activeDays: activeDays,
      metadataCoverage: metadataCoverage,
      insight: _buildInsight(histories, videos),
    );
  }

  List<PlayStatsTrendPoint> _buildTrends({
    required PlayStatsRange range,
    required List<PlayHistoryRecord> histories,
  }) {
    if (histories.isEmpty) {
      return const <PlayStatsTrendPoint>[];
    }
    final grouped = <DateTime, _TrendAccumulator>{};
    for (final item in histories) {
      final dt = DateTime.fromMillisecondsSinceEpoch(item.startedAtMs);
      final key = DateTime(dt.year, dt.month, dt.day);
      final entry = grouped.putIfAbsent(key, _TrendAccumulator.new);
      entry.playedMs += math.max(0, item.watchedMs);
      if (item.countedAsView) {
        entry.viewCount += 1;
      }
    }
    final start = range == PlayStatsRange.all
        ? grouped.keys.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now().subtract(Duration(days: (range.dayCount ?? 1) - 1));
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final points = <PlayStatsTrendPoint>[];
    for (
      var cursor = DateTime(start.year, start.month, start.day);
      !cursor.isAfter(end);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      final entry = grouped[cursor] ?? _TrendAccumulator();
      points.add(
        PlayStatsTrendPoint(
          date: cursor,
          playedMs: entry.playedMs,
          viewCount: entry.viewCount,
        ),
      );
    }
    return points;
  }

  List<PlayStatsHeatmapCell> _buildHeatmap(List<PlayHistoryRecord> histories) {
    final grouped = <String, _HeatmapAccumulator>{};
    for (final item in histories) {
      final dt = DateTime.fromMillisecondsSinceEpoch(item.startedAtMs);
      final key = '${dt.weekday}-${dt.hour}';
      final entry = grouped.putIfAbsent(key, _HeatmapAccumulator.new);
      entry.playedMs += math.max(0, item.watchedMs);
      entry.sessionCount += 1;
    }
    final cells = <PlayStatsHeatmapCell>[];
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      for (var hour = 0; hour < 24; hour += 1) {
        final entry = grouped['$weekday-$hour'] ?? _HeatmapAccumulator();
        cells.add(
          PlayStatsHeatmapCell(
            weekday: weekday,
            hour: hour,
            playedMs: entry.playedMs,
            sessionCount: entry.sessionCount,
          ),
        );
      }
    }
    return cells;
  }

  List<PlayStatsDistributionBucket> _buildMediaTypeBuckets(
    List<PlayHistoryRecord> histories,
  ) {
    final values = <String, int>{};
    for (final item in histories) {
      final key = item.videoKind.trim().toLowerCase() == 'movie'
          ? 'movie'
          : 'anime';
      values.update(
        key,
        (current) => current + math.max(0, item.watchedMs),
        ifAbsent: () => math.max(0, item.watchedMs),
      );
    }
    return _toBuckets(
      values,
      labelBuilder: (id) => id == 'movie' ? '电影' : '剧集',
      topLimit: 6,
    );
  }

  List<PlayStatsDistributionBucket> _buildGenreBuckets(
    List<PlayHistoryRecord> histories, {
    required int topLimit,
  }) {
    final values = <String, int>{};
    for (final item in histories) {
      final weight = math.max(0, item.watchedMs);
      for (final genreId in item.genreIds) {
        final key = '$genreId';
        values.update(
          key,
          (current) => current + weight,
          ifAbsent: () => weight,
        );
      }
    }
    return _toBuckets(values, labelBuilder: (id) => id, topLimit: topLimit);
  }

  List<PlayStatsDistributionBucket> _buildCountryBuckets(
    List<PlayHistoryRecord> histories, {
    required int topLimit,
  }) {
    final values = <String, int>{};
    for (final item in histories) {
      final weight = math.max(0, item.watchedMs);
      for (final code in item.countryCodes) {
        final key = code.trim().toUpperCase();
        if (key.isEmpty) {
          continue;
        }
        values.update(
          key,
          (current) => current + weight,
          ifAbsent: () => weight,
        );
      }
    }
    return _toBuckets(values, labelBuilder: (id) => id, topLimit: topLimit);
  }

  List<PlayStatsDistributionBucket> _buildYearBuckets({
    required List<PlayHistoryRecord> histories,
    required Map<String, VideoStatsRecord> videoById,
    required int topLimit,
  }) {
    final values = <String, int>{};
    for (final item in histories) {
      final video = videoById[item.videoId.trim()];
      final year = video?.year ?? 0;
      if (year <= 0) {
        continue;
      }
      final key = '$year';
      values.update(
        key,
        (current) => current + math.max(0, item.watchedMs),
        ifAbsent: () => math.max(0, item.watchedMs),
      );
    }
    return _toBuckets(values, labelBuilder: (id) => id, topLimit: topLimit);
  }

  List<PlayStatsAffinityPerson> _buildAffinityPeople(
    List<PlayHistoryRecord> histories, {
    required int topLimit,
  }) {
    final values = <String, _AffinityAccumulator>{};
    for (final item in histories) {
      final weight = math.max(0, item.watchedMs);
      for (final credit in item.credits) {
        final key = _affinityKey(credit);
        final entry = values.putIfAbsent(
          key,
          () => _AffinityAccumulator(
            personId: credit.personId,
            name: credit.name,
            role: credit.role,
            job: credit.job,
          ),
        );
        if (entry.personId.isEmpty && credit.personId.trim().isNotEmpty) {
          entry.personId = credit.personId;
        }
        if (entry.name.trim().isEmpty && credit.name.trim().isNotEmpty) {
          entry.name = credit.name;
        }
        if (entry.role.trim().isEmpty && credit.role.trim().isNotEmpty) {
          entry.role = credit.role;
        }
        if (entry.job.trim().isEmpty && credit.job.trim().isNotEmpty) {
          entry.job = credit.job;
        }
        entry.watchedMs += weight;
        entry.appearanceCount += 1;
      }
    }
    final ranked = values.values.toList()
      ..sort((a, b) {
        final valueCompare = b.watchedMs.compareTo(a.watchedMs);
        if (valueCompare != 0) return valueCompare;
        return b.appearanceCount.compareTo(a.appearanceCount);
      });
    return ranked
        .take(topLimit)
        .map(
          (item) => PlayStatsAffinityPerson(
            personId: item.personId,
            name: item.name,
            role: item.role,
            job: item.job,
            watchedMs: item.watchedMs,
            appearanceCount: item.appearanceCount,
          ),
        )
        .toList(growable: false);
  }

  PlayStatsBehaviorSummary _buildBehavior(List<PlayHistoryRecord> histories) {
    final sourceCounts = <String, int>{};
    var completedSessions = 0;
    var forwardSeekCount = 0;
    var backwardSeekCount = 0;
    var introDetected = 0;
    var introSkipped = 0;
    var introWatched = 0;
    var introPlayedMs = 0;
    var outroDetected = 0;
    var outroSkipped = 0;
    var outroWatched = 0;
    var outroPlayedMs = 0;
    for (final item in histories) {
      sourceCounts.update(
        item.startSource.name,
        (current) => current + 1,
        ifAbsent: () => 1,
      );
      if (item.countedAsCompleted) {
        completedSessions += 1;
      }
      forwardSeekCount += math.max(0, item.forwardSeekCount);
      backwardSeekCount += math.max(0, item.backwardSeekCount);
      if (item.opDetected) introDetected += 1;
      if (item.opSkipped) introSkipped += 1;
      if (item.opNotSkipped) introWatched += 1;
      introPlayedMs += math.max(0, item.opPlayedMs);
      if (item.edDetected) outroDetected += 1;
      if (item.edSkipped) outroSkipped += 1;
      if (item.edNotSkipped) outroWatched += 1;
      outroPlayedMs += math.max(0, item.edPlayedMs);
    }
    final totalSessions = histories.length;
    return PlayStatsBehaviorSummary(
      totalSessions: totalSessions,
      completedSessions: completedSessions,
      completionRate: totalSessions <= 0
          ? 0
          : completedSessions / totalSessions,
      forwardSeekCount: forwardSeekCount,
      backwardSeekCount: backwardSeekCount,
      startSourceBuckets: _toBuckets(
        sourceCounts,
        labelBuilder: _startSourceLabel,
        topLimit: sourceCounts.length,
      ),
      intro: PlayStatsOpEdSummary(
        detectedCount: introDetected,
        skippedCount: introSkipped,
        watchedCount: introWatched,
        totalPlayedMs: introPlayedMs,
      ),
      outro: PlayStatsOpEdSummary(
        detectedCount: outroDetected,
        skippedCount: outroSkipped,
        watchedCount: outroWatched,
        totalPlayedMs: outroPlayedMs,
      ),
    );
  }

  List<PlayStatsTopAnime> _buildTopAnimes(
    List<PlayHistoryRecord> histories, {
    required int topLimit,
  }) {
    final grouped = <String, _TopAnimeAccumulator>{};
    for (final item in histories) {
      final key = _animeGroupKey(item);
      if (key.isEmpty) {
        continue;
      }
      final entry = grouped.putIfAbsent(
        key,
        () => _TopAnimeAccumulator(
          animeId: item.animeId,
          videoId: item.videoId,
          videoKind: item.videoKind,
          title: item.animeTitle,
        ),
      );
      if (entry.animeId.trim().isEmpty && item.animeId.trim().isNotEmpty) {
        entry.animeId = item.animeId;
      }
      if (entry.videoId.trim().isEmpty && item.videoId.trim().isNotEmpty) {
        entry.videoId = item.videoId;
      }
      if (entry.videoKind.trim().isEmpty && item.videoKind.trim().isNotEmpty) {
        entry.videoKind = item.videoKind;
      }
      if (entry.title.trim().isEmpty && item.animeTitle.trim().isNotEmpty) {
        entry.title = item.animeTitle;
      }
      entry.playedMs += math.max(0, item.watchedMs);
      entry.sessionCount += 1;
      if (item.countedAsView) {
        entry.viewCount += 1;
      }
      entry.lastPlayedAtMs = math.max(entry.lastPlayedAtMs, item.startedAtMs);
    }
    final ranked = grouped.values.toList()
      ..sort((a, b) {
        final playedCompare = b.playedMs.compareTo(a.playedMs);
        if (playedCompare != 0) return playedCompare;
        return b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs);
      });
    return ranked
        .take(topLimit)
        .map(
          (item) => PlayStatsTopAnime(
            animeId: item.animeId,
            videoId: item.videoId,
            videoKind: item.videoKind,
            title: item.title,
            playedMs: item.playedMs,
            viewCount: item.viewCount,
            sessionCount: item.sessionCount,
            lastPlayedAtMs: item.lastPlayedAtMs,
          ),
        )
        .toList(growable: false);
  }

  List<PlayStatsTopVideo> _buildTopVideos(
    List<PlayHistoryRecord> histories, {
    required int topLimit,
  }) {
    final grouped = <String, _TopVideoAccumulator>{};
    for (final item in histories) {
      final key = item.videoId.trim();
      if (key.isEmpty) {
        continue;
      }
      final entry = grouped.putIfAbsent(
        key,
        () => _TopVideoAccumulator(
          videoId: item.videoId,
          title: item.title,
          animeTitle: item.animeTitle,
          seasonTitle: item.seasonTitle,
          videoKind: item.videoKind,
        ),
      );
      entry.playedMs += math.max(0, item.watchedMs);
      entry.sessionCount += 1;
      if (item.countedAsView) {
        entry.viewCount += 1;
      }
      entry.lastPlayedAtMs = math.max(entry.lastPlayedAtMs, item.startedAtMs);
      entry.maxProgress = math.max(entry.maxProgress, item.maxProgress);
      entry.completed = entry.completed || item.countedAsCompleted;
    }
    final ranked = grouped.values.toList()
      ..sort((a, b) {
        final playedCompare = b.playedMs.compareTo(a.playedMs);
        if (playedCompare != 0) return playedCompare;
        return b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs);
      });
    return ranked
        .take(topLimit)
        .map(
          (item) => PlayStatsTopVideo(
            videoId: item.videoId,
            title: item.title,
            animeTitle: item.animeTitle,
            seasonTitle: item.seasonTitle,
            videoKind: item.videoKind,
            playedMs: item.playedMs,
            viewCount: item.viewCount,
            sessionCount: item.sessionCount,
            lastPlayedAtMs: item.lastPlayedAtMs,
            maxProgress: item.maxProgress,
            completed: item.completed,
          ),
        )
        .toList(growable: false);
  }

  List<PlayStatsContinueWatchingItem> _buildContinueWatching({
    required List<VideoStatsRecord> videos,
    required PlayStatsRange range,
    required int topLimit,
  }) {
    final filtered = videos.where((video) {
      if (!_matchesRange(range, video.lastPlayedAtMs)) {
        return false;
      }
      if (video.completed) {
        return false;
      }
      final progress = video.lastProgress > 0
          ? video.lastProgress
          : video.maxProgress;
      return progress > 0.05 && progress < 0.97;
    }).toList()..sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
    return filtered
        .take(topLimit)
        .map(
          (video) => PlayStatsContinueWatchingItem(
            videoId: video.videoId,
            title: video.title,
            animeTitle: video.animeTitle,
            seasonTitle: video.seasonTitle,
            lastPlayedAtMs: video.lastPlayedAtMs,
            progress: video.lastProgress > 0
                ? video.lastProgress
                : video.maxProgress,
            lastPositionMs: video.lastPositionMs,
            mediaDurationMs: video.mediaDurationMs,
          ),
        )
        .toList(growable: false);
  }

  List<PlayStatsDistributionBucket> _toBuckets(
    Map<String, int> values, {
    required String Function(String id) labelBuilder,
    required int topLimit,
  }) {
    if (values.isEmpty) {
      return const <PlayStatsDistributionBucket>[];
    }
    final total = values.values.fold<int>(0, (sum, item) => sum + item);
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(topLimit)
        .map(
          (entry) => PlayStatsDistributionBucket(
            id: entry.key,
            label: labelBuilder(entry.key),
            value: entry.value,
            share: total <= 0 ? 0 : entry.value / total,
          ),
        )
        .toList(growable: false);
  }

  double _metadataCoverage(List<VideoStatsRecord> videos) {
    if (videos.isEmpty) {
      return 0;
    }
    final covered = videos.where((video) {
      return video.metadataEnriched ||
          video.genreIds.isNotEmpty ||
          video.countryCodes.isNotEmpty ||
          video.year > 0 ||
          video.credits.isNotEmpty;
    }).length;
    return covered / videos.length;
  }

  String _buildInsight(
    List<PlayHistoryRecord> histories,
    List<VideoStatsRecord> videos,
  ) {
    if (histories.isEmpty) {
      return '还没有足够的播放记录，开始观看后这里会生成你的观影战报。';
    }
    final hourWeights = List<int>.filled(24, 0);
    var animePlayedMs = 0;
    var moviePlayedMs = 0;
    var autoNextCount = 0;
    var introDetected = 0;
    var introSkipped = 0;
    for (final item in histories) {
      final dt = DateTime.fromMillisecondsSinceEpoch(item.startedAtMs);
      hourWeights[dt.hour] += math.max(1, item.watchedMs);
      if (item.videoKind.trim().toLowerCase() == 'movie') {
        moviePlayedMs += math.max(0, item.watchedMs);
      } else {
        animePlayedMs += math.max(0, item.watchedMs);
      }
      if (item.startSource == PlayStartSource.autoNext) {
        autoNextCount += 1;
      }
      if (item.opDetected) {
        introDetected += 1;
      }
      if (item.opSkipped) {
        introSkipped += 1;
      }
    }
    final peakHour = hourWeights.indexOf(hourWeights.reduce(math.max));
    final period = _timePeriodLabel(peakHour);
    final prefersAnime = animePlayedMs >= moviePlayedMs;
    final years = videos
        .where((item) => item.year > 0)
        .map((item) => item.year)
        .toList();
    final recentYear = years.isEmpty ? '' : '${(years..sort()).last}年前后';
    final autoNextHeavy = autoNextCount > histories.length * 0.35;
    final skipHeavy =
        introDetected > 0 && introSkipped >= (introDetected * 0.5);
    final clauses = <String>[
      '你主要在$period观看',
      prefersAnime ? '内容偏好更偏向剧集' : '近期电影占比更高',
      if (recentYear.isNotEmpty) '偏好$recentYear的作品',
      if (autoNextHeavy) '有明显连续追看的倾向',
      if (skipHeavy) '而且 OP 跳过倾向比较明显',
    ];
    return '${clauses.join('，')}。';
  }

  bool _matchesRange(PlayStatsRange range, int timestampMs) {
    if (range == PlayStatsRange.all) {
      return true;
    }
    if (timestampMs <= 0) {
      return false;
    }
    final days = range.dayCount ?? 0;
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final start = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return DateTime.fromMillisecondsSinceEpoch(
      timestampMs,
    ).isAfter(start.subtract(const Duration(milliseconds: 1)));
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _startSourceLabel(String id) => switch (id) {
    'manual' => '手动打开',
    'manualSwitch' => '手动换集',
    'autoNext' => '自动连播',
    'replay' => '重播',
    'systemResume' => '系统恢复',
    _ => id,
  };

  String _timePeriodLabel(int hour) {
    if (hour >= 5 && hour < 9) return '清晨';
    if (hour >= 9 && hour < 12) return '上午';
    if (hour >= 12 && hour < 18) return '下午';
    if (hour >= 18 && hour < 23) return '夜间';
    return '深夜';
  }

  String _animeGroupKey(PlayHistoryRecord item) {
    final title = item.animeTitle.trim();
    if (title.isNotEmpty) {
      return title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    }
    return item.animeId.trim();
  }

  String _affinityKey(PlayStatsCredit credit) {
    final personId = credit.personId.trim();
    if (personId.isNotEmpty) {
      return personId;
    }
    final name = credit.name.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (name.isNotEmpty) {
      return 'name:$name';
    }
    return '${credit.role.trim()}|${credit.job.trim()}';
  }
}

class _TrendAccumulator {
  int playedMs;
  int viewCount;

  _TrendAccumulator({this.playedMs = 0, this.viewCount = 0});
}

class _HeatmapAccumulator {
  int playedMs;
  int sessionCount;

  _HeatmapAccumulator({this.playedMs = 0, this.sessionCount = 0});
}

class _AffinityAccumulator {
  String personId;
  String name;
  String role;
  String job;
  int watchedMs = 0;
  int appearanceCount = 0;

  _AffinityAccumulator({
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
  });
}

class _TopAnimeAccumulator {
  String animeId;
  String videoId;
  String videoKind;
  String title;
  int playedMs = 0;
  int viewCount = 0;
  int sessionCount = 0;
  int lastPlayedAtMs = 0;

  _TopAnimeAccumulator({
    required this.animeId,
    required this.videoId,
    required this.videoKind,
    required this.title,
  });
}

class _TopVideoAccumulator {
  final String videoId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final String videoKind;
  int playedMs = 0;
  int viewCount = 0;
  int sessionCount = 0;
  int lastPlayedAtMs = 0;
  double maxProgress = 0;
  bool completed = false;

  _TopVideoAccumulator({
    required this.videoId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.videoKind,
  });
}
