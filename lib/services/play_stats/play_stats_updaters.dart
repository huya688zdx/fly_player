import 'package:sqflite/sqflite.dart';

import 'play_stats_identity.dart';
import 'play_stats_models.dart';
import 'play_stats_repositories.dart';

/// 定义视频维度统计记录的更新接口。
abstract class VideoStatsUpdater {
  /// 根据一次最终播放会话更新视频统计记录。
  Future<void> apply(
    FinalizedPlaySession session, {
    PlayHistoryRecord? previousHistory,
    required DatabaseExecutor executor,
  });
}

/// 定义番剧维度统计记录的更新接口。
abstract class AnimeStatsUpdater {
  /// 根据一次最终播放会话更新番剧统计记录。
  Future<void> apply(
    FinalizedPlaySession session, {
    PlayHistoryRecord? previousHistory,
    required DatabaseExecutor executor,
  });
}

/// 定义季度维度统计记录的更新接口。
abstract class SeasonStatsUpdater {
  /// 根据季度下的视频统计结果重新计算季度聚合值。
  Future<void> recomputeForSeason({
    required String seasonId,
    required String animeId,
    required String seasonTitle,
    required int lastPlayedAtMs,
    required DatabaseExecutor executor,
  });
}

/// 默认的视频维度统计更新器实现。
class DefaultVideoStatsUpdater implements VideoStatsUpdater {
  final VideoStatsRepository _videoStatsRepository;
  final VideoCreditStatsRepository _videoCreditStatsRepository;

  /// 根据视频统计仓储与演职员仓储构造更新器。
  const DefaultVideoStatsUpdater(
    this._videoStatsRepository,
    this._videoCreditStatsRepository,
  );

  /// 见 [VideoStatsUpdater.apply]。
  @override
  Future<void> apply(
    FinalizedPlaySession session, {
    PlayHistoryRecord? previousHistory,
    required DatabaseExecutor executor,
  }) async {
    final existing = await _videoStatsRepository.getByVideoId(
      session.meta.videoId,
      executor: executor,
    );
    final history = session.history;
    final meta = session.meta;
    final previous =
        previousHistory != null &&
            previousHistory.videoId.trim() == meta.videoId.trim()
        ? previousHistory
        : null;
    final clickDelta = previous == null ? session.clickDelta : 0;
    final autoPlayDelta = previous == null ? session.autoPlayDelta : 0;
    final viewDelta =
        _boolCount(history.countedAsView) -
        _boolCount(previous?.countedAsView ?? false);
    final watchedDelta = history.watchedMs - (previous?.watchedMs ?? 0);
    final effectiveCountryCodes = meta.countryCodes.isNotEmpty
        ? meta.countryCodes
        : (existing?.countryCodes ?? const <String>[]);
    final effectiveGenreIds = meta.genreIds.isNotEmpty
        ? meta.genreIds
        : (existing?.genreIds ?? const <int>[]);
    final effectiveCredits = meta.credits.isNotEmpty
        ? meta.credits
        : (existing?.credits ?? const <PlayStatsCredit>[]);
    final effectiveAnimeId = _resolveAnimeId(
      existing?.animeId ?? '',
      meta.animeId,
    );
    final next = VideoStatsRecord(
      videoId: meta.videoId,
      animeId: effectiveAnimeId,
      seasonId: meta.seasonId,
      title: meta.title,
      animeTitle: meta.animeTitle,
      seasonTitle: meta.seasonTitle,
      videoKind: meta.videoKind,
      countsTowardCompletion: meta.countsTowardCompletion,
      country: meta.country,
      countryCodes: effectiveCountryCodes,
      genreIds: effectiveGenreIds,
      year: meta.year,
      mediaDurationMs: meta.mediaDurationMs > 0
          ? meta.mediaDurationMs
          : history.mediaDurationMs,
      clickCount: _nonNegative((existing?.clickCount ?? 0) + clickDelta),
      autoPlayCount: _nonNegative(
        (existing?.autoPlayCount ?? 0) + autoPlayDelta,
      ),
      viewCount: _nonNegative((existing?.viewCount ?? 0) + viewDelta),
      totalPlayedMs: _nonNegative(
        (existing?.totalPlayedMs ?? 0) + watchedDelta,
      ),
      maxProgress: _max(existing?.maxProgress ?? 0, history.maxProgress),
      lastProgress: history.maxProgress,
      lastPositionMs: session.lastPositionMs,
      completed: (existing?.completed ?? false) || history.countedAsCompleted,
      metadataEnriched: existing?.metadataEnriched ?? false,
      lastPlayedAtMs: history.endedAtMs,
      credits: effectiveCredits,
    );
    await _videoStatsRepository.upsert(next, executor: executor);
    if (meta.credits.isNotEmpty) {
      await _videoCreditStatsRepository.replaceForVideo(
        meta.videoId,
        meta.credits
            .where((credit) => credit.personId.trim().isNotEmpty)
            .map(
              (credit) => VideoCreditRecord(
                videoId: meta.videoId,
                animeId: effectiveAnimeId,
                seasonId: meta.seasonId,
                personId: credit.personId,
                name: credit.name,
                role: credit.role,
                job: credit.job,
                order: credit.order,
              ),
            )
            .toList(growable: false),
        executor: executor,
      );
    }
  }

  int _boolCount(bool value) => value ? 1 : 0;

  int _nonNegative(int value) => value < 0 ? 0 : value;

  String _resolveAnimeId(String existingAnimeId, String nextAnimeId) {
    final existing = existingAnimeId.trim();
    final next = nextAnimeId.trim();
    if (existing.isNotEmpty &&
        !PlayStatsIdentityResolver.isDerivedAnimeId(existing) &&
        (next.isEmpty || PlayStatsIdentityResolver.isDerivedAnimeId(next))) {
      return existing;
    }
    if (next.isNotEmpty) {
      return next;
    }
    if (PlayStatsIdentityResolver.isDerivedAnimeId(existing)) {
      return '';
    }
    return existing;
  }

  double _max(double left, double right) => left >= right ? left : right;
}

/// 默认的季度维度统计更新器实现。
class DefaultSeasonStatsUpdater implements SeasonStatsUpdater {
  final VideoStatsRepository _videoStatsRepository;
  final SeasonStatsRepository _seasonStatsRepository;

  /// 根据视频统计仓储与季度仓储构造更新器。
  const DefaultSeasonStatsUpdater(
    this._videoStatsRepository,
    this._seasonStatsRepository,
  );

  /// 见 [SeasonStatsUpdater.recomputeForSeason]。
  @override
  Future<void> recomputeForSeason({
    required String seasonId,
    required String animeId,
    required String seasonTitle,
    required int lastPlayedAtMs,
    required DatabaseExecutor executor,
  }) async {
    if (seasonId.trim().isEmpty) return;
    final totalEpisodeCount = await _videoStatsRepository.countSeasonMainVideos(
      seasonId,
      executor: executor,
    );
    final watchedEpisodeCount = await _videoStatsRepository
        .countSeasonWatchedMainVideos(seasonId, executor: executor);
    final completedEpisodeCount = await _videoStatsRepository
        .countSeasonCompletedMainVideos(seasonId, executor: executor);
    final next = SeasonStatsRecord(
      seasonId: seasonId,
      animeId: animeId,
      title: seasonTitle,
      totalEpisodeCount: totalEpisodeCount,
      watchedEpisodeCount: watchedEpisodeCount,
      completedEpisodeCount: completedEpisodeCount,
      isCompleted:
          totalEpisodeCount > 0 && completedEpisodeCount >= totalEpisodeCount,
      lastPlayedAtMs: lastPlayedAtMs,
    );
    await _seasonStatsRepository.upsert(next, executor: executor);
  }
}

/// 默认的番剧维度统计更新器实现。
class DefaultAnimeStatsUpdater implements AnimeStatsUpdater {
  final AnimeStatsRepository _animeStatsRepository;
  final VideoStatsRepository _videoStatsRepository;
  final SeasonStatsRepository _seasonStatsRepository;

  /// 根据番剧、视频与季度仓储构造更新器。
  const DefaultAnimeStatsUpdater(
    this._animeStatsRepository,
    this._videoStatsRepository,
    this._seasonStatsRepository,
  );

  /// 见 [AnimeStatsUpdater.apply]。
  @override
  Future<void> apply(
    FinalizedPlaySession session, {
    PlayHistoryRecord? previousHistory,
    required DatabaseExecutor executor,
  }) async {
    final updatedVideo = await _videoStatsRepository.getByVideoId(
      session.meta.videoId,
      executor: executor,
    );
    final animeId = (updatedVideo?.animeId ?? session.meta.animeId).trim();
    if (animeId.isEmpty) return;
    final existing = await _animeStatsRepository.getByAnimeId(
      animeId,
      executor: executor,
    );
    final watchedEpisodeCount = await _videoStatsRepository
        .countAnimeWatchedMainVideos(animeId, executor: executor);
    final completedEpisodeCount = await _videoStatsRepository
        .countAnimeCompletedMainVideos(animeId, executor: executor);
    final completedSeasonCount = await _seasonStatsRepository
        .countCompletedSeasonsByAnime(animeId, executor: executor);
    final history = session.history;
    final previous =
        previousHistory != null && previousHistory.animeId.trim() == animeId
        ? previousHistory
        : null;
    final clickDelta = previous == null ? session.clickDelta : 0;
    final viewDelta =
        _boolCount(history.countedAsView) -
        _boolCount(previous?.countedAsView ?? false);
    final watchedDelta = history.watchedMs - (previous?.watchedMs ?? 0);
    final forwardSeekDelta =
        history.forwardSeekCount - (previous?.forwardSeekCount ?? 0);
    final backwardSeekDelta =
        history.backwardSeekCount - (previous?.backwardSeekCount ?? 0);
    final next = AnimeStatsRecord(
      animeId: animeId,
      title: (updatedVideo?.animeTitle ?? session.meta.animeTitle).trim(),
      clickCount: _nonNegative((existing?.clickCount ?? 0) + clickDelta),
      viewCount: _nonNegative((existing?.viewCount ?? 0) + viewDelta),
      totalPlayedMs: _nonNegative(
        (existing?.totalPlayedMs ?? 0) + watchedDelta,
      ),
      forwardSeekCount: _nonNegative(
        (existing?.forwardSeekCount ?? 0) + forwardSeekDelta,
      ),
      backwardSeekCount: _nonNegative(
        (existing?.backwardSeekCount ?? 0) + backwardSeekDelta,
      ),
      watchedEpisodeCount: watchedEpisodeCount,
      completedEpisodeCount: completedEpisodeCount,
      completedSeasonCount: completedSeasonCount,
      lastPlayedAtMs: history.endedAtMs,
    );
    await _animeStatsRepository.upsert(next, executor: executor);
  }

  int _boolCount(bool value) => value ? 1 : 0;

  int _nonNegative(int value) => value < 0 ? 0 : value;
}
