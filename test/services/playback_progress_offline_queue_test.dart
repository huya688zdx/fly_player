import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/playback_progress_offline_queue.dart';
import 'package:fly_player/utils/app_exception.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('服务器进度重放成功后删除队列项', () async {
    await PlaybackProgressOfflineQueue.enqueueServer(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      positionSeconds: 42,
    );

    Map<String, Object?>? captured;
    await PlaybackProgressOfflineQueue.flushServer((progress) async {
      captured = progress;
    });

    expect(captured, <String, Object?>{
      'itemId': 'item-1',
      'mediaSourceId': 'source-1',
      'positionSeconds': 42,
      'isPaused': false,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('playback_server_progress_offline_queue_v1'),
      isNull,
    );
  });

  test('服务器进度 transient 重放失败时保留队列项', () async {
    await PlaybackProgressOfflineQueue.enqueueServer(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      positionSeconds: 42,
    );

    await PlaybackProgressOfflineQueue.flushServer((_) async {
      throw const AppException(
        kind: AppExceptionKind.transient,
        action: 'test',
        message: 'temporary failure',
      );
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('playback_server_progress_offline_queue_v1'),
      isNotNull,
    );
  });
}
