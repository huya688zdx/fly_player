class PlayInfoData {
  final String grandGuid;
  final String type;
  final int ts;
  final String mediaGuid;
  final String videoGuid;
  final String audioGuid;
  final String subtitleGuid;
  final String parentGuid;
  final PlayItem item;
  final PlayConfig? playConfig;

  const PlayInfoData({
    required this.grandGuid,
    required this.type,
    required this.ts,
    required this.mediaGuid,
    required this.videoGuid,
    required this.audioGuid,
    required this.subtitleGuid,
    required this.parentGuid,
    required this.item,
    this.playConfig,
  });

  factory PlayInfoData.fromJson(Map<String, dynamic> json) {
    final itemJson = json['item'];
    if (itemJson is! Map<String, dynamic>) {
      throw Exception('Invalid play info item payload');
    }
    return PlayInfoData(
      grandGuid: (json['grand_guid'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      ts: _asInt(json['ts']),
      mediaGuid: (json['media_guid'] ?? '').toString(),
      videoGuid: (json['video_guid'] ?? '').toString(),
      audioGuid: (json['audio_guid'] ?? '').toString(),
      subtitleGuid: (json['subtitle_guid'] ?? '').toString(),
      parentGuid: (json['parent_guid'] ?? '').toString(),
      item: PlayItem.fromJson(itemJson),
      playConfig: _parsePlayConfig(json['play_config']),
    );
  }

  PlayInfoData copyWith({
    String? grandGuid,
    String? type,
    int? ts,
    String? mediaGuid,
    String? videoGuid,
    String? audioGuid,
    String? subtitleGuid,
    String? parentGuid,
    PlayItem? item,
    PlayConfig? playConfig,
  }) {
    return PlayInfoData(
      grandGuid: grandGuid ?? this.grandGuid,
      type: type ?? this.type,
      ts: ts ?? this.ts,
      mediaGuid: mediaGuid ?? this.mediaGuid,
      videoGuid: videoGuid ?? this.videoGuid,
      audioGuid: audioGuid ?? this.audioGuid,
      subtitleGuid: subtitleGuid ?? this.subtitleGuid,
      parentGuid: parentGuid ?? this.parentGuid,
      item: item ?? this.item,
      playConfig: playConfig ?? this.playConfig,
    );
  }

  bool get isEpisode => type == 'Episode' || item.type == 'Episode';
}

class PlayConfig {
  final String guid;
  final int? skipOpening;
  final int? skipEnding;

  const PlayConfig({
    required this.guid,
    this.skipOpening,
    this.skipEnding,
  });

  factory PlayConfig.fromJson(Map<String, dynamic> json) {
    return PlayConfig(
      guid: (json['guid'] ?? '').toString(),
      skipOpening: _asNullableInt(json['skip_opening']),
      skipEnding: _asNullableInt(json['skip_ending']),
    );
  }

  bool get enabled => skipOpening != null || skipEnding != null;
}

class PlayItem {
  final String guid;
  final String trimId;
  final String type;
  final String title;
  final String tvTitle;
  final String parentTitle;
  final String logos;
  final String posters;
  final String backdrops;
  final String stillPath;
  final String voteAverage;
  final String releaseDate;
  final String airDate;
  final int runtime;
  final int duration;
  final int watchedTs;
  final String overview;
  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int localNumberOfSeasons;
  final int numberOfEpisodes;
  final int localNumberOfEpisodes;
  final List<int> genres;
  final List<String> productionCountries;
  final List<String> resolutions;
  final List<String> audioTypes;
  final List<String> colorRanges;
  final String ancestorName;
  final int canPlay;
  final String playError;
  final int isFavorite;
  final int isWatched;

  const PlayItem({
    required this.guid,
    required this.trimId,
    required this.type,
    required this.title,
    required this.tvTitle,
    required this.parentTitle,
    required this.logos,
    required this.posters,
    required this.backdrops,
    required this.stillPath,
    required this.voteAverage,
    required this.releaseDate,
    required this.airDate,
    required this.runtime,
    required this.duration,
    required this.watchedTs,
    required this.overview,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.numberOfSeasons,
    required this.localNumberOfSeasons,
    required this.numberOfEpisodes,
    required this.localNumberOfEpisodes,
    required this.genres,
    required this.productionCountries,
    required this.resolutions,
    required this.audioTypes,
    required this.colorRanges,
    required this.ancestorName,
    required this.canPlay,
    required this.playError,
    required this.isFavorite,
    required this.isWatched,
  });

  factory PlayItem.fromJson(Map<String, dynamic> json) {
    final stream = json['media_stream'];
    final streamMap = stream is Map<String, dynamic>
        ? stream
        : const <String, dynamic>{};
    return PlayItem(
      guid: (json['guid'] ?? '').toString(),
      trimId: (json['trim_id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      tvTitle: (json['tv_title'] ?? '').toString(),
      parentTitle: (json['parent_title'] ?? '').toString(),
      logos: (json['logos'] ?? '').toString(),
      posters: (json['posters'] ?? '').toString(),
      backdrops: (json['backdrops'] ?? '').toString(),
      stillPath: (json['still_path'] ?? '').toString(),
      voteAverage: (json['vote_average'] ?? '').toString(),
      releaseDate: (json['release_date'] ?? '').toString(),
      airDate: (json['air_date'] ?? '').toString(),
      runtime: _asInt(json['runtime']),
      duration: _asInt(json['duration']),
      watchedTs: _asInt(json['watched_ts']),
      overview: (json['overview'] ?? '').toString(),
      seasonNumber: _asInt(json['season_number']),
      episodeNumber: _asInt(json['episode_number']),
      numberOfSeasons: _asInt(json['number_of_seasons']),
      localNumberOfSeasons: _asInt(json['local_number_of_seasons']),
      numberOfEpisodes: _asInt(json['number_of_episodes']),
      localNumberOfEpisodes: _asInt(json['local_number_of_episodes']),
      genres: _asIntList(json['genres']),
      productionCountries: _asStringList(json['production_countries']),
      resolutions: _asStringList(streamMap['resolutions']),
      audioTypes: _asStringList(streamMap['audio_type']),
      colorRanges: _asStringList(streamMap['color_range_type']),
      ancestorName: (json['ancestor_name'] ?? '').toString(),
      canPlay: _asInt(json['can_play']),
      playError: (json['play_error'] ?? '').toString(),
      isFavorite: _asInt(json['is_favorite']),
      isWatched: _asInt(json['is_watched']),
    );
  }

  String get displayTitle => tvTitle.trim().isNotEmpty ? tvTitle : title;

  String get displaySubTitle {
    if (tvTitle.trim().isNotEmpty && title.trim().isNotEmpty) {
      return title;
    }
    return parentTitle;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse('$value');
}

PlayConfig? _parsePlayConfig(dynamic value) {
  if (value is Map<String, dynamic>) {
    return PlayConfig.fromJson(value);
  }
  return null;
}

List<int> _asIntList(dynamic value) {
  if (value is! List) return const [];
  return value.map(_asInt).toList();
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => e.toString()).toList();
}
