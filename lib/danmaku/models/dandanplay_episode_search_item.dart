class DanDanPlayEpisodeSearchItem {
  final int episodeId;
  final String animeTitle;
  final String episodeTitle;
  final int episodeNumber;

  const DanDanPlayEpisodeSearchItem({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
    required this.episodeNumber,
  });

  String get displayTitle {
    final title = episodeTitle.trim();
    if (title.isEmpty) {
      return episodeNumber > 0 ? 'Episode $episodeNumber' : animeTitle;
    }
    return title;
  }

  String get displaySubtitle {
    final anime = animeTitle.trim();
    if (episodeNumber > 0 && anime.isNotEmpty) {
      return '$anime · Episode $episodeNumber';
    }
    if (anime.isNotEmpty) return anime;
    if (episodeNumber > 0) return 'Episode $episodeNumber';
    return 'DanDanPlay';
  }
}
