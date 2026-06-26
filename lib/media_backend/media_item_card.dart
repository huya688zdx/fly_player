import 'media_image_ref.dart';

/// 卡片 / 列表 / 搜索结果统一的条目展示模型。
///
/// 覆盖首页、搜索页、分类页卡片所需的全部展示字段，全部为后端中立的通用概念
/// （副标题、评分、季/集编号与总数、本地计数、年份区间、作品数、海报尺寸、清晰度），
/// Emby 等后端同样具备，由各自适配层负责把私有字段映射进来。默认空 / 0 表示当前
/// 后端未提供该信息。**不照搬飞牛或 Emby 的原始结构，也不承载滤镜/句柄等私有概念。**
class MediaItemCard {
  final String id;
  final String title;

  /// 副标题（剧集名等）。为空时 [displayTitle] 回退到 [title]。
  final String secondaryTitle;
  final String type;

  /// 单集所属系列的 guid（Emby `SeriesId`）。供「继续观看」单集卡片点进时定位系列详情
  /// （单集本身无选集，须用系列 guid 打开 TV 详情）。非单集 / 后端未提供时为空。
  final String seriesId;

  final MediaImageRef primaryImage;

  /// 多候选封面（飞牛 `poster_list`）。卡片按顺序择优，为空回退 [primaryImage]。
  final List<MediaImageRef> posters;
  final MediaImageRef backdropImage;

  final int durationSeconds;
  final bool watched;

  /// 续看进度位（秒），用于「继续观看」卡片底部进度条。0 表示无进度 / 后端未提供。
  final int resumePositionSeconds;

  /// 评分文本，保留后端原始展示形式（飞牛为字符串，空表示无评分）。
  final String rating;

  /// 上映 / 首播日期文本。
  final String releaseDate;

  /// 剧集首播 / 完结日期，用于年份区间（例如 `2019-2022`）。
  final String firstAirDate;
  final String lastAirDate;

  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;

  /// 本地已入库的季 / 集计数，展示角标时优先于 [numberOfSeasons] / [numberOfEpisodes]。
  final int localNumberOfSeasons;
  final int localNumberOfEpisodes;

  /// person 条目的作品数（"共 N 个作品"）。
  final int numberOfItem;

  /// 海报像素尺寸，用于决定横 / 竖版排版；为 0 表示后端未提供。
  final int posterWidth;
  final int posterHeight;

  /// 清晰度角标（例如 `4K` / `1080p`）。
  final List<String> resolutions;

  const MediaItemCard({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
    this.secondaryTitle = '',
    this.seriesId = '',
    this.posters = const <MediaImageRef>[],
    this.backdropImage = MediaImageRef.empty,
    this.durationSeconds = 0,
    this.watched = false,
    this.resumePositionSeconds = 0,
    this.rating = '',
    this.releaseDate = '',
    this.firstAirDate = '',
    this.lastAirDate = '',
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.localNumberOfSeasons = 0,
    this.localNumberOfEpisodes = 0,
    this.numberOfItem = 0,
    this.posterWidth = 0,
    this.posterHeight = 0,
    this.resolutions = const <String>[],
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

  MediaItemCard copyWith({
    String? id,
    String? title,
    String? secondaryTitle,
    String? type,
    String? seriesId,
    MediaImageRef? primaryImage,
    List<MediaImageRef>? posters,
    MediaImageRef? backdropImage,
    int? durationSeconds,
    bool? watched,
    int? resumePositionSeconds,
    String? rating,
    String? releaseDate,
    String? firstAirDate,
    String? lastAirDate,
    int? seasonNumber,
    int? episodeNumber,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    int? localNumberOfSeasons,
    int? localNumberOfEpisodes,
    int? numberOfItem,
    int? posterWidth,
    int? posterHeight,
    List<String>? resolutions,
  }) {
    return MediaItemCard(
      id: id ?? this.id,
      title: title ?? this.title,
      secondaryTitle: secondaryTitle ?? this.secondaryTitle,
      type: type ?? this.type,
      seriesId: seriesId ?? this.seriesId,
      primaryImage: primaryImage ?? this.primaryImage,
      posters: posters ?? this.posters,
      backdropImage: backdropImage ?? this.backdropImage,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      watched: watched ?? this.watched,
      resumePositionSeconds:
          resumePositionSeconds ?? this.resumePositionSeconds,
      rating: rating ?? this.rating,
      releaseDate: releaseDate ?? this.releaseDate,
      firstAirDate: firstAirDate ?? this.firstAirDate,
      lastAirDate: lastAirDate ?? this.lastAirDate,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
      localNumberOfSeasons: localNumberOfSeasons ?? this.localNumberOfSeasons,
      localNumberOfEpisodes:
          localNumberOfEpisodes ?? this.localNumberOfEpisodes,
      numberOfItem: numberOfItem ?? this.numberOfItem,
      posterWidth: posterWidth ?? this.posterWidth,
      posterHeight: posterHeight ?? this.posterHeight,
      resolutions: resolutions ?? this.resolutions,
    );
  }
}
