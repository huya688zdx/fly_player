import 'play_stats_database.dart';
import 'play_stats_models.dart';
import 'play_stats_repositories.dart';
import 'play_stats_updaters.dart';

class DefaultPlayStatsRepository implements PlayStatsRepository {
  final PlayStatsDatabase _database;
  final PlayHistoryStore _playHistoryStore;
  final VideoStatsUpdater _videoStatsUpdater;
  final AnimeStatsUpdater _animeStatsUpdater;
  final SeasonStatsUpdater _seasonStatsUpdater;

  const DefaultPlayStatsRepository({
    required PlayStatsDatabase database,
    required PlayHistoryStore playHistoryStore,
    required VideoStatsUpdater videoStatsUpdater,
    required AnimeStatsUpdater animeStatsUpdater,
    required SeasonStatsUpdater seasonStatsUpdater,
  }) : _database = database,
       _playHistoryStore = playHistoryStore,
       _videoStatsUpdater = videoStatsUpdater,
       _animeStatsUpdater = animeStatsUpdater,
       _seasonStatsUpdater = seasonStatsUpdater;

  @override
  Future<void> persistFinalizedSession(FinalizedPlaySession session) async {
    await _database.transaction<void>((txn) async {
      await _playHistoryStore.insert(session.history, executor: txn);
      await _videoStatsUpdater.apply(session, executor: txn);
      await _seasonStatsUpdater.recomputeForSeason(
        seasonId: session.meta.seasonId,
        animeId: session.meta.animeId,
        seasonTitle: session.meta.seasonTitle,
        lastPlayedAtMs: session.history.endedAtMs,
        executor: txn,
      );
      await _animeStatsUpdater.apply(session, executor: txn);
    });
  }

  @override
  Future<void> clearAll() => _database.clearAll();
}
