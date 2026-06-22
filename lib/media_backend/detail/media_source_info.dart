/// 后端中立的「媒体源信息」——详情页文件信息 + 视频信息卡的展示数据。
///
/// 独立于 [MediaDetail]（后者按设计只承载纯展示元数据，不含源/轨道信息）。这里只承载
/// **展示用**的源事实（文件路径 / 容器 / 大小 / 添加日期 + 视频/音频/字幕摘要行），不含
/// 播放句柄、直链、轨道选择 id 等播放接线（那些留播放层 / getPlayback）。
///
/// 飞牛有自己的文件信息 / 视频信息渲染路径，本模型只服务 Emby 等公共后端的中立详情页。
class MediaSourceInfo {
  const MediaSourceInfo({
    this.path = '',
    this.container = '',
    this.sizeBytes = 0,
    this.addedDate = '',
    this.streams = const <MediaSourceStream>[],
  });

  /// 服务器侧文件路径（Emby `MediaSources[].Path`）。
  final String path;

  /// 容器格式（如 `mkv` / `mp4`）。
  final String container;

  /// 文件大小（字节）。
  final int sizeBytes;

  /// 添加日期（ISO 字符串，Emby `DateCreated`）。
  final String addedDate;

  /// 视频 / 音频 / 字幕流摘要（已格式化为单行，UI 直接显示）。
  final List<MediaSourceStream> streams;

  bool get isEmpty =>
      path.isEmpty && container.isEmpty && sizeBytes <= 0 && streams.isEmpty;

  bool get isNotEmpty => !isEmpty;

  List<MediaSourceStream> get videoStreams =>
      streams.where((s) => s.type == MediaStreamType.video).toList();
  List<MediaSourceStream> get audioStreams =>
      streams.where((s) => s.type == MediaStreamType.audio).toList();
  List<MediaSourceStream> get subtitleStreams =>
      streams.where((s) => s.type == MediaStreamType.subtitle).toList();
}

enum MediaStreamType { video, audio, subtitle, other }

/// 单条流的展示摘要。[label] 为标题（如 `Japanese FLAC 5.1`），[summary] 为技术行
/// （如 `FLAC · 5.1 · 48000 Hz`）。映射层负责拼好，UI 不再加工。
class MediaSourceStream {
  const MediaSourceStream({
    required this.type,
    this.label = '',
    this.summary = '',
  });

  final MediaStreamType type;
  final String label;
  final String summary;
}
