import '../../media_backend/media_image_request.dart';
import '../../models/media_item.dart';
import '../../models/media_library_item.dart';

/// 带成功状态的首页可选区块结果，用于区分“成功为空”和“请求失败”。
class HomeSectionLoadResult<T> {
  const HomeSectionLoadResult.success(T value)
    : isSuccess = true,
      _value = value;

  const HomeSectionLoadResult.failure() : isSuccess = false, _value = null;

  final bool isSuccess;
  final T? _value;

  T get value {
    if (!isSuccess) {
      throw StateError('失败的首页区块结果没有值');
    }
    return _value as T;
  }

  /// 成功时返回请求值（包括空集合），失败时保留调用方提供的旧值。
  T valueOr(T fallback) => isSuccess ? value : fallback;
}

/// 为并发首页加载分配递增代次，只允许最后启动的请求落地。
class HomeLoadGeneration {
  int _value = 0;

  int begin() => ++_value;

  bool isCurrent(int generation) => generation == _value;

  void invalidate() {
    _value += 1;
  }
}

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
      catalogs: List<MediaItem>.of(catalogs ?? this.catalogs),
      catalogPreviewItems: _copyNestedMap(
        catalogPreviewItems ?? this.catalogPreviewItems,
      ),
      continueWatching: List<MediaLibraryItem>.of(
        continueWatching ?? this.continueWatching,
      ),
      nextUp: List<MediaLibraryItem>.of(nextUp ?? this.nextUp),
      latest: List<MediaLibraryItem>.of(latest ?? this.latest),
      summary: Map<String, dynamic>.of(summary ?? this.summary),
      catalogImageRequests: _copyNestedMap(
        catalogImageRequests ?? this.catalogImageRequests,
      ),
      itemImageRequests: Map<String, MediaImageRequest>.of(
        itemImageRequests ?? this.itemImageRequests,
      ),
      backdropImageRequests: Map<String, MediaImageRequest>.of(
        backdropImageRequests ?? this.backdropImageRequests,
      ),
    );
  }
}

Map<String, List<T>> _copyNestedMap<T>(Map<String, List<T>> source) {
  return source.map(
    (key, value) => MapEntry<String, List<T>>(key, List<T>.of(value)),
  );
}
