import '../../l10n/generated/app_localizations.dart';
import 'bookmark_store.dart';

/// 书签展示的共享口径：媒体库/作品/季/集的分组标签与计数摘要。
/// 书签管理页（媒体库 → 剧 → 季 → 集 → 时间点）与设置里的书签摘要行
/// 共用同一套实现，避免各页自行分组导致口径漂移。

bool bookmarkIsTv(PlayerBookmarkEntry entry) {
  final type = entry.mediaType.trim().toLowerCase();
  return type == 'episode' || type == 'tv';
}

String bookmarkAncestorLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  final label = entry.ancestorName.trim();
  if (label.isNotEmpty) return label;
  return l10n.bookmarkManagerLegacyBookmark;
}

String bookmarkSeriesLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  final seriesTitle = entry.seriesTitle.trim();
  if (seriesTitle.isNotEmpty) return seriesTitle;
  final title = entry.title.trim();
  if (title.isNotEmpty) return title;
  return l10n.bookmarkManagerUnnamedWork;
}

String bookmarkSeasonLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  if (entry.seasonNumber <= 0) return l10n.bookmarkManagerSpecialSeason;
  return l10n.bookmarkManagerSeasonLabel(entry.seasonNumber);
}

String bookmarkEpisodeLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  if (entry.episodeNumber > 0) {
    return l10n.bookmarkManagerEpisodeLabel(entry.episodeNumber);
  }
  final title = entry.title.trim();
  if (title.isNotEmpty) return title;
  return l10n.bookmarkManagerUnnamedEpisode;
}

int bookmarkSeasonOrder(PlayerBookmarkEntry entry) {
  return entry.seasonNumber <= 0 ? 0 : entry.seasonNumber;
}

int bookmarkEpisodeOrder(PlayerBookmarkEntry entry) {
  return entry.episodeNumber <= 0 ? 9999 : entry.episodeNumber;
}

String formatBookmarkTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatBookmarkCreatedAt(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

/// 作品数：剧集按剧名、影片按标题去重；两者皆缺时退回单条书签自身。
int bookmarkWorkCount(List<PlayerBookmarkEntry> entries) {
  return entries.map(_bookmarkWorkIdentityKey).toSet().length;
}

/// 有书签的视频条数（按 item+media 身份去重）：剧集层级用作“集”的口径。
int bookmarkMediaCount(List<PlayerBookmarkEntry> entries) {
  return entries.map((entry) => entry.identityKey).toSet().length;
}

String _bookmarkWorkIdentityKey(PlayerBookmarkEntry entry) {
  final series = entry.seriesTitle.trim();
  if (series.isNotEmpty) return 'series::$series';
  final title = entry.title.trim();
  if (title.isNotEmpty) return 'title::$title';
  return 'entry::${entry.identityKey}';
}
