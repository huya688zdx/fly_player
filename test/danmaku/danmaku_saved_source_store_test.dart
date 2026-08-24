import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/danmaku/settings/danmaku_saved_source_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late DanmakuSavedSourceStore store;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'danmaku_saved_source_store_test_',
    );
    store = DanmakuSavedSourceStore(directoryPath: tempDirectory.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await store.clearAll();
  });

  tearDownAll(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('仅保存候选来源时不应擅自切换当前弹幕', () async {
    await store.saveSource(_source('10001'));

    expect(await store.loadActiveSourceKey('media-1'), isNull);
  });

  test('明确激活来源时应持久化统一后的来源键', () async {
    await store.saveSource(_source('10001'), activate: true);

    expect(await store.loadActiveSourceKey('media-1'), 'dandan:10001');
  });

  test('读取旧版纯数字激活键时应兼容为弹弹play来源键', () async {
    await store.setActiveSourceKey(mediaKey: 'media-1', sourceKey: '10001');

    expect(await store.loadActiveSourceKey('media-1'), 'dandan:10001');
  });

  test('自动匹配无结果只暂停六小时，过期后允许重试', () async {
    const nowMs = 10 * 60 * 60 * 1000;
    await store.saveAutoMatchBlockedReason(
      mediaKey: 'media-1',
      reason: DanmakuSavedSourceStore.autoNoResultReason(nowMs: nowMs),
    );

    expect(
      await store.isAutoMatchBlocked(
        'media-1',
        nowMs: nowMs + const Duration(hours: 5).inMilliseconds,
      ),
      isTrue,
    );
    expect(
      await store.isAutoMatchBlocked(
        'media-1',
        nowMs: nowMs + const Duration(hours: 6).inMilliseconds + 1,
      ),
      isFalse,
    );
  });
}

DanmakuSavedSource _source(String sourceKey) {
  return DanmakuSavedSource(
    type: DanmakuSavedSourceType.danDanPlay,
    mediaKey: 'media-1',
    sourceKey: sourceKey,
    label: '测试动画 第1话',
    commentCount: 10,
    updatedAtMs: 1,
  );
}
