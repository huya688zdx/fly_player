import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/playback/playback_source.dart';

void main() {
  group('MpvMediaSource contract', () {
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
  });
}
