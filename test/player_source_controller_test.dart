import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/playback/player_source_controller.dart';

void main() {
  group('PlayerSourceController.preferredInitialQuality', () {
    const original = PlaybackQualityOption(
      mediaGuid: 'media-1',
      videoGuid: 'video-original',
      resolution: 'Original',
      bitrate: 0,
      isDefault: 0,
      source: PlaybackQualitySource.originalProxy,
      directLinkQualityIndex: null,
    );
    const direct1080 = PlaybackQualityOption(
      mediaGuid: 'media-1',
      videoGuid: 'video-1080',
      resolution: '1080p',
      bitrate: 4000000,
      isDefault: 1,
      source: PlaybackQualitySource.directLink,
      directLinkQualityIndex: 0,
    );
    const direct720 = PlaybackQualityOption(
      mediaGuid: 'media-1',
      videoGuid: 'video-720',
      resolution: '720p',
      bitrate: 2500000,
      isDefault: 0,
      source: PlaybackQualitySource.directLink,
      directLinkQualityIndex: 1,
    );
    const server1080 = PlaybackQualityOption(
      mediaGuid: 'media-1',
      videoGuid: 'video-server-1080',
      resolution: '1080p',
      bitrate: 4000000,
      isDefault: 0,
      source: PlaybackQualitySource.serverSession,
      directLinkQualityIndex: null,
    );

    test('prefers the default direct-link quality by default', () {
      final selected = PlayerSourceController.preferredInitialQuality(
        const <PlaybackQualityOption>[server1080, direct1080, direct720],
      );

      expect(selected, direct1080);
    });

    test('can prefer the lowest direct-link quality on remote hosts', () {
      final selected = PlayerSourceController.preferredInitialQuality(
        const <PlaybackQualityOption>[original, direct1080, direct720],
        preferConservativeDirectLink: true,
      );

      expect(selected, direct720);
    });

    test('falls back to original proxy when no direct-link quality exists', () {
      final selected = PlayerSourceController.preferredInitialQuality(
        const <PlaybackQualityOption>[server1080, original],
      );

      expect(selected, original);
    });
  });

  group('PlayerSourceController.shouldPreferConservativeDirectLink', () {
    test('treats external hosts as conservative direct-link candidates', () {
      expect(
        PlayerSourceController.shouldPreferConservativeDirectLink(
          'https://media.example.com',
        ),
        isTrue,
      );
    });

    test('keeps local hosts on the normal startup path', () {
      expect(
        PlayerSourceController.shouldPreferConservativeDirectLink(
          'http://192.168.6.120:5666',
        ),
        isFalse,
      );
      expect(
        PlayerSourceController.shouldPreferConservativeDirectLink(
          'http://localhost:5666',
        ),
        isFalse,
      );
    });
  });

  group('PlayerSourceController.subtitle helpers', () {
    const externalTrack = SubtitleTrackOption(
      mediaGuid: 'media-1',
      guid: 'sub-external',
      title: 'External',
      codecName: 'ass',
      format: 'ass',
      language: 'eng',
      index: 1,
      isDefault: 0,
      forced: 0,
      isExternal: 1,
      extraFile: 1,
      isBitmap: 0,
    );
    const bitmapTrack = SubtitleTrackOption(
      mediaGuid: 'media-1',
      guid: 'sub-bitmap',
      title: 'PGS',
      codecName: 'hdmv_pgs_subtitle',
      format: 'pgs',
      language: 'eng',
      index: 2,
      isDefault: 0,
      forced: 0,
      isExternal: 0,
      extraFile: 0,
      isBitmap: 1,
    );

    test('requires an external file only when the track truly needs one', () {
      expect(
        PlayerSourceController.subtitleShouldUseExternalFile(
          externalTrack,
          const <String>{},
        ),
        isTrue,
      );
      expect(
        PlayerSourceController.subtitleShouldUseExternalFile(
          externalTrack,
          const <String>{'sub-external'},
        ),
        isFalse,
      );
      expect(
        PlayerSourceController.subtitleShouldUseExternalFile(
          bitmapTrack,
          const <String>{},
        ),
        isFalse,
      );
    });

    test('looks up subtitle tracks by guid', () {
      final resolved = PlayerSourceController.subtitleTrackByGuid(
        'sub-external',
        const <SubtitleTrackOption>[bitmapTrack, externalTrack],
      );

      expect(resolved, externalTrack);
      expect(
        PlayerSourceController.subtitleTrackByGuid(
          'missing',
          const <SubtitleTrackOption>[bitmapTrack, externalTrack],
        ),
        isNull,
      );
    });
  });
}
