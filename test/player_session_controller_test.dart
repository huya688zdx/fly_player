import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/player/controllers/mpv_player_controller.dart';
import 'package:fly_player/player/controllers/player_completion_controller.dart';
import 'package:fly_player/player/controllers/player_session_controller.dart';
import 'package:fly_player/player/controllers/player_source_controller.dart';

void main() {
  group('PlayerSessionController', () {
    test('hydrates state from source and builds snapshot', () {
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
      const quality = PlaybackQualityOption(
        mediaGuid: 'media-1',
        videoGuid: 'video-1',
        resolution: '1080p',
        bitrate: 4000000,
        isDefault: 1,
        source: PlaybackQualitySource.directLink,
        directLinkQualityIndex: 0,
      );
      const source = MpvMediaSource(
        loadNonce: 12,
        itemGuid: 'item-1',
        mediaType: 'movie',
        ancestorName: 'Series',
        mediaGuid: 'media-1',
        seasonGuid: 'season-1',
        seasonNumber: 1,
        episodeNumber: 2,
        tmdbId: 'tmdb-1',
        videoGuid: 'video-1',
        directLinkQualityIndex: 0,
        videoWidth: 1920,
        videoHeight: 1080,
        proxySessionId: 'proxy-1',
        playLink: '/play/1',
        url: 'https://example.com/video.mp4',
        headers: {'Authorization': 'token'},
        title: 'Episode 2',
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
        playbackMode: PlayerPlaybackMode.directLinkQuality,
        playbackSpeed: 1.25,
        listenVideoModeEnabled: true,
        audioTracks: [audioTrack],
        subtitleTracks: [subtitleTrack],
        qualities: [quality],
      );

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
      expect(controller.currentMediaGuid, 'media-1');
      expect(controller.currentHeaders, {'Authorization': 'token'});
      expect(controller.playbackMode, PlayerPlaybackMode.directLinkQuality);
      expect(controller.listenVideoModeEnabled, isTrue);
      expect(controller.resumeStartPosition, const Duration(seconds: 45));
      expect(controller.audioTracks.single.guid, 'audio-1');
      expect(snapshot.subtitleGuid, 'sub-1');
      expect(snapshot.serverFallbackSubtitleGuids, {'server-sub'});
      expect(snapshot.qualities.single.resolution, '1080p');
    });
  });
}
