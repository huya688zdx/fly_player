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
    String resolvedSeriesId = '',
  }) {
    final resolvedType = itemDetail?.type.trim().isNotEmpty == true
        ? itemDetail!.type.trim()
        : card.type.trim();
    final normalizedType = resolvedType.toLowerCase();
    final isEpisode = normalizedType == 'episode';
    final isSeason = normalizedType == 'season';
    final seriesTitle = seriesDetail?.title.trim() ?? '';
    final title = isEpisode
        ? _firstText(<String?>[seriesTitle, card.secondaryTitle, card.title])
        : isSeason && seriesTitle.isNotEmpty
        ? seriesTitle
        : _firstText(<String?>[itemDetail?.displayTitle, card.displayTitle]);
    final cardTitle = card.title.trim();
    final episodeTitle = isEpisode && cardTitle != title ? cardTitle : '';
    final rating = _firstText(<String?>[itemDetail?.rating, card.rating]);
    final detailSeasons = itemDetail?.numberOfSeasons ?? 0;
    final detailEpisodes = itemDetail?.numberOfEpisodes ?? 0;
    final seriesId = resolvedSeriesId.trim().isNotEmpty
        ? resolvedSeriesId.trim()
        : card.seriesId.trim();
    final cardId = card.id.trim();

    return PosterBrowseDisplayItem(
      card: card,
      title: title,
      episodeTitle: episodeTitle,
      type: resolvedType,
      seriesId: seriesId,
      ratingText: formatRating(rating),
      releaseYear: _releaseYear(<String?>[
        itemDetail?.releaseDate,
        itemDetail?.airDate,
        card.releaseDate,
        card.firstAirDate,
      ]),
      overview: _firstText(<String?>[itemDetail?.overview, card.overview]),
      detailTargetId: isEpisode && seriesId.isNotEmpty ? seriesId : cardId,
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
      backgroundImages: _dedupeImages(
        _backgroundCandidates(
          card: card,
          itemDetail: itemDetail,
          seriesDetail: seriesDetail,
          season: season,
          preferSeries: isEpisode,
        ),
      ),
      logoImages: _dedupeImages(
        _logoCandidates(
          itemDetail: itemDetail,
          seriesDetail: seriesDetail,
          preferSeries: isEpisode || isSeason,
        ),
      ),
      posterImages: _dedupeImages(
        _posterCandidates(
          card: card,
          season: season,
          seriesDetail: seriesDetail,
          preferSeries: isEpisode,
        ),
      ),
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

  static List<MediaImageRef> _logoCandidates({
    required MediaDetail? itemDetail,
    required MediaDetail? seriesDetail,
    required bool preferSeries,
  }) {
    final itemLogo = itemDetail?.logoImage ?? MediaImageRef.empty;
    final seriesLogo = seriesDetail?.logoImage ?? MediaImageRef.empty;
    return preferSeries
        ? <MediaImageRef>[seriesLogo, itemLogo]
        : <MediaImageRef>[itemLogo, seriesLogo];
  }

  static List<MediaImageRef> _posterCandidates({
    required MediaItemCard card,
    MediaDetail? seriesDetail,
    MediaSeasonSummary? season,
    required bool preferSeries,
  }) {
    final seasonPrimary = season?.primaryImage ?? MediaImageRef.empty;
    final seriesPrimary = seriesDetail?.primaryImage ?? MediaImageRef.empty;
    if (preferSeries) {
      return <MediaImageRef>[
        seriesPrimary,
        seasonPrimary,
        ...card.posters,
        card.primaryImage,
      ];
    }
    if (card.hasPosterSize && !card.isLandscapePoster) {
      return <MediaImageRef>[
        card.primaryImage,
        ...card.posters,
        seasonPrimary,
        seriesPrimary,
        card.primaryImage,
      ];
    }
    return <MediaImageRef>[
      ...card.posters,
      seasonPrimary,
      seriesPrimary,
      card.primaryImage,
    ];
  }

  static List<MediaImageRef> _backgroundCandidates({
    required MediaItemCard card,
    required MediaDetail? itemDetail,
    required MediaDetail? seriesDetail,
    required MediaSeasonSummary? season,
    required bool preferSeries,
  }) {
    final itemBackdrop = itemDetail?.backdropImage ?? MediaImageRef.empty;
    final seriesBackdrop = seriesDetail?.backdropImage ?? MediaImageRef.empty;
    final seasonPrimary = season?.primaryImage ?? MediaImageRef.empty;
    final seriesPrimary = seriesDetail?.primaryImage ?? MediaImageRef.empty;
    if (preferSeries) {
      return <MediaImageRef>[
        seriesBackdrop,
        itemBackdrop,
        card.backdropImage,
        seriesPrimary,
        seasonPrimary,
        card.primaryImage,
      ];
    }
    return <MediaImageRef>[
      card.backdropImage,
      itemBackdrop,
      seriesBackdrop,
      card.primaryImage,
      seasonPrimary,
      seriesPrimary,
    ];
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
    return card.genres;
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
    final selfAuthenticated = image.selfAuthenticated;
    return '${image.url.length}:${image.url}|$selfAuthenticated|$headerKey';
  }
}
