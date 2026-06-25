import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/services/native_playback_reentry.dart';

/// 记录 start/progress/stopped 调用顺序与位置的假后端。
class _RecordingBackend implements MediaBackend {
  final List<String> calls = <String>[];

  @override
  Future<void> reportPlaybackStart({
    required String itemId,
    required String mediaSourceId,
    int positionSeconds = 0,
  }) async {
    calls.add('start:$itemId@$positionSeconds');
  }

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
    bool isPaused = false,
  }) async {
    calls.add('progress:$itemId@$positionSeconds');
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
  }) async {
    calls.add('stopped:$itemId@$positionSeconds');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在测试桩实现');
}

Map<String, dynamic> _progress(String itemGuid, int ts, {String media = 'm'}) {
  return <String, dynamic>{'itemGuid': itemGuid, 'mediaGuid': media, 'ts': ts};
}

void main() {
  test('首帧进度先 PlaybackStart 再 Progress', () async {
    final backend = _RecordingBackend();
    final reporter = EmbyPlaybackReporter(backend);
    await reporter.report(_progress('ep-1', 10));
    await reporter.report(_progress('ep-1', 20));
    expect(backend.calls, <String>[
      'start:ep-1@10',
      'progress:ep-1@10',
      'progress:ep-1@20',
    ]);
  });

  test('壳内切集：停旧会话（末位）+ 开新会话', () async {
    final backend = _RecordingBackend();
    final reporter = EmbyPlaybackReporter(backend);
    await reporter.report(_progress('ep-1', 10));
    await reporter.report(_progress('ep-1', 50)); // 旧集最后已知位
    await reporter.report(_progress('ep-2', 5)); // 切集
    expect(backend.calls, <String>[
      'start:ep-1@10',
      'progress:ep-1@10',
      'progress:ep-1@50',
      'stopped:ep-1@50', // 用旧集末次 ts 落定
      'start:ep-2@5',
      'progress:ep-2@5',
    ]);
  });

  test('空 itemGuid 跳过、不开会话', () async {
    final backend = _RecordingBackend();
    final reporter = EmbyPlaybackReporter(backend);
    await reporter.report(_progress('', 10));
    expect(backend.calls, isEmpty);
  });
}
