import '../../api/feiniu_api.dart';
import '../../models/play_info.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../playback/media_playback_resolution.dart';

/// 飞牛播放的不透明后端上下文。
///
/// 持 `getPlayback` 已取的飞牛 raw facts，供 `FeiniuPlaybackSourceBridge`（住 player 层）
/// downcast 后调 `PlayerSourceController.buildInitialPlaybackResult` 装配 `MpvMediaSource`，
/// 单次网络、不重复请求。中立层不解读本类型。
class FeiniuPlaybackContext implements MediaPlaybackBackendContext {
  /// 飞牛 API 句柄（桥接器构建直链 / 代理会话时复用）。
  final FeiniuApi api;

  /// 原始播放信息（标题 / 封面 / 层级 / item 等装配所需）。
  final PlayInfoData playInfo;

  /// 选中 source 的原始播放流（直链 target / headers / 轨道索引等）。
  final PlaybackStreamData playbackStream;

  /// 选中的原始画质 / 音轨 / 字幕档（喂 buildInitialPlaybackResult）。
  final PlaybackQualityOption? selectedQuality;
  final AudioTrackOption? selectedAudio;
  final SubtitleTrackOption? selectedSubtitle;

  /// 合并轨道字典后的原始画质列表（装进 MpvMediaSource.qualities，供画质切换 UI）。
  final List<PlaybackQualityOption> mergedQualities;

  /// 合并后的字幕轨（用于内嵌字幕序号计算）。
  final List<SubtitleTrackOption> subtitleTracks;

  /// 生效的 media guid（多版本切换后的实际取流 source）与视频轨 guid。
  final String effectiveSourceId;
  final String videoTrackId;

  /// 原画直链候选 URL（buildInitialPlaybackResult 的 directUrl 入参）。
  final String directUrl;

  const FeiniuPlaybackContext({
    required this.api,
    required this.playInfo,
    required this.playbackStream,
    required this.selectedQuality,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.mergedQualities,
    required this.subtitleTracks,
    required this.effectiveSourceId,
    required this.videoTrackId,
    required this.directUrl,
  });
}
