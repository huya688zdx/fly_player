import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/api/dandanplay_config.dart';

void main() {
  test('Windows linked worktree 能读取主工作区的 DanDanPlay 配置', () async {
    final originalCurrent = Directory.current;
    final sandbox = await Directory.systemTemp.createTemp(
      'dandanplay-windows-config-',
    );
    final mainWorktree = Directory('${sandbox.path}/main')..createSync();
    final linkedWorktree = Directory('${sandbox.path}/linked')..createSync();
    final linkedGitDirectory = Directory(
      '${mainWorktree.path}/.git/worktrees/desktop-playback-poc',
    )..createSync(recursive: true);
    Directory('${mainWorktree.path}/android').createSync();
    Directory('${linkedWorktree.path}/android').createSync();
    File(
      '${linkedWorktree.path}/.git',
    ).writeAsStringSync('gitdir: ${linkedGitDirectory.path}');
    File(
      '${linkedWorktree.path}/android/local.properties',
    ).writeAsStringSync('sdk.dir=C:\\Android\\Sdk\n');
    File('${mainWorktree.path}/android/local.properties').writeAsStringSync(
      'DANDANPLAY_APP_ID=test-app\n'
      'DANDANPLAY_APP_SECRET=test-secret\n',
    );

    Directory.current = linkedWorktree;
    try {
      await DanDanPlayConfig.clearCachedConfig();
      final config = await DanDanPlayConfig.ensureLoaded(forceRefresh: true);

      expect(config.configured, isTrue);
      expect(config.appId, 'test-app');
      expect(config.appSecrets, contains('test-secret'));
    } finally {
      Directory.current = originalCurrent;
      await DanDanPlayConfig.clearCachedConfig();
      await sandbox.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
