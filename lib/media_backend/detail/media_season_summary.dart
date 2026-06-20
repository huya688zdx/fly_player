import '../media_image_ref.dart';

/// 剧集详情页的季列表条目。后端中立，只承载季选择所需的展示信息。
class MediaSeasonSummary {
  final String id;
  final String title;
  final int seasonNumber;
  final int numberOfEpisodes;

  /// 本地已入库的集计数，展示角标时优先于 [numberOfEpisodes]。
  final int localNumberOfEpisodes;
  final MediaImageRef primaryImage;

  const MediaSeasonSummary({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.primaryImage,
    this.numberOfEpisodes = 0,
    this.localNumberOfEpisodes = 0,
  });
}
