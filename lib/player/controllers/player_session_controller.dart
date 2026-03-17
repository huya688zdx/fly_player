import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import 'mpv_player_controller.dart';
import 'player_completion_controller.dart';
import 'player_source_controller.dart';

class PlayerSessionController {
  String currentItemGuid = '';
  String currentMediaType = '';
  String currentAncestorName = '';
  String currentTitle = '';
  String currentSeriesTitle = '';
  String currentSeasonGuid = '';
  int currentSeasonNumber = 0;
  int currentEpisodeNumber = 0;
  String currentTmdbId = '';
  String currentMediaGuid = '';
  String subtitleSourceMediaGuid = '';
  String currentVideoGuid = '';
  int? currentDirectLinkQualityIndex;
  int currentVideoWidth = 0;
  int currentVideoHeight = 0;
  String currentVideoCodecName = '';
  String currentVideoProfile = '';
  String currentColorSpace = '';
  String currentColorTransfer = '';
  String currentColorPrimaries = '';
  int currentBitDepth = 0;
  String? activeProxySessionId;
  String? activeSubtitleProxySessionId;
  String? currentPlayLink;
  String currentUrl = '';
  Map<String, String> currentHeaders = <String, String>{};
  bool currentReliableSeek = true;
  String? currentSeekProbeSummary;
  String? currentAudioGuid;
  String? currentSubtitleGuid;
  String currentResolution = '';
  int currentBitrate = 0;
  int durationSeconds = 0;
  double playbackSpeed = 1.0;
  Duration resumeStartPosition = Duration.zero;
  PlayerPlaybackMode playbackMode = PlayerPlaybackMode.originalQuality;
  List<AudioTrackOption> audioTracks = const <AudioTrackOption>[];
  List<SubtitleTrackOption> subtitleTracks = const <SubtitleTrackOption>[];
  List<PlaybackQualityOption> qualities = const <PlaybackQualityOption>[];

  int hydrateFromSource({
    required MpvMediaSource source,
    required PlayerCompletionController completionController,
    required int currentLoadNonceSeed,
  }) {
    currentItemGuid = source.itemGuid;
    currentMediaType = source.mediaType;
    currentAncestorName = source.ancestorName;
    currentTitle = source.title;
    currentSeriesTitle = source.seriesTitle;
    currentSeasonGuid = source.seasonGuid;
    currentSeasonNumber = source.seasonNumber;
    currentEpisodeNumber = source.episodeNumber;
    currentTmdbId = source.tmdbId;
    currentMediaGuid = source.mediaGuid;
    subtitleSourceMediaGuid = source.mediaGuid;
    currentVideoGuid = source.videoGuid;
    currentDirectLinkQualityIndex = source.directLinkQualityIndex;
    currentVideoWidth = source.videoWidth;
    currentVideoHeight = source.videoHeight;
    currentVideoCodecName = source.videoCodecName;
    currentVideoProfile = source.videoProfile;
    currentColorSpace = source.colorSpace;
    currentColorTransfer = source.colorTransfer;
    currentColorPrimaries = source.colorPrimaries;
    currentBitDepth = source.bitDepth;
    activeProxySessionId = source.proxySessionId;
    activeSubtitleProxySessionId = null;
    currentPlayLink = source.playLink;
    currentUrl = source.url;
    currentHeaders = Map<String, String>.from(source.headers);
    currentReliableSeek = source.reliableSeek;
    currentSeekProbeSummary = source.seekProbeSummary;
    currentAudioGuid = source.audioTrackGuid;
    currentSubtitleGuid = source.subtitleTrackGuid;
    currentResolution = source.resolution;
    currentBitrate = source.bitrate;
    durationSeconds = source.durationSeconds;
    playbackMode = source.playbackMode;
    resumeStartPosition = completionController.normalizedStartPosition(
      startPosition: source.startPosition,
      durationSeconds: source.durationSeconds,
    );
    playbackSpeed = source.playbackSpeed;
    audioTracks = List<AudioTrackOption>.from(source.audioTracks);
    subtitleTracks = List<SubtitleTrackOption>.from(source.subtitleTracks);
    qualities = List<PlaybackQualityOption>.from(source.qualities);
    return source.loadNonce > currentLoadNonceSeed
        ? source.loadNonce
        : currentLoadNonceSeed;
  }

  PlayerSourceSnapshot buildSourceSnapshot({
    required Set<String> serverFallbackSubtitleGuids,
  }) {
    return PlayerSourceSnapshot(
      itemGuid: currentItemGuid,
      mediaGuid: currentMediaGuid,
      subtitleSourceMediaGuid: subtitleSourceMediaGuid,
      videoGuid: currentVideoGuid,
      directLinkQualityIndex: currentDirectLinkQualityIndex,
      audioGuid: currentAudioGuid,
      subtitleGuid: currentSubtitleGuid,
      resolution: currentResolution,
      bitrate: currentBitrate,
      videoWidth: currentVideoWidth,
      videoHeight: currentVideoHeight,
      currentHeaders: currentHeaders,
      activeProxySessionId: activeProxySessionId,
      activeSubtitleProxySessionId: activeSubtitleProxySessionId,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      qualities: qualities,
      playbackMode: playbackMode,
      serverFallbackSubtitleGuids: serverFallbackSubtitleGuids,
    );
  }
}
