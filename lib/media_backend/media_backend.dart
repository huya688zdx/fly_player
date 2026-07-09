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
import 'playback/media_playback_source_bridge.dart';

/// 公共媒体后端接口。
///
/// 页面和播放入口只依赖本接口，不直接调用 FeiniuApi。第一阶段唯一实现是
/// `FeiniuMediaBackend`；未来可新增 `EmbyMediaBackend`，UI 无需出现后端分支。
abstract class MediaBackend {
  /// 当前后端支持的能力，飞牛专属功能通过此处声明。
  MediaBackendCapabilities get capabilities;

  /// 本后端的播放桥接器。播放入口统一经此装配，不解读具体 backend context。
  MediaPlaybackSourceBridge get playbackSourceBridge;

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

  /// 查询「收藏」条目分页（收藏页）。
  ///
  /// 默认返回空（飞牛走自有 `getFavoritePage` 完整路径 + 标签筛选,不经本接口）；Emby 等公共
  /// 后端 override 为 `Filters=IsFavorite` 查询。收藏页对飞牛走专属页面,对其他后端走本接口
  /// 的公共卡片网格。[query] 的 `selection['type']` 用中立类型标签按收藏 Tab 过滤
  /// （movie / tv / episode / person）。
  Future<MediaItemCardPage> queryFavoriteItems(MediaCatalogQuery query) async =>
      const MediaItemCardPage();

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

  /// 解析「系列页主播放键」要起播的具体条目 id（系列本身不可直接播）。
  ///
  /// 默认返回 [seriesId]（飞牛：launcher/NAS 自行把系列解析成续看单集）。Emby 直链播放需先
  /// 定到具体单集，故 override 为续看/首集解析（有进度的集优先，否则首个未看，再否则首集）。
  /// 返回空串表示无可播单集。
  Future<String> resolveSeriesPlaybackTarget(String seriesId) async => seriesId;

  /// 系列页主播放键要起播的「续看/首集」摘要（含季/集号，供按键文案显示「第 X 季 第 Y 集」）。
  ///
  /// 默认 null（飞牛走自有 PlayInfo 文案，不经此）；Emby override 为续看/首集解析。系列页加载时
  /// 调一次拿到目标集，按键文案与点击起播复用同一目标，避免点击时再解析一遍。
  Future<MediaEpisodeSummary?> resolveSeriesNextUpEpisode(
    String seriesId,
  ) async => null;

  /// 某一季的选集列表。
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId);

  /// 解析播放：返回后端中立 bundle + 不透明后端上下文。
  ///
  /// [MediaPlaybackResolution.bundle] 是后端中立播放事实（播放源 / 画质 / 轨道 / 续播 /
  /// 会话句柄）。[MediaPlaybackResolution.backendContext] 由后端桥接器消费装配播放器
  /// 最终 source。本层不构造 `MpvMediaSource`，不导航、不触播放器深层逻辑。
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request);

  /// 向后端回写播放进度（更新续播位）。best-effort：调用方静默吞错。
  ///
  /// 飞牛走自有 `NativeReentrySupport` 通道（含离线队列 / 本地 play stats），故飞牛实现为
  /// 空操作；Emby 用 `/Sessions/Playing/Progress` 更新 `UserData.PlaybackPositionTicks`，
  /// 使跨会话续播一致。[positionSeconds] 为播放位置（秒）。
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
    bool isPaused = false,
  }) async {}

  /// 通知后端某条目播放开始（建立播放会话）。默认空操作。
  ///
  /// 飞牛走自有进度通道，无需会话握手，故为空；Emby **必须先 `POST /Sessions/Playing`** 建会话，
  /// 之后的 [reportPlaybackProgress] 才会被持久化（否则续播位不更新）。[positionSeconds] 为起播位。
  Future<void> reportPlaybackStart({
    required String itemId,
    required String mediaSourceId,
    int positionSeconds = 0,
  }) async {}

  /// 通知后端某条目播放停止（关闭播放会话、落定最终续播位）。默认空操作；Emby `POST
  /// /Sessions/Playing/Stopped`。[positionSeconds] 为停止时的播放位。
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
  }) async {}

  /// 设置 / 取消「收藏」，返回最终收藏态（true=已收藏）。
  ///
  /// 详情页心形键的中立通道——新后端实现此法即可让详情页收藏键生效，无需改 UI。默认不支持
  /// （返回入参，视为无变化）；飞牛走 `FeiniuApi.setFavorite`，Emby 走
  /// `POST/DELETE /Users/{userId}/FavoriteItems/{itemId}`。失败应抛错，由调用方提示。
  /// 能力开关见 [MediaBackendCapabilities.supportsFavorite]。
  Future<bool> setItemFavorite(String itemId, {required bool favorite}) async =>
      favorite;

  /// 标记「已看 / 未看」，返回最终已看态（true=已看）。
  ///
  /// 详情页已看键的中立通道。默认不支持；飞牛走 `FeiniuApi.setWatched`，Emby 走
  /// `POST/DELETE /Users/{userId}/PlayedItems/{itemId}`。能力开关见
  /// [MediaBackendCapabilities.supportsWatched]。
  Future<bool> setItemWatched(String itemId, {required bool watched}) async =>
      watched;

  /// 解析外挂字幕轨为本地可 `sub-add` 的文件路径（原生壳反向通道）。
  ///
  /// [trackId] 为播放桥接器为外挂字幕轨产出的、自包含的轨道标识（后端各自约定编码，外层
  /// 不解释）。飞牛走自有 `NativeReentrySupport.resolveSubtitleFile`（NAS guid → 下载），
  /// 故本接口对飞牛返回 `null`；Emby 解码 `trackId` → 下载字幕全文落临时文件 → 返回路径。
  /// 失败返回 `null`（外挂字幕为旁路能力，原生壳回退「无外挂字幕」）。
  Future<String?> resolveExternalSubtitleFile(
    String trackId, {
    String? format,
  }) async => null;
}
