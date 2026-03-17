import '../models/dandanplay_episode_search_item.dart';
import '../models/danmaku_import_result.dart';
import '../parser/danmaku_import_parser.dart';
import 'dandanplay_api.dart';

class DanDanPlayResolver {
  final DanDanPlayApi _api;

  const DanDanPlayResolver(this._api);

  Future<DanmakuImportResult?> resolveForPlayback({
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
    required String tmdbId,
  }) async {
    final results = await searchEpisodeCandidates(
      keyword: seriesTitle,
      episodeNumber: episodeNumber,
      tmdbId: tmdbId,
    );
    if (results.isEmpty) return null;
    return importEpisodeById(results.first);
  }

  Future<List<DanDanPlayEpisodeSearchItem>> searchEpisodeCandidates({
    required String keyword,
    required int episodeNumber,
    required String tmdbId,
  }) async {
    if (!_api.ready) return const <DanDanPlayEpisodeSearchItem>[];
    final normalizedKeyword = _normalizeSeriesTitle(keyword);
    final tmdbNumericId = _normalizeTmdbId(tmdbId);
    if (normalizedKeyword.isEmpty && tmdbNumericId == null) {
      return const <DanDanPlayEpisodeSearchItem>[];
    }

    final searchResponse = await _api.searchEpisodes(
      anime: normalizedKeyword,
      episode: episodeNumber > 0 ? episodeNumber : null,
      tmdbId: tmdbNumericId,
    );
    final payload = searchResponse.data ?? const <String, dynamic>{};
    final items = (payload['animes'] is List)
        ? payload['animes'] as List<dynamic>
        : ((payload['episodes'] is List)
            ? payload['episodes'] as List<dynamic>
            : const <dynamic>[]);
    return _collectEpisodeItems(items);
  }

  Future<DanmakuImportResult?> importEpisodeById(
    DanDanPlayEpisodeSearchItem item,
  ) async {
    if (!_api.ready) return null;
    final commentsResponse = await _api.fetchComments(item.episodeId);
    final xml = commentsResponse.data?.trim() ?? '';
    if (xml.isEmpty) return null;
    return DanmakuImportParser.parseXmlString(
      xml,
      sourceLabel: '弹弹play · ${item.displaySubtitle}',
    );
  }

  static String normalizeSeriesTitle(String value) => _normalizeSeriesTitle(value);

  static String _normalizeSeriesTitle(String value) {
    var title = value.trim();
    if (title.isEmpty) return '';
    title = title.replaceAll(RegExp(r'第\s*\d+\s*季'), '');
    title = title.replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '');
    return title.trim();
  }

  static int? _normalizeTmdbId(String trimId) {
    final raw = trimId.trim();
    if (raw.length < 3) return null;
    final prefix = raw.substring(0, 2).toLowerCase();
    if (prefix != 'tm' && prefix != 'tt') return null;
    return int.tryParse(raw.substring(2).trim());
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
        final animeTitle = _readString(
          map,
          const <String>[
            'animeTitle',
            'animeTitleCN',
            'animeTitleCHS',
            'title',
            'anime',
            'subjectName',
          ],
          fallback: currentAnimeTitle,
        );
        final episodeId = _readInt(
          map,
          const <String>['episodeId', 'id', 'episode_id'],
        );
        if (episodeId != null && seenIds.add(episodeId)) {
          results.add(
            DanDanPlayEpisodeSearchItem(
              episodeId: episodeId,
              animeTitle: animeTitle,
              episodeTitle: _readString(
                map,
                const <String>[
                  'episodeTitle',
                  'episodeName',
                  'title',
                  'name',
                ],
              ),
              episodeNumber:
                  _readInt(
                    map,
                    const <String>['episodeNumber', 'episode', 'ep'],
                  ) ??
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
