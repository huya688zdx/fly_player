import '../../api/feiniu_api.dart';
import '../../api/person_list_request.dart';
import '../../models/media_library_item.dart';
import '../../models/person_credit.dart';
import '../../models/play_info.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../../providers/nas_provider.dart';

/// 飞牛专属「详情 / 下载 / 选集 / 本地回放元数据」窄能力面。
///
/// controllers 层（详情数据装配、下载面板、原生壳选集列表、本地下载回放源解析）
/// 依赖本接口而非 [FeiniuApi]，保持依赖方向 controllers → media_backend。这些能力
/// 是飞牛专属（下载清晰度 / 原始 detail JSON / 播放流明细 / 原始选集条目），不进
/// 公共 `MediaBackend`；其他后端无需实现，下载等功能只对飞牛生效属预期。
///
/// 定位声明：本类型当前是 **import 收口层（窄门）**——只负责把 controllers 对
/// feiniu_api 的直连收拢到一个可替换的接口后面，DI 尚未闭环（调用点仍就地
/// `forApi`/`forNas` 构造，构造注入的彻底闭环归 5.3 页面收口）。它与 play_stats
/// 的端口适配器 `FeiniuPlayStatsGateway`（由注册表注入的依赖倒置端口）是两种性质，
/// 不得合并。
abstract class FeiniuDetailDataGateway {
  /// 用页面已持有的 [FeiniuApi] 客户端包一层。仅白名单 pages 可用此工厂——
  /// 调用方必须自身已 import feiniu_api（受边界测试白名单约束）。
  factory FeiniuDetailDataGateway.forApi(FeiniuApi api) =
      FeiniuApiDetailDataGateway;

  /// 从 NAS 会话构造。这是被封口层（controllers / 非白名单 pages、screens）
  /// 取得 gateway 的唯一入口——它们不许 import feiniu_api，没有本工厂就只能
  /// 直连破坏封口，故不得删除。
  factory FeiniuDetailDataGateway.forNas(NasProvider nas) =>
      FeiniuApiDetailDataGateway(FeiniuApi(nas));

  /// 条目播放信息（续播位 / 默认轨道 / 条目元数据）。
  Future<PlayInfoData> getPlayInfo(String itemGuid);

  /// 条目多版本轨道字典。
  Future<StreamTrackData> getStreamTrackData(String itemGuid);

  /// 指定媒体版本的播放流明细。
  Future<PlaybackStreamData> getPlaybackStream(String mediaGuid);

  /// 条目原始 detail JSON（下载面板分组 / imdb / trim id 提取用）。
  Future<Map<String, dynamic>> getItemDetail(String itemGuid);

  /// 条目演职员分页。
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    required PersonListRequest request,
  });

  /// 条目可下载清晰度列表。
  Future<List<String>> getDownloadResolutionOptions(
    String playItemGuid, {
    required String lan,
  });

  /// 某一季的选集列表（原生壳选集 payload 消费原始飞牛条目字段：
  /// watched int 透传 / poster 原始路径，故走飞牛专属 gateway 而非公共
  /// `MediaBackend.getSeasonEpisodes` 的中立摘要）。
  Future<List<MediaLibraryItem>> getEpisodeList(String seasonGuid);
}

/// [FeiniuDetailDataGateway] 默认实现：直通 [FeiniuApi]。
class FeiniuApiDetailDataGateway implements FeiniuDetailDataGateway {
  final FeiniuApi _api;

  const FeiniuApiDetailDataGateway(this._api);

  @override
  Future<PlayInfoData> getPlayInfo(String itemGuid) =>
      _api.getPlayInfo(itemGuid);

  @override
  Future<StreamTrackData> getStreamTrackData(String itemGuid) =>
      _api.getStreamTrackData(itemGuid);

  @override
  Future<PlaybackStreamData> getPlaybackStream(String mediaGuid) =>
      _api.getPlaybackStream(mediaGuid);

  @override
  Future<Map<String, dynamic>> getItemDetail(String itemGuid) =>
      _api.getItemDetail(itemGuid);

  @override
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    required PersonListRequest request,
  }) => _api.getPersonList(itemGuid, request: request);

  @override
  Future<List<String>> getDownloadResolutionOptions(
    String playItemGuid, {
    required String lan,
  }) => _api.getDownloadResolutionOptions(playItemGuid, lan: lan);

  @override
  Future<List<MediaLibraryItem>> getEpisodeList(String seasonGuid) =>
      _api.getEpisodeList(seasonGuid);
}
