import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/player/controllers/mpv_player_controller.dart';
import 'package:fly_player/player/controllers/player_completion_controller.dart';
import 'package:fly_player/player/controllers/player_session_controller.dart';
import 'package:fly_player/player/controllers/player_source_controller.dart';

void main() {
  const audioTrack = AudioTrackOption(
    mediaGuid: 'media-1',
    guid: 'audio-1',
    title: 'Stereo',
    codecName: 'aac',
    profile: '',
    language: 'eng',
    audioType: 'main',
    channelLayout: 'stereo',
    channels: 2,
    sampleRate: 48000,
    bps: 128000,
    index: 1,
    isDefault: 1,
  );
  const subtitleTrack = SubtitleTrackOption(
    mediaGuid: 'media-1',
    guid: 'sub-1',
    title: 'English',
    codecName: 'srt',
    format: 'srt',
    language: 'eng',
    index: 2,
    isDefault: 1,
    forced: 0,
    isExternal: 0,
    extraFile: 0,
    isBitmap: 0,
  );
  const quality1080 = PlaybackQualityOption(
    mediaGuid: 'media-1',
    videoGuid: 'video-1',
    resolution: '1080p',
    bitrate: 4000000,
    isDefault: 1,
    source: PlaybackQualitySource.serverSession,
    directLinkQualityIndex: null,
  );
  const quality720 = PlaybackQualityOption(
    mediaGuid: 'media-1',
    videoGuid: 'video-2',
    resolution: '720p',
    bitrate: 2500000,
    isDefault: 0,
    source: PlaybackQualitySource.serverSession,
    directLinkQualityIndex: 2,
  );
  const source = MpvMediaSource(
    loadNonce: 12,
    itemGuid: 'item-1',
    seriesGuid: 'series-1',
    mediaType: 'movie',
    ancestorName: 'Series',
    mediaGuid: 'media-1',
    seasonGuid: 'season-1',
    seasonNumber: 1,
    episodeNumber: 2,
    tmdbId: 'tmdb-1',
    videoGuid: 'video-1',
    directLinkQualityIndex: null,
    videoWidth: 1920,
    videoHeight: 1080,
    proxySessionId: 'proxy-1',
    playLink: '/play/1',
    url: 'https://example.com/video.mp4',
    headers: {'Authorization': 'token'},
    title: 'Episode 2',
    seriesTitle: 'Series',
    startPosition: Duration(seconds: 45),
    audioTrackGuid: 'audio-1',
    subtitleTrackGuid: 'sub-1',
    resolution: '1080p',
    bitrate: 4000000,
    durationSeconds: 3600,
    videoCodecName: 'hevc',
    videoProfile: 'main10',
    colorSpace: 'bt709',
    colorTransfer: 'bt709',
    colorPrimaries: 'bt709',
    bitDepth: 10,
    reliableSeek: false,
    seekProbeSummary: 'direct',
    playbackMode: PlayerPlaybackMode.serverSession,
    playbackSpeed: 1.25,
    listenVideoModeEnabled: true,
    audioTracks: [audioTrack],
    subtitleTracks: [subtitleTrack],
    qualities: [quality1080, quality720],
  );

  group('PlayerSessionController', () {
    test('hydrates state from source and builds snapshot', () {
      final controller = PlayerSessionController();
      final nextLoadNonceSeed = controller.hydrateFromSource(
        source: source,
        completionController: PlayerCompletionController(),
        currentLoadNonceSeed: 5,
      );
      final snapshot = controller.buildSourceSnapshot(
        serverFallbackSubtitleGuids: {'server-sub'},
      );

      expect(nextLoadNonceSeed, 12);
      expect(controller.currentItemGuid, 'item-1');
      expect(controller.currentSeriesGuid, 'series-1');
      expect(controller.currentSeriesTitle, 'Series');
      expect(controller.currentMediaGuid, 'media-1');
      expect(controller.currentVideoGuid, 'video-1');
      expect(controller.currentHeaders, {'Authorization': 'token'});
      expect(controller.playbackMode, PlayerPlaybackMode.serverSession);
      expect(controller.listenVideoModeEnabled, isTrue);
      expect(controller.resumeStartPosition, const Duration(seconds: 45));
      expect(controller.audioTracks.single.guid, 'audio-1');
      expect(snapshot.subtitleGuid, 'sub-1');
      expect(snapshot.serverFallbackSubtitleGuids, {'server-sub'});
      expect(snapshot.qualities.first.resolution, '1080p');
      expect(snapshot.resolution, '1080p');
      expect(snapshot.playbackMode, PlayerPlaybackMode.serverSession);
    });

    test('fully watched progress is normalized back to the beginning', () {
      final controller = PlayerSessionController();

      controller.hydrateFromSource(
        source: source.copyWith(startPosition: const Duration(hours: 1)),
        completionController: PlayerCompletionController(),
        currentLoadNonceSeed: 20,
      );

      expect(controller.resumeStartPosition, Duration.zero);
    });

    test('buildSourceSnapshot reflects runtime-updated playback fields', () {
      final controller = PlayerSessionController()
        ..hydrateFromSource(
          source: source,
          completionController: PlayerCompletionController(),
          currentLoadNonceSeed: 0,
        )
        ..currentVideoGuid = quality720.videoGuid
        ..currentDirectLinkQualityIndex = quality720.directLinkQualityIndex
        ..currentAudioGuid = audioTrack.guid
        ..currentSubtitleGuid = subtitleTrack.guid
        ..currentResolution = quality720.resolution
        ..currentBitrate = quality720.bitrate
        ..currentVideoWidth = 1280
        ..currentVideoHeight = 720
        ..currentHeaders = <String, String>{'Range': 'bytes=0-'}
        ..activeProxySessionId = 'proxy-2'
        ..activeSubtitleProxySessionId = 'subtitle-proxy-1'
        ..playbackMode = PlayerPlaybackMode.directLinkQuality;

      final snapshot = controller.buildSourceSnapshot(
        serverFallbackSubtitleGuids: const <String>{'sub-fallback'},
      );

      expect(snapshot.videoGuid, 'video-2');
      expect(snapshot.directLinkQualityIndex, 2);
      expect(snapshot.resolution, '720p');
      expect(snapshot.bitrate, 2500000);
      expect(snapshot.videoWidth, 1280);
      expect(snapshot.videoHeight, 720);
      expect(snapshot.currentHeaders, {'Range': 'bytes=0-'});
      expect(snapshot.activeProxySessionId, 'proxy-2');
      expect(snapshot.activeSubtitleProxySessionId, 'subtitle-proxy-1');
      expect(snapshot.playbackMode, PlayerPlaybackMode.directLinkQuality);
      expect(snapshot.serverFallbackSubtitleGuids, {'sub-fallback'});
    });
  });
}
