import 'dart:convert';

import 'play_stats_models.dart';

/// 负责播放统计模型与数据库字段之间的转换。
class PlayStatsSqlMapper {
  const PlayStatsSqlMapper._();

  /// 将布尔值转换为 SQLite 常用的整型表示。
  static int boolToInt(bool value) => value ? 1 : 0;

  /// 将 SQLite 返回值转换为布尔值。
  static bool intToBool(Object? value) {
    return switch (value) {
      final bool v => v,
      final int v => v != 0,
      final num v => v != 0,
      final String v => v == '1' || v.toLowerCase() == 'true',
      _ => false,
    };
  }

  /// 将 SQLite 返回值转换为整数。
  static int intValue(Object? value) {
    return switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
  }

  /// 将 SQLite 返回值转换为双精度浮点数。
  static double doubleValue(Object? value) {
    return switch (value) {
      final double v => v,
      final num v => v.toDouble(),
      final String v => double.tryParse(v) ?? 0,
      _ => 0,
    };
  }

  /// 将 SQLite 返回值转换为字符串。
  static String stringValue(Object? value) => value?.toString() ?? '';

  /// 将播放启动来源枚举转换为数据库文本值。
  static String startSourceToText(PlayStartSource value) {
    return switch (value) {
      PlayStartSource.manual => 'manual',
      PlayStartSource.manualSwitch => 'manual_switch',
      PlayStartSource.autoNext => 'auto_next',
      PlayStartSource.replay => 'replay',
      PlayStartSource.systemResume => 'system_resume',
    };
  }

  /// 将数据库中的启动来源文本还原为枚举值。
  static PlayStartSource startSourceFromText(Object? value) {
    return switch (stringValue(value).trim()) {
      'manual_switch' => PlayStartSource.manualSwitch,
      'auto_next' => PlayStartSource.autoNext,
      'replay' => PlayStartSource.replay,
      'system_resume' => PlayStartSource.systemResume,
      _ => PlayStartSource.manual,
    };
  }

  /// 将演职员列表编码为 JSON 文本。
  static String creditsToJson(List<PlayStatsCredit> credits) {
    return jsonEncode(
      credits.map((credit) => credit.toJson()).toList(growable: false),
    );
  }

  /// 将 JSON 文本解码为演职员列表。
  static List<PlayStatsCredit> creditsFromJson(Object? value) {
    final decoded = _decodeJsonList(value);
    if (decoded == null) return const <PlayStatsCredit>[];
    return decoded
        .whereType<Map>()
        .map((entry) {
          return PlayStatsCredit(
            personId: stringValue(entry['personId']),
            name: stringValue(entry['name']),
            role: stringValue(entry['role']),
            job: stringValue(entry['job']),
            order: intValue(entry['order']),
          );
        })
        .toList(growable: false);
  }

  /// 将整数列表编码为 JSON 文本。
  static String intListToJson(List<int> values) =>
      jsonEncode(values.toList(growable: false));

  /// 将 JSON 文本解码为整数列表。
  static List<int> intListFromJson(Object? value) {
    final decoded = _decodeJsonList(value);
    if (decoded == null) return const <int>[];
    return decoded
        .map((entry) => int.tryParse('$entry'))
        .whereType<int>()
        .toList(growable: false);
  }

  /// 将字符串列表编码为 JSON 文本。
  static String stringListToJson(List<String> values) =>
      jsonEncode(values.toList(growable: false));

  /// 将 JSON 文本解码为字符串列表。
  static List<String> stringListFromJson(Object? value) {
    final decoded = _decodeJsonList(value);
    if (decoded == null) return const <String>[];
    return decoded
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  /// 将视频统计记录转换为数据库字段映射。
  static Map<String, Object?> videoStatsToMap(VideoStatsRecord record) {
    return <String, Object?>{
      'video_id': record.videoId,
      'anime_id': record.animeId,
      'season_id': record.seasonId,
      'title': record.title,
      'anime_title': record.animeTitle,
      'season_title': record.seasonTitle,
      'video_kind': record.videoKind,
      'counts_toward_completion': boolToInt(record.countsTowardCompletion),
      'country': record.country,
      'country_codes_json': stringListToJson(record.countryCodes),
      'genre_ids_json': intListToJson(record.genreIds),
      'year': record.year,
      'media_duration_ms': record.mediaDurationMs,
      'click_count': record.clickCount,
      'auto_play_count': record.autoPlayCount,
      'view_count': record.viewCount,
      'total_played_ms': record.totalPlayedMs,
      'max_progress': record.maxProgress,
      'last_progress': record.lastProgress,
      'last_position_ms': record.lastPositionMs,
      'completed': boolToInt(record.completed),
      'metadata_enriched': boolToInt(record.metadataEnriched),
      'last_played_at_ms': record.lastPlayedAtMs,
      'credits_json': creditsToJson(record.credits),
    };
  }

  /// 将数据库行转换为视频统计记录。
  static VideoStatsRecord videoStatsFromMap(Map<String, Object?> row) {
    return VideoStatsRecord(
      videoId: stringValue(row['video_id']),
      animeId: stringValue(row['anime_id']),
      seasonId: stringValue(row['season_id']),
      title: stringValue(row['title']),
      animeTitle: stringValue(row['anime_title']),
      seasonTitle: stringValue(row['season_title']),
      videoKind: stringValue(row['video_kind']),
      countsTowardCompletion: intToBool(row['counts_toward_completion']),
      country: stringValue(row['country']),
      countryCodes: stringListFromJson(row['country_codes_json']),
      genreIds: intListFromJson(row['genre_ids_json']),
      year: intValue(row['year']),
      mediaDurationMs: intValue(row['media_duration_ms']),
      clickCount: intValue(row['click_count']),
      autoPlayCount: intValue(row['auto_play_count']),
      viewCount: intValue(row['view_count']),
      totalPlayedMs: intValue(row['total_played_ms']),
      maxProgress: doubleValue(row['max_progress']),
      lastProgress: doubleValue(row['last_progress']),
      lastPositionMs: intValue(row['last_position_ms']),
      completed: intToBool(row['completed']),
      metadataEnriched: intToBool(row['metadata_enriched']),
      lastPlayedAtMs: intValue(row['last_played_at_ms']),
      credits: creditsFromJson(row['credits_json']),
    );
  }

  /// 将演职员统计记录转换为数据库字段映射。
  static Map<String, Object?> videoCreditToMap(VideoCreditRecord record) {
    return <String, Object?>{
      'video_id': record.videoId,
      'anime_id': record.animeId,
      'season_id': record.seasonId,
      'person_id': record.personId,
      'name': record.name,
      'role': record.role,
      'job': record.job,
      'credit_order': record.order,
    };
  }

  /// 将数据库行转换为演职员统计记录。
  static VideoCreditRecord videoCreditFromMap(Map<String, Object?> row) {
    return VideoCreditRecord(
      videoId: stringValue(row['video_id']),
      animeId: stringValue(row['anime_id']),
      seasonId: stringValue(row['season_id']),
      personId: stringValue(row['person_id']),
      name: stringValue(row['name']),
      role: stringValue(row['role']),
      job: stringValue(row['job']),
      order: intValue(row['credit_order']),
    );
  }

  /// 将番剧统计记录转换为数据库字段映射。
  static Map<String, Object?> animeStatsToMap(AnimeStatsRecord record) {
    return <String, Object?>{
      'anime_id': record.animeId,
      'title': record.title,
      'click_count': record.clickCount,
      'view_count': record.viewCount,
      'total_played_ms': record.totalPlayedMs,
      'forward_seek_count': record.forwardSeekCount,
      'backward_seek_count': record.backwardSeekCount,
      'watched_episode_count': record.watchedEpisodeCount,
      'completed_episode_count': record.completedEpisodeCount,
      'completed_season_count': record.completedSeasonCount,
      'last_played_at_ms': record.lastPlayedAtMs,
    };
  }

  /// 将数据库行转换为番剧统计记录。
  static AnimeStatsRecord animeStatsFromMap(Map<String, Object?> row) {
    return AnimeStatsRecord(
      animeId: stringValue(row['anime_id']),
      title: stringValue(row['title']),
      clickCount: intValue(row['click_count']),
      viewCount: intValue(row['view_count']),
      totalPlayedMs: intValue(row['total_played_ms']),
      forwardSeekCount: intValue(row['forward_seek_count']),
      backwardSeekCount: intValue(row['backward_seek_count']),
      watchedEpisodeCount: intValue(row['watched_episode_count']),
      completedEpisodeCount: intValue(row['completed_episode_count']),
      completedSeasonCount: intValue(row['completed_season_count']),
      lastPlayedAtMs: intValue(row['last_played_at_ms']),
    );
  }

  /// 将季度统计记录转换为数据库字段映射。
  static Map<String, Object?> seasonStatsToMap(SeasonStatsRecord record) {
    return <String, Object?>{
      'season_id': record.seasonId,
      'anime_id': record.animeId,
      'title': record.title,
      'total_episode_count': record.totalEpisodeCount,
      'watched_episode_count': record.watchedEpisodeCount,
      'completed_episode_count': record.completedEpisodeCount,
      'is_completed': boolToInt(record.isCompleted),
      'last_played_at_ms': record.lastPlayedAtMs,
    };
  }

  /// 将数据库行转换为季度统计记录。
  static SeasonStatsRecord seasonStatsFromMap(Map<String, Object?> row) {
    return SeasonStatsRecord(
      seasonId: stringValue(row['season_id']),
      animeId: stringValue(row['anime_id']),
      title: stringValue(row['title']),
      totalEpisodeCount: intValue(row['total_episode_count']),
      watchedEpisodeCount: intValue(row['watched_episode_count']),
      completedEpisodeCount: intValue(row['completed_episode_count']),
      isCompleted: intToBool(row['is_completed']),
      lastPlayedAtMs: intValue(row['last_played_at_ms']),
    );
  }

  /// 将播放历史记录转换为数据库字段映射。
  static Map<String, Object?> playHistoryToMap(PlayHistoryRecord record) {
    return <String, Object?>{
      'history_id': record.historyId,
      'video_id': record.videoId,
      'anime_id': record.animeId,
      'season_id': record.seasonId,
      'title': record.title,
      'anime_title': record.animeTitle,
      'season_title': record.seasonTitle,
      'video_kind': record.videoKind,
      'counts_toward_completion': boolToInt(record.countsTowardCompletion),
      'country_codes_json': stringListToJson(record.countryCodes),
      'genre_ids_json': intListToJson(record.genreIds),
      'credits_json': creditsToJson(record.credits),
      'start_source': startSourceToText(record.startSource),
      'started_at_ms': record.startedAtMs,
      'ended_at_ms': record.endedAtMs,
      'media_duration_ms': record.mediaDurationMs,
      'watched_ms': record.watchedMs,
      'max_progress': record.maxProgress,
      'max_position_ms': record.maxPositionMs,
      'counted_as_view': boolToInt(record.countedAsView),
      'counted_as_completed': boolToInt(record.countedAsCompleted),
      'op_detected': boolToInt(record.opDetected),
      'ed_detected': boolToInt(record.edDetected),
      'op_skipped': boolToInt(record.opSkipped),
      'ed_skipped': boolToInt(record.edSkipped),
      'op_not_skipped': boolToInt(record.opNotSkipped),
      'ed_not_skipped': boolToInt(record.edNotSkipped),
      'op_played_ms': record.opPlayedMs,
      'ed_played_ms': record.edPlayedMs,
      'forward_seek_count': record.forwardSeekCount,
      'backward_seek_count': record.backwardSeekCount,
    };
  }

  /// 将数据库行转换为播放历史记录。
  static PlayHistoryRecord playHistoryFromMap(Map<String, Object?> row) {
    return PlayHistoryRecord(
      historyId: stringValue(row['history_id']),
      videoId: stringValue(row['video_id']),
      animeId: stringValue(row['anime_id']),
      seasonId: stringValue(row['season_id']),
      title: stringValue(row['title']),
      animeTitle: stringValue(row['anime_title']),
      seasonTitle: stringValue(row['season_title']),
      videoKind: stringValue(row['video_kind']),
      countsTowardCompletion: intToBool(row['counts_toward_completion']),
      countryCodes: stringListFromJson(row['country_codes_json']),
      genreIds: intListFromJson(row['genre_ids_json']),
      credits: creditsFromJson(row['credits_json']),
      startSource: startSourceFromText(row['start_source']),
      startedAtMs: intValue(row['started_at_ms']),
      endedAtMs: intValue(row['ended_at_ms']),
      mediaDurationMs: intValue(row['media_duration_ms']),
      watchedMs: intValue(row['watched_ms']),
      maxProgress: doubleValue(row['max_progress']),
      maxPositionMs: intValue(row['max_position_ms']),
      countedAsView: intToBool(row['counted_as_view']),
      countedAsCompleted: intToBool(row['counted_as_completed']),
      opDetected: intToBool(row['op_detected']),
      edDetected: intToBool(row['ed_detected']),
      opSkipped: intToBool(row['op_skipped']),
      edSkipped: intToBool(row['ed_skipped']),
      opNotSkipped: intToBool(row['op_not_skipped']),
      edNotSkipped: intToBool(row['ed_not_skipped']),
      opPlayedMs: intValue(row['op_played_ms']),
      edPlayedMs: intValue(row['ed_played_ms']),
      forwardSeekCount: intValue(row['forward_seek_count']),
      backwardSeekCount: intValue(row['backward_seek_count']),
    );
  }

  static List<dynamic>? _decodeJsonList(Object? value) {
    final raw = stringValue(value).trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
