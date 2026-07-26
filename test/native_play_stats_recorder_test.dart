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

  @override
  Future<void> startPlayback(PlayStatsStartContext context) async {
    started.add(context);
  }

  @override
  void updateMetadata(PlayStatsVideoMeta meta) {}

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
