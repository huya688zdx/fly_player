import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';

class PosterBrowseDisplayItem {
  final MediaItemCard card;
  final String title;
  final String episodeTitle;
  final String type;
  final String seriesId;
  final String ratingText;
  final String releaseYear;
  final String overview;
  final String detailTargetId;
  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final int durationSeconds;
  final List<String> genres;
  final List<String> resolutions;
  final List<MediaImageRef> backgroundImages;
  final List<MediaImageRef> logoImages;
  final List<MediaImageRef> posterImages;

  const PosterBrowseDisplayItem({
    required this.card,
    required this.title,
    required this.episodeTitle,
    required this.type,
    required this.seriesId,
    required this.ratingText,
    required this.releaseYear,
    required this.overview,
    required this.detailTargetId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.durationSeconds,
    required this.genres,
    required this.resolutions,
    required this.backgroundImages,
    required this.logoImages,
    required this.posterImages,
  });

  bool get isEpisode => type.toLowerCase() == 'episode';

  PosterBrowseDisplayItem copyWith({
    MediaItemCard? card,
    String? title,
    String? episodeTitle,
    String? type,
    String? seriesId,
    String? ratingText,
    String? releaseYear,
    String? overview,
    String? detailTargetId,
    int? seasonNumber,
    int? episodeNumber,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    int? durationSeconds,
    List<String>? genres,
    List<String>? resolutions,
    List<MediaImageRef>? backgroundImages,
    List<MediaImageRef>? logoImages,
    List<MediaImageRef>? posterImages,
  }) {
    return PosterBrowseDisplayItem(
      card: card ?? this.card,
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      type: type ?? this.type,
      seriesId: seriesId ?? this.seriesId,
      ratingText: ratingText ?? this.ratingText,
      releaseYear: releaseYear ?? this.releaseYear,
      overview: overview ?? this.overview,
      detailTargetId: detailTargetId ?? this.detailTargetId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      genres: genres ?? this.genres,
      resolutions: resolutions ?? this.resolutions,
      backgroundImages: backgroundImages ?? this.backgroundImages,
      logoImages: logoImages ?? this.logoImages,
      posterImages: posterImages ?? this.posterImages,
    );
  }
}
