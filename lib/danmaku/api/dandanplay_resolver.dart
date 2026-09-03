import '../cache/dandanplay_comment_cache_store.dart';
import '../models/dandanplay_episode_search_item.dart';
import '../models/danmaku_import_result.dart';
import '../parser/danmaku_import_parser.dart';
import 'dandanplay_api.dart';

/// 播放场景下的弹弹 Play 匹配结果。
class DanDanPlayPlaybackResolveResult {
  /// 匹配到的弹弹 Play 剧集条目。
  final DanDanPlayEpisodeSearchItem item;

  /// 已经解析完成的弹幕导入结果。
  final DanmakuImportResult result;

  const DanDanPlayPlaybackResolveResult({
    required this.item,
    required this.result,
  });
}

/// 弹弹 Play 搜索、缓存和导入编排入口。
class DanDanPlayResolver {
  final DanDanPlayApi _api;
  final DanDanPlayCommentCacheStore _cacheStore;

  static final Map<int, Future<DanmakuImportResult?>> _inFlightImports =
      <int, Future<DanmakuImportResult?>>{};

  const DanDanPlayResolver(
    this._api, {
    DanDanPlayCommentCacheStore cacheStore =
        const DanDanPlayCommentCacheStore(),
  }) : _cacheStore = cacheStore;

  /// 按当前播放上下文直接解析可用的弹幕结果。
  ///
  /// 成功时会返回匹配到的剧集以及已经解析完成的弹幕导入结果。
  Future<DanDanPlayPlaybackResolveResult?> resolveForPlayback({
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
    required String tmdbId,
    String itemTitle = '',
  }) async {
    var results = await searchEpisodeCandidates(
      keyword: seriesTitle,
      episodeNumber: episodeNumber,
      tmdbId: tmdbId,
      allowLooseTitleFallback: true,
    );
    if (results.isEmpty && episodeNumber > 0) {
      results = await searchEpisodeCandidates(
        keyword: seriesTitle,
        episodeNumber: 0,
        tmdbId: tmdbId,
        allowLooseTitleFallback: true,
      );
    }
    if (results.isEmpty) return null;
    final item = _pickPlaybackCandidate(
      results,
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      itemTitle: itemTitle,
      episodeNumber: episodeNumber,
    );
    if (item == null) return null;
    final result = await importEpisodeById(item);
    if (result == null) return null;
    return DanDanPlayPlaybackResolveResult(item: item, result: result);
  }

  /// 搜索当前剧集可能对应的弹弹 Play 候选项。
  ///
  /// 会优先走精确关键字 + TMDB 约束，必要时再逐步放宽条件。
  Future<List<DanDanPlayEpisodeSearchItem>> searchEpisodeCandidates({
    required String keyword,
    required int episodeNumber,
    required String tmdbId,
    bool allowLooseTitleFallback = false,
  }) async {
    if (!_api.ready) return const <DanDanPlayEpisodeSearchItem>[];
    final rawKeyword = keyword.trim();
    final normalizedKeyword = _normalizeSeriesTitle(rawKeyword);
    final tmdbNumericId = _normalizeTmdbId(tmdbId);
    if (rawKeyword.isEmpty && tmdbNumericId == null) {
      return const <DanDanPlayEpisodeSearchItem>[];
    }

    final filteredEpisodeNumber = episodeNumber > 0 ? episodeNumber : null;
    final keywords = <String>{
      if (rawKeyword.isNotEmpty) rawKeyword,
      if (normalizedKeyword.isNotEmpty) normalizedKeyword,
    };
    for (final searchKeyword in keywords) {
      final exactResults = await _searchEpisodeCandidatesOnce(
        keyword: searchKeyword,
        episodeNumber: filteredEpisodeNumber,
        tmdbId: tmdbNumericId,
      );
      if (exactResults.isNotEmpty) {
        return exactResults;
      }
    }

    if (tmdbNumericId != null) {
      for (final searchKeyword in keywords) {
        final fallbackWithoutTmdb = await _searchEpisodeCandidatesOnce(
          keyword: searchKeyword,
          episodeNumber: filteredEpisodeNumber,
        );
        if (fallbackWithoutTmdb.isNotEmpty) {
          return fallbackWithoutTmdb;
        }
      }
    }

    if (!allowLooseTitleFallback || normalizedKeyword.isEmpty) {
      return const <DanDanPlayEpisodeSearchItem>[];
    }

    for (final fallbackKeyword in _buildLooseTitleFallbackKeywords(
      normalizedKeyword,
    )) {
      final fallbackResults = await _searchEpisodeCandidatesOnce(
        keyword: fallbackKeyword,
        episodeNumber: filteredEpisodeNumber,
      );
      if (fallbackResults.isNotEmpty) {
        return fallbackResults;
      }
    }
    return const <DanDanPlayEpisodeSearchItem>[];
  }

  /// 按剧集 id 导入弹幕，优先命中本地缓存并对并发请求做去重。
  Future<DanmakuImportResult?> importEpisodeById(
    DanDanPlayEpisodeSearchItem item,
  ) async {
    if (item.episodeId <= 0) return null;
    final cached = await _loadCachedResult(item);
    if (cached != null) {
      return cached;
    }
    if (!_api.ready) return null;
    final inFlight = _inFlightImports[item.episodeId];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _fetchAndCacheEpisode(item);
    _inFlightImports[item.episodeId] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightImports[item.episodeId], future)) {
        _inFlightImports.remove(item.episodeId);
      }
    }
  }

  Future<DanmakuImportResult?> _loadCachedResult(
    DanDanPlayEpisodeSearchItem item,
  ) async {
    String? content;
    try {
      content = await _cacheStore.loadComments(item.episodeId);
    } catch (_) {
      // 评论缓存只是加速项。Windows 未启用 sqflite 时直接回源，不能阻断弹幕加载。
      content = null;
    }
    if (content == null || content.isEmpty) return null;
    try {
      return DanmakuImportParser.parseContentString(
        content,
        sourceLabel: 'DanDanPlay · ${item.displaySubtitle}',
      );
    } catch (_) {
      await _cacheStore.removeComments(item.episodeId);
      return null;
    }
  }

  Future<DanmakuImportResult?> _fetchAndCacheEpisode(
    DanDanPlayEpisodeSearchItem item,
  ) async {
    final commentsResponse = await _api.fetchComments(item.episodeId);
    final content = commentsResponse.data?.trim() ?? '';
    if (content.isEmpty) return null;
    final result = DanmakuImportParser.parseContentString(
      content,
      sourceLabel: 'DanDanPlay · ${item.displaySubtitle}',
    );
    try {
      await _cacheStore.saveComments(
        episodeId: item.episodeId,
        content: content,
      );
    } catch (_) {
      // 回源结果已可播放，缓存写入失败不应把本次加载改成失败。
    }
    return result;
  }

  /// 对外暴露的标题归一化规则，便于调用方复用相同搜索口径。
  static String normalizeSeriesTitle(String value) =>
      _normalizeSeriesTitle(value);

  /// 把 `tm12345` 或纯数字字符串统一转成可搜索的 TMDB 数字 id。
  static int? normalizeTmdbId(String value) => _normalizeTmdbId(value);

  Future<List<DanDanPlayEpisodeSearchItem>> _searchEpisodeCandidatesOnce({
    required String keyword,
    required int? episodeNumber,
    int? tmdbId,
  }) async {
    final searchResponse = await _api.searchEpisodes(
      anime: keyword,
      episode: episodeNumber,
      tmdbId: tmdbId,
    );
    final payload = searchResponse.data ?? const <String, dynamic>{};
    final items = (payload['animes'] is List)
        ? payload['animes'] as List<dynamic>
        : ((payload['episodes'] is List)
              ? payload['episodes'] as List<dynamic>
              : const <dynamic>[]);
    return _collectEpisodeItems(items);
  }

  static String _normalizeSeriesTitle(String value) {
    var title = value.trim();
    if (title.isEmpty) return '';
    title = title.replaceAll(RegExp(r'第\s*[零〇一二三四五六七八九十百\d]+\s*[季期]'), '');
    title = title.replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '');
    title = title.replaceAll(
      RegExp(r'(?:^|[\s._-])S\s*0*\d{1,2}\s*$', caseSensitive: false),
      '',
    );
    return title.trim();
  }

  /// 手动搜索不丢弃其他季度，只把当前季度放到前面，方便用户核对并纠正自动结果。
  static List<DanDanPlayEpisodeSearchItem> sortCandidatesForSeason(
    List<DanDanPlayEpisodeSearchItem> items, {
    required int seasonNumber,
  }) {
    if (seasonNumber <= 0 || items.length < 2) {
      return List<DanDanPlayEpisodeSearchItem>.of(items);
    }
    final matched = <DanDanPlayEpisodeSearchItem>[];
    final remaining = <DanDanPlayEpisodeSearchItem>[];
    for (final item in items) {
      final isRequestedSeason = candidateMatchesSeason(
        item,
        seasonNumber: seasonNumber,
      );
      (isRequestedSeason ? matched : remaining).add(item);
    }
    return <DanDanPlayEpisodeSearchItem>[...matched, ...remaining];
  }

  /// 当前媒体缺少季度信息时不猜测；有季度信息时兼容未标季名的第一季。
  static bool candidateMatchesSeason(
    DanDanPlayEpisodeSearchItem item, {
    required int seasonNumber,
  }) {
    if (seasonNumber <= 0) return false;
    final candidateSeason = _extractSeasonNumber(item.animeTitle);
    return candidateSeason == seasonNumber ||
        (seasonNumber == 1 && candidateSeason == 0);
  }

  static int? _normalizeTmdbId(String trimId) {
    final raw = trimId.trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      return int.tryParse(raw);
    }
    if (raw.length < 3) return null;
    final prefix = raw.substring(0, 2).toLowerCase();
    if (prefix != 'tm') return null;
    return int.tryParse(raw.substring(2).trim());
  }

  static List<String> _buildLooseTitleFallbackKeywords(String title) {
    final segments = title
        .split(RegExp(r'''[\s\-_:：,，、/\\()（）【】《》“”"'!！?？]+'''))
        .expand((item) => item.split(RegExp(r'[与和及之的]')))
        .map((item) => item.trim())
        .where((item) => item.length >= 2 && item != title)
        .toSet()
        .toList(growable: false);
    if (segments.isNotEmpty) {
      return segments;
    }

    final compact = title.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) {
      return const <String>[];
    }
    return <String>{
      compact.substring(compact.length - 4),
      compact.substring(compact.length - 3),
      compact.substring(compact.length - 2),
    }.toList(growable: false);
  }

  static DanDanPlayEpisodeSearchItem? _pickPlaybackCandidate(
    List<DanDanPlayEpisodeSearchItem> items, {
    required String seriesTitle,
    required int seasonNumber,
    required String itemTitle,
    required int episodeNumber,
  }) {
    if (items.isEmpty) return null;
    var candidates = items;
    var seasonResolved = seasonNumber <= 0;
    if (seasonNumber > 0) {
      final sameSeason = items
          .where(
            (item) => _extractSeasonNumber(item.animeTitle) == seasonNumber,
          )
          .toList(growable: false);
      if (sameSeason.isNotEmpty) {
        candidates = sameSeason;
        seasonResolved = true;
      } else if (seasonNumber == 1) {
        final normalizedSeries = _normalizeSeriesTitle(seriesTitle);
        final unmarkedFirstSeason = items
            .where(
              (item) =>
                  _extractSeasonNumber(item.animeTitle) == 0 &&
                  _normalizeSeriesTitle(item.animeTitle) == normalizedSeries,
            )
            .toList(growable: false);
        if (unmarkedFirstSeason.isNotEmpty) {
          candidates = unmarkedFirstSeason;
          seasonResolved = true;
        }
      }
    }
    // DandanPlay 没有 season 查询参数；无法从作品名确认当前季时，继续按单集标题匹配
    // 可能把 S2E1 选成 S1E1。宁可交给手动候选，也不自动套用错误季度。
    if (!seasonResolved) return null;
    final normalizedTitle = _normalizeComparableEpisodeTitle(itemTitle);
    if (normalizedTitle.isNotEmpty) {
      final exactTitleMatches = candidates
          .where(
            (item) =>
                _normalizeComparableEpisodeTitle(item.episodeTitle) ==
                normalizedTitle,
          )
          .toList(growable: false);
      if (exactTitleMatches.length == 1) {
        return exactTitleMatches.first;
      }
      if (exactTitleMatches.isNotEmpty) {
        candidates = exactTitleMatches;
      } else {
        final partialTitleMatches = candidates
            .where((item) {
              final candidate = _normalizeComparableEpisodeTitle(
                item.episodeTitle,
              );
              return candidate.isNotEmpty &&
                  (candidate.contains(normalizedTitle) ||
                      normalizedTitle.contains(candidate));
            })
            .toList(growable: false);
        if (partialTitleMatches.length == 1) {
          return partialTitleMatches.first;
        }
        if (partialTitleMatches.isNotEmpty) {
          candidates = partialTitleMatches;
        }
      }
    }
    if (episodeNumber > 0) {
      final episodeMatches = candidates
          .where(
            (item) =>
                item.episodeNumber == episodeNumber ||
                _extractEpisodeNumber(item.episodeTitle) == episodeNumber,
          )
          .toList(growable: false);
      if (episodeMatches.length == 1) {
        return episodeMatches.first;
      }
      if (episodeMatches.isNotEmpty) {
        candidates = episodeMatches;
      }
    }
    if (candidates.length == 1) return candidates.first;
    return null;
  }

  static String _normalizeComparableEpisodeTitle(String value) {
    var title = value.trim().toLowerCase();
    if (title.isEmpty) return '';
    title = title.replaceFirst(
      RegExp(
        r'^(?:\u7b2c\s*\d+\s*[\u8bdd\u8a71\u96c6]|(?:ep|e|episode)\s*\d+)',
        caseSensitive: false,
      ),
      '',
    );
    title = title.replaceAll(RegExp(r'[\s\-_:.,!?()\[\]{}]+'), '');
    title = title.replaceAll(RegExp(r'[，。！？（）【】《》「」『』·・]+'), '');
    return title.trim();
  }

  static DanDanPlayEpisodeSearchItem? pickPlaybackCandidateForTest(
    List<DanDanPlayEpisodeSearchItem> items, {
    String seriesTitle = '',
    int seasonNumber = 0,
    required String itemTitle,
    required int episodeNumber,
  }) {
    return _pickPlaybackCandidate(
      items,
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      itemTitle: itemTitle,
      episodeNumber: episodeNumber,
    );
  }

  static int _extractSeasonNumber(String value) {
    final title = value.trim();
    if (title.isEmpty) return 0;
    for (final pattern in <RegExp>[
      RegExp(r'第\s*0*(\d{1,2})\s*[季期]'),
      RegExp(r'Season\s*0*(\d{1,2})', caseSensitive: false),
      RegExp(r'(?:^|[\s._-])S0*(\d{1,2})(?:$|[\s._-])', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(title);
      if (match != null) return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    final chinese = RegExp(r'第\s*([一二三四五六七八九十]{1,3})\s*[季期]').firstMatch(title);
    return _parseChineseNumber(chinese?.group(1) ?? '');
  }

  static int _parseChineseNumber(String value) {
    if (value.isEmpty) return 0;
    const digits = <String, int>{
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!value.contains('十')) return digits[value] ?? 0;
    final parts = value.split('十');
    final tens = parts.first.isEmpty ? 1 : (digits[parts.first] ?? 0);
    final ones = parts.length < 2 || parts[1].isEmpty
        ? 0
        : (digits[parts[1]] ?? 0);
    return (tens * 10) + ones;
  }

  static int _extractEpisodeNumber(String value) {
    if (value.trim().isEmpty) return 0;
    final zh = RegExp(
      r'\u7b2c\s*0*(\d{1,4})\s*[\u8bdd\u8a71\u96c6]',
    ).firstMatch(value);
    if (zh != null) return int.tryParse(zh.group(1) ?? '') ?? 0;
    final en = RegExp(
      r'(?:EP|E|Episode)\s*0*(\d{1,4})',
      caseSensitive: false,
    ).firstMatch(value);
    if (en != null) return int.tryParse(en.group(1) ?? '') ?? 0;
    return 0;
  }

  static List<DanDanPlayEpisodeSearchItem> _collectEpisodeItems(
    List<dynamic> items, {
    String inheritedAnimeTitle = '',
  }) {
    final results = <DanDanPlayEpisodeSearchItem>[];
    final seenIds = <int>{};

    void visit(List<dynamic> source, String currentAnimeTitle) {
      for (final item in source) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final animeTitle = _readString(map, const <String>[
          'animeTitle',
          'animeTitleCN',
          'animeTitleCHS',
          'title',
          'anime',
          'subjectName',
        ], fallback: currentAnimeTitle);
        final episodeId = _readInt(map, const <String>[
          'episodeId',
          'id',
          'episode_id',
        ]);
        if (episodeId != null && seenIds.add(episodeId)) {
          results.add(
            DanDanPlayEpisodeSearchItem(
              episodeId: episodeId,
              animeTitle: animeTitle,
              episodeTitle: _readString(map, const <String>[
                'episodeTitle',
                'episodeName',
                'title',
                'name',
              ]),
              episodeNumber:
                  _readInt(map, const <String>[
                    'episodeNumber',
                    'episode',
                    'ep',
                  ]) ??
                  0,
            ),
          );
        }
        final nested = map['episodes'];
        if (nested is List && nested.isNotEmpty) {
          visit(nested, animeTitle);
        }
      }
    }

    visit(items, inheritedAnimeTitle);
    return results;
  }

  static String _readString(
    Map<String, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}
