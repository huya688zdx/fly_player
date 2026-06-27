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
    final item =
        _pickPlaybackCandidate(
          results,
          itemTitle: itemTitle,
          episodeNumber: episodeNumber,
        ) ??
        results.first;
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
    final normalizedKeyword = _normalizeSeriesTitle(keyword);
    final tmdbNumericId = _normalizeTmdbId(tmdbId);
    if (normalizedKeyword.isEmpty && tmdbNumericId == null) {
      return const <DanDanPlayEpisodeSearchItem>[];
    }

    final filteredEpisodeNumber = episodeNumber > 0 ? episodeNumber : null;
    final exactResults = await _searchEpisodeCandidatesOnce(
      keyword: normalizedKeyword,
      episodeNumber: filteredEpisodeNumber,
      tmdbId: tmdbNumericId,
    );
    if (exactResults.isNotEmpty) {
      return exactResults;
    }

    if (normalizedKeyword.isNotEmpty && tmdbNumericId != null) {
      final fallbackWithoutTmdb = await _searchEpisodeCandidatesOnce(
        keyword: normalizedKeyword,
        episodeNumber: filteredEpisodeNumber,
      );
      if (fallbackWithoutTmdb.isNotEmpty) {
        return fallbackWithoutTmdb;
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
    final content = await _cacheStore.loadComments(item.episodeId);
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
    await _cacheStore.saveComments(episodeId: item.episodeId, content: content);
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
    title = title.replaceAll(RegExp(r'第\s*\d+\s*季'), '');
    title = title.replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '');
    return title.trim();
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
    required String itemTitle,
    required int episodeNumber,
  }) {
    if (items.isEmpty) return null;
    final normalizedTitle = _normalizeComparableEpisodeTitle(itemTitle);
    if (normalizedTitle.isNotEmpty) {
      for (final item in items) {
        final candidate = _normalizeComparableEpisodeTitle(item.episodeTitle);
        if (candidate.isNotEmpty && candidate == normalizedTitle) {
          return item;
        }
      }
      for (final item in items) {
        final candidate = _normalizeComparableEpisodeTitle(item.episodeTitle);
        if (candidate.isNotEmpty &&
            (candidate.contains(normalizedTitle) ||
                normalizedTitle.contains(candidate))) {
          return item;
        }
      }
    }
    if (episodeNumber > 0) {
      for (final item in items) {
        if (item.episodeNumber == episodeNumber ||
            _extractEpisodeNumber(item.episodeTitle) == episodeNumber) {
          return item;
        }
      }
    }
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
    required String itemTitle,
    required int episodeNumber,
  }) {
    return _pickPlaybackCandidate(
      items,
      itemTitle: itemTitle,
      episodeNumber: episodeNumber,
    );
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
