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
MediaItemSummary mapFeiniuItemSummary(MediaLibraryItem item) {
  return MediaItemSummary(
    id: item.guid,
    title: item.displayTitle,
    type: item.type,
    primaryImage: MediaImageRef(url: item.poster),
    backdropImage: MediaImageRef.empty,
    durationSeconds: item.duration,
    watched: item.watched != 0,
  );
}
