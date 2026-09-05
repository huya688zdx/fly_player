import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../playback/media_playback.dart';

/// 飞牛播放结构到公共播放模型的映射。
///
/// **只在适配层内部接触飞牛字段**（`mediaGuid` / `videoGuid` / `audioGuid` /
/// `subtitleGuid`），对外只暴露中立命名的 [MediaPlaybackSource] / [MediaPlaybackQuality] /
/// [MediaPlaybackTrack]。不导入 Flutter widget、provider、navigator、播放器页面。

/// 把飞牛画质候选映射为公共画质列表。
///
/// 飞牛 `media_guid` 进中立 `id` / `sourceId`，`video_guid` 进 `videoTrackId`，
/// `source` 枚举映射为公共投递方式。
List<MediaPlaybackQuality> mapFeiniuPlaybackQualities(
  List<PlaybackQualityOption> qualities,
) {
  return qualities
      .map(
        (quality) => MediaPlaybackQuality(
          id: quality.mediaGuid,
          sourceId: quality.mediaGuid,
          videoTrackId: quality.videoGuid,
          label: quality.resolution,
          resolution: quality.resolution,
          bitrate: quality.bitrate,
          isDefault: quality.isDefault == 1,
          delivery: _deliveryForSource(quality.source),
          directLinkIndex: quality.directLinkQualityIndex,
        ),
      )
      .toList(growable: false);
}

/// 把飞牛音轨候选映射为公共音轨列表。
///
/// 飞牛 `guid` 进中立 `id`（不泄漏 `audioGuid` 命名）。
List<MediaPlaybackTrack> mapFeiniuAudioTracks(List<AudioTrackOption> tracks) {
  return tracks
      .map(
        (track) => MediaPlaybackTrack(
          id: track.guid,
          kind: MediaPlaybackTrackKind.audio,
          index: track.index,
          label: track.displayLabel,
          language: track.language,
          codec: track.codecName,
          title: track.title,
          isDefault: track.isDefault == 1,
        ),
      )
      .toList(growable: false);
}

/// 把飞牛字幕候选映射为公共字幕列表。
///
/// 飞牛 `guid` 进中立 `id`（不泄漏 `subtitleGuid` 命名）。字幕位置按 `is_external` /
/// `extra_file` 两个标志判定，复刻播放器对字幕三态的处理。
List<MediaPlaybackTrack> mapFeiniuSubtitleTracks(
  List<SubtitleTrackOption> tracks,
) {
  return tracks
      .map(
        (track) => MediaPlaybackTrack(
          id: track.guid,
          kind: MediaPlaybackTrackKind.subtitle,
          index: track.index,
          label: track.displayLabel,
          language: track.language,
          codec: track.codecName.isNotEmpty ? track.codecName : track.format,
          title: track.title,
          isDefault: track.isDefault == 1,
          subtitleLocation: _subtitleLocation(track),
        ),
      )
      .toList(growable: false);
}

/// 装配选中的公共播放源。
///
/// `headers` 由 [playbackStream] 的 `responseHeaders`（Cookie / User-Agent）派生，
/// 显式传入的 [headers] 覆盖派生值；`responseHeaders` 无 UA 时回退 `requestUserAgent`。
/// 视频编码/色彩/尺寸元数据取自 [playbackStream] 的 `videoStream`。
/// 投递方式取自 [selectedQuality]，为空回退 [MediaPlaybackDeliveryKind.original]。
MediaPlaybackSource mapFeiniuPlaybackSource({
  required String sourceId,
  required String videoTrackId,
  required PlaybackStreamData playbackStream,
  required PlaybackQualityOption? selectedQuality,
  required String candidateUrl,
  required Map<String, String> headers,
}) {
  final video = playbackStream.videoStream;
  final mergedHeaders = <String, String>{};
  final cookie = playbackStream.responseHeaders.cookieHeader;
  if (cookie.isNotEmpty) {
    mergedHeaders['Cookie'] = cookie;
  }
  final userAgent = playbackStream.responseHeaders.primaryUserAgent.isNotEmpty
      ? playbackStream.responseHeaders.primaryUserAgent
      : playbackStream.requestUserAgent;
  if (userAgent.isNotEmpty) {
    mergedHeaders['User-Agent'] = userAgent;
  }
  // 显式 headers 优先（直链 target headers 等）。
  mergedHeaders.addAll(headers);

  return MediaPlaybackSource(
    id: sourceId,
    videoTrackId: videoTrackId,
    delivery: _deliveryForSource(selectedQuality?.source),
    url: candidateUrl,
    headers: mergedHeaders,
    width: video?.width ?? 0,
    height: video?.height ?? 0,
    videoCodec: video?.codecName ?? '',
    videoProfile: video?.profile ?? '',
    colorSpace: video?.colorSpace ?? '',
    colorTransfer: video?.colorTransfer ?? '',
    colorPrimaries: video?.colorPrimaries ?? '',
    bitDepth: video?.bitDepth ?? 0,
  );
}

MediaPlaybackDeliveryKind _deliveryForSource(PlaybackQualitySource? source) {
  switch (source) {
    case PlaybackQualitySource.directLink:
      return MediaPlaybackDeliveryKind.directLink;
    case PlaybackQualitySource.serverSession:
      return MediaPlaybackDeliveryKind.serverSession;
    case PlaybackQualitySource.originalProxy:
    case null:
      return MediaPlaybackDeliveryKind.original;
  }
}

/// 字幕位置：
/// - 两标志皆 0 → 内嵌（embedded）；
/// - `isExternal` 与 `extraFile` 同时为 1 → 设备本地（local），复刻
///   `local_subtitle_bundle` / `player_subtitle_controller` 对本地字幕的双标志签名；
/// - 仅其一为 1 → 服务端外挂（external）。
MediaSubtitleLocation _subtitleLocation(SubtitleTrackOption track) {
  final isExternal = track.isExternal == 1;
  final isExtraFile = track.extraFile == 1;
  if (isExternal && isExtraFile) {
    return MediaSubtitleLocation.local;
  }
  if (isExternal || isExtraFile) {
    return MediaSubtitleLocation.external;
  }
  return MediaSubtitleLocation.embedded;
}
