import 'package:flutter/material.dart';

import '../models/media_library_item.dart';
import 'episode_picker_sheet.dart';

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

String buildEpisodePickerSectionLabel(List<MediaLibraryItem> episodes) {
  final first = episodes.isNotEmpty ? episodes.first : null;
  final seriesTitle = first?.tvTitle.trim() ?? '';
  final seasonNumber = first?.seasonNumber ?? 0;
  if (seriesTitle.isNotEmpty && seasonNumber > 0) {
    return '$seriesTitle \u7B2C$seasonNumber\u5B63';
  }
  if (seriesTitle.isNotEmpty) return seriesTitle;
  if (seasonNumber > 0) return '\u7B2C$seasonNumber\u5B63';
  return '\u5267\u96C6\u5217\u8868';
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
    title: _episodeTitle(episode),
    durationLabel: _episodeDurationLabel(episode, playbackState: playbackState),
    statusLabel: playback.$1,
    statusColor: playback.$2,
    posterPath: episode.poster,
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
  final episodeTitle = episode.title.trim();
  final fallbackTitle = episode.displayTitle.trim();

  final contentTitle = switch ((
    seriesTitle.isNotEmpty,
    episodeTitle.isNotEmpty,
  )) {
    (true, true) when seriesTitle != episodeTitle =>
      '$seriesTitle $episodeTitle',
    (_, true) => episodeTitle,
    (true, _) => seriesTitle,
    _ => fallbackTitle,
  };

  return '$prefix$contentTitle'.trim();
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
    return ('\u64AD\u653E\u4E2D..', const Color(0xFF2D87FF));
  }
  if (episode.watched == 1 && watchedSeconds <= 0) {
    return ('\u5DF2\u89C2\u770B', Colors.white);
  }
  if (durationSeconds > 0 && watchedSeconds > 0) {
    final percent = (watchedSeconds / durationSeconds * 100).clamp(0, 100);
    if (percent >= 95 || episode.watched == 1) {
      return ('\u5DF2\u89C2\u770B', Colors.white);
    }
    return ('\u5DF2\u89C2\u770B${percent.round()}%', const Color(0xFF2D87FF));
  }
  if (episode.watched == 1) {
    return ('\u5DF2\u89C2\u770B', Colors.white);
  }
  return ('\u672A\u89C2\u770B', Colors.white70);
}
