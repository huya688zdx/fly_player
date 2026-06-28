import '../l10n/generated/app_localizations.dart';
import '../models/play_info.dart';

String formatPlayerTitle({
  required String seriesTitle,
  required String episodeTitle,
  required AppLocalizations l10n,
  int seasonNumber = 0,
  int episodeNumber = 0,
  String fallbackTitle = '',
}) {
  final normalizedSeriesTitle = seriesTitle.trim();
  final normalizedEpisodeTitle = episodeTitle.trim();
  final normalizedFallbackTitle = fallbackTitle.trim();

  final titleParts = <String>[
    if (normalizedSeriesTitle.isNotEmpty) normalizedSeriesTitle,
    if (seasonNumber > 0) l10n.playerEpisodeSeasonTemplate(seasonNumber),
    if (episodeNumber > 0) l10n.playerEpisodeNumberTemplate(episodeNumber),
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
  required AppLocalizations l10n,
  String fallbackTitle = '',
}) {
  return formatPlayerTitle(
    seriesTitle: item.tvTitle.trim().isNotEmpty
        ? item.tvTitle.trim()
        : item.displayTitle,
    episodeTitle: item.title,
    l10n: l10n,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    fallbackTitle: fallbackTitle,
  );
}
