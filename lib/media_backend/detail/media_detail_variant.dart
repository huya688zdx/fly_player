import 'media_source_info.dart';

/// 「查看全部」媒体明细页的一张卡片：[header] 为卡片标题行（如 `4K HEVC HDR`），
/// [fields] 为逐字段明细（枚举键 + 已格式化值，标签由 UI 用 l10n 渲染）。
class MediaInfoCard {
  const MediaInfoCard({required this.header, required this.fields});

  final String header;
  final List<MediaInfoField> fields;
}

/// 「查看全部」媒体明细页的后端中立数据——一个可切换的版本（飞牛多清晰度 / Emby 多源）。
///
/// 飞牛与 Emby 各自把自家轨道数据格式化成同一组 [MediaInfoCard]，喂给同一个
/// `MediaDetailOverlayPage` 渲染，从而视觉统一、格式化逻辑各归各家（与 `VideoInfoSection`
/// 同款抽象）。文件信息不在此页——飞牛/Emby 都走详情主页独立的 `FileInfoSection`。
/// 飞牛映射在 `mapFeiniuMediaDetailVariant`（lib/media_backend/feiniu/），不在本模型上。
class MediaDetailVariant {
  const MediaDetailVariant({
    required this.key,
    required this.title,
    this.video,
    this.audios = const <MediaInfoCard>[],
    this.subtitles = const <MediaInfoCard>[],
  });

  final String key;
  final String title;
  final MediaInfoCard? video;
  final List<MediaInfoCard> audios;
  final List<MediaInfoCard> subtitles;

  /// Emby 等公共后端：从中立 [MediaSourceInfo] 构建（明细行由映射层在 [MediaSourceStream.fields]
  /// 备好）。文件信息走详情主页独立的 `FileInfoSection`（与飞牛同），不放进本 overlay。
  factory MediaDetailVariant.fromSource({
    required String key,
    required String title,
    required MediaSourceInfo info,
  }) {
    MediaInfoCard cardOf(MediaSourceStream s) =>
        MediaInfoCard(header: s.label, fields: s.fields);
    final videoStreams = info.videoStreams;
    return MediaDetailVariant(
      key: key,
      title: title,
      video: videoStreams.isEmpty ? null : cardOf(videoStreams.first),
      audios: info.audioStreams.map(cardOf).toList(growable: false),
      subtitles: info.subtitleStreams.map(cardOf).toList(growable: false),
    );
  }
}
