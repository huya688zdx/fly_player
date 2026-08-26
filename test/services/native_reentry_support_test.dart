import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_session_reload.dart';
import 'package:fly_player/services/native_reentry_support.dart';

void main() {
  group('NativeReentrySupport.buildNativeEpisodeImageFields', () {
    test('根海报字段与选集字段共用同一同源策略', () {
      final fields = NativeReentrySupport.buildNativeImageFields(
        poster: 'https://nas.test:5666/poster.jpg',
        token: 'nas-token',
        accessCode: '访问码',
        baseUrl: 'https://nas.test:5666',
        usingLocal: false,
      );

      expect(fields['imageAuth'], 'nas-token');
      expect(
        fields['imageHeaders'],
        containsPair('x-access-code', base64Encode(utf8.encode('访问码'))),
      );
    });

    test('同源飞牛海报输出完整图片头并保留旧 imageAuth', () {
      final fields = NativeReentrySupport.buildNativeEpisodeImageFields(
        poster: 'https://nas.test:5666/poster.jpg',
        token: 'nas-token',
        accessCode: '访问码',
        baseUrl: 'https://nas.test:5666',
        usingLocal: false,
      );

      expect(fields['imageAuth'], 'nas-token');
      expect(fields['imageHeaders'], <String, String>{
        'Authorization': 'nas-token',
        'Trim-MC-token': 'nas-token',
        'x-access-code': base64Encode(utf8.encode('访问码')),
        'x-access-source': 'app',
      });
    });

    test('本地和跨源海报均不携带飞牛凭据', () {
      for (final fields in <Map<String, dynamic>>[
        NativeReentrySupport.buildNativeEpisodeImageFields(
          poster: 'file:///storage/poster.jpg',
          token: 'nas-token',
          accessCode: 'code',
          baseUrl: 'https://nas.test:5666',
          usingLocal: true,
        ),
        NativeReentrySupport.buildNativeEpisodeImageFields(
          poster: 'https://cdn.test/poster.jpg',
          token: 'nas-token',
          accessCode: 'code',
          baseUrl: 'https://nas.test:5666',
          usingLocal: false,
        ),
      ]) {
        expect(fields['imageAuth'], isEmpty);
        expect(fields['imageHeaders'], isEmpty);
      }
    });
  });

  group('NativeReentrySupport.resolveReloadRequestParams', () {
    const currentStart = Duration(seconds: 120);

    test('全保留：默认意图 → audio/subtitle/quality 皆 null，续播位沿用当前', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.audioGuid, isNull, reason: '保留当前音轨');
      expect(params.subtitleGuid, isNull, reason: '保留当前字幕');
      expect(params.qualityIndex, isNull, reason: '保留当前画质');
      expect(params.startPosition, currentStart);
    });

    test('切音轨：audioTrackId 透传，其余保留', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(audioTrackId: 'a-2'),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.audioGuid, 'a-2');
      expect(params.subtitleGuid, isNull);
      expect(params.qualityIndex, isNull);
    });

    test('切字幕轨：subtitleGuid 透传', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(subtitleTrackId: 's-3'),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.subtitleGuid, 's-3');
    });

    test('关闭字幕：subtitleDisabled → 空串', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(subtitleDisabled: true),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.subtitleGuid, '');
    });

    test('切画质（含保留音轨/字幕回归点）：合法下标透传，audio/subtitle 仍 null', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(qualityIndex: 1),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.qualityIndex, 1);
      expect(params.audioGuid, isNull, reason: '切画质保留当前音轨');
      expect(params.subtitleGuid, isNull, reason: '切画质保留当前字幕');
    });

    test('画质下标越界 → 回落为保留当前画质（不崩溃）', () {
      final over = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(qualityIndex: 9),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(over.qualityIndex, isNull);
      final negative = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(qualityIndex: -1),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(negative.qualityIndex, isNull);
    });

    test('指定起播位 → 覆盖当前续播位', () {
      final params = NativeReentrySupport.resolveReloadRequestParams(
        const MediaSessionReloadIntent(startPosition: Duration(seconds: 5)),
        qualityCount: 3,
        currentStartPosition: currentStart,
      );
      expect(params.startPosition, const Duration(seconds: 5));
    });
  });

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
