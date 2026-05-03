import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/media_library_item.dart';
import '../../models/tv_episode_browser_models.dart';
import '../panels/episode_picker_sheet.dart';

class EpisodePickerPresenterLabels {
  final String episodeList;
  final String specialSeason;
  final String seasonTemplate;
  final String playing;
  final String watched;
  final String watchedPercentTemplate;
  final String unwatched;

  const EpisodePickerPresenterLabels({
    this.episodeList = 'Episode list',
    this.specialSeason = 'Specials',
    this.seasonTemplate = 'Season {season}',
    this.playing = 'Playing..',
    this.watched = 'Watched',
    this.watchedPercentTemplate = 'Watched {percent}%',
    this.unwatched = 'Unwatched',
  });

  factory EpisodePickerPresenterLabels.fromL10n(AppLocalizations l10n) {
    return EpisodePickerPresenterLabels(
      episodeList: l10n.playerEpisodeList,
      specialSeason: l10n.playerEpisodeSpecialSeason,
      seasonTemplate: l10n.playerEpisodeSeasonTemplate('{season}'),
      playing: l10n.playerEpisodePlaying,
      watched: l10n.playerEpisodeWatched,
      watchedPercentTemplate: l10n.playerEpisodeWatchedPercent('{percent}'),
      unwatched: l10n.playerEpisodeUnwatched,
    );
  }

  String seasonLabel(int seasonNumber) {
    return seasonTemplate.replaceAll('{season}', seasonNumber.toString());
  }

  String watchedPercentLabel(int percent) {
    return watchedPercentTemplate.replaceAll('{percent}', percent.toString());
  }
}

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
  EpisodePickerPresenterLabels labels = const EpisodePickerPresenterLabels(),
}) {
  final first = episodes.isNotEmpty ? episodes.first : null;
  final seriesTitle = buildEpisodePickerSeriesTitle(
    episodes,
    fallbackSeriesTitle: fallbackSeriesTitle,
  );
  final seasonLabel = first == null
      ? ''
      : buildEpisodePickerSeasonLabel(first, labels: labels);
  if (seriesTitle.isNotEmpty && seasonLabel.isNotEmpty) {
    return '$seriesTitle $seasonLabel';
  }
  if (seasonLabel.isNotEmpty) return seasonLabel;
  if (seriesTitle.isNotEmpty) return seriesTitle;
  return labels.episodeList;
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
  EpisodePickerPresenterLabels labels = const EpisodePickerPresenterLabels(),
}) {
  if (item.seasonNumber == 0) return labels.specialSeason;
  if (item.seasonNumber > 0) return labels.seasonLabel(item.seasonNumber);

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
  EpisodePickerPresenterLabels labels = const EpisodePickerPresenterLabels(),
}) {
  return seasons
      .map(
        (season) => TvEpisodeSeasonOptionData(
          guid: season.guid,
          label: buildEpisodePickerSeasonLabel(season, labels: labels),
          selected: season.guid == selectedSeasonGuid,
        ),
      )
      .toList(growable: false);
}

EpisodePickerSheetItem buildEpisodePickerSheetItem(
  MediaLibraryItem episode, {
  required EpisodePickerPlaybackState playbackState,
  EpisodePickerPresenterLabels labels = const EpisodePickerPresenterLabels(),
}) {
  final playback = _episodePlaybackPresentation(
    episode,
    playbackState: playbackState,
    labels: labels,
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
  required EpisodePickerPresenterLabels labels,
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
    return (labels.playing, const Color(0xFF2D87FF));
  }
  if (episode.watched == 1 && watchedSeconds <= 0) {
    return (labels.watched, Colors.white);
  }
  if (durationSeconds > 0 && watchedSeconds > 0) {
    final percent = (watchedSeconds / durationSeconds * 100).clamp(0, 100);
    if (percent >= 95 || episode.watched == 1) {
      return (labels.watched, Colors.white);
    }
    return (
      labels.watchedPercentLabel(percent.round()),
      const Color(0xFF2D87FF),
    );
  }
  if (episode.watched == 1) {
    return (labels.watched, Colors.white);
  }
  return (labels.unwatched, Colors.white70);
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
