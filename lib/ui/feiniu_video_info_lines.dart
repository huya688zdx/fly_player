import '../models/stream_track_data.dart';
import '../utils/media_language_mapper.dart';
import '../widgets/detail/video_info_section.dart';

/// 飞牛「视频信息」三行文本的格式化（H-015:原 `VideoInfoLines.fromFeiniu` 工厂,
/// 从共享 UI 组件文件迁到调用方侧,让 [VideoInfoSection] 保持后端中立)。
/// 文案与旧工厂逐字不变;唯一调用方为飞牛详情页。
VideoInfoLines feiniuVideoInfoLines(
  VideoStreamInfo? video,
  AudioTrackOption? audio,
  SubtitleTrackOption? subtitle,
) {
  return VideoInfoLines(
    video: _videoLine(video),
    audio: _audioLine(audio),
    subtitle: _subtitleLine(subtitle),
  );
}

String _videoLine(VideoStreamInfo? video) {
  if (video == null) return '';
  final res = video.resolutionType.trim().isEmpty ? '' : video.resolutionType;
  final codec = video.codecName.trim().isEmpty
      ? ''
      : video.codecName.toUpperCase();
  final mbps = video.bps > 0
      ? '${(video.bps / 1000000.0).toStringAsFixed(2)} mbps'
      : '';
  final bit = video.bitDepth > 0 ? '${video.bitDepth} bit' : '';
  final parts = <String>[
    if (res.isNotEmpty) res,
    if (codec.isNotEmpty) codec,
    if (mbps.isNotEmpty) mbps,
    if (bit.isNotEmpty) bit,
  ];
  return parts.join(' ');
}

String _audioLine(AudioTrackOption? audio) {
  if (audio == null) return '';
  final lan = MediaLanguageMapper.languageName(audio.language);
  final codec = audio.codecName.trim().isEmpty
      ? ''
      : audio.codecName.toUpperCase();
  final ch = audio.channelLayout.trim().isNotEmpty
      ? audio.channelLayout.trim()
      : _channelFromCount(audio.channels);
  final rate = audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : '';
  final parts = <String>[
    if (lan.isNotEmpty) lan,
    if (codec.isNotEmpty) codec,
    if (ch.isNotEmpty) ch,
    if (rate.isNotEmpty) rate,
  ];
  return parts.join('  ');
}

String _subtitleLine(SubtitleTrackOption? subtitle) {
  if (subtitle == null) return '';
  final lan = MediaLanguageMapper.languageName(subtitle.language);
  final fmt =
      (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
          .trim()
          .toUpperCase();
  final parts = <String>[if (lan.isNotEmpty) lan, if (fmt.isNotEmpty) fmt];
  return parts.join('  ');
}

String _channelFromCount(int channels) {
  if (channels == 1) return '1.0ch';
  if (channels == 2) return '2.0ch';
  if (channels == 6) return '5.1ch';
  if (channels == 8) return '7.1ch';
  return channels > 0 ? '$channels ch' : '';
}
