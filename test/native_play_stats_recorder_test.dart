import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/play_stats/native_play_stats_recorder.dart';
import 'package:fly_player/services/play_stats/play_stats_models.dart';
import 'package:fly_player/services/play_stats/play_stats_session_controller.dart';

void main() {
  late _FakeSessionController controller;
  late NativePlayStatsRecorder recorder;

  setUp(() {
    controller = _FakeSessionController();
    recorder = NativePlayStatsRecorder(sessionController: controller);
  });

  tearDown(() => recorder.dispose());

  test('onLaunch 用 loadArgs 元数据开 manual 会话', () async {
    await recorder.onLaunch(
      _loadArgs(
        itemGuid: 'ep-1',
        title: '第 1 集',
        seriesTitle: '某剧',
        mediaType: 'Episode',
        durationSeconds: 1200,
        startPositionMs: 5000,
      ),
    );

    expect(controller.started, hasLength(1));
    final context = controller.started.single;
    expect(context.startSource, PlayStartSource.manual);
    expect(context.startPositionMs, 5000);
    expect(context.meta.videoId, 'ep-1');
    expect(context.meta.title, '第 1 集');
    expect(context.meta.animeTitle, '某剧');
    expect(context.meta.videoKind, 'episode');
    expect(context.meta.mediaDurationMs, 1200 * 1000);
  });

  test('mediaType=Movie 映射 movie,无剧集特征也判 movie', () async {
    await recorder.onLaunch(
      _loadArgs(
        itemGuid: 'mv-1',
        seriesGuid: '',
        seasonGuid: '',
        episodeNumber: 0,
        mediaType: 'Movie',
      ),
    );
    expect(controller.started.single.meta.videoKind, 'movie');
  });

  test('onProgress 秒转毫秒喂 updateProgress,isPaused 透传', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 30, duration: 1200),
    );
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 33, duration: 1200, isPaused: true),
    );

    expect(controller.progressUpdates, hasLength(2));
    expect(controller.progressUpdates[0]['positionMs'], 30 * 1000);
    expect(controller.progressUpdates[0]['mediaDurationMs'], 1200 * 1000);
    expect(controller.progressUpdates[0]['paused'], false);
    expect(controller.progressUpdates[1]['paused'], true);
  });

  test('itemGuid 变化用缓存元数据切 manualSwitch 会话', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    recorder.cacheSource(_loadArgs(itemGuid: 'ep-2', title: '第 2 集'));

    // 预取解析只缓存,不开会话。
    expect(controller.started, hasLength(1));

    await recorder.onProgress(
      _progress(itemGuid: 'ep-2', ts: 3, duration: 1200),
    );

    expect(controller.started, hasLength(2));
    expect(controller.started[1].startSource, PlayStartSource.manualSwitch);
    expect(controller.started[1].meta.title, '第 2 集');
    expect(controller.started[1].startPositionMs, 3 * 1000);
  });

  test('无 launch 的孤儿进度以最小元数据开 systemResume 会话', () async {
    await recorder.onProgress(
      _progress(itemGuid: 'ep-x', ts: 10, duration: 600),
    );

    expect(controller.started, hasLength(1));
    expect(controller.started.single.startSource, PlayStartSource.systemResume);
    expect(controller.started.single.meta.videoId, 'ep-x');
  });

  test('每 5 个进度样本 flush 一次 periodic', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    for (var ts = 3; ts <= 15; ts += 3) {
      await recorder.onProgress(
        _progress(itemGuid: 'ep-1', ts: ts, duration: 1200),
      );
    }
    expect(controller.flushReasons, ['periodic']);
  });

  test('空闲超时收口会话,后续进度重开会话', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 3, duration: 1200),
    );

    await recorder.handleIdleTimeout();

    expect(controller.finishReasons, ['idle_timeout']);

    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 6, duration: 1200),
    );
    expect(controller.started, hasLength(2));
    expect(controller.started[1].startSource, PlayStartSource.systemResume);
  });

  test('externalLocalSource 条目完全不入统计', () async {
    await recorder.onLaunch(
      _loadArgs(itemGuid: 'local-1', externalLocalSource: true),
    );
    await recorder.onProgress(
      _progress(itemGuid: 'local-1', ts: 3, duration: 600),
    );

    expect(controller.started, isEmpty);
    expect(controller.progressUpdates, isEmpty);
  });

  test('cacheSourceFromLoadArgsJson 解析 JSON 字符串入缓存', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    recorder.cacheSourceFromLoadArgsJson(
      '{"itemGuid":"ep-9","title":"第 9 集","seriesGuid":"series-1",'
      '"seriesTitle":"某剧","mediaType":"Episode","durationSeconds":900}',
    );
    await recorder.onProgress(
      _progress(itemGuid: 'ep-9', ts: 3, duration: 900),
    );

    expect(controller.started[1].meta.title, '第 9 集');
  });

  test('cacheSourceFromLoadArgsJson 传坏 JSON 不崩溃且不入缓存', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));

    // 语法错误的 JSON。
    recorder.cacheSourceFromLoadArgsJson('{oops');
    // 合法 JSON 但顶层不是 Map。
    recorder.cacheSourceFromLoadArgsJson('[1,2]');

    // 两者都不应写入缓存:用一个不带元数据的 itemGuid 触发 onProgress,
    // 若曾经错误入缓存,这里会拿到脏的 meta。
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 3, duration: 1200),
    );

    // 没有崩溃、原有会话正常运作即视为通过。
    expect(controller.started, hasLength(1));
    expect(controller.progressUpdates, hasLength(1));
  });

  test('10 个进度样本 flush 两次 periodic(计数归零后重新累积)', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    for (var i = 0; i < 10; i++) {
      await recorder.onProgress(
        _progress(itemGuid: 'ep-1', ts: 3 + i * 3, duration: 1200),
      );
    }
    expect(controller.flushReasons, ['periodic', 'periodic']);
  });

  test('暂停心跳不计入 flush 采样计数', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    // 4 个播放样本。
    for (var i = 0; i < 4; i++) {
      await recorder.onProgress(
        _progress(itemGuid: 'ep-1', ts: 3 + i * 3, duration: 1200),
      );
    }
    // 若干暂停心跳,不应推进 flush 计数。
    for (var i = 0; i < 6; i++) {
      await recorder.onProgress(
        _progress(itemGuid: 'ep-1', ts: 15, duration: 1200, isPaused: true),
      );
    }
    expect(controller.flushReasons, isEmpty);

    // 再喂 1 个播放样本,凑满 5 个才 flush。
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 18, duration: 1200),
    );
    expect(controller.flushReasons, ['periodic']);
  });

  test('活跃条目再次 cacheSource 带新时长同步给会话 updateMetadata', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1', durationSeconds: 1200));

    recorder.cacheSource(_loadArgs(itemGuid: 'ep-1', durationSeconds: 1500));

    expect(controller.metadataUpdates, isNotEmpty);
    expect(controller.metadataUpdates.last.mediaDurationMs, 1500 * 1000);
  });

  test('handleIdleTimeout 无活跃会话时 no-op', () async {
    await recorder.handleIdleTimeout();
    expect(controller.finishReasons, isEmpty);
  });

  test('缓存淘汰 FIFO 跳过活跃条目', () async {
    // 先让 ep-0 成为活跃会话(且是最早缓存的条目)。
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-0'));
    // 再缓存 15 个其它条目,使缓存达到上限(16)。
    for (var i = 1; i < 16; i++) {
      recorder.cacheSource(_loadArgs(itemGuid: 'ep-$i'));
    }
    // 此时缓存已满,继续缓存新条目应淘汰最早的非活跃条目(ep-1),而不是活跃的 ep-0。
    recorder.cacheSource(_loadArgs(itemGuid: 'ep-16'));

    // 让活跃会话收口,活跃条目占位释放,再重新切回 ep-0 触发新会话开局,
    // 通过 meta 是否仍完整来验证 ep-0 在淘汰期间未被挤出缓存。
    await recorder.handleIdleTimeout();
    await recorder.onProgress(
      _progress(itemGuid: 'ep-0', ts: 3, duration: 1200),
    );
    expect(controller.started, hasLength(2));
    expect(controller.started[1].startSource, PlayStartSource.systemResume);
    expect(controller.started[1].meta.title, '第 1 集');

    // 反证:真正被淘汰的 ep-1 切回时应退化为 _minimalMeta(title 为空)。
    await recorder.onProgress(
      _progress(itemGuid: 'ep-1', ts: 3, duration: 1200),
    );
    expect(controller.started, hasLength(3));
    expect(controller.started[2].meta.title, isEmpty);
  });

  group('Timer 真实触发路径(fake_async 驱动虚拟时间)', () {
    test('喂一次进度后越过 idleTimeout,看门狗自动收口', () {
      fakeAsync((async) {
        final fakeController = _FakeSessionController();
        final fakeRecorder = NativePlayStatsRecorder(
          sessionController: fakeController,
        );

        unawaited(fakeRecorder.onLaunch(_loadArgs(itemGuid: 'ep-1')));
        async.flushMicrotasks();
        unawaited(
          fakeRecorder.onProgress(
            _progress(itemGuid: 'ep-1', ts: 3, duration: 1200),
          ),
        );
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(fakeController.finishReasons, ['idle_timeout']);

        fakeRecorder.dispose();
      });
    });

    test('未到期不收口;喂狗续命后再到期才收口', () {
      fakeAsync((async) {
        final fakeController = _FakeSessionController();
        final fakeRecorder = NativePlayStatsRecorder(
          sessionController: fakeController,
        );

        unawaited(fakeRecorder.onLaunch(_loadArgs(itemGuid: 'ep-1')));
        async.flushMicrotasks();

        // 推进 29s(未到 30s 阈值)。
        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        expect(fakeController.finishReasons, isEmpty);

        // 喂一次进度续命,计时器从这里重新计数。
        unawaited(
          fakeRecorder.onProgress(
            _progress(itemGuid: 'ep-1', ts: 29, duration: 1200),
          ),
        );
        async.flushMicrotasks();

        // 再推进 29s,距离续命时刻仍未到 30s,不应收口。
        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        expect(fakeController.finishReasons, isEmpty);

        // 再推进 2s,累计超过续命后的 30s 阈值,应收口。
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(fakeController.finishReasons, ['idle_timeout']);

        fakeRecorder.dispose();
      });
    });
  });
}

Map<String, dynamic> _loadArgs({
  String itemGuid = 'ep-1',
  String seriesGuid = 'series-1',
  String seasonGuid = 'season-1',
  String title = '第 1 集',
  String seriesTitle = '某剧',
  String tmdbId = '',
  String mediaType = 'Episode',
  int episodeNumber = 1,
  int durationSeconds = 1200,
  int startPositionMs = 0,
  bool externalLocalSource = false,
}) {
  return <String, dynamic>{
    'itemGuid': itemGuid,
    'seriesGuid': seriesGuid,
    'seasonGuid': seasonGuid,
    'title': title,
    'seriesTitle': seriesTitle,
    'tmdbId': tmdbId,
    'mediaType': mediaType,
    'episodeNumber': episodeNumber,
    'durationSeconds': durationSeconds,
    'startPositionMs': startPositionMs,
    'externalLocalSource': externalLocalSource,
  };
}

Map<String, dynamic> _progress({
  required String itemGuid,
  required int ts,
  required int duration,
  bool isPaused = false,
}) {
  return <String, dynamic>{
    'itemGuid': itemGuid,
    'mediaGuid': 'media-$itemGuid',
    'videoGuid': 'video-$itemGuid',
    'ts': ts,
    'duration': duration,
    'isPaused': isPaused,
  };
}

class _FakeSessionController implements PlayStatsSessionController {
  final List<PlayStatsStartContext> started = <PlayStatsStartContext>[];
  final List<Map<String, Object?>> progressUpdates = <Map<String, Object?>>[];
  final List<String> flushReasons = <String>[];
  final List<String> finishReasons = <String>[];
  final List<PlayStatsVideoMeta> metadataUpdates = <PlayStatsVideoMeta>[];

  @override
  Future<void> startPlayback(PlayStatsStartContext context) async {
    started.add(context);
  }

  @override
  void updateMetadata(PlayStatsVideoMeta meta) {
    metadataUpdates.add(meta);
  }

  @override
  void updateProgress({
    required int positionMs,
    required int mediaDurationMs,
    required bool paused,
    required DateTime now,
    required bool playbackCompleted,
  }) {
    progressUpdates.add(<String, Object?>{
      'positionMs': positionMs,
      'mediaDurationMs': mediaDurationMs,
      'paused': paused,
    });
  }

  @override
  void recordSeek({
    required int fromMs,
    required int toMs,
    required bool userInitiated,
  }) {}

  @override
  void markOpEdDetected({OpEdSegment? intro, OpEdSegment? outro}) {}

  @override
  void recordOpEdSkip({required bool intro}) {}

  @override
  void recordOpEdDismiss({required bool intro}) {}

  @override
  Future<void> flushPlayback({required String reason}) async {
    flushReasons.add(reason);
  }

  @override
  Future<void> finishPlayback({required String reason}) async {
    finishReasons.add(reason);
  }
}
