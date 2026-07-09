import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';

void main() {
  group('多后端抽象边界', () {
    test('播放 launcher 不再按具体后端上下文或桥接器分发', () {
      final launcherFiles = <String>[
        'lib/controllers/item_playback_launcher.dart',
        'lib/controllers/tv_season_playback_launcher.dart',
      ];

      for (final path in launcherFiles) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('FeiniuPlaybackContext')));
        expect(source, isNot(contains('EmbyPlaybackContext')));
        expect(source, isNot(contains('FeiniuPlaybackSourceBridge')));
        expect(source, isNot(contains('EmbyPlaybackSourceBridge')));
      }
    });

    test('能力模型用语义化 getter 区分飞牛遗留族与服务器族', () {
      expect(
        const MediaBackendCapabilities.feiniu().usesLegacyFeiniuFlow,
        isTrue,
      );
      expect(MediaBackendKind.feiniu.isServerFamily, isFalse);
      expect(MediaBackendKind.emby.isServerFamily, isTrue);

      expect(
        const MediaBackendCapabilities.server(
          kind: MediaBackendKind.emby,
        ).usesLegacyFeiniuFlow,
        isFalse,
      );
    });
  });
}
