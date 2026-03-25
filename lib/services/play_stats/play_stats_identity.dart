class PlayStatsAnimeIdentity {
  final String animeId;
  final String animeTitle;

  const PlayStatsAnimeIdentity({
    required this.animeId,
    required this.animeTitle,
  });
}

class PlayStatsIdentityResolver {
  const PlayStatsIdentityResolver._();

  static PlayStatsAnimeIdentity resolveAnimeIdentity({
    String seriesGuid = '',
    String grandGuid = '',
    String trimId = '',
    String tvTitle = '',
    String seriesTitle = '',
    String fallbackTitle = '',
  }) {
    final animeTitle = _firstNonEmpty(tvTitle, seriesTitle, fallbackTitle);
    return PlayStatsAnimeIdentity(
      animeId: _firstNonEmpty(seriesGuid, grandGuid),
      animeTitle: animeTitle,
    );
  }

  static bool isDerivedAnimeId(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('tmdb:') || normalized.startsWith('title:');
  }

  static String _firstNonEmpty(
    String first, [
    String second = '',
    String third = '',
    String fourth = '',
  ]) {
    for (final value in <String>[first, second, third, fourth]) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }
}
