import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';

void main() {
  test('弹弹play来源键统一使用命名空间前缀', () {
    final source = DanmakuSavedSource(
      type: DanmakuSavedSourceType.danDanPlay,
      mediaKey: 'episode-1',
      sourceKey: '12345',
      label: '测试动画',
      commentCount: 10,
      updatedAtMs: 1,
    );

    expect(source.sourceKey, 'dandan:12345');
  });

  test('弹弹play来源归一化不改变本地来源键', () {
    final source = DanmakuSavedSource(
      type: DanmakuSavedSourceType.localFile,
      mediaKey: 'episode-1',
      sourceKey: '12345',
      label: '本地弹幕',
      commentCount: 10,
      updatedAtMs: 1,
    );

    expect(source.sourceKey, '12345');
  });
}
