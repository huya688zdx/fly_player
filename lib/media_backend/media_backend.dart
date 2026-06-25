import 'detail/media_detail.dart';
import 'detail/media_episode_summary.dart';
import 'detail/media_season_summary.dart';
import 'detail/media_source_info.dart';
import 'detail/media_source_version.dart';
import 'filter/media_catalog_filter.dart';
import 'media_backend_capabilities.dart';
import 'media_catalog.dart';
import 'media_item_card.dart';
import 'playback/media_playback.dart';
import 'playback/media_playback_resolution.dart';

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

  /// 某个人物（演职员）参与的作品列表，供人物详情页作品区。
  ///
  /// 默认返回空（飞牛走自有的按职务分页 getPersonItemList 路径，不经本接口）；Emby 等公共
  /// 后端 override（人物本身的姓名 / 简介 / 照片复用 [getItemDetail]）。
  Future<List<MediaItemCard>> getPersonItems(String personId) async =>
      const <MediaItemCard>[];

  /// 单个条目的「媒体源信息」（文件路径 / 大小 / 视频音频字幕摘要），供详情页文件/视频信息卡。
  ///
  /// 仅展示用，不含播放句柄/直链。飞牛有自己的文件/视频信息渲染路径，返回 `null` 表示该后端
  /// 不通过本接口提供（由页面侧走原路径）。
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId);

  /// 单个条目的「可选播放版本」列表（每个版本含其音轨 / 字幕轨），供详情页版本 / 音轨 /
  /// 字幕选择器。仅展示 + 选择标识，不含播放句柄 / 直链。
  ///
  /// 默认返回空（飞牛走自有版本 / 轨道选择路径，不经本接口）；Emby 等公共后端 override。
  Future<List<MediaSourceVersion>> getItemSourceVersions(String itemId) async =>
      const <MediaSourceVersion>[];

  /// 剧集的季列表。
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId);

  /// 某一季的选集列表。
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId);

  /// 解析播放：返回后端中立 bundle + 不透明后端上下文。
  ///
  /// [MediaPlaybackResolution.bundle] 是后端中立播放事实（播放源 / 画质 / 轨道 / 续播 /
  /// 会话句柄）。[MediaPlaybackResolution.backendContext] 由后端桥接器消费装配播放器
  /// 最终 source。本层不构造 `MpvMediaSource`，不导航、不触播放器深层逻辑。
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request);
}
