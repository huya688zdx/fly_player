import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/play_stats_report/play_stats_report_formatters.dart';
import 'package:fly_player/screens/play_stats_report/play_stats_report_widgets.dart';
import 'package:fly_player/screens/play_stats_report_screen.dart';
import 'package:fly_player/services/play_stats/play_stats.dart';
import 'package:fly_player/ui/app_info_popover.dart';

void main() {
  testWidgets('switches range and opens detail page', (
    WidgetTester tester,
  ) async {
    final repository = _FakeSummaryRepository();

    await tester.pumpWidget(
      Provider<NasProvider?>.value(
        value: null,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayStatsReportScreen(
            summaryRepository: repository,
            detailPageBuilder: (_) =>
                const Scaffold(body: Text('detail stub page')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('30天'), findsOneWidget);

    await tester.tap(find.text('7天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('7天'), findsOneWidget);
    expect(
      repository.loadedRanges,
      containsAll(<PlayStatsRange>[
        PlayStatsRange.days30,
        PlayStatsRange.days7,
      ]),
    );

    await tester.tap(find.text('详细数据'));
    await tester.pumpAndSettle();

    expect(find.text('detail stub page'), findsOneWidget);
  });

  testWidgets('paginates history items by six entries per page', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final formatters = PlayStatsReportFormatters(
      l10n: AppLocalizationsZh(),
      genreMap: <int, String>{},
      countryMap: <String, String>{},
    );
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStatsPagedTimelineList(
            items: List<PlayHistoryRecord>.generate(
              7,
              (index) => _history(
                historyId: 'h$index',
                videoId: 'v$index',
                title: 'History ${index + 1}',
                startedAt: now.subtract(Duration(minutes: index)),
              ),
            ),
            formatters: formatters,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('History 1'), findsOneWidget);
    expect(find.text('History 6'), findsOneWidget);
    expect(find.text('History 7'), findsNothing);

    await tester.tap(find.byKey(const Key('play-stats-history-next-page')));
    await tester.pumpAndSettle();

    expect(find.text('History 7'), findsOneWidget);
  });

  testWidgets('affinity rank item responds to tap', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStatsRankList(
            items: <PlayStatsRankDisplayItem>[
              PlayStatsRankDisplayItem(
                title: 'Person',
                subtitle: '演员 · 12m',
                trailing: '3 次',
                onTap: () => tapped = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Person'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('hero metrics show reusable info popover copy', (
    WidgetTester tester,
  ) async {
    final formatters = PlayStatsReportFormatters(
      l10n: AppLocalizationsZh(),
      genreMap: <int, String>{},
      countryMap: <String, String>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStatsHeroCard(
            overview: const PlayStatsOverview(
              totalPlayedMs: 583000,
              totalClickCount: 19,
              totalViewCount: 7,
              totalCompletedVideoCount: 3,
              totalCompletedSeasonCount: 1,
              activeDays: 4,
              metadataCoverage: 0.85,
              insight: '测试洞察',
            ),
            selectedRange: PlayStatsRange.days30,
            formatters: formatters,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppInfoPopoverAnchor).first);
    await tester.pumpAndSettle();

    expect(find.text('播放次数'), findsWidgets);
    expect(find.text('统计这段时间里，你主动点开播放或手动切换内容的次数。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(find.text('统计这段时间里，你主动点开播放或手动切换内容的次数。'), findsNothing);
  });

  testWidgets('info popover stays visible on narrow viewport edge', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final formatters = PlayStatsReportFormatters(
      l10n: AppLocalizationsZh(),
      genreMap: <int, String>{},
      countryMap: <String, String>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStatsHeroCard(
            overview: const PlayStatsOverview(
              totalPlayedMs: 583000,
              totalClickCount: 19,
              totalViewCount: 7,
              totalCompletedVideoCount: 3,
              totalCompletedSeasonCount: 1,
              activeDays: 4,
              metadataCoverage: 0.85,
              insight: '测试洞察',
            ),
            selectedRange: PlayStatsRange.days30,
            formatters: formatters,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppInfoPopoverAnchor).last);
    await tester.pumpAndSettle();

    expect(find.text('元数据覆盖'), findsWidgets);
    expect(find.text('覆盖越高，下面的偏好分析和亲和榜越完整、越可靠。'), findsOneWidget);
  });

  testWidgets('pie summary updates center when selecting legend item', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStatsPieSummary(
            buckets: const <PlayStatsDistributionBucket>[
              PlayStatsDistributionBucket(
                id: 'anime',
                label: '剧集',
                value: 990,
                share: 0.99,
              ),
              PlayStatsDistributionBucket(
                id: 'movie',
                label: '电影',
                value: 10,
                share: 0.01,
              ),
            ],
            palette: const <Color>[Colors.cyan, Colors.amber],
            centerLabel: '内容占比',
            centerValue: '总计',
            labelBuilder: (bucket) => bucket.label,
            selectedCenterValueBuilder: (bucket) => '${bucket.value}',
            selectedCenterDetailBuilder: (bucket) =>
                '${(bucket.share * 100).round()}%',
          ),
        ),
      ),
    );

    expect(find.text('内容占比'), findsOneWidget);
    expect(find.text('总计'), findsOneWidget);

    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();

    expect(find.text('电影'), findsWidgets);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('1%'), findsWidgets);
  });
}

class _FakeSummaryRepository implements PlayStatsSummaryRepository {
  final List<PlayStatsRange> loadedRanges = <PlayStatsRange>[];

  @override
  Future<PlayStatsReportSnapshot> loadReportSnapshot({
    required AppLocalizations l10n,
    required PlayStatsRange range,
    int topLimit = 8,
  }) async {
    loadedRanges.add(range);
    final count = switch (range) {
      PlayStatsRange.days7 => 7,
      PlayStatsRange.days30 => 30,
      PlayStatsRange.days90 => 90,
      PlayStatsRange.days180 => 180,
      PlayStatsRange.days365 => 365,
      PlayStatsRange.all => 999,
    };
    final now = DateTime.now();
    return PlayStatsReportSnapshot(
      range: range,
      overview: PlayStatsOverview(
        totalPlayedMs: count * 1000,
        totalClickCount: 3,
        totalViewCount: count,
        totalCompletedVideoCount: 1,
        totalCompletedSeasonCount: 1,
        activeDays: 1,
        metadataCoverage: 0.5,
        insight: 'range-${range.name}',
      ),
      trends: <PlayStatsTrendPoint>[
        PlayStatsTrendPoint(date: now, playedMs: count * 1000, viewCount: 1),
      ],
      heatmap: const <PlayStatsHeatmapCell>[
        PlayStatsHeatmapCell(
          weekday: 1,
          hour: 20,
          playedMs: 1000,
          sessionCount: 1,
        ),
      ],
      mediaTypeBuckets: const <PlayStatsDistributionBucket>[
        PlayStatsDistributionBucket(
          id: 'anime',
          label: '番剧',
          value: 100,
          share: 1,
        ),
      ],
      genreBuckets: const <PlayStatsDistributionBucket>[
        PlayStatsDistributionBucket(
          id: '18',
          label: '18',
          value: 100,
          share: 1,
        ),
      ],
      countryBuckets: const <PlayStatsDistributionBucket>[
        PlayStatsDistributionBucket(
          id: 'JP',
          label: 'JP',
          value: 100,
          share: 1,
        ),
      ],
      yearBuckets: const <PlayStatsDistributionBucket>[
        PlayStatsDistributionBucket(
          id: '2024',
          label: '2024',
          value: 100,
          share: 1,
        ),
      ],
      affinityPeople: const <PlayStatsAffinityPerson>[
        PlayStatsAffinityPerson(
          personId: 'p1',
          name: 'Person',
          role: 'Lead',
          job: 'Cast',
          watchedMs: 1000,
          appearanceCount: 1,
        ),
      ],
      behavior: const PlayStatsBehaviorSummary(
        totalSessions: 1,
        completedSessions: 1,
        completionRate: 1,
        forwardSeekCount: 0,
        backwardSeekCount: 0,
        startSourceBuckets: <PlayStatsDistributionBucket>[
          PlayStatsDistributionBucket(
            id: 'manual',
            label: '手动打开',
            value: 1,
            share: 1,
          ),
        ],
        intro: PlayStatsOpEdSummary(
          detectedCount: 0,
          skippedCount: 0,
          watchedCount: 0,
          totalPlayedMs: 0,
        ),
        outro: PlayStatsOpEdSummary(
          detectedCount: 0,
          skippedCount: 0,
          watchedCount: 0,
          totalPlayedMs: 0,
        ),
      ),
      topAnimes: const <PlayStatsTopAnime>[
        PlayStatsTopAnime(
          animeId: 'a1',
          videoId: 'v1',
          videoKind: 'episode',
          title: 'Anime',
          playedMs: 1000,
          viewCount: 1,
          sessionCount: 1,
          lastPlayedAtMs: 1,
        ),
      ],
      topVideos: const <PlayStatsTopVideo>[
        PlayStatsTopVideo(
          videoId: 'v1',
          title: 'Video',
          animeTitle: 'Anime',
          seasonTitle: 'S1',
          videoKind: 'episode',
          playedMs: 1000,
          viewCount: 1,
          sessionCount: 1,
          lastPlayedAtMs: 1,
          maxProgress: 0.5,
          completed: false,
        ),
      ],
      recentHistory: List<PlayHistoryRecord>.generate(
        7,
        (index) => _history(
          historyId: 'h$index',
          videoId: 'v$index',
          title: 'History ${index + 1}',
          startedAt: now.subtract(Duration(minutes: index)),
        ),
      ),
      continueWatching: const <PlayStatsContinueWatchingItem>[
        PlayStatsContinueWatchingItem(
          videoId: 'v1',
          title: 'Video',
          animeTitle: 'Anime',
          seasonTitle: 'S1',
          lastPlayedAtMs: 1,
          progress: 0.5,
          lastPositionMs: 1,
          mediaDurationMs: 10,
        ),
      ],
    );
  }

  @override
  Future<PlayStatsDashboard> loadDashboard({
    int topVideoLimit = 10,
    int topAnimeLimit = 10,
    int recentHistoryLimit = 20,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PlayStatsDebugSnapshot> loadDebugSnapshot({AppLocalizations? l10n}) {
    throw UnimplementedError();
  }

  @override
  Future<List<AnimeStatsRecord>> loadTopAnimesByPlayedMs({int limit = 20}) {
    throw UnimplementedError();
  }

  @override
  Future<List<VideoStatsRecord>> loadTopVideosByPlayedMs({int limit = 20}) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlayHistoryRecord>> loadRecentHistory({int limit = 50}) {
    throw UnimplementedError();
  }
}

PlayHistoryRecord _history({
  required String historyId,
  required String videoId,
  required String title,
  required DateTime startedAt,
}) {
  return PlayHistoryRecord(
    historyId: historyId,
    videoId: videoId,
    animeId: 'anime-1',
    seasonId: 'season-1',
    title: title,
    animeTitle: 'Anime',
    seasonTitle: '第1季',
    videoKind: 'episode',
    countsTowardCompletion: true,
    countryCodes: const <String>['JP'],
    genreIds: const <int>[18],
    credits: const <PlayStatsCredit>[],
    startSource: PlayStartSource.manual,
    startedAtMs: startedAt.millisecondsSinceEpoch,
    endedAtMs: startedAt
        .add(const Duration(minutes: 12))
        .millisecondsSinceEpoch,
    mediaDurationMs: 24 * 60 * 1000,
    watchedMs: 8 * 60 * 1000,
    maxProgress: 0.4,
    maxPositionMs: 8 * 60 * 1000,
    countedAsView: true,
    countedAsCompleted: false,
    opDetected: false,
    edDetected: false,
    opSkipped: false,
    edSkipped: false,
    opNotSkipped: false,
    edNotSkipped: false,
    opPlayedMs: 0,
    edPlayedMs: 0,
    forwardSeekCount: 0,
    backwardSeekCount: 0,
  );
}
