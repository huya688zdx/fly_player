import '../../models/media_item.dart';
import '../../models/media_library_item.dart';
import '../media_catalog.dart';
import '../media_image_ref.dart';
import '../media_item_card.dart';
import '../media_item_summary.dart';

/// 把飞牛媒体库入口 [MediaItem] 映射为公共 [MediaCatalog]。
MediaCatalog mapFeiniuCatalog(MediaItem item) {
  return MediaCatalog(
    id: item.id,
    title: item.name,
    type: item.type ?? '',
    primaryImage: MediaImageRef(url: item.path ?? ''),
    posters: item.posters
        .map((path) => MediaImageRef(url: path))
        .toList(growable: false),
  );
}

/// 把飞牛条目 [MediaLibraryItem] 映射为公共 [MediaItemSummary]。
///
/// 保留原始 `title` 与 `tvTitle`（映射为 secondaryTitle），由公共模型的
/// displayTitle getter 复刻飞牛的显示名回退逻辑，确保过渡期还原旧模型时无损。
MediaItemSummary mapFeiniuItemSummary(MediaLibraryItem item) {
  return MediaItemSummary(
    id: item.guid,
    title: item.title,
    secondaryTitle: item.tvTitle,
    type: item.type,
    primaryImage: MediaImageRef(url: item.poster),
    backdropImage: MediaImageRef.empty,
    durationSeconds: item.duration,
    watched: item.watched != 0,
    rating: item.voteAverage,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    numberOfSeasons: item.numberOfSeasons,
    numberOfEpisodes: item.numberOfEpisodes,
    releaseDate: item.releaseDate,
    posterWidth: item.posterWidth,
    posterHeight: item.posterHeight,
  );
}

/// 把飞牛条目 [MediaLibraryItem] 映射为统一富卡片模型 [MediaItemCard]。
///
/// 无损搬运首页 / 搜索 / 分类卡片实际消费的全部展示字段：原始 `title` + `tvTitle`
/// （映射为 secondaryTitle，由 displayTitle getter 复刻飞牛回退语义）、多候选封面、
/// 年份区间所需的首播 / 完结日期、本地季集计数、person 作品数、清晰度角标等。
/// 滤镜 / 句柄等飞牛私有概念不进入公共模型。
MediaItemCard mapFeiniuItemCard(MediaLibraryItem item) {
  return MediaItemCard(
    id: item.guid,
    title: item.title,
    secondaryTitle: item.tvTitle,
    type: item.type,
    primaryImage: MediaImageRef(url: item.poster),
    posters: item.posterList
        .map((path) => MediaImageRef(url: path))
        .toList(growable: false),
    durationSeconds: item.duration,
    watched: item.watched != 0,
    rating: item.voteAverage,
    releaseDate: item.releaseDate,
    firstAirDate: item.firstAirDate,
    lastAirDate: item.lastAirDate,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    numberOfSeasons: item.numberOfSeasons,
    numberOfEpisodes: item.numberOfEpisodes,
    localNumberOfSeasons: item.localNumberOfSeasons,
    localNumberOfEpisodes: item.localNumberOfEpisodes,
    numberOfItem: item.numberOfItem,
    posterWidth: item.posterWidth,
    posterHeight: item.posterHeight,
    resolutions: item.resolutions,
  );
}
