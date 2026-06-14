import 'dart:io';

import '../api/feiniu_api.dart';
import '../models/download_task_record.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../utils/play_detail_track_selector.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/player_title_formatter.dart';

/// 已下载记录的显示标题（groupTitle + recordTitle 拼合）。
String localDownloadRecordTitle(DownloadTaskRecord record) {
  final groupTitle = record.groupTitle.trim();
  final recordTitle = DownloadTaskService.instance
      .displayTitleForRecord(record)
      .trim();
  if (recordTitle.isEmpty) {
    return groupTitle.isNotEmpty ? groupTitle : record.fileName.trim();
  }
  if (groupTitle.isEmpty || recordTitle.startsWith(groupTitle)) {
    return recordTitle;
  }
  return '$groupTitle $recordTitle';
}

/// 从下载记录解析本地播放 source。NAS 连接时合并 getPlayInfo/StreamTrack/PlaybackStream
/// 元数据，未连接用 record 的 audioTracks/subtitleTracks/poster fallback。
/// [startPositionMs] 覆盖续播位（切集保持当前进度时使用）。
/// 文件不存在返回 null；任何 NAS 请求失败都静默 fallback，不阻塞播放。
Future<({MpvMediaSource source, PlayInfoData? playInfo, String title})?>
resolveLocalDownloadSource(
  DownloadTaskRecord record,
  NasProvider nas, {
  int? startPositionMs,
}) async {
  final path = record.filePath.trim();
  if (path.isEmpty || !File(path).existsSync()) return null;
  final api = FeiniuApi(nas);
  final fallbackTitle = localDownloadRecordTitle(record);
  final normalizedItemGuid = record.itemGuid.trim();
  PlayInfoData? initialPlayInfo;
  StreamTrackData? trackData;
  PlaybackStreamData? playbackStream;
  try {
    initialPlayInfo = await api.getPlayInfo(normalizedItemGuid);
  } catch (_) {}
  final resolvedMediaGuid = record.mediaGuid.trim().isNotEmpty
      ? record.mediaGuid.trim()
      : (initialPlayInfo?.mediaGuid.trim().isNotEmpty == true
            ? initialPlayInfo!.mediaGuid.trim()
            : normalizedItemGuid);
  try {
    trackData = await api.getStreamTrackData(normalizedItemGuid);
  } catch (_) {}
  try {
    if (resolvedMediaGuid.isNotEmpty) {
      playbackStream = await api.getPlaybackStream(resolvedMediaGuid);
    }
  } catch (_) {}
  final playItem = initialPlayInfo?.item;
  final title = playItem == null
      ? fallbackTitle
      : formatPlayerTitleFromPlayItem(playItem, fallbackTitle: fallbackTitle);
  final trackVideo = resolvedMediaGuid.isEmpty
      ? null
      : trackData?.videoForMedia(resolvedMediaGuid);
  final playbackVideo = playbackStream?.videoStream;
  final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
    playbackStream?.qualities ?? const <PlaybackQualityOption>[],
    trackData,
  );
  final fallbackAudioTracks = record.audioTracks;
  final audioTracks = playbackStream?.audioStreams.isNotEmpty == true
      ? playbackStream!.audioStreams
      : (resolvedMediaGuid.isEmpty
            ? fallbackAudioTracks
            : trackData?.audiosForMedia(resolvedMediaGuid) ??
                  fallbackAudioTracks);
  final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
    selectedAudioGuid: initialPlayInfo?.audioGuid ?? '',
    audioTracks: audioTracks,
  );
  final fallbackSubtitleTracks = record.subtitleTracks;
  final subtitleTracks = playbackStream?.subtitleStreams.isNotEmpty == true
      ? PlayDetailTrackSelector.mergeSubtitleTracks(
          primaryTracks: playbackStream!.subtitleStreams,
          extraTracks: resolvedMediaGuid.isEmpty
              ? fallbackSubtitleTracks
              : trackData?.subtitlesForMedia(resolvedMediaGuid) ??
                    fallbackSubtitleTracks,
        )
      : (resolvedMediaGuid.isEmpty
            ? fallbackSubtitleTracks
            : trackData?.subtitlesForMedia(resolvedMediaGuid) ??
                  fallbackSubtitleTracks);
  final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
    selectedSubtitleGuid: initialPlayInfo?.subtitleGuid ?? '',
    subtitleTracks: subtitleTracks,
  );
  final embeddedSubtitleTrackIndex =
      PlayDetailTrackSelector.embeddedSubtitleTrackIndex(
        selectedSubtitle: selectedSubtitle,
        subtitleTracks: subtitleTracks,
      );
  final networkDurationSeconds = playItem?.duration ?? 0;
  final watchedSeconds = initialPlayInfo == null
      ? 0
      : (initialPlayInfo.ts > 0
            ? initialPlayInfo.ts
            : playItem?.watchedTs ?? 0);
  final networkCompleted =
      initialPlayInfo != null &&
      networkDurationSeconds > 0 &&
      ((networkDurationSeconds - watchedSeconds) <= 0 ||
          playItem?.isWatched == 1);
  final resume = await PlaybackResumePositionResolver.resolve(
    videoIds: <String>[
      playItem?.guid ?? '',
      normalizedItemGuid,
      record.itemGuid,
      record.id,
    ],
    durationSeconds: networkDurationSeconds,
    networkPositionSeconds: watchedSeconds,
    networkPositionAvailable: initialPlayInfo != null,
    networkCompleted: networkCompleted,
  );
  final durationSeconds = resume.effectiveDurationSeconds;
  final source = MpvMediaSource.localFile(
    filePath: path,
    itemGuid: playItem?.guid.trim().isNotEmpty == true
        ? playItem!.guid.trim()
        : normalizedItemGuid,
    seriesGuid: initialPlayInfo?.grandGuid.trim() ?? '',
    seasonGuid: initialPlayInfo?.parentGuid.trim().isNotEmpty == true
        ? initialPlayInfo!.parentGuid.trim()
        : record.groupId.trim(),
    posterPath: playItem == null
        ? (record.posterUrls.isNotEmpty
              ? record.posterUrls.first
              : (record.groupPosterUrls.isNotEmpty
                    ? record.groupPosterUrls.first
                    : ''))
        : resolvePlayerArtworkPathForPlayItem(playItem),
    mediaGuid: resolvedMediaGuid,
    mediaType: playItem?.type ?? '',
    ancestorName: playItem?.ancestorName ?? '',
    videoGuid: trackVideo?.guid.trim().isNotEmpty == true
        ? trackVideo!.guid.trim()
        : (playbackVideo?.guid.trim().isNotEmpty == true
              ? playbackVideo!.guid.trim()
              : resolvedMediaGuid),
    title: title,
    seriesTitle: (playItem?.tvTitle ?? '').trim().isNotEmpty
        ? playItem!.tvTitle.trim()
        : record.groupTitle.trim(),
    // 离线时 playItem 为空：回退到下载记录里落盘的 tmid/季集号（弹幕 tmid 搜索/选集用）。
    seasonNumber: (playItem?.seasonNumber ?? 0) > 0
        ? playItem!.seasonNumber
        : record.seasonNumber,
    tmdbId: (playItem?.trimId.trim().isNotEmpty ?? false)
        ? playItem!.trimId.trim()
        : record.tmdbId,
    episodeNumber: (playItem?.episodeNumber ?? 0) > 0
        ? playItem!.episodeNumber
        : record.episodeNumber,
    startPosition: startPositionMs != null
        ? Duration(milliseconds: startPositionMs)
        : resume.position,
    audioTrackGuid: selectedAudio?.guid ?? initialPlayInfo?.audioGuid,
    subtitleTrackIndex: embeddedSubtitleTrackIndex,
    subtitleTrackGuid: initialPlayInfo?.subtitleGuid,
    resolution: record.resolution.trim().isNotEmpty
        ? record.resolution.trim()
        : (playbackVideo?.resolutionType.trim().isNotEmpty == true
              ? playbackVideo!.resolutionType.trim()
              : trackVideo?.resolutionType ?? ''),
    bitrate: playbackVideo?.bps ?? trackVideo?.bps ?? 0,
    durationSeconds: durationSeconds,
    videoWidth: playbackVideo?.width ?? trackVideo?.width ?? 0,
    videoHeight: playbackVideo?.height ?? trackVideo?.height ?? 0,
    videoCodecName: playbackVideo?.codecName ?? trackVideo?.codecName ?? '',
    videoProfile: playbackVideo?.profile ?? trackVideo?.profile ?? '',
    colorSpace: playbackVideo?.colorSpace ?? trackVideo?.colorSpace ?? '',
    colorTransfer:
        playbackVideo?.colorTransfer ?? trackVideo?.colorTransfer ?? '',
    colorPrimaries:
        playbackVideo?.colorPrimaries ?? trackVideo?.colorPrimaries ?? '',
    bitDepth: playbackVideo?.bitDepth ?? trackVideo?.bitDepth ?? 0,
    audioTracks: audioTracks,
    subtitleTracks: subtitleTracks,
    qualities: mergedQualities,
    playbackSpeed: 1.0,
  );
  return (source: source, playInfo: initialPlayInfo, title: title);
}
