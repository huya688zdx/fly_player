/// 表示从播放详情中解析出的番剧身份信息。
class PlayStatsAnimeIdentity {
  final String animeId;
  final String animeTitle;

  /// 根据番剧标识与标题构造对象。
  const PlayStatsAnimeIdentity({
    required this.animeId,
    required this.animeTitle,
  });
}

/// 提供播放统计所需的身份解析辅助逻辑。
class PlayStatsIdentityResolver {
  const PlayStatsIdentityResolver._();

  /// 从详情页字段中推导番剧维度的身份信息。
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

  /// 判断给定番剧标识是否属于派生标识。
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
