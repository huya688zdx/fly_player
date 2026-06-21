/// 后端中立的「服务端会话重载意图」模型。
///
/// 表达转码 / 服务端托管态下「只改指定项、保留其余」的一次重载意图——切音轨不动画质、
/// 切画质保留音轨/字幕。它是反向重载路径上 [MediaPlaybackRequest] 的对位物：后者表达
/// 「从头解析一次播放」，本类表达「在已有会话上做最小改动」。
///
/// 约束（见 `docs/superpowers/specs/2026-06-21-public-media-playback-reverse-reload-design.md`）：
/// - 字段名一律中立，禁止出现 `mediaGuid` / `videoGuid` / `audioGuid` / `subtitleGuid` /
///   `proxySession` / `Feiniu` / `Emby`。飞牛 guid 在 player 层桥接器内部映射。
/// - 不承载 `MpvMediaSource`、本地代理、导航等播放器装配信息；「当前会话」由 player 层
///   桥接器从既有 `MpvMediaSource`（loadArgs）读取，不进本模型。
library;

/// 服务端会话重载意图（中立）。
///
/// **null 一律表示「保留当前选择」**，不是「回服务端默认」——对齐 player 层
/// `reloadServerPlaySession` 的真实行为（`request.audioGuid ?? snapshot.audioGuid`、
/// `request.subtitleGuid ?? snapshot.subtitleGuid`）。这保证「切画质时音轨/字幕沿用当前」
/// 这个关键回归点不被测反。
class MediaSessionReloadIntent {
  const MediaSessionReloadIntent({
    this.audioTrackId,
    this.subtitleTrackId,
    this.subtitleDisabled = false,
    this.qualityIndex,
    this.startPosition,
  });

  /// 目标音轨标识；`null` = 保留当前音轨。
  final String? audioTrackId;

  /// 目标字幕标识；`null` 且 [subtitleDisabled] 为 `false` = 保留当前字幕选择。
  ///
  /// 与 [subtitleDisabled] 配合区分三态：非空=切到该字幕轨；空且 disabled=关闭字幕；
  /// 空且非 disabled=保留当前。
  final String? subtitleTrackId;

  /// 是否显式关闭字幕。
  ///
  /// 仅当为 `true` 才表示关闭；为 `false` 时由 [subtitleTrackId] 决定切轨或保留当前。
  final bool subtitleDisabled;

  /// 目标画质在候选列表中的下标；`null` = 保留当前画质。
  ///
  /// 下标越界由 player 层桥接器回落为「保留当前画质」（不崩溃），对齐既有 reload 行为。
  final int? qualityIndex;

  /// 目标起播位置；`null` = 保留当前续播位。
  final Duration? startPosition;
}
