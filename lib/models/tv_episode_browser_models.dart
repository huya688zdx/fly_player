class TvEpisodeSeasonOptionData {
  final String guid;
  final String label;
  final bool selected;

  const TvEpisodeSeasonOptionData({
    required this.guid,
    required this.label,
    required this.selected,
  });
}

enum TvEpisodeStatusTone { none, secondary, accent }

class TvEpisodeCardData {
  final String guid;
  final String shortLabel;
  final String title;
  final String summary;
  final String durationText;
  final String statusLabel;
  final TvEpisodeStatusTone statusTone;
  final List<String> imageUrls;
  final List<String> resolutions;
  final bool selected;
  final bool playing;
  final bool completed;
  final double progress;

  const TvEpisodeCardData({
    required this.guid,
    required this.shortLabel,
    required this.title,
    required this.summary,
    required this.durationText,
    required this.statusLabel,
    this.statusTone = TvEpisodeStatusTone.secondary,
    required this.imageUrls,
    required this.resolutions,
    required this.selected,
    required this.playing,
    required this.completed,
    required this.progress,
  });
}

class TvEpisodePickerPayload {
  final int totalCount;
  final List<TvEpisodeCardData> entries;

  const TvEpisodePickerPayload({
    required this.totalCount,
    required this.entries,
  });
}
