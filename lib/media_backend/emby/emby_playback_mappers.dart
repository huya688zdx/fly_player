import '../playback/media_playback.dart';

/// Emby `MediaSource` / `MediaStreams` → 播放中立模型（直链直播）。
///
/// 与 `emby_media_mappers.dart` 的 `mapEmbySourceVersions`（详情页展示版本）**同源解析**
/// `MediaStreams`，但产出**播放中立** [MediaPlaybackSource] / [MediaPlaybackTrack]，供
/// `EmbyMediaBackend.getPlayback` 装配 [MediaPlaybackBundle]。
///
/// 投递方式固定 [MediaPlaybackDeliveryKind.directLink]：static 直链原文件，mpv 直接吃原始
/// 容器、所有内嵌音轨/字幕在 mpv 侧按轨道号切换，无服务端转码会话（见
/// `docs/superpowers/specs/2026-06-25-emby-playback-design.md` §2）。

/// 选中 `MediaSource` → 中立播放源。视频属性取首条 video `MediaStream`；[url] 为已拼好的
/// 直链（[EmbyApi.buildStreamUrl]），[headers] 为过 fnos 边缘闸的 entry-token cookie（或空）。
MediaPlaybackSource mapEmbyPlaybackSource(
  Map<String, Object?> source, {
  required String url,
  Map<String, String> headers = const <String, String>{},
}) {
  final video = _firstStreamOfType(source, 'video');
  final videoIndex = video == null ? -1 : _asInt(video['Index']);
  return MediaPlaybackSource(
    id: (source['Id'] ?? '').toString(),
    // Emby 无独立视频轨 guid 概念；用视频流容器 index 作中立视频轨标识（缺则空）。
    videoTrackId: videoIndex >= 0 ? '$videoIndex' : '',
    delivery: MediaPlaybackDeliveryKind.directLink,
    url: url,
    headers: headers,
    width: _asInt(video?['Width']),
    height: _asInt(video?['Height']),
    videoCodec: (video?['Codec'] ?? '').toString(),
    videoProfile: (video?['Profile'] ?? '').toString(),
    colorSpace: (video?['ColorSpace'] ?? '').toString(),
    colorTransfer: (video?['ColorTransfer'] ?? '').toString(),
    colorPrimaries: (video?['ColorPrimaries'] ?? '').toString(),
    bitDepth: _asInt(video?['BitDepth']),
    // 直链原文件可靠 seek；不强制本地代理。
    reliableSeek: true,
    forceNativeProxy: false,
  );
}

/// 选中 `MediaSource` → 中立音轨 / 字幕轨候选。
///
/// 轨道 id = 容器内 stream `Index`（与详情页选择器、`Default*StreamIndex` 同口径），index 同值
/// 供桥接器映射 mpv 轨道号。`isDefault` 由 `DefaultAudioStreamIndex` / `DefaultSubtitleStreamIndex`
/// 判定；字幕 `subtitleLocation` 按 `IsExternal` 分内嵌 / 外挂。
({List<MediaPlaybackTrack> audio, List<MediaPlaybackTrack> subtitle})
mapEmbyPlaybackTracks(Map<String, Object?> source) {
  final defaultAudio = _defaultIndex(source['DefaultAudioStreamIndex']);
  final defaultSubtitle = _defaultIndex(source['DefaultSubtitleStreamIndex']);
  final audio = <MediaPlaybackTrack>[];
  final subtitle = <MediaPlaybackTrack>[];
  final rawStreams = source['MediaStreams'];
  if (rawStreams is List) {
    for (final raw in rawStreams) {
      if (raw is! Map) continue;
      final stream = Map<String, Object?>.from(raw);
      final index = _asInt(stream['Index']);
      switch ((stream['Type'] ?? '').toString().toLowerCase()) {
        case 'audio':
          audio.add(
            _track(
              stream,
              index,
              MediaPlaybackTrackKind.audio,
              isDefault: defaultAudio != null && index == defaultAudio,
            ),
          );
          break;
        case 'subtitle':
          subtitle.add(
            _track(
              stream,
              index,
              MediaPlaybackTrackKind.subtitle,
              isDefault: defaultSubtitle != null && index == defaultSubtitle,
            ),
          );
          break;
      }
    }
  }
  return (audio: audio, subtitle: subtitle);
}

/// 选中 `MediaSource` 默认音轨 / 字幕的 stream Index 字符串（喂 selectPlaybackTrack 的
/// fallbackTrackId）；无 / 关闭（负值）返回空。
String embyDefaultAudioId(Map<String, Object?> source) =>
    _defaultIdString(source['DefaultAudioStreamIndex']);

String embyDefaultSubtitleId(Map<String, Object?> source) =>
    _defaultIdString(source['DefaultSubtitleStreamIndex']);

MediaPlaybackTrack _track(
  Map<String, Object?> stream,
  int index,
  MediaPlaybackTrackKind kind, {
  required bool isDefault,
}) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final language = (stream['Language'] ?? '').toString().trim();
  final title = (stream['Title'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim();
  final label = display.isNotEmpty
      ? display
      : <String>[
          if (language.isNotEmpty) language,
          if (title.isNotEmpty) title,
          if (codec.isNotEmpty) codec.toUpperCase(),
        ].join(' ').trim();
  final external = stream['IsExternal'] == true;
  return MediaPlaybackTrack(
    id: '$index',
    kind: kind,
    index: index,
    label: label.isNotEmpty ? label : '#$index',
    language: language,
    codec: codec,
    title: title,
    isDefault: isDefault,
    subtitleLocation: kind == MediaPlaybackTrackKind.subtitle
        ? (external
              ? MediaSubtitleLocation.external
              : MediaSubtitleLocation.embedded)
        : null,
  );
}

Map<String, Object?>? _firstStreamOfType(
  Map<String, Object?> source,
  String type,
) {
  final rawStreams = source['MediaStreams'];
  if (rawStreams is! List) return null;
  for (final raw in rawStreams) {
    if (raw is! Map) continue;
    final stream = Map<String, Object?>.from(raw);
    if ((stream['Type'] ?? '').toString().toLowerCase() == type) return stream;
  }
  return null;
}

/// `Default*StreamIndex` → int；缺失 / 负值（无 / 关闭）返回 null。
int? _defaultIndex(Object? value) {
  final index = value is int ? value : int.tryParse('${value ?? ''}');
  if (index == null || index < 0) return null;
  return index;
}

String _defaultIdString(Object? value) {
  final index = _defaultIndex(value);
  return index == null ? '' : '$index';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
