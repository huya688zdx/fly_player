import '../l10n/generated/app_localizations.dart';

/// 单集卡副标题统一格式：「第 X 季 第 Y 集 · 单集名」。
///
/// 季集号缺失时退化为「第 Y 集 · 单集名」或仅单集名。收藏 / 分类 / 搜索等卡片共用,
/// 保证单集在各列表里都带得出「哪一部 · 第几季第几集」信息(卡片主标题展示剧名)。
String mediaEpisodeSubtitle(
  AppLocalizations l10n,
  int seasonNumber,
  int episodeNumber,
  String episodeName,
) {
  final label = seasonNumber > 0 && episodeNumber > 0
      ? l10n.detailSeasonEpisodeNumber(seasonNumber, episodeNumber)
      : (episodeNumber > 0 ? l10n.detailEpisodeNumber(episodeNumber) : '');
  final name = episodeName.trim();
  if (label.isNotEmpty && name.isNotEmpty) return '$label · $name';
  if (label.isNotEmpty) return label;
  return name;
}
