/// 定义播放会话的启动来源。
enum PlayStartSource { manual, manualSwitch, autoNext, replay, systemResume }

/// 表示与视频关联的一条演职员信息。
class PlayStatsCredit {
  final String personId;
  final String name;
  final String role;
  final String job;
  final int order;

  /// 根据演职员字段构造对象。
  const PlayStatsCredit({
    required this.personId,
    required this.name,
    required this.role,
    required this.job,
    this.order = 0,
  });

  /// 转换为可序列化的映射结构。
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

/// 表示单个视频在统计体系中的业务元数据。
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

  /// 根据视频统计元数据字段构造对象。
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

  /// 基于现有对象生成一份变更后的副本。
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

/// 表示按视频维度聚合后的统计记录。
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

  /// 根据视频统计字段构造记录对象。
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

/// 表示按视频维度持久化的演职员统计记录。
class VideoCreditRecord {
  final String videoId;
  final String animeId;
  final String seasonId;
  final String personId;
  final String name;
  final String role;
  final String job;
  final int order;

  /// 根据演职员统计字段构造记录对象。
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

/// 表示按番剧维度聚合后的统计记录。
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

  /// 根据番剧统计字段构造记录对象。
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

/// 表示按季度维度聚合后的统计记录。
class SeasonStatsRecord {
  final String seasonId;
  final String animeId;
  final String title;
  final int totalEpisodeCount;
  final int watchedEpisodeCount;
  final int completedEpisodeCount;
  final bool isCompleted;
  final int lastPlayedAtMs;

  /// 根据季度统计字段构造记录对象。
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

/// 表示一次播放会话的历史记录。
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

  /// 根据播放历史字段构造记录对象。
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

/// 表示识别出的片头或片尾时间区间。
class OpEdSegment {
  final bool isIntro;
  final int startMs;
  final int endMs;

  /// 根据片头片尾时间范围构造对象。
  const OpEdSegment({
    required this.isIntro,
    required this.startMs,
    required this.endMs,
  });

  /// 返回当前片段的有效时长。
  int get durationMs => endMs > startMs ? endMs - startMs : 0;
}

/// 表示单次播放中片头片尾相关行为的统计快照。
class OpEdSnapshot {
  final bool opDetected;
  final bool edDetected;
  final bool opSkipped;
  final bool edSkipped;
  final bool opNotSkipped;
  final bool edNotSkipped;
  final int opPlayedMs;
  final int edPlayedMs;

  /// 根据片头片尾统计字段构造对象。
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

/// 描述启动一次播放统计会话所需的上下文。
class PlayStatsStartContext {
  final PlayStartSource startSource;
  final PlayStatsVideoMeta meta;
  final int startPositionMs;
  final int startedAtMs;

  /// 根据播放启动上下文字段构造对象。
  const PlayStatsStartContext({
    required this.startSource,
    required this.meta,
    required this.startPositionMs,
    required this.startedAtMs,
  });
}

/// 表示已经收口并可持久化的播放会话结果。
class FinalizedPlaySession {
  final PlayHistoryRecord history;
  final PlayStatsVideoMeta meta;
  final int clickDelta;
  final int autoPlayDelta;
  final int lastPositionMs;
  final String finishReason;

  /// 根据最终播放会话字段构造对象。
  const FinalizedPlaySession({
    required this.history,
    required this.meta,
    required this.clickDelta,
    required this.autoPlayDelta,
    required this.lastPositionMs,
    required this.finishReason,
  });
}
