import '../models/play_info.dart';

String formatPlayerTitle({
  required String seriesTitle,
  required String episodeTitle,
  int seasonNumber = 0,
  int episodeNumber = 0,
  String fallbackTitle = '',
}) {
  final normalizedSeriesTitle = seriesTitle.trim();
  final normalizedEpisodeTitle = episodeTitle.trim();
  final normalizedFallbackTitle = fallbackTitle.trim();

  final titleParts = <String>[
    if (normalizedSeriesTitle.isNotEmpty) normalizedSeriesTitle,
    if (seasonNumber > 0) '第$seasonNumber季',
    if (episodeNumber > 0) '第$episodeNumber集',
  ];

  final shouldAppendEpisodeTitle =
      normalizedEpisodeTitle.isNotEmpty &&
      normalizedEpisodeTitle != normalizedSeriesTitle;
  if (shouldAppendEpisodeTitle) {
    titleParts.add(normalizedEpisodeTitle);
  }

  if (titleParts.isNotEmpty) {
    return titleParts.join(' ');
  }
  if (normalizedEpisodeTitle.isNotEmpty) {
    return normalizedEpisodeTitle;
  }
  if (normalizedFallbackTitle.isNotEmpty) {
    return normalizedFallbackTitle;
  }
  return normalizedSeriesTitle;
}

String formatPlayerTitleFromPlayItem(
  PlayItem item, {
  String fallbackTitle = '',
}) {
  return formatPlayerTitle(
    seriesTitle: item.tvTitle.trim().isNotEmpty
        ? item.tvTitle.trim()
        : item.displayTitle,
    episodeTitle: item.title,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    fallbackTitle: fallbackTitle,
  );
}
