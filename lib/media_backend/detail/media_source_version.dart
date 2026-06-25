import 'media_source_info.dart';

/// 后端中立的「可选播放版本」——详情页版本 / 音轨 / 字幕选择器的数据。
///
/// 一个版本对应同一条目的一个可播放源（Emby `MediaSources[]` 的一项，通常是同一影片的
/// 不同文件 / 清晰度 / 剪辑版本）。承载该版本的展示信息（复用 [MediaSourceInfo]）+ 可选
/// 音轨 / 字幕轨。**只承载展示 + 选择标识**，不含播放句柄 / 直链（那些留播放层 getPlayback）。
///
/// 飞牛有自己的版本 / 轨道选择路径（深绑 `MpvMediaSource`），本模型只服务 Emby 等公共后端
/// 的中立详情页。
class MediaSourceVersion {
  const MediaSourceVersion({
    required this.id,
    this.label = '',
    this.badges = const <String>[],
    this.info = const MediaSourceInfo(),
    this.audioTracks = const <MediaTrackOption>[],
    this.subtitleTracks = const <MediaTrackOption>[],
    this.defaultAudioId = '',
    this.defaultSubtitleId = '',
  });

  /// 稳定标识（Emby `MediaSources[].Id`）。
  final String id;

  /// 版本显示名（分辨率 / 文件名 / `Name`）。
  final String label;

  /// 能力角标（分辨率 / HDR 等，未归一的原始值；UI 侧再 normalize）。
  final List<String> badges;

  /// 该版本的文件 / 视频展示信息（详情页文件信息卡）。
  final MediaSourceInfo info;

  /// 可选音轨。
  final List<MediaTrackOption> audioTracks;

  /// 可选字幕轨。
  final List<MediaTrackOption> subtitleTracks;

  /// 默认音轨 id（Emby `DefaultAudioStreamIndex`），无则空。
  final String defaultAudioId;

  /// 默认字幕 id（Emby `DefaultSubtitleStreamIndex`），无 / 关闭则空。
  final String defaultSubtitleId;
}

/// 一条可选轨道（音轨 / 字幕）的中立描述。
///
/// [id] 为稳定标识（Emby stream `Index` 串）；[label] 为显示名（语言 / `DisplayTitle`）；
/// [summary] 为技术行（编码 / 布局等，可空）；[isExternal] 标记外挂字幕。
class MediaTrackOption {
  const MediaTrackOption({
    required this.id,
    this.label = '',
    this.summary = '',
    this.isExternal = false,
  });

  final String id;
  final String label;
  final String summary;
  final bool isExternal;
}
