import 'package:flutter/material.dart';

import '../../models/media_library_item.dart';
import '../../models/tv_episode_browser_models.dart';
import '../panels/episode_picker_sheet.dart';

class EpisodePickerPlaybackState {
  final String currentItemGuid;
  final bool isPlaying;
  final int currentPositionSeconds;
  final int currentDurationSeconds;

  const EpisodePickerPlaybackState({
    required this.currentItemGuid,
    required this.isPlaying,
    required this.currentPositionSeconds,
    required this.currentDurationSeconds,
  });
}

String buildEpisodePickerSectionLabel(
  List<MediaLibraryItem> episodes, {
  String fallbackSeriesTitle = '',
}) {
  final first = episodes.isNotEmpty ? episodes.first : null;
  final seriesTitle = buildEpisodePickerSeriesTitle(
    episodes,
    fallbackSeriesTitle: fallbackSeriesTitle,
  );
  final seasonLabel = first == null ? '' : buildEpisodePickerSeasonLabel(first);
  if (seriesTitle.isNotEmpty && seasonLabel.isNotEmpty) {
    return '$seriesTitle $seasonLabel';
  }
  if (seasonLabel.isNotEmpty) return seasonLabel;
  if (seriesTitle.isNotEmpty) return seriesTitle;
  return '剧集列表';
}

String buildEpisodePickerSeriesTitle(
  List<MediaLibraryItem> episodes, {
  String fallbackSeriesTitle = '',
}) {
  final first = episodes.isNotEmpty ? episodes.first : null;
  final seriesTitle = first?.tvTitle.trim() ?? '';
  if (seriesTitle.isNotEmpty) return seriesTitle;
  return fallbackSeriesTitle.trim();
}

String buildEpisodePickerSeasonLabel(
  MediaLibraryItem item, {
  String fallbackLabel = '',
}) {
  if (item.seasonNumber == 0) return '特别篇';
  if (item.seasonNumber > 0) return '第${item.seasonNumber}季';

  final normalizedFallback = fallbackLabel.trim();
  if (normalizedFallback.isNotEmpty) return normalizedFallback;

  final parentTitle = item.parentTitle.trim();
  if (parentTitle.isNotEmpty && parentTitle != item.tvTitle.trim()) {
    return parentTitle;
  }

  final title = item.title.trim();
  if (title.isNotEmpty && title != item.tvTitle.trim()) {
    return title;
  }
  return '';
}

List<TvEpisodeSeasonOptionData> buildEpisodePickerSeasonOptions(
  List<MediaLibraryItem> seasons, {
  required String selectedSeasonGuid,
}) {
  return seasons
      .map(
        (season) => TvEpisodeSeasonOptionData(
          guid: season.guid,
          label: buildEpisodePickerSeasonLabel(season),
          selected: season.guid == selectedSeasonGuid,
        ),
      )
      .toList(growable: false);
}

EpisodePickerSheetItem buildEpisodePickerSheetItem(
  MediaLibraryItem episode, {
  required EpisodePickerPlaybackState playbackState,
}) {
  final playback = _episodePlaybackPresentation(
    episode,
    playbackState: playbackState,
  );
  return EpisodePickerSheetItem(
    id: episode.guid,
    shortLabel: _episodeShortLabel(episode),
    title: _episodeTitle(episode),
    durationLabel: _episodeDurationLabel(episode, playbackState: playbackState),
    statusLabel: playback.$1,
    statusColor: playback.$2,
    posterPath: episode.poster,
    completed: _episodeCompleted(episode, playbackState: playbackState),
    isPlaying:
        episode.guid == playbackState.currentItemGuid &&
        playbackState.isPlaying,
    selected: episode.guid == playbackState.currentItemGuid,
  );
}

String _episodeTitle(MediaLibraryItem episode) {
  final prefix = episode.episodeNumber > 0
      ? '${episode.episodeNumber.toString().padLeft(2, '0')}. '
      : '';
  final seriesTitle = episode.tvTitle.trim();
  final episodeTitle = _stripSeriesTitlePrefix(
    episode.title.trim(),
    seriesTitle,
  );
  final fallbackTitle = _stripSeriesTitlePrefix(
    episode.displayTitle.trim(),
    seriesTitle,
  );

  final contentTitle = switch ((
    episodeTitle.isNotEmpty,
    fallbackTitle.isNotEmpty,
  )) {
    (true, _) => episodeTitle,
    (_, true) => fallbackTitle,
    _ => seriesTitle,
  };

  return '$prefix$contentTitle'.trim();
}

String _stripSeriesTitlePrefix(String title, String seriesTitle) {
  if (title.isEmpty || seriesTitle.isEmpty) return title;

  var result = title;
  const separators = <String>[
    ' ',
    '　',
    '-',
    '–',
    '—',
    '·',
    ':',
    '：',
    '/',
    '／',
    '|',
    '｜',
    '《',
    '》',
    '「',
    '」',
    '(',
    '（',
  ];

  while (result.startsWith(seriesTitle)) {
    result = result.substring(seriesTitle.length).trimLeft();
    if (result.isEmpty) {
      return title;
    }
    final first = result.characters.first;
    if (!separators.contains(first)) {
      return title;
    }
    result = result.substring(first.length).trimLeft();
  }

  return result.isEmpty ? title : result;
}

String _episodeShortLabel(MediaLibraryItem episode) {
  if (episode.episodeNumber > 0) return '${episode.episodeNumber}';
  if (episode.numberOfItem > 0) return '${episode.numberOfItem}';
  return '?';
}

String _episodeDurationLabel(
  MediaLibraryItem episode, {
  required EpisodePickerPlaybackState playbackState,
}) {
  final seconds = episode.duration > 0
      ? episode.duration
      : (episode.guid == playbackState.currentItemGuid
            ? playbackState.currentDurationSeconds
            : 0);
  if (seconds <= 0) return '';

  final totalSeconds = seconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final remainder = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

(String, Color) _episodePlaybackPresentation(
  MediaLibraryItem episode, {
  required EpisodePickerPlaybackState playbackState,
}) {
  final isCurrent = episode.guid == playbackState.currentItemGuid;
  final durationSeconds = episode.duration > 0
      ? episode.duration
      : (isCurrent ? playbackState.currentDurationSeconds : 0);
  final rawSeconds = isCurrent
      ? playbackState.currentPositionSeconds
      : (episode.ts > 0 ? episode.ts : episode.watchedTs);
  final watchedSeconds = durationSeconds > 0
      ? rawSeconds.clamp(0, durationSeconds)
      : rawSeconds.clamp(0, 999999);

  if (isCurrent) {
    return ('播放中..', const Color(0xFF2D87FF));
  }
  if (episode.watched == 1 && watchedSeconds <= 0) {
    return ('已观看', Colors.white);
  }
  if (durationSeconds > 0 && watchedSeconds > 0) {
    final percent = (watchedSeconds / durationSeconds * 100).clamp(0, 100);
    if (percent >= 95 || episode.watched == 1) {
      return ('已观看', Colors.white);
    }
    return ('已观看${percent.round()}%', const Color(0xFF2D87FF));
  }
  if (episode.watched == 1) {
    return ('已观看', Colors.white);
  }
  return ('未观看', Colors.white70);
}

bool _episodeCompleted(
  MediaLibraryItem episode, {
  required EpisodePickerPlaybackState playbackState,
}) {
  final isCurrent = episode.guid == playbackState.currentItemGuid;
  final durationSeconds = episode.duration > 0
      ? episode.duration
      : (isCurrent ? playbackState.currentDurationSeconds : 0);
  final rawSeconds = isCurrent
      ? playbackState.currentPositionSeconds
      : (episode.ts > 0 ? episode.ts : episode.watchedTs);
  if (episode.watched == 1) return true;
  if (durationSeconds <= 0 || rawSeconds <= 0) return false;
  return (rawSeconds / durationSeconds) >= 0.95;
}
