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
        'lib/screens/poster_browse/poster_browse_screen.dart',
        'lib/screens/poster_browse/poster_browse_loader.dart',
      ];

      for (final path in publicBoundaryFiles) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('== MediaBackendKind.emby')));
        expect(source, isNot(contains('!= MediaBackendKind.emby')));
        expect(source, isNot(contains('isEmby')));
      }
    });

    test('播放统计模块不直连具体后端 API', () {
      // 回填与统计页的元数据能力统一走 PlayStatsMetadataGateway 抽象,
      // 飞牛实现由 MediaBackendRegistry 注入,统计模块自身不得再 import 任何后端客户端。
      for (final entity in Directory(
        'lib/services/play_stats',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        expect(
          source,
          isNot(contains(RegExp(r'''import\s+['"][^'"]*feiniu_api\.dart'''))),
          reason: '${entity.path} 不应直连 feiniu_api',
        );
        expect(
          source,
          isNot(contains(RegExp(r'''import\s+['"][^'"]*emby_api\.dart'''))),
          reason: '${entity.path} 不应直连 emby_api',
        );
      }
    });

    test('pages/screens 直连 feiniu_api 需在白名单内(白名单只许缩短,修一个删一行)', () {
      // 静态扫描 lib/pages、lib/screens、lib/widgets、lib/ui、lib/controllers 下所有
      // .dart 文件是否 import feiniu_api.dart。widgets/ui/controllers 当前无命中,
      // 扩根目录纯为封口,防止未来公共组件层/控制器层新出现直连
      // (controllers 已全量收口到 FeiniuDetailDataGateway,T13/A-034~A-038)。
      // 这是"公共页面绕过 MediaBackend 抽象层直连飞牛 API"的历史遗留面,新增 import 必须
      // 先接入后端抽象再落地,否则本测试会因"未在白名单"而失败;已收口的文件要把它从
      // 白名单里删掉——白名单只许缩短,不许再增长。
      const whitelist = <String>{
        'lib/pages/media_collection_detail_page.dart',
        'lib/pages/play_detail_entry_page.dart',
        'lib/pages/play_detail_page.dart',
        'lib/pages/tv_detail_page.dart',
        'lib/pages/tv_season_detail_page.dart',
        'lib/screens/category_items_screen.dart',
        'lib/screens/connection_screen.dart',
        'lib/screens/favorite_items_screen.dart',
        'lib/screens/fn_connect_web_login_page.dart',
        'lib/screens/media_info_screen.dart',
        'lib/screens/media_list_screen.dart',
        'lib/screens/person_detail_screen.dart',
        'lib/screens/play_detail_screen.dart',
        'lib/screens/poster_browse/poster_browse_loader.dart',
        'lib/screens/poster_browse/poster_browse_screen.dart',
        'lib/screens/search_screen.dart',
      };

      final importPattern = RegExp(
        r'''import\s+['"][^'"]*feiniu_api\.dart['"]''',
      );
      final actual = <String>{};
      for (final root in [
        'lib/pages',
        'lib/screens',
        'lib/widgets',
        'lib/ui',
        'lib/controllers',
      ]) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final normalized = entity.path.replaceAll('\\', '/');
          if (importPattern.hasMatch(entity.readAsStringSync())) {
            actual.add(normalized);
          }
        }
      }

      final unexpected = actual.difference(whitelist);
      final stale = whitelist.difference(actual);

      expect(
        unexpected,
        isEmpty,
        reason: '发现未在白名单内直连 feiniu_api 的文件,新代码请改走 MediaBackend 抽象: $unexpected',
      );
      expect(
        stale,
        isEmpty,
        reason: '白名单里的文件已不再直连 feiniu_api,请把这些条目从白名单删除: $stale',
      );
    });

    test('公共 UI 层 MediaBackendKind.feiniu 硬分支需在白名单内(白名单只许缩短,修一个删一行)', () {
      // 统计 lib/pages、lib/screens、lib/widgets、lib/ui 下 `MediaBackendKind.feiniu`
      // 字面量出现次数,按文件建立计数白名单。widgets/ui 当前无命中,扩根目录纯为封口,
      // 防止未来公共组件层新出现硬分支。这是"公共页面直接判断具体后端种类"的历史遗留面,
      // 新增判断必须先收敛进 MediaBackendCapabilities 的语义化 getter 再落地;已收口的文件
      // 要把整行计数条目删掉——白名单只许缩短,不许再增长。
      const whitelist = <String, int>{
        'lib/pages/media_collection_detail_page.dart': 1,
        'lib/pages/play_detail_page.dart': 2,
        'lib/pages/tv_detail_page.dart': 4,
        'lib/pages/tv_season_detail_page.dart': 1,
        'lib/screens/category_items_screen.dart': 2,
        'lib/screens/connection_screen.dart': 5,
        'lib/screens/favorite_items_screen.dart': 3,
        'lib/screens/media_list_screen.dart': 8,
        'lib/screens/person_detail_screen.dart': 1,
        'lib/screens/play_detail_screen.dart': 1,
        'lib/screens/poster_browse/poster_browse_loader.dart': 1,
      };

      final literalPattern = RegExp(r'MediaBackendKind\.feiniu');
      final actual = <String, int>{};
      for (final root in [
        'lib/pages',
        'lib/screens',
        'lib/widgets',
        'lib/ui',
      ]) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final normalized = entity.path.replaceAll('\\', '/');
          final count = literalPattern
              .allMatches(entity.readAsStringSync())
              .length;
          if (count > 0) {
            actual[normalized] = count;
          }
        }
      }

      final unexpectedFiles = actual.keys.toSet().difference(
        whitelist.keys.toSet(),
      );
      final staleFiles = whitelist.keys.toSet().difference(actual.keys.toSet());
      final mismatched = <String>[
        for (final key in actual.keys)
          if (whitelist.containsKey(key) && whitelist[key] != actual[key])
            '$key: 白名单=${whitelist[key]} 实际=${actual[key]}',
      ];

      expect(
        unexpectedFiles,
        isEmpty,
        reason:
            '发现未在白名单内出现 MediaBackendKind.feiniu 硬分支的文件,请收敛到能力模型: '
            '$unexpectedFiles',
      );
      expect(
        staleFiles,
        isEmpty,
        reason:
            '白名单里的文件已不再出现 MediaBackendKind.feiniu,请把这些条目从白名单删除: '
            '$staleFiles',
      );
      expect(
        mismatched,
        isEmpty,
        reason: '白名单计数与实际不符,请更新为最新计数(计数减少也要同步更新): $mismatched',
      );
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
