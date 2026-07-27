import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'play_stats_database.dart';
import 'play_stats_identity.dart';
import 'play_stats_mappers.dart';
import 'play_stats_metadata_gateway.dart';
import 'play_stats_models.dart';
import 'play_stats_repositories.dart';

/// 负责为统计记录补全番剧、季度与演职员元数据。
///
/// 元数据来源由调用方以 [PlayStatsBackfillGateway] 注入，本服务不直连任何后端 API。
class PlayStatsMetadataBackfillService {
  final PlayStatsDatabase _database;
  final VideoStatsRepository _videoStatsRepository;
  final VideoCreditStatsRepository _videoCreditStatsRepository;

  Timer? _scheduledTimer;
  final Set<String> _preferredVideoIds = <String>{};
  Future<void>? _activeRun;

  /// 根据数据库与仓储依赖构造回填服务。
  PlayStatsMetadataBackfillService({
    required PlayStatsDatabase database,
    required VideoStatsRepository videoStatsRepository,
    required VideoCreditStatsRepository videoCreditStatsRepository,
  }) : _database = database,
       _videoStatsRepository = videoStatsRepository,
       _videoCreditStatsRepository = videoCreditStatsRepository;

  /// 以延迟执行的方式安排一次元数据回填任务。
  void schedule({
    required PlayStatsBackfillGateway gateway,
    Iterable<String> preferredVideoIds = const <String>[],
    Duration delay = const Duration(seconds: 8),
    int limit = 8,
  }) {
    for (final videoId in preferredVideoIds) {
      final normalized = videoId.trim();
      if (normalized.isNotEmpty) {
        _preferredVideoIds.add(normalized);
      }
    }
    _scheduledTimer?.cancel();
    _scheduledTimer = Timer(
      delay,
      () => unawaited(
        backfillNow(
          gateway: gateway,
          preferredVideoIds: preferredVideoIds,
          limit: limit,
        ),
      ),
    );
  }

  /// 立即执行一次元数据回填任务。
  Future<void> backfillNow({
    required PlayStatsBackfillGateway gateway,
    Iterable<String> preferredVideoIds = const <String>[],
    int limit = 8,
  }) {
    for (final videoId in preferredVideoIds) {
      final normalized = videoId.trim();
      if (normalized.isNotEmpty) {
        _preferredVideoIds.add(normalized);
      }
    }
    final active = _activeRun;
    if (active != null) {
      return active;
    }
    final future = _run(gateway: gateway, limit: limit);
    _activeRun = future.whenComplete(() {
      if (identical(_activeRun, future)) {
        _activeRun = null;
      }
    });
    return _activeRun!;
  }

  Future<void> _run({
    required PlayStatsBackfillGateway gateway,
    required int limit,
  }) async {
    _scheduledTimer?.cancel();
    final processed = <String>{};
    // 本轮是否真的改写过 video_stats/play_history，决定收尾要不要重建聚合表。
    var aggregatesDirty = false;
    try {
      while (true) {
        final candidateIds = <String>[];
        while (_preferredVideoIds.isNotEmpty && candidateIds.length < limit) {
          final videoId = _preferredVideoIds.first;
          _preferredVideoIds.remove(videoId);
          if (videoId.isEmpty || processed.contains(videoId)) {
            continue;
          }
          candidateIds.add(videoId);
          processed.add(videoId);
        }
        if (candidateIds.length < limit) {
          final more = await _videoStatsRepository
              .listMetadataBackfillCandidateIds(limit: limit);
          for (final videoId in more) {
            if (candidateIds.length >= limit) {
              break;
            }
            if (videoId.isEmpty || processed.contains(videoId)) {
              continue;
            }
            candidateIds.add(videoId);
            processed.add(videoId);
          }
        }
        if (candidateIds.isEmpty) {
          return;
        }
        for (final videoId in candidateIds) {
          final mutated = await _backfillSingleVideo(
            gateway: gateway,
            videoId: videoId,
          );
          aggregatesDirty = aggregatesDirty || mutated;
        }
      }
    } finally {
      // 聚合表是"全表删除后按 video_stats/play_history 重建"，逐视频重建纯属重复劳动；
      // 整轮回填结束（含中途抛错退出）后统一重建一次即可，期间没有其它读取方依赖它。
      if (aggregatesDirty) {
        await _database.transaction<void>(_rebuildAggregateTables);
      }
    }
  }

  /// 回填单个视频的元数据；返回是否真的写入过数据库。
  Future<bool> _backfillSingleVideo({
    required PlayStatsBackfillGateway gateway,
    required String videoId,
  }) async {
    final normalizedVideoId = videoId.trim();
    if (normalizedVideoId.isEmpty) {
      return false;
    }
    final existing = await _videoStatsRepository.getByVideoId(
      normalizedVideoId,
    );
    if (existing == null) {
      return false;
    }

    Map<String, dynamic>? itemDetail;
    try {
      itemDetail = await gateway.fetchItemDetail(normalizedVideoId);
    } catch (_) {
      return false;
    }
    final isMovie = _isMovieType(_stringValue(itemDetail['type']));
    final ancestorGuid = _stringValue(itemDetail['ancestor_guid']);
    final seasonGuid = _firstNonEmpty(
      _stringValue(itemDetail['parent_guid']),
      existing.seasonId,
    );
    Map<String, dynamic>? seasonDetail;
    if (!isMovie && seasonGuid.isNotEmpty) {
      try {
        seasonDetail = await gateway.fetchItemDetail(seasonGuid);
      } catch (_) {}
    }

    Map<String, dynamic>? animeDetail;
    final currentAnimeId = existing.animeId.trim();
    final seasonParentGuid = _stringValue(seasonDetail?['parent_guid']);
    final taxonomyDetail = _resolveTaxonomyDetail(
      isMovie: isMovie,
      itemDetail: itemDetail,
      seasonDetail: seasonDetail,
      animeDetail: null,
    );
    final realAnimeGuid = _firstUsableRealAnimeGuid(
      <String>[seasonParentGuid, currentAnimeId],
      videoId: normalizedVideoId,
      seasonId: seasonGuid,
      ancestorGuid: ancestorGuid,
    );
    final shouldLoadAnimeDetail =
        realAnimeGuid.isNotEmpty &&
        (_intListValue(taxonomyDetail?['genres']).isEmpty ||
            _stringListValue(taxonomyDetail?['production_countries']).isEmpty ||
            _stringValue(itemDetail['tv_title']).isEmpty ||
            existing.genreIds.isEmpty ||
            existing.countryCodes.isEmpty ||
            existing.year <= 0);
    if (shouldLoadAnimeDetail) {
      try {
        animeDetail = await gateway.fetchItemDetail(realAnimeGuid);
      } catch (_) {}
    }
    if (existing.metadataEnriched &&
        !_needsIdentityRepair(
          existing: existing,
          itemDetail: itemDetail,
          seasonDetail: seasonDetail,
          ancestorGuid: ancestorGuid,
        ) &&
        !_needsTaxonomyRepair(
          existing: existing,
          taxonomyDetail: _resolveTaxonomyDetail(
            isMovie: isMovie,
            itemDetail: itemDetail,
            seasonDetail: seasonDetail,
            animeDetail: animeDetail,
          ),
        )) {
      return false;
    }
    final resolvedTaxonomyDetail = _resolveTaxonomyDetail(
      isMovie: isMovie,
      itemDetail: itemDetail,
      seasonDetail: seasonDetail,
      animeDetail: animeDetail,
    );

    final creditsResult = await _loadCredits(
      gateway: gateway,
      videoId: normalizedVideoId,
      seasonId: seasonGuid,
      allowSeasonFallback: !isMovie,
    );
    final creditsResolved = creditsResult.resolved;
    final credits = creditsResult.credits;

    final effectiveTitle = _firstNonEmpty(
      _stringValue(itemDetail['title']),
      existing.title,
    );
    final animeIdentity = PlayStatsIdentityResolver.resolveAnimeIdentity(
      seriesGuid: realAnimeGuid,
      trimId: _stringValue(itemDetail['trim_id']),
      tvTitle: _stringValue(itemDetail['tv_title']),
      seriesTitle: existing.animeTitle,
      fallbackTitle: effectiveTitle,
    );
    final effectiveAnimeId = animeIdentity.animeId;
    final effectiveSeasonId = seasonGuid;
    final effectiveAnimeTitle = _firstNonEmpty(
      _stringValue(animeDetail?['tv_title']),
      _stringValue(animeDetail?['title']),
      animeIdentity.animeTitle,
      existing.animeTitle,
    );
    final effectiveSeasonTitle = _firstNonEmpty(
      _stringValue(itemDetail['parent_title']),
      _stringValue(seasonDetail?['title']),
      existing.seasonTitle,
    );
    final effectiveVideoKind = _firstNonEmpty(
      _stringValue(itemDetail['type']),
      existing.videoKind,
    );
    final effectiveGenreIds = _pickIntList(
      _intListValue(resolvedTaxonomyDetail?['genres']),
      _intListValue(itemDetail['genres']),
      existing.genreIds,
    );
    final effectiveCountryCodes = _pickStringList(
      _stringListValue(resolvedTaxonomyDetail?['production_countries']),
      _stringListValue(itemDetail['production_countries']),
      existing.countryCodes,
    );
    final effectiveCountry = effectiveCountryCodes.isNotEmpty
        ? effectiveCountryCodes.first
        : existing.country;
    final effectiveYear = _pickPositiveInt(
      _yearFromDetail(resolvedTaxonomyDetail),
      _yearFromDetail(itemDetail),
      existing.year,
    );
    final effectiveCredits = creditsResolved ? credits : existing.credits;

    await _database.transaction<void>((txn) async {
      await txn.update(
        'video_stats',
        <String, Object?>{
          'anime_id': effectiveAnimeId,
          'season_id': effectiveSeasonId,
          'title': effectiveTitle,
          'anime_title': effectiveAnimeTitle,
          'season_title': effectiveSeasonTitle,
          'video_kind': effectiveVideoKind,
          'country': effectiveCountry,
          'country_codes_json': PlayStatsSqlMapper.stringListToJson(
            effectiveCountryCodes,
          ),
          'genre_ids_json': PlayStatsSqlMapper.intListToJson(effectiveGenreIds),
          'year': effectiveYear,
          'credits_json': PlayStatsSqlMapper.creditsToJson(effectiveCredits),
          'metadata_enriched': PlayStatsSqlMapper.boolToInt(creditsResolved),
        },
        where: 'video_id = ?',
        whereArgs: <Object?>[normalizedVideoId],
      );
      await txn.update(
        'play_history',
        <String, Object?>{
          'anime_id': effectiveAnimeId,
          'season_id': effectiveSeasonId,
          'title': effectiveTitle,
          'anime_title': effectiveAnimeTitle,
          'season_title': effectiveSeasonTitle,
          'video_kind': effectiveVideoKind,
          'country_codes_json': PlayStatsSqlMapper.stringListToJson(
            effectiveCountryCodes,
          ),
          'genre_ids_json': PlayStatsSqlMapper.intListToJson(effectiveGenreIds),
          'credits_json': PlayStatsSqlMapper.creditsToJson(effectiveCredits),
        },
        where: 'video_id = ?',
        whereArgs: <Object?>[normalizedVideoId],
      );
      if (creditsResolved) {
        await _videoCreditStatsRepository.replaceForVideo(
          normalizedVideoId,
          credits
              .where((credit) => credit.personId.trim().isNotEmpty)
              .map(
                (credit) => VideoCreditRecord(
                  videoId: normalizedVideoId,
                  animeId: effectiveAnimeId,
                  seasonId: effectiveSeasonId,
                  personId: credit.personId,
                  name: credit.name,
                  role: credit.role,
                  job: credit.job,
                  order: credit.order,
                ),
              )
              .toList(growable: false),
          executor: txn,
        );
      }
    });
    return true;
  }

  Future<void> _rebuildAggregateTables(DatabaseExecutor txn) async {
    await txn.delete('season_stats');
    final seasonRows = await txn.rawQuery('''
SELECT
  season_id,
  MAX(anime_id) AS anime_id,
  MAX(season_title) AS title,
  SUM(CASE WHEN counts_toward_completion = 1 THEN 1 ELSE 0 END) AS total_episode_count,
  SUM(CASE WHEN counts_toward_completion = 1 AND view_count > 0 THEN 1 ELSE 0 END) AS watched_episode_count,
  SUM(CASE WHEN counts_toward_completion = 1 AND completed = 1 THEN 1 ELSE 0 END) AS completed_episode_count,
  MAX(last_played_at_ms) AS last_played_at_ms
FROM video_stats
WHERE TRIM(season_id) <> ''
GROUP BY season_id
''');
    for (final row in seasonRows) {
      final totalEpisodeCount = PlayStatsSqlMapper.intValue(
        row['total_episode_count'],
      );
      final completedEpisodeCount = PlayStatsSqlMapper.intValue(
        row['completed_episode_count'],
      );
      await txn.insert(
        'season_stats',
        PlayStatsSqlMapper.seasonStatsToMap(
          SeasonStatsRecord(
            seasonId: _stringValue(row['season_id']),
            animeId: _stringValue(row['anime_id']),
            title: _stringValue(row['title']),
            totalEpisodeCount: totalEpisodeCount,
            watchedEpisodeCount: PlayStatsSqlMapper.intValue(
              row['watched_episode_count'],
            ),
            completedEpisodeCount: completedEpisodeCount,
            isCompleted:
                totalEpisodeCount > 0 &&
                completedEpisodeCount >= totalEpisodeCount,
            lastPlayedAtMs: PlayStatsSqlMapper.intValue(
              row['last_played_at_ms'],
            ),
          ),
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await txn.delete('anime_stats');
    final videoAggRows = await txn.rawQuery('''
SELECT
  anime_id,
  MAX(anime_title) AS title,
  SUM(CASE WHEN counts_toward_completion = 1 AND view_count > 0 THEN 1 ELSE 0 END) AS watched_episode_count,
  SUM(CASE WHEN counts_toward_completion = 1 AND completed = 1 THEN 1 ELSE 0 END) AS completed_episode_count
FROM video_stats
WHERE TRIM(anime_id) <> ''
GROUP BY anime_id
''');
    final videoAggByAnimeId = <String, Map<String, Object?>>{};
    for (final row in videoAggRows) {
      final animeId = _stringValue(row['anime_id']);
      if (animeId.isNotEmpty) {
        videoAggByAnimeId[animeId] = row;
      }
    }
    final seasonAggRows = await txn.rawQuery('''
SELECT anime_id, SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) AS completed_season_count
FROM season_stats
WHERE TRIM(anime_id) <> ''
GROUP BY anime_id
''');
    final completedSeasonCountByAnimeId = <String, int>{};
    for (final row in seasonAggRows) {
      final animeId = _stringValue(row['anime_id']);
      if (animeId.isNotEmpty) {
        completedSeasonCountByAnimeId[animeId] = PlayStatsSqlMapper.intValue(
          row['completed_season_count'],
        );
      }
    }
    final historyAggRows = await txn.rawQuery('''
SELECT
  anime_id,
  MAX(anime_title) AS title,
  SUM(CASE WHEN start_source IN ('manual', 'manual_switch') THEN 1 ELSE 0 END) AS click_count,
  SUM(CASE WHEN counted_as_view = 1 THEN 1 ELSE 0 END) AS view_count,
  SUM(watched_ms) AS total_played_ms,
  SUM(forward_seek_count) AS forward_seek_count,
  SUM(backward_seek_count) AS backward_seek_count,
  MAX(ended_at_ms) AS last_played_at_ms
FROM play_history
WHERE TRIM(anime_id) <> ''
GROUP BY anime_id
''');
    final animeIds = <String>{
      ...videoAggByAnimeId.keys,
      ...completedSeasonCountByAnimeId.keys,
      ...historyAggRows
          .map((row) => _stringValue(row['anime_id']))
          .where((value) => value.isNotEmpty),
    };
    for (final animeId in animeIds) {
      final videoAgg = videoAggByAnimeId[animeId];
      final historyAgg = historyAggRows.cast<Map<String, Object?>>().firstWhere(
        (row) => _stringValue(row['anime_id']) == animeId,
        orElse: () => const <String, Object?>{},
      );
      await txn.insert(
        'anime_stats',
        PlayStatsSqlMapper.animeStatsToMap(
          AnimeStatsRecord(
            animeId: animeId,
            title: _firstNonEmpty(
              _stringValue(videoAgg?['title']),
              _stringValue(historyAgg['title']),
              animeId,
            ),
            clickCount: PlayStatsSqlMapper.intValue(historyAgg['click_count']),
            viewCount: PlayStatsSqlMapper.intValue(historyAgg['view_count']),
            totalPlayedMs: PlayStatsSqlMapper.intValue(
              historyAgg['total_played_ms'],
            ),
            forwardSeekCount: PlayStatsSqlMapper.intValue(
              historyAgg['forward_seek_count'],
            ),
            backwardSeekCount: PlayStatsSqlMapper.intValue(
              historyAgg['backward_seek_count'],
            ),
            watchedEpisodeCount: PlayStatsSqlMapper.intValue(
              videoAgg?['watched_episode_count'],
            ),
            completedEpisodeCount: PlayStatsSqlMapper.intValue(
              videoAgg?['completed_episode_count'],
            ),
            completedSeasonCount: completedSeasonCountByAnimeId[animeId] ?? 0,
            lastPlayedAtMs: PlayStatsSqlMapper.intValue(
              historyAgg['last_played_at_ms'],
            ),
          ),
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<_CreditsLoadResult> _loadCredits({
    required PlayStatsBackfillGateway gateway,
    required String videoId,
    required String seasonId,
    required bool allowSeasonFallback,
  }) async {
    final normalizedVideoId = videoId.trim();
    final normalizedSeasonId = seasonId.trim();
    var resolved = false;

    try {
      final credits = await gateway.fetchCredits(normalizedVideoId);
      resolved = true;
      if (credits.isNotEmpty) {
        return _CreditsLoadResult(resolved: true, credits: credits);
      }
    } catch (_) {}

    if (allowSeasonFallback &&
        normalizedSeasonId.isNotEmpty &&
        normalizedSeasonId != normalizedVideoId) {
      try {
        final credits = await gateway.fetchCredits(normalizedSeasonId);
        return _CreditsLoadResult(resolved: true, credits: credits);
      } catch (_) {}
    }

    return _CreditsLoadResult(
      resolved: resolved,
      credits: const <PlayStatsCredit>[],
    );
  }

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  bool _needsIdentityRepair({
    required VideoStatsRecord existing,
    required Map<String, dynamic> itemDetail,
    required Map<String, dynamic>? seasonDetail,
    required String ancestorGuid,
  }) {
    final existingAnimeId = existing.animeId.trim();
    final existingAnimeTitle = existing.animeTitle.trim();
    final tvTitle = _stringValue(itemDetail['tv_title']);
    final ancestorName = _stringValue(itemDetail['ancestor_name']);
    final seasonParentGuid = _stringValue(seasonDetail?['parent_guid']);
    if (existingAnimeId.isEmpty || existingAnimeTitle.isEmpty) {
      return true;
    }
    if (PlayStatsIdentityResolver.isDerivedAnimeId(existingAnimeId)) {
      return true;
    }
    if (seasonParentGuid.isNotEmpty && existingAnimeId != seasonParentGuid) {
      return true;
    }
    if (ancestorGuid.isNotEmpty && existingAnimeId == ancestorGuid) {
      return true;
    }
    if (ancestorName.isNotEmpty && existingAnimeTitle == ancestorName) {
      return true;
    }
    if (tvTitle.isNotEmpty && existingAnimeTitle != tvTitle) {
      return true;
    }
    return false;
  }

  String _firstUsableRealAnimeGuid(
    Iterable<String> candidates, {
    required String videoId,
    required String seasonId,
    required String ancestorGuid,
  }) {
    for (final candidate in candidates) {
      if (_isUsableRealAnimeGuidCandidate(
        candidate,
        videoId: videoId,
        seasonId: seasonId,
        ancestorGuid: ancestorGuid,
      )) {
        return candidate.trim();
      }
    }
    return '';
  }

  bool _isUsableRealAnimeGuidCandidate(
    String value, {
    required String videoId,
    required String seasonId,
    required String ancestorGuid,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (PlayStatsIdentityResolver.isDerivedAnimeId(normalized)) {
      return false;
    }
    if (normalized == videoId || normalized == seasonId) {
      return false;
    }
    if (ancestorGuid.isNotEmpty && normalized == ancestorGuid) {
      return false;
    }
    return true;
  }

  String _firstNonEmpty(
    String first, [
    String second = '',
    String third = '',
    String fourth = '',
  ]) {
    for (final value in <String>[first, second, third, fourth]) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  List<int> _intListValue(Object? value) {
    if (value is List) {
      return value
          .map((entry) => int.tryParse('$entry') ?? 0)
          .where((entry) => entry > 0)
          .toSet()
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return _intListValue(decoded);
      } catch (_) {
        return const <int>[];
      }
    }
    return const <int>[];
  }

  List<String> _stringListValue(Object? value) {
    if (value is List) {
      return value
          .map((entry) => '$entry'.trim().toUpperCase())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return _stringListValue(decoded);
      } catch (_) {
        return const <String>[];
      }
    }
    return const <String>[];
  }

  List<int> _pickIntList(
    List<int> first,
    List<int> second,
    List<int> fallback,
  ) {
    if (first.isNotEmpty) return first;
    if (second.isNotEmpty) return second;
    return fallback;
  }

  List<String> _pickStringList(
    List<String> first,
    List<String> second,
    List<String> fallback,
  ) {
    if (first.isNotEmpty) return first;
    if (second.isNotEmpty) return second;
    return fallback;
  }

  int _pickPositiveInt(int first, int second, int fallback) {
    if (first > 0) return first;
    if (second > 0) return second;
    return fallback;
  }

  Map<String, dynamic>? _resolveTaxonomyDetail({
    required bool isMovie,
    required Map<String, dynamic>? itemDetail,
    required Map<String, dynamic>? seasonDetail,
    required Map<String, dynamic>? animeDetail,
  }) {
    if (isMovie) {
      return itemDetail;
    }
    return animeDetail ?? seasonDetail ?? itemDetail;
  }

  bool _needsTaxonomyRepair({
    required VideoStatsRecord existing,
    required Map<String, dynamic>? taxonomyDetail,
  }) {
    if (taxonomyDetail == null) {
      return false;
    }
    final targetGenreIds = _intListValue(taxonomyDetail['genres']);
    final targetCountryCodes = _stringListValue(
      taxonomyDetail['production_countries'],
    );
    final targetYear = _yearFromDetail(taxonomyDetail);
    if (targetGenreIds.isNotEmpty &&
        !_listEqualsInt(existing.genreIds, targetGenreIds)) {
      return true;
    }
    if (targetCountryCodes.isNotEmpty &&
        !_listEqualsString(existing.countryCodes, targetCountryCodes)) {
      return true;
    }
    if (targetYear > 0 && existing.year != targetYear) {
      return true;
    }
    return false;
  }

  bool _isMovieType(String value) => value.trim().toLowerCase() == 'movie';

  int _yearFromDetail(Map<String, dynamic>? detail) {
    if (detail == null) {
      return 0;
    }
    final rawValue = _firstNonEmpty(
      _stringValue(detail['release_date']),
      _stringValue(detail['air_date']),
    );
    final match = RegExp(r'(\d{4})').firstMatch(rawValue);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  bool _listEqualsInt(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _listEqualsString(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _CreditsLoadResult {
  final bool resolved;
  final List<PlayStatsCredit> credits;

  const _CreditsLoadResult({required this.resolved, required this.credits});
}
