import '../media_image_ref.dart';

/// 剧集详情页的选集列表条目。后端中立，只承载选集所需的展示信息。
class MediaEpisodeSummary {
  final String id;
  final String title;
  final int seasonNumber;
  final int episodeNumber;
  final String overview;
  final String airDate;
  final int durationSeconds;

  /// 已看展示态快照。
  final bool watched;

  /// 续播位置（秒）。
  final int resumePositionSeconds;
  final MediaImageRef primaryImage;

  /// 清晰度角标（例如 `1080p` / `4K`）；后端未提供时为空。
  final List<String> resolutions;

  const MediaEpisodeSummary({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.primaryImage,
    this.overview = '',
    this.airDate = '',
    this.durationSeconds = 0,
    this.watched = false,
    this.resumePositionSeconds = 0,
    this.resolutions = const <String>[],
  });
}
