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
    directLinkQualityIndex: null,
  );
  const quality480 = PlaybackQualityOption(
    mediaGuid: 'media-1',
    videoGuid: 'video-3',
    resolution: '480p',
    bitrate: 1200000,
    isDefault: 0,
    source: PlaybackQualitySource.serverSession,
    directLinkQualityIndex: null,
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
    directLinkQualityIndex: null,
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
    playbackMode: PlayerPlaybackMode.serverSession,
    playbackSpeed: 1.25,
    listenVideoModeEnabled: true,
    audioTracks: [audioTrack],
    subtitleTracks: [subtitleTrack],
    qualities: [quality1080, quality720, quality480],
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
      expect(controller.currentMediaGuid, 'media-1');
      expect(controller.currentHeaders, {'Authorization': 'token'});
      expect(controller.playbackMode, PlayerPlaybackMode.serverSession);
      expect(controller.listenVideoModeEnabled, isTrue);
      expect(controller.resumeStartPosition, const Duration(seconds: 45));
      expect(controller.audioTracks.single.guid, 'audio-1');
      expect(snapshot.subtitleGuid, 'sub-1');
      expect(snapshot.serverFallbackSubtitleGuids, {'server-sub'});
      expect(snapshot.qualities.first.resolution, '1080p');
      expect(controller.committedResolution, '1080p');
      expect(
        controller.committedPlaybackMode,
        PlayerPlaybackMode.serverSession,
      );
      expect(controller.committedSubtitleSelection.normalizedGuid, 'sub-1');
    });

    test(
      'builds selection request from committed state and keeps external subtitle',
      () {
        final controller = PlayerSessionController()
          ..hydrateFromSource(
            source: source,
            completionController: PlayerCompletionController(),
            currentLoadNonceSeed: 0,
          )
          ..currentSubtitleGuid = 'sub-external';

        final request = controller.createSelectionRequest(
          quality: quality480,
          subtitleSelection: controller.currentSubtitleSelection(
            subtitleExplicitlyDisabled: false,
            pendingExternalSubtitlePath: '/tmp/sub.ass',
          ),
          startPosition: const Duration(minutes: 5),
          pausedAfterReload: true,
        );

        expect(request.transitionToken, greaterThan(0));
        expect(request.quality, quality480);
        expect(request.subtitleSelection.isExternal, isTrue);
        expect(request.subtitleSelection.normalizedGuid, 'sub-external');
        expect(
          request.subtitleSelection.normalizedExternalPath,
          '/tmp/sub.ass',
        );
        expect(request.startPosition, const Duration(minutes: 5));
        expect(request.pausedAfterReload, isTrue);
      },
    );

    test(
      'createSelectionRequest without explicit quality keeps subtitle change quality-neutral',
      () {
        final controller = PlayerSessionController()
          ..hydrateFromSource(
            source: source,
            completionController: PlayerCompletionController(),
            currentLoadNonceSeed: 0,
          );

        final request = controller.createSelectionRequest(
          subtitleSelection: const PlayerSubtitleSelection.managed('sub-1'),
          startPosition: const Duration(seconds: 20),
          pausedAfterReload: false,
        );

        expect(request.quality, isNull);
        expect(request.subtitleSelection.normalizedGuid, 'sub-1');
      },
    );

    test(
      'committed quality option stays on committed state while target is pending',
      () {
        final controller = PlayerSessionController()
          ..hydrateFromSource(
            source: source,
            completionController: PlayerCompletionController(),
            currentLoadNonceSeed: 0,
          );

        final request = controller.createSelectionRequest(
          quality: quality480,
          startPosition: const Duration(seconds: 10),
          pausedAfterReload: false,
        );
        controller.beginSelectionTransition(request);

        expect(
          controller.findCommittedQualityOption(<PlaybackQualityOption>[
            quality1080,
            quality720,
            quality480,
          ]),
          quality1080,
        );
      },
    );

    test(
      'createSelectionRequest inherits pending target quality during transition',
      () {
        final controller = PlayerSessionController()
          ..hydrateFromSource(
            source: source,
            completionController: PlayerCompletionController(),
            currentLoadNonceSeed: 0,
          );

        final qualityRequest = controller.createSelectionRequest(
          quality: quality720,
          startPosition: const Duration(seconds: 10),
          pausedAfterReload: false,
        );
        controller.beginSelectionTransition(qualityRequest);

        final subtitleRequest = controller.createSelectionRequest(
          subtitleSelection: const PlayerSubtitleSelection.managed('sub-1'),
          startPosition: const Duration(seconds: 12),
          pausedAfterReload: false,
        );

        expect(subtitleRequest.quality, quality720);
      },
    );

    test(
      'runtime sync updates snapshot quality without changing committed state',
      () {
        final controller = PlayerSessionController()
          ..hydrateFromSource(
            source: source,
            completionController: PlayerCompletionController(),
            currentLoadNonceSeed: 0,
          );

        final runtimeSource = source.copyWith(
          videoGuid: 'video-2',
          resolution: '720p',
          bitrate: 2500000,
          url: 'https://example.com/720.m3u8',
        );

        controller.syncRuntimeStateFromSource(source: runtimeSource);
        final snapshot = controller.buildSourceSnapshot(
          serverFallbackSubtitleGuids: const <String>{},
        );

        expect(snapshot.videoGuid, 'video-2');
        expect(snapshot.resolution, '720p');
        expect(snapshot.bitrate, 2500000);
        expect(snapshot.playbackMode, PlayerPlaybackMode.serverSession);
        expect(controller.committedVideoGuid, 'video-1');
        expect(controller.committedResolution, '1080p');
      },
    );

    test('stale transition commit is ignored and latest request wins', () {
      final controller = PlayerSessionController()
        ..hydrateFromSource(
          source: source,
          completionController: PlayerCompletionController(),
          currentLoadNonceSeed: 0,
        );

      final request480 = controller.createSelectionRequest(
        quality: quality480,
        startPosition: const Duration(seconds: 10),
        pausedAfterReload: false,
      );
      controller.beginSelectionTransition(request480);

      final request720 = controller.createSelectionRequest(
        quality: quality720,
        startPosition: const Duration(seconds: 12),
        pausedAfterReload: false,
      );
      controller.beginSelectionTransition(request720);

      controller.scheduleSelectionCommit(
        transitionToken: request480.transitionToken,
        loadNonce: 101,
        request: request480,
      );
      final staleCommit = controller.commitSelectionIfReady(
        loadNonce: 101,
        mediaGuid: 'media-1',
        videoGuid: 'video-3',
        directLinkQualityIndex: null,
        audioGuid: 'audio-1',
        subtitleSelection: const PlayerSubtitleSelection.managed('sub-1'),
        resolution: '480p',
        bitrate: 1200000,
        playbackMode: PlayerPlaybackMode.serverSession,
      );
      expect(staleCommit, isNull);
      expect(controller.committedResolution, '1080p');

      controller.scheduleSelectionCommit(
        transitionToken: request720.transitionToken,
        loadNonce: 102,
        request: request720,
      );
      final latestCommit = controller.commitSelectionIfReady(
        loadNonce: 102,
        mediaGuid: 'media-1',
        videoGuid: 'video-2',
        directLinkQualityIndex: null,
        audioGuid: 'audio-1',
        subtitleSelection: const PlayerSubtitleSelection.managed('sub-1'),
        resolution: '720p',
        bitrate: 2500000,
        playbackMode: PlayerPlaybackMode.serverSession,
      );
      expect(latestCommit, isNotNull);
      expect(controller.committedResolution, '720p');
      expect(controller.committedVideoGuid, 'video-2');
    });

    test('discarding failed transition keeps committed state unchanged', () {
      final controller = PlayerSessionController()
        ..hydrateFromSource(
          source: source,
          completionController: PlayerCompletionController(),
          currentLoadNonceSeed: 0,
        );

      final request = controller.createSelectionRequest(
        quality: quality480,
        startPosition: const Duration(seconds: 10),
        pausedAfterReload: false,
      );
      controller.beginSelectionTransition(request);
      controller.discardSelectionTransition(request.transitionToken);

      expect(controller.committedResolution, '1080p');
      expect(controller.committedVideoGuid, 'video-1');
      expect(controller.targetSelectionRequest, isNull);
    });
  });
}
