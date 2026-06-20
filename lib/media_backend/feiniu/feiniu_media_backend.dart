import '../../api/feiniu_api.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_catalog.dart';
import '../media_item_summary.dart';
import 'feiniu_media_mappers.dart';

/// 飞牛后端适配器：内部调用现有 [FeiniuApi]，把飞牛模型映射为公共模型。
///
/// 第一阶段不改变数据来源，只改变调用边界——首页等页面通过 [MediaBackend]
/// 间接访问飞牛，飞牛表现必须与迁移前一致。
class FeiniuMediaBackend implements MediaBackend {
  final FeiniuApi api;

  const FeiniuMediaBackend(this.api);

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  Future<List<MediaCatalog>> getCatalogs() async {
    final items = await api.getMediaList();
    return items.map(mapFeiniuCatalog).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() => api.getMediaSummary();

  @override
  Future<List<MediaItemSummary>> getContinueWatching({
    bool forceRefresh = false,
  }) async {
    final items = await api.getPlayList(forceRefresh: forceRefresh);
    return items.map(mapFeiniuItemSummary).toList(growable: false);
  }

  @override
  Future<List<MediaItemSummary>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    final items = await api.getItemsByCategoryGuid(
      catalogId,
      page: page,
      limit: limit,
    );
    return items.map(mapFeiniuItemSummary).toList(growable: false);
  }
}
