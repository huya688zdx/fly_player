import '../../media_backend/detail/media_detail.dart';
import '../../media_backend/detail/media_season_summary.dart';
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';
import 'poster_browse_display_item.dart';

class PosterBrowseDisplayBuilder {
  const PosterBrowseDisplayBuilder();

  PosterBrowseDisplayItem build({
    required MediaItemCard card,
    MediaDetail? itemDetail,
    MediaDetail? seriesDetail,
    MediaSeasonSummary? season,
  }) {
    final isEpisode = card.type.trim().toLowerCase() == 'episode';
    final title = isEpisode
        ? _firstText(<String?>[
            seriesDetail?.title,
            card.secondaryTitle,
            card.title,
          ])
        : _firstText(<String?>[itemDetail?.displayTitle, card.displayTitle]);
    final cardTitle = card.title.trim();
    final episodeTitle = isEpisode && cardTitle != title ? cardTitle : '';
    final rating = _firstText(<String?>[itemDetail?.rating, card.rating]);
    final detailSeasons = itemDetail?.numberOfSeasons ?? 0;
    final detailEpisodes = itemDetail?.numberOfEpisodes ?? 0;

    return PosterBrowseDisplayItem(
      card: card,
      title: title,
      episodeTitle: episodeTitle,
      type: card.type,
      seriesId: card.seriesId,
      ratingText: formatRating(rating),
      releaseYear: _releaseYear(<String?>[
        itemDetail?.releaseDate,
        itemDetail?.airDate,
        card.releaseDate,
      ]),
      overview: _firstText(<String?>[itemDetail?.overview]),
      detailTargetId: isEpisode && card.seriesId.trim().isNotEmpty
          ? card.seriesId
          : card.id,
      seasonNumber: card.seasonNumber,
      episodeNumber: card.episodeNumber,
      numberOfSeasons: _positiveFirst(<int>[
        detailSeasons,
        card.localNumberOfSeasons,
        card.numberOfSeasons,
      ]),
      numberOfEpisodes: _positiveFirst(<int>[
        detailEpisodes,
        card.localNumberOfEpisodes,
        card.numberOfEpisodes,
      ]),
      durationSeconds: _positiveFirst(<int>[
        itemDetail?.durationSeconds ?? 0,
        card.durationSeconds,
      ]),
      genres: _detailGenresOrCard(itemDetail, card),
      resolutions: itemDetail != null && itemDetail.resolutions.isNotEmpty
          ? itemDetail.resolutions
          : card.resolutions,
      backgroundImages: _dedupeImages(<MediaImageRef>[
        card.backdropImage,
        itemDetail?.backdropImage ?? MediaImageRef.empty,
        seriesDetail?.backdropImage ?? MediaImageRef.empty,
        card.primaryImage,
        season?.primaryImage ?? MediaImageRef.empty,
        seriesDetail?.primaryImage ?? MediaImageRef.empty,
      ]),
      logoImages: _dedupeImages(<MediaImageRef>[
        itemDetail?.logoImage ?? MediaImageRef.empty,
        seriesDetail?.logoImage ?? MediaImageRef.empty,
      ]),
      posterImages: _dedupeImages(<MediaImageRef>[
        if (card.hasPosterSize && !card.isLandscapePoster) card.primaryImage,
        season?.primaryImage ?? MediaImageRef.empty,
        seriesDetail?.primaryImage ?? MediaImageRef.empty,
        card.primaryImage,
      ]),
    );
  }

  String formatRating(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      return '';
    }
    final formatted = value.toStringAsFixed(1);
    return formatted.endsWith('.0')
        ? formatted.substring(0, formatted.length - 2)
        : formatted;
  }

  static String _firstText(Iterable<String?> values) {
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static String _releaseYear(Iterable<String?> values) {
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.length >= 4) {
        return text.substring(0, 4);
      }
    }
    return '';
  }

  static int _positiveFirst(Iterable<int> values) {
    for (final value in values) {
      if (value > 0) {
        return value;
      }
    }
    return 0;
  }

  static List<String> _detailGenresOrCard(
    MediaDetail? itemDetail,
    MediaItemCard card,
  ) {
    if (itemDetail != null && itemDetail.genreLabels.isNotEmpty) {
      return itemDetail.genreLabels;
    }
    try {
      final value = (card as dynamic).genres;
      if (value is List<String>) {
        return value;
      }
      if (value is List) {
        return value.whereType<String>().toList(growable: false);
      }
    } on NoSuchMethodError {
      return const <String>[];
    }
    return const <String>[];
  }

  static List<MediaImageRef> _dedupeImages(Iterable<MediaImageRef> images) {
    final seen = <String>{};
    final result = <MediaImageRef>[];
    for (final image in images) {
      if (image.isEmpty) {
        continue;
      }
      final key = _imageKey(image);
      if (seen.add(key)) {
        result.add(image);
      }
    }
    return List<MediaImageRef>.unmodifiable(result);
  }

  static String _imageKey(MediaImageRef image) {
    final headers = image.headers.entries.toList()
      ..sort(
        (a, b) => a.key == b.key
            ? a.value.compareTo(b.value)
            : a.key.compareTo(b.key),
      );
    final headerKey = headers
        .map(
          (entry) =>
              '${entry.key.length}:${entry.key}${entry.value.length}:${entry.value}',
        )
        .join('|');
    final selfAuthenticated = image.url.contains('api_key=');
    return '${image.url.length}:${image.url}|$selfAuthenticated|$headerKey';
  }
}
