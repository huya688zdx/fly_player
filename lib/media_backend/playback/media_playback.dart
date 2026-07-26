/// 后端中立的公共播放模型。
///
/// 这些模型表达「播放所需的后端中立事实」——播放源、画质候选、音轨/字幕候选、
/// 默认选择、续播位置、后端会话句柄、所需 headers——而不是播放器最终 load 参数。
///
/// 约束（见 `docs/superpowers/specs/2026-06-21-public-media-playback-design.md`）：
/// - 字段名一律中立，禁止出现 `mediaGuid` / `videoGuid` / `audioGuid` /
///   `subtitleGuid` / `Feiniu` / `Emby`。飞牛的 media guid 在适配层映射进 `id` /
///   `sourceId` / `videoTrackId` 等中立字段。
/// - 不承载 `MpvMediaSource`、本地代理、导航等播放器/UI 装配信息。
library;

/// 播放源的投递方式：原画、直链、服务端会话、转码。
///
/// 飞牛走原画 / 直链 / 服务端会话；Emby 走直链 / 转码（HLS）。公共层用同一枚举
/// 表达，UI 不需要 `if (isEmby)` 判断。
enum MediaPlaybackDeliveryKind {
  original,
  directLink,
  serverSession,
  transcoding,
}

/// 轨道类型：音轨或字幕。
enum MediaPlaybackTrackKind { audio, subtitle }

/// 字幕位置：内嵌、服务端外挂、设备本地。
enum MediaSubtitleLocation { embedded, external, local }

/// 一次播放请求：表达「用户想如何开始/重载一次播放」，不表达后端 DTO。
class MediaPlaybackRequest {
  /// 条目标识（飞牛 item guid / Emby item id）。
  final String itemId;

  /// 解析失败时的回退标题。
  final String fallbackTitle;

  /// 是否从头开始（清除续播记录）。
  final bool startFromBeginning;

  /// 指定续播位置；为空表示由后端解析。
  final Duration? resumePosition;

  /// 画质下标覆盖；`qualityId` 优先于本字段。
  final int? qualityIndex;

  /// 画质标识覆盖（飞牛映射到 media guid，Emby 映射到 media source / 质量候选 id）。
  final String? qualityId;

  /// 指定音轨标识。
  final String? audioTrackId;

  /// 指定字幕标识。
  final String? subtitleTrackId;

  /// 是否显式关闭字幕。
  ///
  /// 区分「关闭字幕」与「选默认字幕」——`subtitleTrackId == null` 且本字段为 `true`
  /// 表示关闭，避免公共层把关闭误当默认。
  final bool subtitleTrackExplicitlyDisabled;

  /// 发起播放的系列上下文标识；为空表示由后端从条目自身推导。
  ///
  /// 来自调用方（剧集/季页面）已知的系列 id——飞牛映射到剧集 series guid，
  /// Emby 映射到 series id。桥接装配时显式值优先于后端推导值。
  final String seriesId;

  /// 若该条目已播放完成，本次是否从头开始。
  ///
  /// 默认 `false`：保留后端解析出的网络续播位置（如电影/单条目）。剧集场景下
  /// 置 `true`，使「已看完的一集」重新点播时回到开头，而非停在结尾。
  final bool restartWhenCompleted;

  /// 按序号继承音轨：优先选择候选列表中第 N 条音轨（跨集沿用「当前第几条音轨」）。
  ///
  /// 用于剧集切集时把当前选中的音轨序号带到下一集；越界或为空时不生效，回退服务端
  /// 默认。`audioTrackId`（显式 guid）优先于本字段。
  final int? preferredAudioTrackIndex;

  /// 按序号继承字幕：优先选择候选列表中第 N 条字幕。语义同 [preferredAudioTrackIndex]；
  /// `subtitleTrackExplicitlyDisabled` 表达「关闭字幕」的继承。
  final int? preferredSubtitleTrackIndex;

  /// 按分辨率继承画质：优先选择候选列表中分辨率匹配的档（跨集沿用「当前分辨率」，如
  /// 1080p 转码档）。为空或找不到时回退默认画质梯度。`qualityId`/`qualityIndex` 优先。
  final String preferredQualityResolution;

  const MediaPlaybackRequest({
    required this.itemId,
    this.fallbackTitle = '',
    this.startFromBeginning = false,
    this.resumePosition,
    this.qualityIndex,
    this.qualityId,
    this.audioTrackId,
    this.subtitleTrackId,
    this.subtitleTrackExplicitlyDisabled = false,
    this.seriesId = '',
    this.restartWhenCompleted = false,
    this.preferredAudioTrackIndex,
    this.preferredSubtitleTrackIndex,
    this.preferredQualityResolution = '',
  });
}

/// 选中的后端播放源。
///
/// 不等价于 mpv 最终 URL——飞牛仍可能需要 `PlayerSourceController` 进一步决定
/// 代理 / 直链 / 服务端会话。`headers` 必须保留（Emby `RequiredHttpHeaders` 与
/// 飞牛直链 headers 都不能丢）。
class MediaPlaybackSource {
  /// 播放源标识（飞牛 media guid / Emby media source id）。
  final String id;

  /// 视频轨标识（飞牛 video guid / Emby video stream 的中立封装）。
  final String videoTrackId;

  final MediaPlaybackDeliveryKind delivery;

  /// 候选 URL；后续桥接到 `MpvMediaSource` 时仍可按本地代理改写。
  final String url;

  final Map<String, String> headers;
  final int width;
  final int height;
  final String videoCodec;
  final String videoProfile;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final int bitDepth;
  final bool reliableSeek;
  final bool forceNativeProxy;

  const MediaPlaybackSource({
    required this.id,
    required this.videoTrackId,
    required this.delivery,
    this.url = '',
    this.headers = const <String, String>{},
    this.width = 0,
    this.height = 0,
    this.videoCodec = '',
    this.videoProfile = '',
    this.colorSpace = '',
    this.colorTransfer = '',
    this.colorPrimaries = '',
    this.bitDepth = 0,
    this.reliableSeek = false,
    this.forceNativeProxy = false,
  });
}

/// 画质候选。
class MediaPlaybackQuality {
  final String id;
  final String sourceId;
  final String videoTrackId;
  final String label;
  final String resolution;
  final int bitrate;
  final bool isDefault;
  final MediaPlaybackDeliveryKind delivery;

  /// 直链投递时的候选下标；非直链为空。
  final int? directLinkIndex;

  const MediaPlaybackQuality({
    required this.id,
    required this.sourceId,
    required this.videoTrackId,
    required this.delivery,
    this.label = '',
    this.resolution = '',
    this.bitrate = 0,
    this.isDefault = false,
    this.directLinkIndex,
  });
}

/// 音轨 / 字幕候选。
class MediaPlaybackTrack {
  final String id;
  final MediaPlaybackTrackKind kind;

  /// 后端轨道索引；可空。
  final int? index;

  final String label;
  final String language;
  final String codec;
  final String title;
  final bool isDefault;

  /// 字幕位置；音轨为空。
  final MediaSubtitleLocation? subtitleLocation;

  const MediaPlaybackTrack({
    required this.id,
    required this.kind,
    this.index,
    this.label = '',
    this.language = '',
    this.codec = '',
    this.title = '',
    this.isDefault = false,
    this.subtitleLocation,
  });
}

/// 后端播放会话句柄。
///
/// 飞牛映射 proxy / 服务端会话 HLS 时间；Emby 映射 `PlaySessionId`，后续用于
/// progress / stopped check-in 与转码停止。第一阶段只建模型，不调度生命周期。
class MediaPlaybackSession {
  final String id;
  final bool serverManaged;
  final bool requiresStop;
  final int hlsTimeSeconds;

  const MediaPlaybackSession({
    this.id = '',
    this.serverManaged = false,
    this.requiresStop = false,
    this.hlsTimeSeconds = 0,
  });
}

/// 播放解析结果：后端中立的播放事实，非播放器 load 参数。
/// 后端中立的拖动 seek 预览缩略图：某一播放位置对应一张缩略图直链。
///
/// 来源因后端而异（Emby 用章节图，未来可扩展 BIF/瓦片），公共层只表达「位置 → 图 URL」
/// 这一中立事实。原生壳拖动 seek 时按目标位置取最近一张显示。[url] 已是带鉴权 query 的
/// 完整直链；过 fnos 中转闸所需的 cookie 由播放 [MediaPlaybackSource.headers] 复用。
class MediaSeekThumbnail {
  const MediaSeekThumbnail({required this.position, required this.url});

  final Duration position;
  final String url;
}

class MediaPlaybackBundle {
  final String itemId;
  final String title;
  final String itemType;
  final String seriesId;
  final String seasonId;
  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String posterUrl;
  final String tmdbId;
  final int durationSeconds;
  final Duration startPosition;
  final MediaPlaybackSource selectedSource;
  final MediaPlaybackQuality? selectedQuality;
  final MediaPlaybackTrack? selectedAudioTrack;
  final MediaPlaybackTrack? selectedSubtitleTrack;
  final List<MediaPlaybackQuality> qualities;
  final List<MediaPlaybackTrack> audioTracks;
  final List<MediaPlaybackTrack> subtitleTracks;
  final MediaPlaybackSession session;

  /// 拖动 seek 预览缩略图（按位置升序）。空 = 该后端/条目无缩略图（飞牛恒空），
  /// 原生壳退回纯时间药丸。
  final List<MediaSeekThumbnail> seekThumbnails;

  /// BIF 预览缩略图直链（Roku BIF 格式单文件，整片按固定间隔抽帧）。非空时原生壳
  /// 优先下载解析 BIF 取帧，未生成（404）/解析失败退回 [seekThumbnails] 章节图。
  /// 空 = 该后端不支持（飞牛恒空）。URL 已带鉴权 query；过 fnos 中转闸的 cookie
  /// 由播放 [MediaPlaybackSource.headers] 复用。
  final String seekThumbnailBifUrl;

  const MediaPlaybackBundle({
    required this.itemId,
    required this.selectedSource,
    required this.session,
    this.seekThumbnails = const <MediaSeekThumbnail>[],
    this.seekThumbnailBifUrl = '',
    this.title = '',
    this.itemType = '',
    this.seriesId = '',
    this.seasonId = '',
    this.seriesTitle = '',
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.posterUrl = '',
    this.tmdbId = '',
    this.durationSeconds = 0,
    this.startPosition = Duration.zero,
    this.selectedQuality,
    this.selectedAudioTrack,
    this.selectedSubtitleTrack,
    this.qualities = const <MediaPlaybackQuality>[],
    this.audioTracks = const <MediaPlaybackTrack>[],
    this.subtitleTracks = const <MediaPlaybackTrack>[],
  });
}
