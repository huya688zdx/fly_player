import 'play_stats_database.dart';
import 'play_stats_models.dart';
import 'play_stats_identity.dart';
import 'play_stats_repositories.dart';
import 'play_stats_updaters.dart';
import 'dart:convert';

/// 默认的播放统计仓储实现，负责写入历史并更新聚合表。
class DefaultPlayStatsRepository implements PlayStatsRepository {
  final PlayStatsDatabase _database;
  final PlayHistoryStore _playHistoryStore;
  final VideoStatsUpdater _videoStatsUpdater;
  final AnimeStatsUpdater _animeStatsUpdater;
  final SeasonStatsUpdater _seasonStatsUpdater;

  /// 根据数据库、历史存储与更新器依赖构造仓储。
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

  /// 见 [PlayStatsRepository.persistFinalizedSession]。
  @override
  Future<void> persistFinalizedSession(FinalizedPlaySession session) async {
    await _database.transaction<void>((txn) async {
      final previousHistory = await _playHistoryStore.getByHistoryId(
        session.history.historyId,
        executor: txn,
      );
      await _playHistoryStore.insert(session.history, executor: txn);
      if (_database is SqflitePlayStatsDatabase) {
        final ref = (_database).bindingReference;
        if (ref.isNotEmpty) {
          final row = (await txn.query(
            'fly_record_provenance',
            where: 'history_id = ?',
            whereArgs: [session.history.historyId],
          )).single;
          final envelope = Map<String, dynamic>.from(
            jsonDecode(row['envelope_json'] as String) as Map,
          );
          envelope['source_ref'] ??= {
            ...ref,
            'remote_item_id': session.meta.videoId,
            if (session.meta.animeId.isNotEmpty &&
                !PlayStatsIdentityResolver.isDerivedAnimeId(
                  session.meta.animeId,
                ))
              'remote_series_id': session.meta.animeId,
            if (session.meta.seasonId.isNotEmpty)
              'remote_season_id': session.meta.seasonId,
          };
          await txn.update(
            'fly_record_provenance',
            {'envelope_json': jsonEncode(envelope)},
            where: 'history_id = ?',
            whereArgs: [session.history.historyId],
          );
        }
      }
      await _videoStatsUpdater.apply(
        session,
        previousHistory: previousHistory,
        executor: txn,
      );
      final seasonTargets = <_SeasonRecomputeTarget>{
        _SeasonRecomputeTarget(
          seasonId: session.meta.seasonId,
          animeId: session.meta.animeId,
          seasonTitle: session.meta.seasonTitle,
          lastPlayedAtMs: session.history.endedAtMs,
        ),
        if (previousHistory != null &&
            previousHistory.seasonId.trim().isNotEmpty &&
            previousHistory.seasonId.trim() != session.meta.seasonId.trim())
          _SeasonRecomputeTarget(
            seasonId: previousHistory.seasonId,
            animeId: previousHistory.animeId,
            seasonTitle: previousHistory.seasonTitle,
            lastPlayedAtMs: previousHistory.endedAtMs,
          ),
      };
      for (final target in seasonTargets) {
        await _seasonStatsUpdater.recomputeForSeason(
          seasonId: target.seasonId,
          animeId: target.animeId,
          seasonTitle: target.seasonTitle,
          lastPlayedAtMs: target.lastPlayedAtMs,
          executor: txn,
        );
      }
      await _animeStatsUpdater.apply(
        session,
        previousHistory: previousHistory,
        executor: txn,
      );
    });
  }

  /// 见 [PlayStatsRepository.clearAll]。
  @override
  Future<void> clearAll() => _database.clearAll();
}

class _SeasonRecomputeTarget {
  final String seasonId;
  final String animeId;
  final String seasonTitle;
  final int lastPlayedAtMs;

  const _SeasonRecomputeTarget({
    required this.seasonId,
    required this.animeId,
    required this.seasonTitle,
    required this.lastPlayedAtMs,
  });

  @override
  bool operator ==(Object other) {
    return other is _SeasonRecomputeTarget &&
        other.seasonId.trim() == seasonId.trim();
  }

  @override
  int get hashCode => seasonId.trim().hashCode;
}
