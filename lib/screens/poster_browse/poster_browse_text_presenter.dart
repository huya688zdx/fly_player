import '../../l10n/generated/app_localizations.dart';
import 'poster_browse_display_item.dart';

class PosterBrowseTextPresenter {
  const PosterBrowseTextPresenter({required this.l10n});

  final AppLocalizations l10n;

  String secondaryLabel(PosterBrowseDisplayItem item) {
    final type = item.type.trim().toLowerCase();
    final parts = <String>[];

    switch (type) {
      case 'episode':
        final seasonNumber = item.seasonNumber;
        final episodeNumber = item.episodeNumber;
        if (seasonNumber > 0 && episodeNumber > 0) {
          parts.add(
            l10n.detailSeasonEpisodeNumber(seasonNumber, episodeNumber),
          );
        } else if (seasonNumber > 0) {
          parts.add(l10n.detailSeasonNumber(seasonNumber));
        } else if (episodeNumber > 0) {
          parts.add(l10n.detailEpisodeNumber(episodeNumber));
        }
        _addIfNotEmpty(parts, item.episodeTitle);
      case 'season':
        if (item.seasonNumber > 0) {
          parts.add(l10n.detailSeasonNumber(item.seasonNumber));
        }
        if (item.numberOfEpisodes > 0) {
          parts.add(l10n.detailEpisodeTotal(item.numberOfEpisodes));
        }
      case 'series':
      case 'tv':
        if (item.numberOfSeasons > 0) {
          parts.add(l10n.detailTvSeasonCount(item.numberOfSeasons));
        }
        if (item.numberOfEpisodes > 0) {
          parts.add(l10n.detailEpisodeTotal(item.numberOfEpisodes));
        }
      default:
        break;
    }

    return parts.join(' · ');
  }

  List<String> metaTexts(PosterBrowseDisplayItem item) {
    final texts = <String>[];

    final ratingText = item.ratingText.trim();
    if (ratingText.isNotEmpty) {
      texts.add('★ $ratingText');
    }

    _addIfNotEmpty(texts, item.releaseYear);

    final genreText = item.genres
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .take(3)
        .join(' / ');
    _addIfNotEmpty(texts, genreText);

    if (item.durationSeconds > 0) {
      final minutes = item.durationSeconds ~/ 60;
      texts.add(l10n.detailDurationMinutes(minutes < 1 ? 1 : minutes));
    }

    for (final resolution
        in item.resolutions
            .map((resolution) => resolution.trim())
            .where((resolution) => resolution.isNotEmpty)
            .take(2)) {
      texts.add(resolution);
    }

    return List<String>.unmodifiable(_dedupeKeepingOrder(texts));
  }

  static void _addIfNotEmpty(List<String> parts, String value) {
    final text = value.trim();
    if (text.isNotEmpty) {
      parts.add(text);
    }
  }

  static List<String> _dedupeKeepingOrder(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }
}
