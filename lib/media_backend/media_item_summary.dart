import 'media_image_ref.dart';

/// 卡片 / 列表 / 搜索结果需要的最小条目信息。
///
/// 只表达前端真正要展示的字段，不照搬飞牛或 Emby 的原始结构。下面这些展示字段
/// 都是后端中立的通用概念（副标题、评分、季/集编号与总数、上映日期、海报尺寸），
/// Emby 等后端同样具备，由各自适配层负责把私有字段映射进来。默认空 / 0 表示
/// 当前后端未提供该信息。
class MediaItemSummary {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;
  final MediaImageRef backdropImage;
  final int durationSeconds;
  final bool watched;

  /// 副标题（剧集名等）。为空时 [displayTitle] 回退到 [title]。
  final String secondaryTitle;

  /// 评分文本，保留后端原始展示形式（飞牛为字符串，空表示无评分）。
  final String rating;

  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;

  /// 上映 / 首播日期文本。
  final String releaseDate;

  /// 海报像素尺寸，用于决定横 / 竖版排版；为 0 表示后端未提供。
  final int posterWidth;
  final int posterHeight;

  const MediaItemSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
    required this.backdropImage,
    required this.durationSeconds,
    required this.watched,
    this.secondaryTitle = '',
    this.rating = '',
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.releaseDate = '',
    this.posterWidth = 0,
    this.posterHeight = 0,
  });

  /// 优先副标题，其次主标题，二者皆空时回退占位（复刻飞牛 displayTitle 语义）。
  String get displayTitle {
    final secondary = secondaryTitle.trim();
    if (secondary.isNotEmpty) {
      return secondary;
    }
    final value = title.trim();
    return value.isEmpty ? 'Unknown' : value;
  }

  bool get hasPosterSize => posterWidth > 0 && posterHeight > 0;

  bool get isLandscapePoster => hasPosterSize && posterWidth >= posterHeight;
}
