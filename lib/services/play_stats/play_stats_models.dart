enum PlayStartSource { manual, manualSwitch, autoNext, replay, systemResume }

class PlayStatsCredit {
  final String personId;
  final String name;
  final String role;
  final String job;
  final int order;

  const PlayStatsCredit({
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
    this.order = 0,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'personId': personId,
      'name': name,
      'role': role,
      'job': job,
      'order': order,
    };
  }
}

class PlayStatsVideoMeta {
  final String videoId;
  final String animeId;
  final String seasonId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final String videoKind;
  final bool countsTowardCompletion;
  final String country;
  final List<String> countryCodes;
  final List<int> genreIds;
  final int year;
  final int mediaDurationMs;
  final List<PlayStatsCredit> credits;

  const PlayStatsVideoMeta({
    required this.videoId,
    required this.animeId,
    required this.seasonId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.videoKind,
    required this.countsTowardCompletion,
    required this.country,
    this.countryCodes = const <String>[],
    this.genreIds = const <int>[],
    required this.year,
    required this.mediaDurationMs,
    this.credits = const <PlayStatsCredit>[],
  });

  PlayStatsVideoMeta copyWith({
    String? videoId,
    String? animeId,
    String? seasonId,
    String? title,
    String? animeTitle,
    String? seasonTitle,
    String? videoKind,
    bool? countsTowardCompletion,
    String? country,
    List<String>? countryCodes,
    List<int>? genreIds,
    int? year,
    int? mediaDurationMs,
    List<PlayStatsCredit>? credits,
  }) {
    return PlayStatsVideoMeta(
      videoId: videoId ?? this.videoId,
      animeId: animeId ?? this.animeId,
      seasonId: seasonId ?? this.seasonId,
      title: title ?? this.title,
      animeTitle: animeTitle ?? this.animeTitle,
      seasonTitle: seasonTitle ?? this.seasonTitle,
      videoKind: videoKind ?? this.videoKind,
      countsTowardCompletion:
          countsTowardCompletion ?? this.countsTowardCompletion,
      country: country ?? this.country,
      countryCodes: countryCodes ?? this.countryCodes,
      genreIds: genreIds ?? this.genreIds,
      year: year ?? this.year,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      credits: credits ?? this.credits,
    );
  }
}

class VideoStatsRecord {
  final String videoId;
  final String animeId;
  final String seasonId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final String videoKind;
  final bool countsTowardCompletion;
  final String country;
  final List<String> countryCodes;
  final List<int> genreIds;
  final int year;
  final int mediaDurationMs;
  final int clickCount;
  final int autoPlayCount;
  final int viewCount;
  final int totalPlayedMs;
  final double maxProgress;
  final double lastProgress;
  final int lastPositionMs;
  final bool completed;
  final bool metadataEnriched;
  final int lastPlayedAtMs;
  final List<PlayStatsCredit> credits;

  const VideoStatsRecord({
    required this.videoId,
    required this.animeId,
    required this.seasonId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.videoKind,
    required this.countsTowardCompletion,
    required this.country,
    this.countryCodes = const <String>[],
    this.genreIds = const <int>[],
    required this.year,
    required this.mediaDurationMs,
    required this.clickCount,
    required this.autoPlayCount,
    required this.viewCount,
    required this.totalPlayedMs,
    required this.maxProgress,
    required this.lastProgress,
    required this.lastPositionMs,
    required this.completed,
    required this.metadataEnriched,
    required this.lastPlayedAtMs,
    required this.credits,
  });
}

class VideoCreditRecord {
  final String videoId;
  final String animeId;
  final String seasonId;
  final String personId;
  final String name;
  final String role;
  final String job;
  final int order;

  const VideoCreditRecord({
    required this.videoId,
    required this.animeId,
    required this.seasonId,
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
    required this.order,
  });
}

class AnimeStatsRecord {
  final String animeId;
  final String title;
  final int clickCount;
  final int viewCount;
  final int totalPlayedMs;
  final int forwardSeekCount;
  final int backwardSeekCount;
  final int watchedEpisodeCount;
  final int completedEpisodeCount;
  final int completedSeasonCount;
  final int lastPlayedAtMs;

  const AnimeStatsRecord({
    required this.animeId,
    required this.title,
    required this.clickCount,
    required this.viewCount,
    required this.totalPlayedMs,
    required this.forwardSeekCount,
    required this.backwardSeekCount,
    required this.watchedEpisodeCount,
    required this.completedEpisodeCount,
    required this.completedSeasonCount,
    required this.lastPlayedAtMs,
  });
}

class SeasonStatsRecord {
  final String seasonId;
  final String animeId;
  final String title;
  final int totalEpisodeCount;
  final int watchedEpisodeCount;
  final int completedEpisodeCount;
  final bool isCompleted;
  final int lastPlayedAtMs;

  const SeasonStatsRecord({
    required this.seasonId,
    required this.animeId,
    required this.title,
    required this.totalEpisodeCount,
    required this.watchedEpisodeCount,
    required this.completedEpisodeCount,
    required this.isCompleted,
    required this.lastPlayedAtMs,
  });
}

class PlayHistoryRecord {
  final String historyId;
  final String videoId;
  final String animeId;
  final String seasonId;
  final String title;
  final String animeTitle;
  final String seasonTitle;
  final String videoKind;
  final bool countsTowardCompletion;
  final List<String> countryCodes;
  final List<int> genreIds;
  final List<PlayStatsCredit> credits;
  final PlayStartSource startSource;
  final int startedAtMs;
  final int endedAtMs;
  final int mediaDurationMs;
  final int watchedMs;
  final double maxProgress;
  final int maxPositionMs;
  final bool countedAsView;
  final bool countedAsCompleted;
  final bool opDetected;
  final bool edDetected;
  final bool opSkipped;
  final bool edSkipped;
  final bool opNotSkipped;
  final bool edNotSkipped;
  final int opPlayedMs;
  final int edPlayedMs;
  final int forwardSeekCount;
  final int backwardSeekCount;

  const PlayHistoryRecord({
    required this.historyId,
    required this.videoId,
    required this.animeId,
    required this.seasonId,
    required this.title,
    required this.animeTitle,
    required this.seasonTitle,
    required this.videoKind,
    required this.countsTowardCompletion,
    this.countryCodes = const <String>[],
    this.genreIds = const <int>[],
    this.credits = const <PlayStatsCredit>[],
    required this.startSource,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.mediaDurationMs,
    required this.watchedMs,
    required this.maxProgress,
    required this.maxPositionMs,
    required this.countedAsView,
    required this.countedAsCompleted,
    required this.opDetected,
    required this.edDetected,
    required this.opSkipped,
    required this.edSkipped,
    required this.opNotSkipped,
    required this.edNotSkipped,
    required this.opPlayedMs,
    required this.edPlayedMs,
    required this.forwardSeekCount,
    required this.backwardSeekCount,
  });
}

class OpEdSegment {
  final bool isIntro;
  final int startMs;
  final int endMs;

  const OpEdSegment({
    required this.isIntro,
    required this.startMs,
    required this.endMs,
  });

  int get durationMs => endMs > startMs ? endMs - startMs : 0;
}

class OpEdSnapshot {
  final bool opDetected;
  final bool edDetected;
  final bool opSkipped;
  final bool edSkipped;
  final bool opNotSkipped;
  final bool edNotSkipped;
  final int opPlayedMs;
  final int edPlayedMs;

  const OpEdSnapshot({
    required this.opDetected,
    required this.edDetected,
    required this.opSkipped,
    required this.edSkipped,
    required this.opNotSkipped,
    required this.edNotSkipped,
    required this.opPlayedMs,
    required this.edPlayedMs,
  });
}

class PlayStatsStartContext {
  final PlayStartSource startSource;
  final PlayStatsVideoMeta meta;
  final int startPositionMs;
  final int startedAtMs;

  const PlayStatsStartContext({
    required this.startSource,
    required this.meta,
    required this.startPositionMs,
    required this.startedAtMs,
  });
}

class FinalizedPlaySession {
  final PlayHistoryRecord history;
  final PlayStatsVideoMeta meta;
  final int clickDelta;
  final int autoPlayDelta;
  final int lastPositionMs;
  final String finishReason;

  const FinalizedPlaySession({
    required this.history,
    required this.meta,
    required this.clickDelta,
    required this.autoPlayDelta,
    required this.lastPositionMs,
    required this.finishReason,
  });
}
