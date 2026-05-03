import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/player/controllers/weak_network_quality_recommender.dart';

PlaybackQualityOption _quality({
  required String resolution,
  required int bitrate,
  int? index,
}) {
  return PlaybackQualityOption(
    mediaGuid: 'media-$resolution',
    videoGuid: 'video-$resolution',
    resolution: resolution,
    bitrate: bitrate,
    isDefault: resolution == '1080p' ? 1 : 0,
    source: PlaybackQualitySource.directLink,
    directLinkQualityIndex: index,
  );
}

void main() {
  group('weak network quality recommender', () {
    test('chooses the highest bitrate quality that fits current speed', () {
      final qualities = <PlaybackQualityOption>[
        _quality(resolution: '1080p', bitrate: 8000000, index: 0),
        _quality(resolution: '720p', bitrate: 4000000, index: 1),
        _quality(resolution: '480p', bitrate: 2000000, index: 2),
      ];

      final recommendation = recommendWeakNetworkQuality(
        qualities: qualities,
        currentQuality: qualities.first,
        networkSpeedBytesPerSecond: 700000,
      );

      expect(recommendation, isNotNull);
      expect(recommendation!.quality.resolution, '720p');
    });

    test(
      'falls back to the next lower known bitrate when speed is too low',
      () {
        final qualities = <PlaybackQualityOption>[
          _quality(resolution: '1080p', bitrate: 8000000, index: 0),
          _quality(resolution: '720p', bitrate: 4000000, index: 1),
          _quality(resolution: '480p', bitrate: 2000000, index: 2),
        ];

        final recommendation = recommendWeakNetworkQuality(
          qualities: qualities,
          currentQuality: qualities.first,
          networkSpeedBytesPerSecond: 100000,
        );

        expect(recommendation, isNotNull);
        expect(recommendation!.quality.resolution, '720p');
      },
    );

    test(
      'returns null when current quality is already the best safe option',
      () {
        final qualities = <PlaybackQualityOption>[
          _quality(resolution: '1080p', bitrate: 8000000, index: 0),
          _quality(resolution: '720p', bitrate: 4000000, index: 1),
          _quality(resolution: '480p', bitrate: 2000000, index: 2),
        ];

        final recommendation = recommendWeakNetworkQuality(
          qualities: qualities,
          currentQuality: qualities[1],
          networkSpeedBytesPerSecond: 700000,
        );

        expect(recommendation, isNull);
      },
    );

    test('checks whether the downgrade is meaningful', () {
      final currentQuality = _quality(
        resolution: '1080p',
        bitrate: 8000000,
        index: 0,
      );
      final recommendedQuality = _quality(
        resolution: '720p',
        bitrate: 4000000,
        index: 1,
      );
      final nearCurrentQuality = _quality(
        resolution: '1080p high',
        bitrate: 7000000,
        index: 2,
      );

      expect(
        isMeaningfulWeakNetworkDowngrade(
          currentQuality: currentQuality,
          recommendedQuality: recommendedQuality,
        ),
        isTrue,
      );
      expect(
        isMeaningfulWeakNetworkDowngrade(
          currentQuality: currentQuality,
          recommendedQuality: nearCurrentQuality,
        ),
        isFalse,
      );
    });

    test('formats speed labels and buffering details', () {
      expect(formatWeakNetworkSpeedLabel(0), '-- KB/s');
      expect(formatWeakNetworkSpeedLabel(153600), '150 KB/s');
      expect(formatWeakNetworkSpeedLabel(1572864), '1.5 MB/s');

      expect(
        buildWeakNetworkBufferingDetails(
          networkSpeedBytesPerSecond: 153600,
          estimatedResumeWait: null,
        ),
        '\u5f53\u524d\u7f51\u901f 150 KB/s',
      );
      expect(
        buildWeakNetworkBufferingDetails(
          networkSpeedBytesPerSecond: 1572864,
          estimatedResumeWait: const Duration(seconds: 9),
        ),
        '\u5f53\u524d\u7f51\u901f 1.5 MB/s \u00b7 \u9884\u8ba1\u6062\u590d 9\u79d2',
      );
    });
  });
}
