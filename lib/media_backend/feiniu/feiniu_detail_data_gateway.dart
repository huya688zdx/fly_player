import '../../api/feiniu_api.dart';
import '../../api/person_list_request.dart';
import '../../models/person_credit.dart';
import '../../models/play_info.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../../providers/nas_provider.dart';

/// 飞牛专属「详情 / 下载 / 本地回放元数据」窄能力面。
///
/// controllers 层（详情数据装配、下载面板、本地下载回放源解析）依赖本接口而非
/// [FeiniuApi]，保持依赖方向 controllers → media_backend。这些能力是飞牛专属
/// （下载清晰度 / 原始 detail JSON / 播放流明细），不进公共 `MediaBackend`；
/// 其他后端无需实现，下载等功能只对飞牛生效属预期。
abstract class FeiniuDetailDataGateway {
  /// 用页面已持有的 [FeiniuApi] 客户端包一层。
  const factory FeiniuDetailDataGateway.forApi(FeiniuApi api) =
      FeiniuApiDetailDataGateway;

  /// 从 NAS 会话构造（调用方只持有 [NasProvider] 时用）。
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
}

/// [FeiniuDetailDataGateway] 默认实现：直通 [FeiniuApi]。
class FeiniuApiDetailDataGateway implements FeiniuDetailDataGateway {
  final FeiniuApi api;

  const FeiniuApiDetailDataGateway(this.api);

  @override
  Future<PlayInfoData> getPlayInfo(String itemGuid) =>
      api.getPlayInfo(itemGuid);

  @override
  Future<StreamTrackData> getStreamTrackData(String itemGuid) =>
      api.getStreamTrackData(itemGuid);

  @override
  Future<PlaybackStreamData> getPlaybackStream(String mediaGuid) =>
      api.getPlaybackStream(mediaGuid);

  @override
  Future<Map<String, dynamic>> getItemDetail(String itemGuid) =>
      api.getItemDetail(itemGuid);

  @override
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    required PersonListRequest request,
  }) => api.getPersonList(itemGuid, request: request);

  @override
  Future<List<String>> getDownloadResolutionOptions(
    String playItemGuid, {
    required String lan,
  }) => api.getDownloadResolutionOptions(playItemGuid, lan: lan);
}
