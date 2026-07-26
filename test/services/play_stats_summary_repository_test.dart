import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
import 'package:fly_player/services/play_stats/play_stats_mappers.dart';
import 'package:fly_player/services/play_stats/play_stats_models.dart';
import 'package:fly_player/services/play_stats/play_stats_report_aggregator.dart';
import 'package:fly_player/services/play_stats/play_stats_report_models.dart';
import 'package:fly_player/services/play_stats/play_stats_summary_repository.dart';

void main() {
  const aggregator = PlayStatsReportAggregator();
  final AppLocalizations l10n = AppLocalizationsZhCn();
  final now = DateTime.now();

  final videos = _buildVideos(now);
  final histories = _buildHistories(now);
  final seasons = _buildSeasons(now);

  final historyRows = histories
      .map(PlayStatsSqlMapper.playHistoryToMap)
      .toList(growable: false);
  final videoRows = videos
      .map(PlayStatsSqlMapper.videoStatsToMap)
      .toList(growable: false);
  final seasonRows = seasons
      .map(PlayStatsSqlMapper.seasonStatsToMap)
      .toList(growable: false);

  for (final range in <PlayStatsRange>[
    PlayStatsRange.all,
    PlayStatsRange.days30,
  ]) {
    test('后台 isolate 聚合与旧的主 isolate 聚合结果一致（$range）', () async {
      // 旧链路：仓储在主 isolate 上映射行并调用聚合器。
      final expected = aggregator.buildSnapshot(
        l10n: l10n,
        range: range,
        histories: historyRows
            .map(PlayStatsSqlMapper.playHistoryFromMap)
            .toList(growable: false),
        videos: videoRows
            .map(PlayStatsSqlMapper.videoStatsFromMap)
            .toList(growable: false),
        seasons: seasonRows
            .map(PlayStatsSqlMapper.seasonStatsFromMap)
            .toList(growable: false),
        topLimit: 8,
      );

      // 新链路：原始行整体丢到后台 isolate，映射与聚合都在那边完成。
      final request = PlayStatsReportSnapshotRequest(
        l10n: l10n,
        range: range,
        topLimit: 8,
        aggregator: aggregator,
        historyRows: historyRows,
        videoRows: videoRows,
        seasonRows: seasonRows,
      );
      final actual = await Isolate.run(
        () => buildPlayStatsReportSnapshot(request),
      );

      expect(_describe(actual), _describe(expected));
    });
  }

  test('季度表按已完结与时间范围预过滤不改变快照', () {
    const range = PlayStatsRange.days30;
    final startMs = _rangeStartMs(range, now);
    // 仓储改成在 SQL 侧只取 is_completed = 1 且落在范围内的季度行。
    final filtered = seasons
        .where(
          (season) => season.isCompleted && season.lastPlayedAtMs >= startMs,
        )
        .toList(growable: false);
    expect(filtered.length, lessThan(seasons.length));

    PlayStatsReportSnapshot build(List<SeasonStatsRecord> input) {
      return aggregator.buildSnapshot(
        l10n: l10n,
        range: range,
        histories: histories,
        videos: videos,
        seasons: input,
        topLimit: 8,
      );
    }

    expect(_describe(build(filtered)), _describe(build(seasons)));
    expect(build(filtered).overview.totalCompletedSeasonCount, 2);
  });
}

int _rangeStartMs(PlayStatsRange range, DateTime now) {
  final days = range.dayCount ?? 0;
  final cutoff = now.subtract(Duration(days: days - 1));
  return DateTime(cutoff.year, cutoff.month, cutoff.day).millisecondsSinceEpoch;
}

List<VideoStatsRecord> _buildVideos(DateTime now) {
  return <VideoStatsRecord>[
    _video(
      videoId: 'video-1',
      animeId: 'anime-1',
      seasonId: 'season-1',
      title: '第一集',
      animeTitle: '星际漫游',
      videoKind: 'episode',
      year: 2021,
      countryCodes: const <String>['CN', 'JP'],
      genreIds: const <int>[16, 18],
      lastPlayedAtMs: now
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
      lastProgress: 0.4,
      completed: false,
    ),
    _video(
      videoId: 'video-2',
      animeId: 'anime-1',
      seasonId: 'season-1',
      title: '第二集',
      animeTitle: '星际漫游',
      videoKind: 'episode',
      year: 2021,
      countryCodes: const <String>['CN'],
      genreIds: const <int>[16],
      lastPlayedAtMs: now
          .subtract(const Duration(days: 5))
          .millisecondsSinceEpoch,
      lastProgress: 0.99,
      completed: true,
    ),
    _video(
      videoId: 'video-3',
      animeId: 'anime-2',
      seasonId: '',
      title: '深海之下',
      animeTitle: '深海之下',
      videoKind: 'movie',
      year: 2019,
      countryCodes: const <String>['US'],
      genreIds: const <int>[28],
      lastPlayedAtMs: now
          .subtract(const Duration(days: 60))
          .millisecondsSinceEpoch,
      lastProgress: 0.5,
      completed: false,
    ),
  ];
}

List<PlayHistoryRecord> _buildHistories(DateTime now) {
  return <PlayHistoryRecord>[
    _history(
      historyId: 'history-1',
      videoId: 'video-1',
      animeId: 'anime-1',
      seasonId: 'season-1',
      title: '第一集',
      animeTitle: '星际漫游',
      videoKind: 'episode',
      startSource: PlayStartSource.manual,
      startedAt: now.subtract(const Duration(days: 2)),
      watchedMs: 1200000,
      countedAsView: true,
      countedAsCompleted: false,
      countryCodes: const <String>['CN', 'JP'],
      genreIds: const <int>[16, 18],
      credits: const <PlayStatsCredit>[
        PlayStatsCredit(
          personId: 'person-1',
          name: '张三',
          role: '主角',
          job: 'actor',
        ),
        PlayStatsCredit(personId: '', name: '李四', role: '', job: 'director'),
      ],
    ),
    _history(
      historyId: 'history-2',
      videoId: 'video-2',
      animeId: 'anime-1',
      seasonId: 'season-1',
      title: '第二集',
      animeTitle: '星际漫游 ',
      videoKind: 'episode',
      startSource: PlayStartSource.autoNext,
      startedAt: now.subtract(const Duration(days: 5)),
      watchedMs: 1400000,
      countedAsView: true,
      countedAsCompleted: true,
      countryCodes: const <String>['CN'],
      genreIds: const <int>[16],
      credits: const <PlayStatsCredit>[
        PlayStatsCredit(personId: 'person-1', name: '张三', role: '', job: ''),
      ],
    ),
    _history(
      historyId: 'history-3',
      videoId: 'video-3',
      animeId: 'anime-2',
      seasonId: '',
      title: '深海之下',
      animeTitle: '深海之下',
      videoKind: 'movie',
      startSource: PlayStartSource.manualSwitch,
      startedAt: now.subtract(const Duration(days: 60)),
      watchedMs: 4800000,
      countedAsView: true,
      countedAsCompleted: true,
      countryCodes: const <String>['US'],
      genreIds: const <int>[28],
      credits: const <PlayStatsCredit>[
        PlayStatsCredit(
          personId: 'person-2',
          name: '王五',
          role: '导演',
          job: 'director',
        ),
      ],
    ),
  ];
}

List<SeasonStatsRecord> _buildSeasons(DateTime now) {
  return <SeasonStatsRecord>[
    SeasonStatsRecord(
      seasonId: 'season-1',
      animeId: 'anime-1',
      title: '第一季',
      totalEpisodeCount: 2,
      watchedEpisodeCount: 2,
      completedEpisodeCount: 2,
      isCompleted: true,
      lastPlayedAtMs: now
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    ),
    SeasonStatsRecord(
      seasonId: 'season-2',
      animeId: 'anime-1',
      title: '第二季',
      totalEpisodeCount: 4,
      watchedEpisodeCount: 4,
      completedEpisodeCount: 4,
      isCompleted: true,
      lastPlayedAtMs: now
          .subtract(const Duration(days: 6))
          .millisecondsSinceEpoch,
    ),
    // 已完结但落在 30 天范围外，应被范围条件排除。
    SeasonStatsRecord(
      seasonId: 'season-3',
      animeId: 'anime-3',
      title: '陈年旧季',
      totalEpisodeCount: 3,
      watchedEpisodeCount: 3,
      completedEpisodeCount: 3,
      isCompleted: true,
      lastPlayedAtMs: now
          .subtract(const Duration(days: 90))
          .millisecondsSinceEpoch,
    ),
    // 未完结，任何范围下都不计入。
    SeasonStatsRecord(
      seasonId: 'season-4',
      animeId: 'anime-4',
      title: '连载中',
      totalEpisodeCount: 12,
      watchedEpisodeCount: 3,
      completedEpisodeCount: 3,
      isCompleted: false,
      lastPlayedAtMs: now
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch,
    ),
  ];
}

VideoStatsRecord _video({
  required String videoId,
  required String animeId,
  required String seasonId,
  required String title,
  required String animeTitle,
  required String videoKind,
  required int year,
  required List<String> countryCodes,
  required List<int> genreIds,
  required int lastPlayedAtMs,
  required double lastProgress,
  required bool completed,
}) {
  return VideoStatsRecord(
    videoId: videoId,
    animeId: animeId,
    seasonId: seasonId,
    title: title,
    animeTitle: animeTitle,
    seasonTitle: '第一季',
    videoKind: videoKind,
    countsTowardCompletion: videoKind != 'movie',
    country: countryCodes.isEmpty ? '' : countryCodes.first,
    countryCodes: countryCodes,
    genreIds: genreIds,
    year: year,
    mediaDurationMs: 1500000,
    clickCount: 1,
    autoPlayCount: 0,
    viewCount: 1,
    totalPlayedMs: 1200000,
    maxProgress: lastProgress,
    lastProgress: lastProgress,
    lastPositionMs: 600000,
    completed: completed,
    metadataEnriched: true,
    lastPlayedAtMs: lastPlayedAtMs,
    credits: const <PlayStatsCredit>[
      PlayStatsCredit(
        personId: 'person-1',
        name: '张三',
        role: '主角',
        job: 'actor',
      ),
    ],
  );
}

PlayHistoryRecord _history({
  required String historyId,
  required String videoId,
  required String animeId,
  required String seasonId,
  required String title,
  required String animeTitle,
  required String videoKind,
  required PlayStartSource startSource,
  required DateTime startedAt,
  required int watchedMs,
  required bool countedAsView,
  required bool countedAsCompleted,
  required List<String> countryCodes,
  required List<int> genreIds,
  required List<PlayStatsCredit> credits,
}) {
  return PlayHistoryRecord(
    historyId: historyId,
    videoId: videoId,
    animeId: animeId,
    seasonId: seasonId,
    title: title,
    animeTitle: animeTitle,
    seasonTitle: '第一季',
    videoKind: videoKind,
    countsTowardCompletion: videoKind != 'movie',
    countryCodes: countryCodes,
    genreIds: genreIds,
    credits: credits,
    startSource: startSource,
    startedAtMs: startedAt.millisecondsSinceEpoch,
    endedAtMs: startedAt.millisecondsSinceEpoch + watchedMs,
    mediaDurationMs: 1500000,
    watchedMs: watchedMs,
    maxProgress: 0.8,
    maxPositionMs: 1200000,
    countedAsView: countedAsView,
    countedAsCompleted: countedAsCompleted,
    opDetected: true,
    edDetected: true,
    opSkipped: true,
    edSkipped: false,
    opNotSkipped: false,
    edNotSkipped: true,
    opPlayedMs: 3000,
    edPlayedMs: 5000,
    forwardSeekCount: 2,
    backwardSeekCount: 1,
  );
}

/// 把快照展开成可直接比对的纯文本，覆盖全部字段。
String _describe(PlayStatsReportSnapshot snapshot) {
  final overview = snapshot.overview;
  final behavior = snapshot.behavior;
  return <String>[
    'range=${snapshot.range}',
    'overview=${overview.totalPlayedMs},${overview.totalClickCount},'
        '${overview.totalViewCount},${overview.totalCompletedVideoCount},'
        '${overview.totalCompletedSeasonCount},${overview.activeDays},'
        '${overview.metadataCoverage},${overview.insight}',
    'trends=${snapshot.trends.map((item) => '${item.date.toIso8601String()}:'
        '${item.playedMs}:${item.viewCount}').join('|')}',
    'heatmap=${snapshot.heatmap.map((item) => '${item.weekday}:${item.hour}:'
        '${item.playedMs}:${item.sessionCount}').join('|')}',
    'mediaType=${_describeBuckets(snapshot.mediaTypeBuckets)}',
    'genre=${_describeBuckets(snapshot.genreBuckets)}',
    'country=${_describeBuckets(snapshot.countryBuckets)}',
    'year=${_describeBuckets(snapshot.yearBuckets)}',
    'affinity=${snapshot.affinityPeople.map((item) => '${item.personId}:'
        '${item.name}:${item.role}:${item.job}:${item.watchedMs}:'
        '${item.appearanceCount}').join('|')}',
    'behavior=${behavior.totalSessions},${behavior.completedSessions},'
        '${behavior.completionRate},${behavior.forwardSeekCount},'
        '${behavior.backwardSeekCount},'
        '${_describeBuckets(behavior.startSourceBuckets)},'
        '${_describeOpEd(behavior.intro)},${_describeOpEd(behavior.outro)}',
    'topAnimes=${snapshot.topAnimes.map((item) => '${item.animeId}:'
        '${item.videoId}:${item.videoKind}:${item.title}:${item.playedMs}:'
        '${item.viewCount}:${item.sessionCount}:${item.lastPlayedAtMs}').join('|')}',
    'topVideos=${snapshot.topVideos.map((item) => '${item.videoId}:'
        '${item.title}:${item.animeTitle}:${item.seasonTitle}:'
        '${item.videoKind}:${item.playedMs}:${item.viewCount}:'
        '${item.sessionCount}:${item.lastPlayedAtMs}:${item.maxProgress}:'
        '${item.completed}').join('|')}',
    'recent=${snapshot.recentHistory.map((item) => '${item.historyId}:'
        '${item.videoId}:${item.startedAtMs}:${item.watchedMs}:'
        '${item.startSource}:${item.genreIds}:${item.countryCodes}:'
        '${item.credits.map((credit) => credit.toJson()).toList()}').join('|')}',
    'continue=${snapshot.continueWatching.map((item) => '${item.videoId}:'
        '${item.title}:${item.animeTitle}:${item.seasonTitle}:'
        '${item.lastPlayedAtMs}:${item.progress}:${item.lastPositionMs}:'
        '${item.mediaDurationMs}').join('|')}',
    'isEmpty=${snapshot.isEmpty}',
  ].join('\n');
}

String _describeBuckets(List<PlayStatsDistributionBucket> buckets) {
  return buckets
      .map((item) => '${item.id}:${item.label}:${item.value}:${item.share}')
      .join('|');
}

String _describeOpEd(PlayStatsOpEdSummary summary) {
  return '${summary.detectedCount}:${summary.skippedCount}:'
      '${summary.watchedCount}:${summary.totalPlayedMs}';
}
