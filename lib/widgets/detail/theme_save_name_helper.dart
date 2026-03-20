String buildThemeSaveNameBase({
  required String title,
  String? seriesTitle,
  int? seasonNumber,
  int? episodeNumber,
  bool isEpisode = false,
}) {
  final normalizedTitle = title.trim();
  final normalizedSeriesTitle = seriesTitle?.trim() ?? '';
  final effectiveTitle = normalizedTitle.isNotEmpty
      ? normalizedTitle
      : normalizedSeriesTitle;

  if (!isEpisode) {
    return '${effectiveTitle.isNotEmpty ? effectiveTitle : '自定义主题'}主题色';
  }

  final parts = <String>[
    normalizedSeriesTitle.isNotEmpty ? normalizedSeriesTitle : effectiveTitle,
  ];
  final resolvedSeason = seasonNumber ?? 0;
  final resolvedEpisode = episodeNumber ?? 0;

  if (resolvedSeason == 0) {
    parts.add('特别篇');
  } else if (resolvedSeason > 0) {
    parts.add('第$resolvedSeason季');
  }

  if (resolvedEpisode > 0) {
    parts.add('第$resolvedEpisode集');
  }

  return '${parts.where((part) => part.trim().isNotEmpty).join('·')}·主题色';
}
