import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/storage_management_service.dart';

void main() {
  group('播放统计占用文件识别', () {
    test('默认库与其 wal/shm/journal 附属文件都算进统计', () {
      const databaseName = SqflitePlayStatsDatabase.databaseName;

      expect(
        StorageManagementService.isPlayStatsDatabaseFileName(databaseName),
        isTrue,
      );
      for (final suffix in <String>['-wal', '-shm', '-journal']) {
        expect(
          StorageManagementService.isPlayStatsDatabaseFileName(
            '$databaseName$suffix',
          ),
          isTrue,
          reason: '附属文件 $suffix 漏算',
        );
      }
    });

    test('账号作用域库同样计入（此前只统计默认库导致漏算）', () {
      for (final fileName in <String>[
        'play_stats_account.db',
        'play_stats_user_1.db',
        'play_stats_user_1.db-wal',
        'play_stats_user_1.db-shm',
        'play_stats_user_1.db-journal',
      ]) {
        expect(
          StorageManagementService.isPlayStatsDatabaseFileName(fileName),
          isTrue,
          reason: '作用域库 $fileName 漏算',
        );
      }
    });

    test('其它数据库与非数据库文件不计入', () {
      for (final fileName in <String>[
        'danmaku_comment_cache.db',
        'downloads.db',
        'play_stats.txt',
        'play_stats_user_1.log',
        'other_play_stats.db',
        // 作用域后缀必须以 _ 开头，紧贴的数字属于别的库名。
        'play_stats2.db',
        // 备份/导出件不是活动数据库，不该算进占用。
        'play_stats.db.bak',
      ]) {
        expect(
          StorageManagementService.isPlayStatsDatabaseFileName(fileName),
          isFalse,
          reason: '$fileName 不应计入播放统计占用',
        );
      }
    });
  });
}
