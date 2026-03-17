import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../ui/app_transitions.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/player_title_formatter.dart';
import '../utils/play_detail_track_selector.dart';

class ItemPlaybackLauncher {
  const ItemPlaybackLauncher();

  Future<PlayDetailPlayerReturnData?> open(
    BuildContext context, {
    required String itemGuid,
    String fallbackTitle = '',
    bool startFromBeginning = false,
    Duration? resumePosition,
  }) async {
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final playInfo = await api.getPlayInfo(itemGuid);
    if (startFromBeginning) {
      await api.resetPlaybackRecord(
        itemGuid: playInfo.item.guid,
        mediaGuid: playInfo.mediaGuid,
      );
    }
    StreamTrackData? trackData;
    try {
      trackData = await api.getStreamTrackData(itemGuid);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load stream track data',
          source: 'item_playback_launcher',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$itemGuid',
        ),
      );
    }
    final playbackStream = await api.getPlaybackStream(playInfo.mediaGuid);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );
    final initialQuality = PlayerSourceController.preferredInitialQuality(
      mergedQualities,
    );

    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: playInfo.audioGuid,
      audioTracks: playbackStream.audioStreams,
    );
    final subtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: trackData?.subtitlesForMedia(playInfo.mediaGuid) ?? const [],
    );
    final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
      selectedSubtitleGuid: playInfo.subtitleGuid,
      subtitleTracks: subtitleTracks,
    );

    final playbackVideoGuid =
        initialQuality?.videoGuid.trim().isNotEmpty == true
        ? initialQuality!.videoGuid.trim()
        : (playbackStream.videoStream?.guid.trim().isNotEmpty == true
              ? playbackStream.videoStream!.guid.trim()
              : playInfo.videoGuid.trim());
    final playbackResolution =
        initialQuality?.isDirectLink == true &&
            initialQuality!.resolution.trim().isNotEmpty
        ? initialQuality.resolution.trim()
        : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
              ? playbackStream.videoStream!.resolutionType.trim()
              : '');
    final playbackBitrate = initialQuality?.isDirectLink == true
        ? initialQuality!.bitrate
        : (playbackStream.videoStream?.bps ?? 0);
    final preferExternalSubtitle =
        selectedSubtitle != null &&
        (selectedSubtitle.isExternal == 1 ||
            selectedSubtitle.extraFile == 1 ||
            selectedSubtitle.guid.startsWith('local:'));
    final embeddedSubtitleTrackIndex =
        selectedSubtitle == null || preferExternalSubtitle
        ? null
        : () {
            final embeddedTracks = subtitleTracks
                .where((track) {
                  if (track.guid.trim().isEmpty) return false;
                  if (track.guid.startsWith('local:')) return false;
                  return track.isExternal != 1 && track.extraFile != 1;
                })
                .toList(growable: false);
            final ordinal = embeddedTracks.indexWhere(
              (track) => track.guid == selectedSubtitle.guid,
            );
            if (ordinal < 0) return null;
            return ordinal + 1;
          }();

    final initialSeconds = startFromBeginning
        ? 0
        : (resumePosition?.inSeconds ??
                  (playInfo.ts > 0 ? playInfo.ts : playInfo.item.watchedTs))
              .clamp(0, playInfo.item.duration);
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: api.getStreamUrl(playInfo.mediaGuid),
          mediaGuid: playInfo.mediaGuid,
          videoGuid: playbackVideoGuid,
          playbackStream: playbackStream,
          quality: initialQuality,
          selectedAudio: selectedAudio,
          startPosition: Duration(seconds: initialSeconds),
        );
    final playableSource = initialPlayback.playableSource;
    final resolvedStartPosition =
        !playableSource.reliableSeek && initialSeconds > 0
        ? Duration.zero
        : Duration(seconds: initialSeconds);
    final title = formatPlayerTitleFromPlayItem(
      playInfo.item,
      fallbackTitle: fallbackTitle,
    );

    final source = MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: playInfo.item.guid,
      seasonGuid: playInfo.parentGuid,
      posterPath: resolvePlayerArtworkPathForPlayItem(playInfo.item),
      mediaGuid: initialPlayback.mediaGuid,
      mediaType: playInfo.item.type,
      ancestorName: playInfo.item.ancestorName,
      videoGuid: initialPlayback.videoGuid,
      directLinkQualityIndex: initialQuality?.isDirectLink == true
          ? initialQuality!.directLinkQualityIndex
          : null,
      videoWidth: playbackStream.videoStream?.width ?? 0,
      videoHeight: playbackStream.videoStream?.height ?? 0,
      proxySessionId: playableSource.proxySessionId,
      playLink: initialPlayback.playLink,
      url: playableSource.url,
      headers: playableSource.headers,
      title: title,
      seriesTitle: playInfo.item.tvTitle.trim().isNotEmpty
          ? playInfo.item.tvTitle.trim()
          : fallbackTitle.trim(),
      seasonNumber: playInfo.item.seasonNumber,
      tmdbId: playInfo.item.trimId,
      episodeNumber: playInfo.item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      audioTrackGuid: selectedAudio?.guid ?? playInfo.audioGuid,
      subtitleTrackGuid: selectedSubtitle?.guid ?? playInfo.subtitleGuid,
      resolution: playbackResolution,
      bitrate: playbackBitrate,
      durationSeconds: playInfo.item.duration,
      videoCodecName: playbackStream.videoStream?.codecName ?? '',
      videoProfile: playbackStream.videoStream?.profile ?? '',
      colorSpace: playbackStream.videoStream?.colorSpace ?? '',
      colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
      colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
      bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
      preferExternalSubtitle: preferExternalSubtitle,
      forceNativeProxy: playableSource.forceNativeProxy,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      playbackMode: initialPlayback.playbackMode,
      playbackSpeed: 1.0,
      audioTracks: playbackStream.audioStreams,
      subtitleTracks: subtitleTracks,
      qualities: mergedQualities,
    );

    if (!context.mounted) return null;
    final navigator = Navigator.of(context);
    final embeddedResult = await EmbeddedDetailLauncher.openFullscreenPlayer(
      title: title,
      source: source,
    );
    if (embeddedResult.handled) {
      return embeddedResult.data;
    }
    final result = await navigator.push(
      AppTransitions.playerRoute(MpvPlayerPage(title: title, source: source)),
    );
    return result is PlayDetailPlayerReturnData ? result : null;
  }
}
