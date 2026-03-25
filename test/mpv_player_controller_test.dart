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
        listenVideoModeEnabled: true,
      );

      final decoded = MpvMediaSource.fromMap(source.toMap());

      expect(decoded.listenVideoModeEnabled, isTrue);
      expect(decoded.videoGuid, 'video-1');
    });

    test('parses listen video mode from native state events', () {
      const fallback = MpvPlayerValue.initial();

      final value = MpvPlayerValue.fromEvent(<Object?, Object?>{
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
  });
}
