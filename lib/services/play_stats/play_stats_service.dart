import 'play_stats_session_controller.dart';
import 'play_stats_backfill_service.dart';
import 'play_stats_database.dart';
import 'play_stats_repositories.dart';
import 'play_stats_repository_impl.dart';
import 'play_stats_summary_repository.dart';
import 'play_stats_updaters.dart';

/// 统一装配播放统计模块各项能力的服务门面。
class PlayStatsService {
  PlayStatsService._internal() {
    final db = SqflitePlayStatsDatabase();
    final historyStore = SqflitePlayHistoryStore(db);
    final videoRepo = SqfliteVideoStatsRepository(db);
    final videoCreditRepo = SqfliteVideoCreditStatsRepository(db);
    final animeRepo = SqfliteAnimeStatsRepository(db);
    final seasonRepo = SqfliteSeasonStatsRepository(db);
    final summaryRepo = SqflitePlayStatsSummaryRepository(db);
    final backfill = PlayStatsMetadataBackfillService(
      database: db,
      videoStatsRepository: videoRepo,
      videoCreditStatsRepository: videoCreditRepo,
    );
    final videoUpdater = DefaultVideoStatsUpdater(videoRepo, videoCreditRepo);
    final seasonUpdater = DefaultSeasonStatsUpdater(videoRepo, seasonRepo);
    final animeUpdater = DefaultAnimeStatsUpdater(
      animeRepo,
      videoRepo,
      seasonRepo,
    );
    final playStatsRepo = DefaultPlayStatsRepository(
      database: db,
      playHistoryStore: historyStore,
      videoStatsUpdater: videoUpdater,
      animeStatsUpdater: animeUpdater,
      seasonStatsUpdater: seasonUpdater,
    );
    database = db;
    playHistoryStore = historyStore;
    videoStatsRepository = videoRepo;
    videoCreditStatsRepository = videoCreditRepo;
    animeStatsRepository = animeRepo;
    seasonStatsRepository = seasonRepo;
    summaryRepository = summaryRepo;
    metadataBackfillService = backfill;
    videoStatsUpdater = videoUpdater;
    seasonStatsUpdater = seasonUpdater;
    animeStatsUpdater = animeUpdater;
    repository = playStatsRepo;
    sessionController = DefaultPlayStatsSessionController(
      repository: playStatsRepo,
    );
  }

  static final PlayStatsService instance = PlayStatsService._internal();

  late final PlayStatsDatabase database;
  late final PlayHistoryStore playHistoryStore;
  late final VideoStatsRepository videoStatsRepository;
  late final VideoCreditStatsRepository videoCreditStatsRepository;
  late final AnimeStatsRepository animeStatsRepository;
  late final SeasonStatsRepository seasonStatsRepository;
  late final PlayStatsSummaryRepository summaryRepository;
  late final PlayStatsMetadataBackfillService metadataBackfillService;
  late final VideoStatsUpdater videoStatsUpdater;
  late final SeasonStatsUpdater seasonStatsUpdater;
  late final AnimeStatsUpdater animeStatsUpdater;
  late final PlayStatsRepository repository;
  late final PlayStatsSessionController sessionController;
  String get currentScope => (database as SqflitePlayStatsDatabase).ownerScope;

  /// 绑定当前统计数据所属的账号作用域。
  Future<void> bindOwnerScope(String ownerScope) async {
    if ((database as SqflitePlayStatsDatabase).ownerScope ==
        ownerScope.trim().toLowerCase()) {
      return;
    }
    // Finish only the local statistics session before changing its database.
    // Media backend progress and native playback remain on their existing path.
    await sessionController.finishPlayback(reason: 'owner_scope_change');
    await (sessionController as DefaultPlayStatsSessionController)
        .drainPendingWrites();
    await metadataBackfillService.drainPendingWrites();
    await database.bindOwnerScope(ownerScope);
  }
}
