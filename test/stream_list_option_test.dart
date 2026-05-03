import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/stream_list_option.dart';

void main() {
  group('StreamListOption', () {
    test('uses unknown version label for streams without video metadata', () {
      final options = StreamListOption.fromApiData({
        'video_streams': [
          {
            'media_guid': 'media-a',
            'guid': 'video-a',
            'resolution_type': '',
            'color_range_type': '',
            'duration': 0,
          },
          {
            'media_guid': 'media-b',
            'guid': 'video-b',
            'resolution_type': '',
            'color_range_type': '',
            'duration': 0,
          },
          {
            'media_guid': 'media-c',
            'guid': 'video-c',
            'resolution_type': '1080p',
            'color_range_type': 'SDR',
            'duration': 6522,
          },
        ],
      });

      expect(options.map((e) => e.label), [
        StreamListOption.unknownVersionLabel,
        StreamListOption.unknownVersionLabel,
        '1080P SDR',
      ]);
    });
  });
}
