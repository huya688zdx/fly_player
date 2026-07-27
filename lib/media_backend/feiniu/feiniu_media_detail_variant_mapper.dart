import '../../l10n/generated/app_localizations.dart';
import '../../models/stream_track_data.dart';
import '../../utils/media_language_mapper.dart';
import '../detail/media_detail_variant.dart';
import '../detail/media_source_info.dart';

/// 飞牛：当前清晰度的视频 / 音频 / 字幕轨道 DTO → 中立 [MediaDetailVariant]
/// （行序与文案逐字保持原 `_VideoCard`/`_AudioCard`/`_SubtitleCard`）。
///
/// 原为 `MediaDetailVariant.fromFeiniu` 工厂暴露在 pages 层，A-037/F-003 迁到
/// 飞牛后端侧：pages / 公共模型不再携带飞牛 DTO 映射。
MediaDetailVariant mapFeiniuMediaDetailVariant({
  required String key,
  required String title,
  required AppLocalizations l10n,
  VideoStreamInfo? video,
  List<AudioTrackOption> audios = const <AudioTrackOption>[],
  List<SubtitleTrackOption> subtitles = const <SubtitleTrackOption>[],
}) {
  return MediaDetailVariant(
    key: key,
    title: title,
    video: video == null ? null : _feiniuVideoCard(video),
    audios: audios.map(_feiniuAudioCard).toList(growable: false),
    subtitles: subtitles
        .map((s) => _feiniuSubtitleCard(s, l10n))
        .toList(growable: false),
  );
}

MediaInfoCard _feiniuVideoCard(VideoStreamInfo video) {
  final headerParts = <String>[
    if (video.resolutionType.trim().isNotEmpty) video.resolutionType,
    if (video.codecName.trim().isNotEmpty) video.codecName.toUpperCase(),
    if (video.colorRangeType.trim().isNotEmpty) video.colorRangeType,
  ];
  return MediaInfoCard(
    header: headerParts.join(' '),
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.encoder, video.codecName),
      MediaInfoField(MediaInfoFieldKey.profile, video.profile),
      MediaInfoField(MediaInfoFieldKey.level, video.level),
      MediaInfoField(
        MediaInfoFieldKey.resolution,
        _resolution(video.width, video.height),
      ),
      MediaInfoField(MediaInfoFieldKey.aspectRatio, video.displayAspectRatio),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.interlaced,
        _boolRaw(video.progressive == 1),
      ),
      MediaInfoField(MediaInfoFieldKey.frameRate, video.rFrameRate),
      MediaInfoField(MediaInfoFieldKey.bitrate, _kbps(video.bps)),
      MediaInfoField(MediaInfoFieldKey.range, video.colorRangeType),
      MediaInfoField(MediaInfoFieldKey.colorPrimaries, video.colorPrimaries),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.colorSpace, video.colorSpace),
      MediaInfoField(MediaInfoFieldKey.colorTransfer, video.colorTransfer),
      MediaInfoField(
        MediaInfoFieldKey.bitDepth,
        video.bitDepth > 0 ? '${video.bitDepth} bit' : '',
      ),
      MediaInfoField(MediaInfoFieldKey.pixelFormat, video.pixFmt),
      MediaInfoField(
        MediaInfoFieldKey.refs,
        video.refs > 0 ? '${video.refs}' : '',
      ),
    ],
  );
}

MediaInfoCard _feiniuAudioCard(AudioTrackOption audio) {
  final lan = MediaLanguageMapper.languageName(audio.language);
  final headerParts = <String>[
    if (lan.isNotEmpty) lan,
    if (audio.codecName.trim().isNotEmpty) audio.codecName,
    if (audio.channelLayout.trim().isNotEmpty) audio.channelLayout,
  ];
  return MediaInfoCard(
    header: headerParts.join(' '),
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.language, lan),
      MediaInfoField(MediaInfoFieldKey.encoder, audio.codecName),
      MediaInfoField(MediaInfoFieldKey.profile, audio.profile),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.channels, _channelText(audio.channels)),
      MediaInfoField(
        MediaInfoFieldKey.sampleRate,
        audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : '',
      ),
      MediaInfoField(MediaInfoFieldKey.bitrate, _kbps(audio.bps)),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.layout, audio.channelLayout),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _boolRaw(audio.isDefault == 1),
      ),
    ],
  );
}

MediaInfoCard _feiniuSubtitleCard(
  SubtitleTrackOption subtitle,
  AppLocalizations l10n,
) {
  final lan = MediaLanguageMapper.languageName(subtitle.language);
  final fmt =
      (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
          .trim()
          .toUpperCase();
  final header =
      '${lan.isEmpty ? l10n.mediaDetailsSubtitleSection : lan} ($fmt)';
  return MediaInfoCard(
    header: header,
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.language, lan),
      MediaInfoField(MediaInfoFieldKey.encoder, fmt.toLowerCase()),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _boolRaw(subtitle.isDefault == 1),
      ),
      MediaInfoField(MediaInfoFieldKey.forced, _boolRaw(subtitle.forced == 1)),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.external,
        _boolRaw(subtitle.isExternal == 1),
      ),
    ],
  );
}

String _boolRaw(bool value) => value ? '1' : '0';

String _resolution(int w, int h) {
  if (w <= 0 || h <= 0) return '';
  return '$w * $h';
}

String _kbps(int bps) {
  if (bps <= 0) return '';
  if (bps >= 1000000) return '${(bps / 1000000.0).toStringAsFixed(2)} mbps';
  return '${(bps / 1000.0).toStringAsFixed(0)} kbps';
}

String _channelText(int channels) {
  if (channels <= 0) return '';
  if (channels == 1) return '1 ch';
  if (channels == 2) return '2 ch';
  return '$channels ch';
}
