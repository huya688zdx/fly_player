import 'detail/media_detail.dart';
import 'detail/media_episode_summary.dart';
import 'detail/media_season_summary.dart';
import 'filter/media_catalog_filter.dart';
import 'media_backend_capabilities.dart';
import 'media_catalog.dart';
import 'media_item_card.dart';
import 'playback/media_playback.dart';

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

  /// 单个条目的详情（展示信息）。不含播放接线（轨道 / 句柄 / 直链），那些留播放入口。
  Future<MediaDetail> getItemDetail(String itemId);

  /// 剧集的季列表。
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId);

  /// 某一季的选集列表。
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId);

  /// 解析播放所需的后端中立 bundle（播放源 / 画质 / 轨道 / 续播 / 会话句柄）。
  ///
  /// 不构造 `MpvMediaSource`，不导航、不触播放器深层逻辑——那些留播放入口的桥接层。
  Future<MediaPlaybackBundle> getPlayback(MediaPlaybackRequest request);
}
