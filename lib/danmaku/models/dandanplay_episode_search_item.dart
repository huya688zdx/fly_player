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
      return episodeNumber > 0 ? '第$episodeNumber集' : animeTitle;
    }
    return title;
  }

  String get displaySubtitle {
    final anime = animeTitle.trim();
    if (episodeNumber > 0 && anime.isNotEmpty) {
      return '$anime · 第$episodeNumber集';
    }
    if (anime.isNotEmpty) return anime;
    if (episodeNumber > 0) return '第$episodeNumber集';
    return '弹弹play';
  }
}
