class MediaLibraryItem {
  final String guid;
  final String title;
  final String tvTitle;
  final String type;
  final String poster;
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
  final String ancestorGuid;
  final String ancestorName;
  final List<String> resolutions;

  MediaLibraryItem({
    required this.guid,
    required this.title,
    required this.tvTitle,
    required this.type,
    required this.poster,
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
    required this.ancestorGuid,
    required this.ancestorName,
    this.resolutions = const [],
  });

  factory MediaLibraryItem.fromJson(Map<String, dynamic> json) {
    final stream = json['media_stream'];
    final rawResolutions = stream is Map<String, dynamic>
        ? stream['resolutions']
        : null;

    return MediaLibraryItem(
      guid: (json['guid'] ?? '').toString(),
      title: (json['title'] ?? 'Unknown').toString(),
      tvTitle: (json['tv_title'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      poster: (json['poster'] ?? '').toString(),
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
      ancestorGuid: (json['ancestor_guid'] ?? '').toString(),
      ancestorName: (json['ancestor_name'] ?? '').toString(),
      resolutions: rawResolutions is List
          ? rawResolutions.map((e) => e.toString()).toList()
          : const [],
    );
  }

  String get displayTitle => tvTitle.trim().isNotEmpty ? tvTitle : title;
}
