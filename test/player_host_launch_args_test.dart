import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/controllers/mpv_player_controller.dart';
import 'package:fly_player/player/controllers/player_source_controller.dart';
import 'package:fly_player/player/models/player_host_launch_args.dart';

void main() {
  group('PlayerHostLaunchArgs', () {
    test('parses nested platform map into typed args', () {
      final args = PlayerHostLaunchArgs.fromPlatformMap({
        'title': 'Episode 1',
        'fromParallelHost': true,
        'layoutMode': 'pip',
        'source': {
          'itemGuid': 'item-1',
          'mediaGuid': 'media-1',
          'videoGuid': 'video-1',
          'url': 'https://example.com/video.mp4',
          'headers': {
            'Authorization': 'Bearer token',
          },
          'title': 'Episode 1',
          'playbackMode': 'directLinkQuality',
        },
      });

      expect(args, isNotNull);
      expect(args!.title, 'Episode 1');
      expect(args.fromParallelHost, isTrue);
      expect(args.layoutMode, 'pip');
      expect(args.source.itemGuid, 'item-1');
      expect(args.source.mediaGuid, 'media-1');
      expect(args.source.videoGuid, 'video-1');
      expect(args.source.url, 'https://example.com/video.mp4');
      expect(args.source.headers, {'Authorization': 'Bearer token'});
      expect(args.source.playbackMode, PlayerPlaybackMode.directLinkQuality);
    });

    test('returns null when title or source is missing', () {
      expect(
        PlayerHostLaunchArgs.fromNormalizedMap(const {'title': 'Only title'}),
        isNull,
      );
      expect(
        PlayerHostLaunchArgs.fromNormalizedMap(const {
          'source': <String, Object?>{},
        }),
        isNull,
      );
    });

    test('serializes back to stable map structure', () {
      const source = MpvMediaSource(
        itemGuid: 'item-2',
        mediaGuid: 'media-2',
        videoGuid: 'video-2',
        url: 'https://example.com/direct.mp4',
        headers: {'User-Agent': 'FlyPlayer'},
        title: 'Episode 2',
      );
      const args = PlayerHostLaunchArgs(
        title: 'Episode 2',
        source: source,
        fromParallelHost: false,
        layoutMode: 'fullscreen',
      );

      final encoded = args.toMap();

      expect(encoded['title'], 'Episode 2');
      expect(encoded['fromParallelHost'], isFalse);
      expect(encoded['layoutMode'], 'fullscreen');
      expect(encoded['source'], isA<Map<String, Object?>>());
      expect((encoded['source'] as Map<String, Object?>)['itemGuid'], 'item-2');
    });
  });
}
