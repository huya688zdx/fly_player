import '../../media_backend/media_image_request.dart';
import '../../models/media_item.dart';
import '../../models/media_library_item.dart';

/// 首页各内容区块及其图片请求的统一快照。
class HomeViewData {
  const HomeViewData({
    this.catalogs = const <MediaItem>[],
    this.catalogPreviewItems = const <String, List<MediaLibraryItem>>{},
    this.continueWatching = const <MediaLibraryItem>[],
    this.nextUp = const <MediaLibraryItem>[],
    this.latest = const <MediaLibraryItem>[],
    this.summary = const <String, dynamic>{},
    this.catalogImageRequests = const <String, List<MediaImageRequest>>{},
    this.itemImageRequests = const <String, MediaImageRequest>{},
    this.backdropImageRequests = const <String, MediaImageRequest>{},
  });

  const HomeViewData.empty() : this();

  final List<MediaItem> catalogs;
  final Map<String, List<MediaLibraryItem>> catalogPreviewItems;
  final List<MediaLibraryItem> continueWatching;
  final List<MediaLibraryItem> nextUp;
  final List<MediaLibraryItem> latest;
  final Map<String, dynamic> summary;
  final Map<String, List<MediaImageRequest>> catalogImageRequests;
  final Map<String, MediaImageRequest> itemImageRequests;
  final Map<String, MediaImageRequest> backdropImageRequests;

  HomeViewData copyWith({
    List<MediaItem>? catalogs,
    Map<String, List<MediaLibraryItem>>? catalogPreviewItems,
    List<MediaLibraryItem>? continueWatching,
    List<MediaLibraryItem>? nextUp,
    List<MediaLibraryItem>? latest,
    Map<String, dynamic>? summary,
    Map<String, List<MediaImageRequest>>? catalogImageRequests,
    Map<String, MediaImageRequest>? itemImageRequests,
    Map<String, MediaImageRequest>? backdropImageRequests,
  }) {
    return HomeViewData(
      catalogs: catalogs ?? this.catalogs,
      catalogPreviewItems: catalogPreviewItems ?? this.catalogPreviewItems,
      continueWatching: continueWatching ?? this.continueWatching,
      nextUp: nextUp ?? this.nextUp,
      latest: latest ?? this.latest,
      summary: summary ?? this.summary,
      catalogImageRequests: catalogImageRequests ?? this.catalogImageRequests,
      itemImageRequests: itemImageRequests ?? this.itemImageRequests,
      backdropImageRequests:
          backdropImageRequests ?? this.backdropImageRequests,
    );
  }
}
