import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/native_reentry_support.dart';

void main() {
  group('NativeReentrySupport.preserveEpisodesForServerReload', () {
    test('切画质重载后并回 episodes（Bug C：选集/连播数据源不丢）', () {
      final previous = <String, dynamic>{
        'itemGuid': 'ep-1',
        'episodes': <Map<String, dynamic>>[
          <String, dynamic>{'itemGuid': 'ep-1', 'episodeNumber': 1},
          <String, dynamic>{'itemGuid': 'ep-2', 'episodeNumber': 2},
        ],
      };
      // 重载产出的新 source map（MpvMediaSource.toMap 不含 episodes）。
      final reloaded = <String, dynamic>{
        'url': 'http://nas.test/new.m3u8',
        'itemGuid': 'ep-1',
      };

      final result = NativeReentrySupport.preserveEpisodesForServerReload(
        previous,
        reloaded,
      );

      expect(result['url'], 'http://nas.test/new.m3u8');
      expect(result['episodes'], isA<List>());
      expect((result['episodes'] as List), hasLength(2));
      expect((result['episodes'] as List).first, isA<Map>());
    });

    test('原 loadArgs 无 episodes 时不写空键', () {
      final previous = <String, dynamic>{'itemGuid': 'ep-1'};
      final reloaded = <String, dynamic>{'url': 'http://nas.test/new.m3u8'};

      final result = NativeReentrySupport.preserveEpisodesForServerReload(
        previous,
        reloaded,
      );

      expect(result.containsKey('episodes'), isFalse);
    });

    test('episodes 为空列表时不并回（避免覆盖成空选集）', () {
      final previous = <String, dynamic>{
        'itemGuid': 'ep-1',
        'episodes': <Map<String, dynamic>>[],
      };
      final reloaded = <String, dynamic>{'url': 'http://nas.test/new.m3u8'};

      final result = NativeReentrySupport.preserveEpisodesForServerReload(
        previous,
        reloaded,
      );

      expect(result.containsKey('episodes'), isFalse);
    });
  });
}
