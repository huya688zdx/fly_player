import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/controllers/mpv_player_controller.dart';

void main() {
  group('Mpv player listen video mode', () {
    test('round-trips media source listen video mode', () {
      const source = MpvMediaSource(
        loadNonce: 7,
        itemGuid: 'item-1',
        mediaGuid: 'media-1',
        videoGuid: 'video-1',
        url: 'https://example.com/video.mp4',
        headers: <String, String>{'Authorization': 'token'},
        title: 'Episode 1',
        startPaused: true,
        listenVideoModeEnabled: true,
      );

      final decoded = MpvMediaSource.fromMap(source.toMap());

      expect(decoded.listenVideoModeEnabled, isTrue);
      expect(decoded.startPaused, isTrue);
      expect(decoded.videoGuid, 'video-1');
    });

    test('round-trips external local source flags', () {
      const source = MpvMediaSource(
        loadNonce: 8,
        itemGuid: 'local-item',
        mediaGuid: 'local-media',
        videoGuid: 'local-video',
        url: 'content://media/external/video/media/42',
        headers: <String, String>{},
        title: 'Local Video',
        isDownloadedFile: true,
        externalLocalSource: true,
        danmakuAutoSearchAllowed: false,
        externalLocalFileSizeBytes: 123456,
      );

      final decoded = MpvMediaSource.fromMap(source.toMap());

      expect(decoded.externalLocalSource, isTrue);
      expect(decoded.danmakuAutoSearchAllowed, isFalse);
      expect(decoded.externalLocalFileSizeBytes, 123456);
      expect(decoded.isDownloadedFile, isTrue);
      expect(decoded.url, 'content://media/external/video/media/42');
    });

    test('external local source flags have conservative defaults', () {
      const source = MpvMediaSource(
        itemGuid: 'item-1',
        mediaGuid: 'media-1',
        videoGuid: 'video-1',
        url: 'https://example.com/video.mp4',
        headers: <String, String>{},
        title: 'Episode 1',
      );

      final decoded = MpvMediaSource.fromMap(source.toMap());

      expect(decoded.externalLocalSource, isFalse);
      expect(decoded.danmakuAutoSearchAllowed, isTrue);
      expect(decoded.externalLocalFileSizeBytes, 0);
    });

    test('parses listen video mode from native state events', () {
      const fallback = MpvPlayerValue.initial();

      final value = MpvPlayerValue.fromEvent(const <Object?, Object?>{
        'ready': true,
        'nativeLibLoaded': true,
        'listenVideoModeEnabled': true,
        'statusText': 'Listen video mode enabled',
      }, fallback: fallback);

      expect(value.ready, isTrue);
      expect(value.nativeLibLoaded, isTrue);
      expect(value.listenVideoModeEnabled, isTrue);
      expect(value.statusText, 'Listen video mode enabled');
    });

    test('parses weak network fields from native state events', () {
      const fallback = MpvPlayerValue.initial();

      final value = MpvPlayerValue.fromEvent(const <Object?, Object?>{
        'playbackPhase': 'buffering',
        'weakNetworkMode': true,
        'networkSpeedBytesPerSecond': 262144,
        'rebufferTargetMs': 8000,
        'estimatedResumeWaitMs': 12000,
      }, fallback: fallback);

      expect(value.playbackPhase, MpvPlaybackPhase.buffering);
      expect(value.weakNetworkMode, isTrue);
      expect(value.networkSpeedBytesPerSecond, 262144);
      expect(value.rebufferTarget, const Duration(seconds: 8));
      expect(value.estimatedResumeWait, const Duration(seconds: 12));
    });
  });
}
