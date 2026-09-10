import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/storage_management_host.dart';

void main() {
  const host = DesktopStorageManagementHost();

  test('概览：桌面端原生侧统计归零且截图不受限', () async {
    final overview = await host.getStorageOverview();

    final playback = overview['playbackCache']! as Map<Object?, Object?>;
    expect(playback['bytes'], 0);
    expect(playback['fileCount'], 0);
    expect(playback['completeCount'], 0);
    expect(playback['active'], isFalse);

    expect(overview['danmakuAiCache'], <String, Object?>{
      'bytes': 0,
      'fileCount': 0,
    });
    expect(overview['otherCache'], <String, Object?>{
      'bytes': 0,
      'fileCount': 0,
    });

    final screenshots = overview['screenshots']! as Map<Object?, Object?>;
    expect(screenshots['bytes'], 0);
    expect(screenshots['fileCount'], 0);
    expect(screenshots['restricted'], isFalse);

    expect(overview['nativeSettingsBytes'], 0);
  });

  test('清理动作：Android 专属项按成功空操作返回，未知动作返回 unknown_action', () async {
    for (final action in const <String>[
      'clearPlaybackCache',
      'clearDanmakuAiCache',
      'clearOtherCache',
      'clearParallelWindowSettings',
      'clearScopedTreeAccess',
    ]) {
      expect(
        (await host.clearStorageAction(action))['success'],
        isTrue,
        reason: '$action 应按成功空操作返回',
      );
    }

    final screenshots = await host.clearStorageAction('clearScreenshots');
    expect(screenshots['success'], isTrue);
    expect(screenshots['restricted'], isFalse);
    expect(screenshots['deletedCount'], 0);

    expect(
      (await host.clearStorageAction('unknown_action'))['code'],
      'unknown_action',
    );
  });

  test('缓存与权限：桌面端无播放缓存、文件访问视为已授权', () async {
    expect(await host.listPlaybackCacheEntries(), isEmpty);
    expect(
      (await host.clearPlaybackCacheEntries(const <String>[
        'resource-1',
      ]))['success'],
      isTrue,
    );

    final downloadable = await host
        .queryCachedDownloadable(const <String, Object?>{
          'itemGuid': 'item-1',
          'mediaGuid': 'media-1',
          'videoGuid': 'video-1',
          'resourceKey': 'resource-1',
        });
    expect(downloadable['found'], isFalse);
    expect(downloadable['downloadable'], isFalse);
    expect(downloadable['code'], 'not_found');

    expect(
      (await host.promoteCachedMedia(const <String, Object?>{
        'itemGuid': 'item-1',
        'targetMode': 'appExternalMovies',
      }))['success'],
      isFalse,
    );

    expect(await host.hasFileAccess(), isTrue);
    expect(await host.requestFileAccess(), isTrue);
  });
}
