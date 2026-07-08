class MediaLibraryItem {
  final String guid;
  final String title;
  final String tvTitle;
  final String type;
  final String poster;
  final int posterWidth;
  final int posterHeight;
  final List<String> posterList;
  final String releaseDate;
  final String firstAirDate;
  final String lastAirDate;
  final String voteAverage;
  final String overview;
  final int watched;
  final int watchedTs;
  final int ts;
  final int duration;
  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final int localNumberOfSeasons;
  final int localNumberOfEpisodes;
  final int numberOfItem;
  final String parentGuid;
  final String parentTitle;
  final String ancestorGuid;
  final String ancestorName;
  final String path;
  final List<String> resolutions;

  MediaLibraryItem({
    required this.guid,
    required this.title,
    required this.tvTitle,
    required this.type,
    required this.poster,
    this.posterWidth = 0,
    this.posterHeight = 0,
    this.posterList = const <String>[],
    required this.releaseDate,
    required this.firstAirDate,
    required this.lastAirDate,
    required this.voteAverage,
    required this.overview,
    required this.watched,
    required this.watchedTs,
    required this.ts,
    required this.duration,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.localNumberOfSeasons,
    required this.localNumberOfEpisodes,
    this.numberOfItem = 0,
    required this.parentGuid,
    required this.parentTitle,
    required this.ancestorGuid,
    required this.ancestorName,
    required this.path,
    this.resolutions = const <String>[],
  });

  factory MediaLibraryItem.fromJson(Map<String, dynamic> json) {
    final stream = json['media_stream'];
    final rawResolutions = stream is Map<String, dynamic>
        ? stream['resolutions']
        : null;
    final rawPosterList = json['poster_list'];
    final posterList = rawPosterList is List
        ? rawPosterList.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    final poster = (json['poster'] ?? json['posters'] ?? '').toString().trim();
    final resolvedPoster = poster.isNotEmpty
        ? poster
        : (posterList.isNotEmpty ? posterList.first : '');

    return MediaLibraryItem(
      guid: (json['guid'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      tvTitle: (json['tv_title'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      poster: resolvedPoster,
      posterWidth: (json['poster_width'] is int)
          ? json['poster_width'] as int
          : int.tryParse('${json['poster_width']}') ?? 0,
      posterHeight: (json['poster_height'] is int)
          ? json['poster_height'] as int
          : int.tryParse('${json['poster_height']}') ?? 0,
      posterList: posterList,
      releaseDate: (json['release_date'] ?? json['air_date'] ?? '').toString(),
      firstAirDate: (json['first_air_date'] ?? '').toString(),
      lastAirDate: (json['last_air_date'] ?? '').toString(),
      voteAverage: (json['vote_average'] ?? '').toString(),
      overview: (json['overview'] ?? '').toString(),
      watched: (json['watched'] is int)
          ? json['watched'] as int
          : int.tryParse('${json['watched']}') ?? 0,
      watchedTs: (json['watched_ts'] is int)
          ? json['watched_ts'] as int
          : int.tryParse('${json['watched_ts']}') ?? 0,
      ts: (json['ts'] is int)
          ? json['ts'] as int
          : int.tryParse('${json['ts']}') ?? 0,
      duration: (json['duration'] is int)
          ? json['duration'] as int
          : int.tryParse('${json['duration']}') ?? 0,
      seasonNumber: (json['season_number'] is int)
          ? json['season_number'] as int
          : int.tryParse('${json['season_number']}') ?? 0,
      episodeNumber: (json['episode_number'] is int)
          ? json['episode_number'] as int
          : int.tryParse('${json['episode_number']}') ?? 0,
      numberOfSeasons: (json['number_of_seasons'] is int)
          ? json['number_of_seasons'] as int
          : int.tryParse('${json['number_of_seasons']}') ?? 0,
      numberOfEpisodes: (json['number_of_episodes'] is int)
          ? json['number_of_episodes'] as int
          : int.tryParse('${json['number_of_episodes']}') ?? 0,
      localNumberOfSeasons: (json['local_number_of_seasons'] is int)
          ? json['local_number_of_seasons'] as int
          : int.tryParse('${json['local_number_of_seasons']}') ?? 0,
      localNumberOfEpisodes: (json['local_number_of_episodes'] is int)
          ? json['local_number_of_episodes'] as int
          : int.tryParse('${json['local_number_of_episodes']}') ?? 0,
      numberOfItem: (json['number_of_item'] is int)
          ? json['number_of_item'] as int
          : int.tryParse('${json['number_of_item']}') ?? 0,
      parentGuid: (json['parent_guid'] ?? '').toString(),
      parentTitle: (json['parent_title'] ?? '').toString(),
      ancestorGuid: (json['ancestor_guid'] ?? '').toString(),
      ancestorName: (json['ancestor_name'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      resolutions: rawResolutions is List
          ? rawResolutions.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'guid': guid,
      'title': title,
      'tv_title': tvTitle,
      'type': type,
      'poster': poster,
      'poster_width': posterWidth,
      'poster_height': posterHeight,
      'poster_list': posterList,
      'release_date': releaseDate,
      'first_air_date': firstAirDate,
      'last_air_date': lastAirDate,
      'vote_average': voteAverage,
      'overview': overview,
      'watched': watched,
      'watched_ts': watchedTs,
      'ts': ts,
      'duration': duration,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'local_number_of_seasons': localNumberOfSeasons,
      'local_number_of_episodes': localNumberOfEpisodes,
      'number_of_item': numberOfItem,
      'parent_guid': parentGuid,
      'parent_title': parentTitle,
      'ancestor_guid': ancestorGuid,
      'ancestor_name': ancestorName,
      'path': path,
      'media_stream': <String, dynamic>{'resolutions': resolutions},
    };
  }

  String get displayTitle => tvTitle.trim().isNotEmpty ? tvTitle : title;

  bool get hasPosterSize => posterWidth > 0 && posterHeight > 0;

  bool get isLandscapePoster => hasPosterSize && posterWidth >= posterHeight;

  MediaLibraryItem copyWith({
    String? guid,
    String? title,
    String? tvTitle,
    String? type,
    String? poster,
    int? posterWidth,
    int? posterHeight,
    List<String>? posterList,
    String? releaseDate,
    String? firstAirDate,
    String? lastAirDate,
    String? voteAverage,
    String? overview,
    int? watched,
    int? watchedTs,
    int? ts,
    int? duration,
    int? seasonNumber,
    int? episodeNumber,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    int? localNumberOfSeasons,
    int? localNumberOfEpisodes,
    int? numberOfItem,
    String? parentGuid,
    String? parentTitle,
    String? ancestorGuid,
    String? ancestorName,
    String? path,
    List<String>? resolutions,
  }) {
    return MediaLibraryItem(
      guid: guid ?? this.guid,
      title: title ?? this.title,
      tvTitle: tvTitle ?? this.tvTitle,
      type: type ?? this.type,
      poster: poster ?? this.poster,
      posterWidth: posterWidth ?? this.posterWidth,
      posterHeight: posterHeight ?? this.posterHeight,
      posterList: posterList ?? this.posterList,
      releaseDate: releaseDate ?? this.releaseDate,
      firstAirDate: firstAirDate ?? this.firstAirDate,
      lastAirDate: lastAirDate ?? this.lastAirDate,
      voteAverage: voteAverage ?? this.voteAverage,
      overview: overview ?? this.overview,
      watched: watched ?? this.watched,
      watchedTs: watchedTs ?? this.watchedTs,
      ts: ts ?? this.ts,
      duration: duration ?? this.duration,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
      localNumberOfSeasons: localNumberOfSeasons ?? this.localNumberOfSeasons,
      localNumberOfEpisodes:
          localNumberOfEpisodes ?? this.localNumberOfEpisodes,
      numberOfItem: numberOfItem ?? this.numberOfItem,
      parentGuid: parentGuid ?? this.parentGuid,
      parentTitle: parentTitle ?? this.parentTitle,
      ancestorGuid: ancestorGuid ?? this.ancestorGuid,
      ancestorName: ancestorName ?? this.ancestorName,
      path: path ?? this.path,
      resolutions: resolutions ?? this.resolutions,
    );
  }
}
