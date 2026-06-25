import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media_backend/detail/media_episode_summary.dart';
import '../media_backend/detail/media_season_summary.dart';
import '../media_backend/media_backend.dart';

/// Emby 原生壳「选集」反向通道支持。
///
/// 对位飞牛 [NativeReentrySupport] 的选集三方法（loadEpisodePickerData /
/// loadSeasonEpisodes / setEpisodePickerViewType），但数据源是**后端中立** [MediaBackend]
/// 的 `getItemSeasons` / `getSeasonEpisodes`，而非 FeiniuApi——故无飞牛专属的下载角标 /
/// 封面 NAS 鉴权 / 服务端 viewType 偏好。
///
/// 飞牛靠 `loadEpisodePickerData` 拉**季列表 + 当前季完整剧集**点亮原生壳选集面板（季 chip /
/// 跨季切换 / 宫格列表视图），靠 `loadSeasonEpisodes` 轻量预取其它季。Emby 之前只把当前季
/// 静态 `episodes` 透进 loadArgs（够「下一集」与单季选集，但无季 chip、不能跨季），绑上这三个
/// 回调后达成与飞牛壳一致的选集体验。viewType 仅本地持久化（Emby 无对应服务端偏好口径），
/// 写共享键 `playlist_view_type`（原生壳读同键），与飞牛壳口径一致。
class EmbyNativePickerSupport {
  const EmbyNativePickerSupport._();

  static const String viewTypeCard = 'card';
  static const String viewTypeButton = 'button';
  static const String _viewTypeKey = 'playlist_view_type';

  /// 选集面板数据：viewType + 季列表 + 指定季剧集。[currentLoadArgs] 为原生壳回传的
  /// 当前 loadArgs(JSON)，含 `seriesGuid` / `seasonGuid`。请求季优先 [seasonGuid]，否则
  /// 取当前播放季；季列表取数失败退化为「仅当前季」（用 [fallbackEpisodes] 兜底，不报错）。
  static Future<Map<String, dynamic>?> loadEpisodePickerData(
    MediaBackend backend, {
    required String currentLoadArgs,
    String seasonGuid = '',
    List<Map<String, dynamic>> fallbackEpisodes =
        const <Map<String, dynamic>>[],
  }) async {
    if (currentLoadArgs.trim().isEmpty) return null;
    final Map<String, dynamic> loadArgs;
    try {
      loadArgs = (jsonDecode(currentLoadArgs) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      return null;
    }
    final seriesGuid = (loadArgs['seriesGuid'] ?? '').toString().trim();
    final requestedSeasonGuid = seasonGuid.trim().isNotEmpty
        ? seasonGuid.trim()
        : (loadArgs['seasonGuid'] ?? '').toString().trim();
    final viewType = await _loadViewType();
    final seasons = await _loadSeasons(backend, seriesGuid);
    final targetSeasonGuid = _resolveTargetSeasonGuid(
      requestedSeasonGuid: requestedSeasonGuid,
      seasons: seasons,
      fallbackEpisodes: fallbackEpisodes,
    );
    final episodes = await _loadSeasonEpisodeMaps(
      backend,
      targetSeasonGuid,
      fallbackEpisodes: fallbackEpisodes,
    );
    return <String, dynamic>{
      'viewType': viewType,
      'selectedSeasonGuid': targetSeasonGuid,
      'seriesTitle': (loadArgs['seriesTitle'] ?? '').toString(),
      'seasons': seasons
          .map(
            (season) => <String, dynamic>{
              ...season,
              'selected': season['seasonGuid'] == targetSeasonGuid,
            },
          )
          .toList(growable: false),
      'episodes': episodes,
    };
  }

  /// 只拉指定季剧集（单次 `getSeasonEpisodes`），供原生壳后台并行预取其它季 / 按需切季。
  static Future<Map<String, dynamic>?> loadSeasonEpisodes(
    MediaBackend backend, {
    required String seasonGuid,
  }) async {
    final guid = seasonGuid.trim();
    if (guid.isEmpty) return null;
    final episodes = await _loadSeasonEpisodeMaps(
      backend,
      guid,
      fallbackEpisodes: const <Map<String, dynamic>>[],
    );
    if (episodes.isEmpty) return null;
    return <String, dynamic>{'seasonGuid': guid, 'episodes': episodes};
  }

  /// 中立选集 → 原生壳选集行 map 列表（供播放入口把整季 episodes 透进原生壳点亮「选集 /
  /// 下一集」）。原生壳「下一集」`nextEpisodeGuidOrNull` 与选集面板都读 loadArgs 的 episodes，
  /// 空则功能不亮——故单集起播 / 切集必须带上本季列表。
  static List<Map<String, dynamic>> nativeEpisodePayload(
    List<MediaEpisodeSummary> episodes,
    String seasonGuid,
  ) {
    return <Map<String, dynamic>>[
      for (final episode in episodes) _episodeMap(seasonGuid, episode),
    ];
  }

  /// 持久化选集视图偏好（宫格 / 列表）到本地共享键；非法值返回 false。
  static Future<bool> setEpisodePickerViewType(String viewType) async {
    final normalized = viewType.trim();
    if (normalized != viewTypeCard && normalized != viewTypeButton) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewTypeKey, normalized);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _loadViewType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_viewTypeKey)?.trim();
      if (value == viewTypeCard || value == viewTypeButton) return value!;
    } catch (_) {}
    return viewTypeCard;
  }

  static Future<List<Map<String, dynamic>>> _loadSeasons(
    MediaBackend backend,
    String seriesGuid,
  ) async {
    if (seriesGuid.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final seasons = await backend.getItemSeasons(seriesGuid);
      return seasons
          .map(
            (season) => <String, dynamic>{
              'seasonGuid': season.id,
              'seasonLabel': _seasonLabel(season),
              'seasonNumber': season.seasonNumber,
            },
          )
          .where((season) => (season['seasonGuid'] ?? '').toString().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  static String _resolveTargetSeasonGuid({
    required String requestedSeasonGuid,
    required List<Map<String, dynamic>> seasons,
    required List<Map<String, dynamic>> fallbackEpisodes,
  }) {
    if (requestedSeasonGuid.isNotEmpty) return requestedSeasonGuid;
    final firstEpisode = fallbackEpisodes.isNotEmpty
        ? fallbackEpisodes.first
        : null;
    final fallbackSeason = firstEpisode == null
        ? ''
        : ((firstEpisode['seasonGuid'] ?? firstEpisode['parentGuid'])
                  ?.toString()
                  .trim() ??
              '');
    if (fallbackSeason.isNotEmpty) return fallbackSeason;
    return seasons.isNotEmpty
        ? (seasons.first['seasonGuid'] ?? '').toString().trim()
        : '';
  }

  static Future<List<Map<String, dynamic>>> _loadSeasonEpisodeMaps(
    MediaBackend backend,
    String seasonGuid, {
    required List<Map<String, dynamic>> fallbackEpisodes,
  }) async {
    if (seasonGuid.trim().isEmpty) return fallbackEpisodes;
    try {
      final episodes = await backend.getSeasonEpisodes(seasonGuid.trim());
      final mapped = <Map<String, dynamic>>[
        for (final episode in episodes) _episodeMap(seasonGuid.trim(), episode),
      ];
      return mapped.isNotEmpty ? mapped : fallbackEpisodes;
    } catch (_) {
      return fallbackEpisodes;
    }
  }

  /// 中立选集 → 原生壳选集行 map。键对齐飞牛 `_nativeEpisodeMap`：原生面板读 `duration`
  /// （秒）/ `watched`（1/0）/ `poster` 渲染时长 / 已观看角标 / 缩略图。Emby 封面 api_key 自
  /// 鉴权直链，故 `imageAuth` 留空。
  static Map<String, dynamic> _episodeMap(
    String seasonGuid,
    MediaEpisodeSummary episode,
  ) {
    return <String, dynamic>{
      'itemGuid': episode.id,
      'seasonGuid': seasonGuid,
      'episodeNumber': episode.episodeNumber,
      'shortLabel': episode.episodeNumber > 0 ? '${episode.episodeNumber}' : '',
      'title': episode.title,
      'poster': episode.primaryImage.url,
      'imageAuth': '',
      'duration': episode.durationSeconds,
      'watched': episode.watched ? 1 : 0,
      'ts': episode.resumePositionSeconds,
    };
  }

  static String _seasonLabel(MediaSeasonSummary season) {
    if (season.seasonNumber == 0) return '特别篇';
    if (season.seasonNumber > 0) return '第${season.seasonNumber}季';
    final title = season.title.trim();
    return title.isNotEmpty ? title : '季';
  }
}
