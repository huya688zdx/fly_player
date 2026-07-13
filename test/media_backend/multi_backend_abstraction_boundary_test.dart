import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_backend_registry.dart';

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

    test('播放入口通过 PlaybackHost 调度原生播放', () {
      final playbackEntryFiles = <String>[
        'lib/controllers/item_playback_launcher.dart',
        'lib/controllers/tv_season_playback_launcher.dart',
        'lib/pages/play_detail_page.dart',
        'lib/screens/download_list_screen.dart',
      ];

      for (final path in playbackEntryFiles) {
        final source = File(path).readAsStringSync();
        expect(source, contains('NativePlaybackHost'));
        expect(
          source,
          isNot(
            contains(
              RegExp(r'NativePlayerBridge\.(?:maybeLaunch|launch)\s*\('),
            ),
          ),
        );
      }
    });

    test('详情页仅在原生宿主启动成功时提前返回', () {
      final source = File('lib/pages/play_detail_page.dart').readAsStringSync();

      expect(
        source,
        contains(
          RegExp(
            r'if\s*\(\s*await\s+const\s+NativePlaybackHost\(\)\.launch\s*\(',
          ),
        ),
      );
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

    test('服务器族公共层不再写死 Emby 判断', () {
      final publicBoundaryFiles = <String>[
        'lib/providers/media_backend_provider.dart',
        'lib/screens/media_list_screen.dart',
        'lib/screens/media_list_screen_widgets.dart',
        'lib/screens/login_history_screen.dart',
      ];

      for (final path in publicBoundaryFiles) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('== MediaBackendKind.emby')));
        expect(source, isNot(contains('!= MediaBackendKind.emby')));
        expect(source, isNot(contains('isEmby')));
      }
    });

    test('服务器族后端从注册表描述符创建', () {
      final descriptor = MediaBackendRegistry.requireDescriptor(
        MediaBackendKind.emby,
      );

      expect(descriptor.kind, MediaBackendKind.emby);
      expect(descriptor.displayName, 'Emby');
      expect(descriptor.badgeText, 'E');
      expect(
        MediaBackendRegistry.serverDescriptors.map((item) => item.kind),
        contains(MediaBackendKind.emby),
      );
    });
  });
}
