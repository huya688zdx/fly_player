import '../../l10n/generated/app_localizations.dart';

String buildThemeSaveNameBase({
  required AppLocalizations l10n,
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
    return l10n.themeSaveName(
      effectiveTitle.isNotEmpty ? effectiveTitle : l10n.themeSaveDefaultBase,
    );
  }

  final parts = <String>[
    normalizedSeriesTitle.isNotEmpty ? normalizedSeriesTitle : effectiveTitle,
  ];
  final resolvedSeason = seasonNumber ?? 0;
  final resolvedEpisode = episodeNumber ?? 0;

  if (resolvedSeason == 0) {
    parts.add(l10n.bookmarkManagerSpecialSeason);
  } else if (resolvedSeason > 0) {
    parts.add(l10n.bookmarkManagerSeasonLabel(resolvedSeason));
  }

  if (resolvedEpisode > 0) {
    parts.add(l10n.bookmarkManagerEpisodeLabel(resolvedEpisode));
  }

  return l10n.themeSaveName(
    parts.where((part) => part.trim().isNotEmpty).join('·'),
  );
}
