import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/play_stats/play_stats.dart';

void main() {
  group('PlayStatsReportAggregator', () {
    test('builds weighted overview, behavior, and preference summaries', () {
      final now = DateTime.now();
      const aggregator = PlayStatsReportAggregator();
      final histories = <PlayHistoryRecord>[
        _history(
          historyId: 'h1',
          videoId: 'video-1',
          animeId: 'anime-1',
          seasonId: 'season-1',
          title: 'Episode 1',
          animeTitle: 'Alpha',
          seasonTitle: 'S1',
          watchedMs: 40 * 60 * 1000,
          startedAt: now.subtract(const Duration(days: 1, hours: 2)),
          countedAsView: true,
          countedAsCompleted: true,
          genreIds: const <int>[16, 18],
          countryCodes: const <String>['JP'],
          startSource: PlayStartSource.autoNext,
          forwardSeekCount: 2,
          opDetected: true,
          opSkipped: true,
          credits: const <PlayStatsCredit>[
            PlayStatsCredit(
              personId: 'p1',
              name: 'Actor A',
              role: 'Lead',
              job: 'Cast',
            ),
          ],
        ),
        _history(
          historyId: 'h2',
          videoId: 'video-2',
          animeId: 'anime-2',
          seasonId: 'season-2',
          title: 'Movie',
          animeTitle: 'Movie',
          seasonTitle: '',
          videoKind: 'movie',
          watchedMs: 90 * 60 * 1000,
          startedAt: now.subtract(const Duration(days: 2, hours: 4)),
          countedAsView: true,
          countedAsCompleted: false,
          genreIds: const <int>[18],
          countryCodes: const <String>['US'],
          startSource: PlayStartSource.manual,
          backwardSeekCount: 1,
          edDetected: true,
          edNotSkipped: true,
          credits: const <PlayStatsCredit>[
            PlayStatsCredit(
              personId: 'p2',
              name: 'Director B',
              role: 'Director',
              job: 'Crew',
            ),
          ],
        ),
      ];
      final videos = <VideoStatsRecord>[
        _video(
          videoId: 'video-1',
          animeId: 'anime-1',
          seasonId: 'season-1',
          title: 'Episode 1',
          animeTitle: 'Alpha',
          seasonTitle: 'S1',
          lastPlayedAtMs: now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          year: 2024,
          lastProgress: 0.35,
        ),
        _video(
          videoId: 'video-2',
          animeId: 'anime-2',
          seasonId: 'season-2',
          title: 'Movie',
          animeTitle: 'Movie',
          seasonTitle: '',
          videoKind: 'movie',
          lastPlayedAtMs: now
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
          year: 2022,
          completed: false,
          lastProgress: 0.0,
        ),
      ];
      final seasons = <SeasonStatsRecord>[
        SeasonStatsRecord(
          seasonId: 'season-1',
          animeId: 'anime-1',
          title: 'S1',
          totalEpisodeCount: 12,
          watchedEpisodeCount: 12,
          completedEpisodeCount: 12,
          isCompleted: true,
          lastPlayedAtMs: now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
      ];

      final snapshot = aggregator.buildSnapshot(
        range: PlayStatsRange.days7,
        histories: histories,
        videos: videos,
        seasons: seasons,
      );

      expect(snapshot.overview.totalPlayedMs, 130 * 60 * 1000);
      expect(snapshot.overview.totalClickCount, 1);
      expect(snapshot.overview.totalViewCount, 2);
      expect(snapshot.overview.totalCompletedVideoCount, 1);
      expect(snapshot.overview.totalCompletedSeasonCount, 1);
      expect(snapshot.behavior.totalSessions, 2);
      expect(snapshot.behavior.completedSessions, 1);
      expect(snapshot.behavior.forwardSeekCount, 2);
      expect(snapshot.behavior.backwardSeekCount, 1);
      expect(snapshot.behavior.startSourceBuckets.first.id, 'autoNext');
      expect(snapshot.genreBuckets.first.id, '18');
      expect(snapshot.countryBuckets.first.id, 'US');
      expect(snapshot.yearBuckets.first.id, '2022');
      expect(snapshot.affinityPeople.first.name, 'Director B');
      expect(snapshot.topVideos.first.videoId, 'video-2');
      expect(snapshot.continueWatching.single.videoId, 'video-1');
      expect(snapshot.trends, hasLength(7));
    });

    test(
      'filters continue watching and season completion by selected range',
      () {
        final now = DateTime.now();
        const aggregator = PlayStatsReportAggregator();
        final histories = <PlayHistoryRecord>[
          _history(
            historyId: 'h1',
            videoId: 'video-1',
            animeId: 'anime-1',
            seasonId: 'season-1',
            title: 'Episode 1',
            animeTitle: 'Alpha',
            seasonTitle: 'S1',
            watchedMs: 15 * 60 * 1000,
            startedAt: now.subtract(const Duration(days: 40)),
          ),
        ];
        final videos = <VideoStatsRecord>[
          _video(
            videoId: 'video-1',
            animeId: 'anime-1',
            seasonId: 'season-1',
            title: 'Episode 1',
            animeTitle: 'Alpha',
            seasonTitle: 'S1',
            lastPlayedAtMs: now
                .subtract(const Duration(days: 40))
                .millisecondsSinceEpoch,
            lastProgress: 0.6,
          ),
        ];
        final seasons = <SeasonStatsRecord>[
          SeasonStatsRecord(
            seasonId: 'season-1',
            animeId: 'anime-1',
            title: 'S1',
            totalEpisodeCount: 12,
            watchedEpisodeCount: 10,
            completedEpisodeCount: 10,
            isCompleted: true,
            lastPlayedAtMs: now
                .subtract(const Duration(days: 40))
                .millisecondsSinceEpoch,
          ),
        ];

        final recentSnapshot = aggregator.buildSnapshot(
          range: PlayStatsRange.days30,
          histories: const <PlayHistoryRecord>[],
          videos: videos,
          seasons: seasons,
        );
        final allSnapshot = aggregator.buildSnapshot(
          range: PlayStatsRange.all,
          histories: histories,
          videos: videos,
          seasons: seasons,
        );

        expect(recentSnapshot.continueWatching, isEmpty);
        expect(recentSnapshot.overview.totalCompletedSeasonCount, 0);
        expect(allSnapshot.continueWatching, hasLength(1));
        expect(allSnapshot.overview.totalCompletedSeasonCount, 1);
      },
    );

    test('merges same-title anime entries even when anime ids differ', () {
      final now = DateTime.now();
      const aggregator = PlayStatsReportAggregator();
      final histories = <PlayHistoryRecord>[
        _history(
          historyId: 'h1',
          videoId: 'video-1',
          animeId: 'anime-a',
          seasonId: 'season-a',
          title: 'Episode A',
          animeTitle: '葬送的芙莉莲',
          seasonTitle: '第1季',
          watchedMs: 60 * 1000,
          startedAt: now.subtract(const Duration(days: 1)),
          countedAsView: true,
        ),
        _history(
          historyId: 'h2',
          videoId: 'video-2',
          animeId: 'anime-b',
          seasonId: 'season-b',
          title: 'Episode B',
          animeTitle: '葬送的芙莉莲',
          seasonTitle: '特别篇',
          watchedMs: 40 * 1000,
          startedAt: now.subtract(const Duration(days: 2)),
          countedAsView: true,
        ),
      ];

      final snapshot = aggregator.buildSnapshot(
        range: PlayStatsRange.days7,
        histories: histories,
        videos: const <VideoStatsRecord>[],
        seasons: const <SeasonStatsRecord>[],
      );

      final frierenEntries = snapshot.topAnimes
          .where((item) => item.title == '葬送的芙莉莲')
          .toList(growable: false);
      expect(frierenEntries, hasLength(1));
      expect(frierenEntries.single.playedMs, 100 * 1000);
      expect(frierenEntries.single.sessionCount, 2);
      expect(frierenEntries.single.videoId, 'video-1');
    });

    test('merges same person across works even when role or job differs', () {
      final now = DateTime.now();
      const aggregator = PlayStatsReportAggregator();
      final histories = <PlayHistoryRecord>[
        _history(
          historyId: 'h1',
          videoId: 'video-1',
          animeId: 'anime-1',
          seasonId: 'season-1',
          title: 'Episode 1',
          animeTitle: 'Alpha',
          seasonTitle: 'S1',
          watchedMs: 60 * 1000,
          startedAt: now.subtract(const Duration(days: 1)),
          credits: const <PlayStatsCredit>[
            PlayStatsCredit(
              personId: '',
              name: 'Same Person',
              role: 'Lead',
              job: 'Cast',
            ),
          ],
        ),
        _history(
          historyId: 'h2',
          videoId: 'video-2',
          animeId: 'anime-2',
          seasonId: 'season-2',
          title: 'Episode 2',
          animeTitle: 'Beta',
          seasonTitle: 'S2',
          watchedMs: 40 * 1000,
          startedAt: now.subtract(const Duration(days: 2)),
          credits: const <PlayStatsCredit>[
            PlayStatsCredit(
              personId: '',
              name: 'Same Person',
              role: 'Director',
              job: 'Crew',
            ),
          ],
        ),
      ];

      final snapshot = aggregator.buildSnapshot(
        range: PlayStatsRange.days7,
        histories: histories,
        videos: const <VideoStatsRecord>[],
        seasons: const <SeasonStatsRecord>[],
      );

      final entries = snapshot.affinityPeople
          .where((item) => item.name == 'Same Person')
          .toList(growable: false);
      expect(entries, hasLength(1));
      expect(entries.single.watchedMs, 100 * 1000);
      expect(entries.single.appearanceCount, 2);
    });
  });
}

PlayHistoryRecord _history({
  required String historyId,
  required String videoId,
  required String animeId,
  required String seasonId,
  required String title,
  required String animeTitle,
  required String seasonTitle,
  required int watchedMs,
  required DateTime startedAt,
  String videoKind = 'episode',
  bool countedAsView = false,
  bool countedAsCompleted = false,
  List<int> genreIds = const <int>[],
  List<String> countryCodes = const <String>[],
  List<PlayStatsCredit> credits = const <PlayStatsCredit>[],
  PlayStartSource startSource = PlayStartSource.manual,
  int forwardSeekCount = 0,
  int backwardSeekCount = 0,
  bool opDetected = false,
  bool edDetected = false,
  bool opSkipped = false,
  bool edSkipped = false,
  bool opNotSkipped = false,
  bool edNotSkipped = false,
}) {
  return PlayHistoryRecord(
    historyId: historyId,
    videoId: videoId,
    animeId: animeId,
    seasonId: seasonId,
    title: title,
    animeTitle: animeTitle,
    seasonTitle: seasonTitle,
    videoKind: videoKind,
    countsTowardCompletion: true,
    countryCodes: countryCodes,
    genreIds: genreIds,
    credits: credits,
    startSource: startSource,
    startedAtMs: startedAt.millisecondsSinceEpoch,
    endedAtMs: startedAt
        .add(const Duration(minutes: 30))
        .millisecondsSinceEpoch,
    mediaDurationMs: 45 * 60 * 1000,
    watchedMs: watchedMs,
    maxProgress: countedAsCompleted ? 0.92 : 0.55,
    maxPositionMs: watchedMs,
    countedAsView: countedAsView,
    countedAsCompleted: countedAsCompleted,
    opDetected: opDetected,
    edDetected: edDetected,
    opSkipped: opSkipped,
    edSkipped: edSkipped,
    opNotSkipped: opNotSkipped,
    edNotSkipped: edNotSkipped,
    opPlayedMs: opDetected ? 90 * 1000 : 0,
    edPlayedMs: edDetected ? 90 * 1000 : 0,
    forwardSeekCount: forwardSeekCount,
    backwardSeekCount: backwardSeekCount,
  );
}

VideoStatsRecord _video({
  required String videoId,
  required String animeId,
  required String seasonId,
  required String title,
  required String animeTitle,
  required String seasonTitle,
  required int lastPlayedAtMs,
  String videoKind = 'episode',
  int year = 0,
  bool completed = false,
  double lastProgress = 0.25,
}) {
  return VideoStatsRecord(
    videoId: videoId,
    animeId: animeId,
    seasonId: seasonId,
    title: title,
    animeTitle: animeTitle,
    seasonTitle: seasonTitle,
    videoKind: videoKind,
    countsTowardCompletion: true,
    country: '',
    countryCodes: const <String>['JP'],
    genreIds: const <int>[18],
    year: year,
    mediaDurationMs: 45 * 60 * 1000,
    clickCount: 1,
    autoPlayCount: 0,
    viewCount: 1,
    totalPlayedMs: 20 * 60 * 1000,
    maxProgress: lastProgress,
    lastProgress: lastProgress,
    lastPositionMs: (45 * 60 * 1000 * lastProgress).round(),
    completed: completed,
    metadataEnriched: year > 0,
    lastPlayedAtMs: lastPlayedAtMs,
    credits: const <PlayStatsCredit>[
      PlayStatsCredit(
        personId: 'p1',
        name: 'Actor A',
        role: 'Lead',
        job: 'Cast',
      ),
    ],
  );
}
