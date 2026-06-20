import '../../models/media_item.dart';
import '../../models/media_library_item.dart';
import '../media_catalog.dart';
import '../media_image_ref.dart';
import '../media_item_summary.dart';

/// 把飞牛媒体库入口 [MediaItem] 映射为公共 [MediaCatalog]。
MediaCatalog mapFeiniuCatalog(MediaItem item) {
  return MediaCatalog(
    id: item.id,
    title: item.name,
    type: item.type ?? '',
    primaryImage: MediaImageRef(url: item.path ?? ''),
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
