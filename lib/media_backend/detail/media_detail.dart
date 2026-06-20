import '../media_image_ref.dart';

/// 后端中立的详情页展示模型。
///
/// 只承载详情页**展示**真正需要的信息（标题 / 简介 / 图片 / 评分 / 年份时长 /
/// 季集编号 / 题材地区 / 角标 / 已看收藏续播快照 / 外部 ID / 演职员），全部为通用
/// 概念，Emby 等后端同样具备，由各自适配层映射进来。
///
/// **不承载播放接线**：媒体 / 视频 / 音轨 / 字幕句柄、是否可播、播放配置（片头片尾）、
/// 轨道清单等飞牛 / Emby 私有的播放信息留在页面侧（Phase 6），不进本模型。
class MediaDetail {
  final String id;

  /// 稳定类型枚举（Movie / TV / Episode / ...），供 UI 路由与展示分支使用。
  final String type;

  final String title;

  /// 副标题（剧集名等）。为空时 [displayTitle] 回退到 [title]。
  final String secondaryTitle;

  /// 所属父级标题（季 / 剧集名）。
  final String parentTitle;

  final String overview;

  final MediaImageRef primaryImage;
  final MediaImageRef backdropImage;
  final MediaImageRef logoImage;

  /// 评分文本，保留后端原始展示形式（飞牛为字符串，空表示无评分）。
  final String rating;

  final String releaseDate;
  final String airDate;

  /// 单集 / 影片时长（分钟）。
  final int runtimeMinutes;

  /// 总时长（秒）。
  final int durationSeconds;

  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final int localNumberOfSeasons;
  final int localNumberOfEpisodes;

  /// 已翻好的题材名（适配层用后端字典翻译，UI 直接显示）。
  final List<String> genreLabels;

  /// 已翻好的地区名（适配层用 ISO3166 字典翻译，UI 直接显示）。
  final List<String> regionLabels;

  final List<String> resolutions;
  final List<String> audioTypes;
  final List<String> colorRanges;

  /// 已看 / 收藏的**展示态快照**，供首屏渲染；写回仍走后端，本地切换用 [copyWith]。
  final bool watched;
  final bool favorite;

  /// 续播位置（秒），用于"继续观看"展示。
  final int resumePositionSeconds;

  final MediaExternalIds externalIds;
  final List<MediaDetailPerson> cast;
  final List<MediaDetailPerson> crew;

  const MediaDetail({
    required this.id,
    required this.type,
    required this.title,
    required this.primaryImage,
    this.secondaryTitle = '',
    this.parentTitle = '',
    this.overview = '',
    this.backdropImage = MediaImageRef.empty,
    this.logoImage = MediaImageRef.empty,
    this.rating = '',
    this.releaseDate = '',
    this.airDate = '',
    this.runtimeMinutes = 0,
    this.durationSeconds = 0,
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.localNumberOfSeasons = 0,
    this.localNumberOfEpisodes = 0,
    this.genreLabels = const <String>[],
    this.regionLabels = const <String>[],
    this.resolutions = const <String>[],
    this.audioTypes = const <String>[],
    this.colorRanges = const <String>[],
    this.watched = false,
    this.favorite = false,
    this.resumePositionSeconds = 0,
    this.externalIds = const MediaExternalIds(),
    this.cast = const <MediaDetailPerson>[],
    this.crew = const <MediaDetailPerson>[],
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

  MediaDetail copyWith({
    String? id,
    String? type,
    String? title,
    String? secondaryTitle,
    String? parentTitle,
    String? overview,
    MediaImageRef? primaryImage,
    MediaImageRef? backdropImage,
    MediaImageRef? logoImage,
    String? rating,
    String? releaseDate,
    String? airDate,
    int? runtimeMinutes,
    int? durationSeconds,
    int? seasonNumber,
    int? episodeNumber,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    int? localNumberOfSeasons,
    int? localNumberOfEpisodes,
    List<String>? genreLabels,
    List<String>? regionLabels,
    List<String>? resolutions,
    List<String>? audioTypes,
    List<String>? colorRanges,
    bool? watched,
    bool? favorite,
    int? resumePositionSeconds,
    MediaExternalIds? externalIds,
    List<MediaDetailPerson>? cast,
    List<MediaDetailPerson>? crew,
  }) {
    return MediaDetail(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      secondaryTitle: secondaryTitle ?? this.secondaryTitle,
      parentTitle: parentTitle ?? this.parentTitle,
      overview: overview ?? this.overview,
      primaryImage: primaryImage ?? this.primaryImage,
      backdropImage: backdropImage ?? this.backdropImage,
      logoImage: logoImage ?? this.logoImage,
      rating: rating ?? this.rating,
      releaseDate: releaseDate ?? this.releaseDate,
      airDate: airDate ?? this.airDate,
      runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
      localNumberOfSeasons: localNumberOfSeasons ?? this.localNumberOfSeasons,
      localNumberOfEpisodes:
          localNumberOfEpisodes ?? this.localNumberOfEpisodes,
      genreLabels: genreLabels ?? this.genreLabels,
      regionLabels: regionLabels ?? this.regionLabels,
      resolutions: resolutions ?? this.resolutions,
      audioTypes: audioTypes ?? this.audioTypes,
      colorRanges: colorRanges ?? this.colorRanges,
      watched: watched ?? this.watched,
      favorite: favorite ?? this.favorite,
      resumePositionSeconds:
          resumePositionSeconds ?? this.resumePositionSeconds,
      externalIds: externalIds ?? this.externalIds,
      cast: cast ?? this.cast,
      crew: crew ?? this.crew,
    );
  }
}

/// 外部数据库 ID（TMDB / IMDb 等）。
class MediaExternalIds {
  final String tmdbId;
  final String imdbId;

  const MediaExternalIds({this.tmdbId = '', this.imdbId = ''});
}

/// 演职员条目。[department] 区分 cast / crew，[role] 为角色名或职务。
class MediaDetailPerson {
  final String id;
  final String name;
  final String role;
  final String department;
  final MediaImageRef avatar;

  const MediaDetailPerson({
    required this.id,
    required this.name,
    this.role = '',
    this.department = '',
    this.avatar = MediaImageRef.empty,
  });
}
