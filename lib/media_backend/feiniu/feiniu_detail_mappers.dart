import '../../models/media_library_item.dart';
import '../../models/person_credit.dart';
import '../../models/play_info.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../media_image_ref.dart';

/// 把飞牛 [PlayInfoData] 映射为公共详情模型 [MediaDetail]。
///
/// **只搬展示半**：标题 / 简介 / 图片 / 评分 / 年份时长 / 季集编号 / 题材地区 / 角标 /
/// 已看收藏续播快照 / 外部 ID / 演职员。飞牛播放接线（`mediaGuid` / `videoGuid` /
/// `audioGuid` / `subtitleGuid` / `canPlay` / `playError` / `playConfig` / 轨道）
/// 不进公共模型，留页面侧到 Phase 6。
///
/// 题材 / 地区在适配层用后端字典翻成显示名（详情页纯只读，不走 Phase 4.5 的双轨 label）：
/// [genresMap] 把 genre id 翻成题材名，[regionNames] 把 ISO3166 code 翻成地区名
/// （先直查、再大写查表，复刻分类页语义），未命中原样回退。[imdbId] 由调用方（data loader）
/// 另行解析后传入，不在 [PlayItem] 字段内。
MediaDetail mapFeiniuItemDetail(
  PlayInfoData info, {
  required Map<int, String> genresMap,
  required Map<String, String> regionNames,
  List<PersonCredit> credits = const <PersonCredit>[],
  String imdbId = '',
}) {
  final item = info.item;
  return MediaDetail(
    id: item.guid,
    type: item.type,
    title: item.title,
    secondaryTitle: item.tvTitle,
    parentTitle: item.parentTitle,
    overview: item.overview,
    primaryImage: MediaImageRef(url: item.posters),
    backdropImage: MediaImageRef(url: item.backdrops),
    logoImage: MediaImageRef(url: item.logos),
    rating: item.voteAverage,
    releaseDate: item.releaseDate,
    airDate: item.airDate,
    runtimeMinutes: item.runtime,
    durationSeconds: item.duration,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    numberOfSeasons: item.numberOfSeasons,
    numberOfEpisodes: item.numberOfEpisodes,
    localNumberOfSeasons: item.localNumberOfSeasons,
    localNumberOfEpisodes: item.localNumberOfEpisodes,
    genreLabels: item.genres
        .map((id) => genresMap[id] ?? '$id')
        .toList(growable: false),
    regionLabels: item.productionCountries
        .map((code) => _regionLabel(code, regionNames))
        .toList(growable: false),
    resolutions: item.resolutions,
    audioTypes: item.audioTypes,
    colorRanges: item.colorRanges,
    watched: item.isWatched != 0,
    favorite: item.isFavorite != 0,
    resumePositionSeconds: info.ts,
    externalIds: MediaExternalIds(tmdbId: item.trimId, imdbId: imdbId),
    people: credits.map(_mapCredit).toList(growable: false),
  );
}

/// 把飞牛季条目 [MediaLibraryItem] 映射为公共 [MediaSeasonSummary]。
MediaSeasonSummary mapFeiniuSeason(MediaLibraryItem item) {
  return MediaSeasonSummary(
    id: item.guid,
    title: item.displayTitle,
    seasonNumber: item.seasonNumber,
    numberOfEpisodes: item.numberOfEpisodes,
    localNumberOfEpisodes: item.localNumberOfEpisodes,
    primaryImage: MediaImageRef(url: item.poster),
  );
}

/// 把飞牛集条目 [MediaLibraryItem] 映射为公共 [MediaEpisodeSummary]。
MediaEpisodeSummary mapFeiniuEpisode(MediaLibraryItem item) {
  return MediaEpisodeSummary(
    id: item.guid,
    title: item.displayTitle,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    overview: item.overview,
    airDate: item.releaseDate,
    durationSeconds: item.duration,
    watched: item.watched != 0,
    resumePositionSeconds: item.ts,
    primaryImage: MediaImageRef(url: item.poster),
  );
}

/// 从飞牛 `getItemDetail` 返回的 Map 中提取 IMDb 标识。
///
/// `imdb_id` 既可能在顶层，也可能嵌在 `item` 下（复刻详情页 data loader 语义）。
/// 放在适配层，避免后端适配器反向依赖 UI 控制器。
String extractFeiniuImdbId(Map<String, dynamic> detail) {
  final direct = (detail['imdb_id'] ?? '').toString().trim();
  if (direct.isNotEmpty) return direct;
  final item = detail['item'];
  if (item is Map<String, dynamic>) {
    final nested = (item['imdb_id'] ?? '').toString().trim();
    if (nested.isNotEmpty) return nested;
  }
  return '';
}

String _regionLabel(String code, Map<String, String> regionNames) {
  return regionNames[code] ?? regionNames[code.toUpperCase()] ?? code;
}

MediaDetailPerson _mapCredit(PersonCredit credit) {
  final name = credit.name.trim().isNotEmpty
      ? credit.name
      : credit.originalName;
  return MediaDetailPerson(
    id: credit.personGuid,
    name: name,
    role: credit.role,
    department: credit.job,
    avatar: MediaImageRef(url: credit.profilePath),
  );
}
