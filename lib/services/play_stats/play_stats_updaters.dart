import 'package:sqflite/sqflite.dart';

import 'play_stats_identity.dart';
import 'play_stats_models.dart';
import 'play_stats_repositories.dart';

abstract class VideoStatsUpdater {
  Future<void> apply(
    FinalizedPlaySession session, {
    required DatabaseExecutor executor,
  });
}

abstract class AnimeStatsUpdater {
  Future<void> apply(
    FinalizedPlaySession session, {
    required DatabaseExecutor executor,
  });
}

abstract class SeasonStatsUpdater {
  Future<void> recomputeForSeason({
    required String seasonId,
    required String animeId,
    required String seasonTitle,
    required int lastPlayedAtMs,
    required DatabaseExecutor executor,
  });
}

class DefaultVideoStatsUpdater implements VideoStatsUpdater {
  final VideoStatsRepository _videoStatsRepository;
  final VideoCreditStatsRepository _videoCreditStatsRepository;

  const DefaultVideoStatsUpdater(
    this._videoStatsRepository,
    this._videoCreditStatsRepository,
  );

  @override
  Future<void> apply(
    FinalizedPlaySession session, {
    required DatabaseExecutor executor,
  }) async {
    final existing = await _videoStatsRepository.getByVideoId(
      session.meta.videoId,
      executor: executor,
    );
    final history = session.history;
    final meta = session.meta;
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
      clickCount: (existing?.clickCount ?? 0) + session.clickDelta,
      autoPlayCount: (existing?.autoPlayCount ?? 0) + session.autoPlayDelta,
      viewCount: (existing?.viewCount ?? 0) + (history.countedAsView ? 1 : 0),
      totalPlayedMs: (existing?.totalPlayedMs ?? 0) + history.watchedMs,
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

class DefaultSeasonStatsUpdater implements SeasonStatsUpdater {
  final VideoStatsRepository _videoStatsRepository;
  final SeasonStatsRepository _seasonStatsRepository;

  const DefaultSeasonStatsUpdater(
    this._videoStatsRepository,
    this._seasonStatsRepository,
  );

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

class DefaultAnimeStatsUpdater implements AnimeStatsUpdater {
  final AnimeStatsRepository _animeStatsRepository;
  final VideoStatsRepository _videoStatsRepository;
  final SeasonStatsRepository _seasonStatsRepository;

  const DefaultAnimeStatsUpdater(
    this._animeStatsRepository,
    this._videoStatsRepository,
    this._seasonStatsRepository,
  );

  @override
  Future<void> apply(
    FinalizedPlaySession session, {
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
    final next = AnimeStatsRecord(
      animeId: animeId,
      title: (updatedVideo?.animeTitle ?? session.meta.animeTitle).trim(),
      clickCount: (existing?.clickCount ?? 0) + session.clickDelta,
      viewCount: (existing?.viewCount ?? 0) + (history.countedAsView ? 1 : 0),
      totalPlayedMs: (existing?.totalPlayedMs ?? 0) + history.watchedMs,
      forwardSeekCount:
          (existing?.forwardSeekCount ?? 0) + history.forwardSeekCount,
      backwardSeekCount:
          (existing?.backwardSeekCount ?? 0) + history.backwardSeekCount,
      watchedEpisodeCount: watchedEpisodeCount,
      completedEpisodeCount: completedEpisodeCount,
      completedSeasonCount: completedSeasonCount,
      lastPlayedAtMs: history.endedAtMs,
    );
    await _animeStatsRepository.upsert(next, executor: executor);
  }
}
