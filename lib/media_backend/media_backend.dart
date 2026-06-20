import 'filter/media_catalog_filter.dart';
import 'media_backend_capabilities.dart';
import 'media_catalog.dart';
import 'media_item_card.dart';

/// 公共媒体后端接口。
///
/// 页面和播放入口只依赖本接口，不直接调用 FeiniuApi。第一阶段唯一实现是
/// `FeiniuMediaBackend`；未来可新增 `EmbyMediaBackend`，UI 无需出现后端分支。
abstract class MediaBackend {
  /// 当前后端支持的能力，飞牛专属功能通过此处声明。
  MediaBackendCapabilities get capabilities;

  /// 首页媒体库入口列表。
  Future<List<MediaCatalog>> getCatalogs();

  /// 首页概要数据。第一阶段仍为飞牛原始结构，后续逐步公共化。
  Future<Map<String, dynamic>> getHomeSummary();

  /// 继续观看列表。
  Future<List<MediaItemCard>> getContinueWatching({bool forceRefresh = false});

  /// 某个媒体库的预览条目。
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  });

  /// 按关键字搜索条目。
  Future<List<MediaItemCard>> searchItems(String query);

  /// 某个媒体库的可筛选 / 可排序 schema（维度、选项、数据字典）。
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(String catalogId);

  /// 按筛选条件分页查询某个媒体库的条目。
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query);
}
