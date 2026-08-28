# 播放统计写入链路修复(原生壳接回 PlayStatsService)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) 语法跟踪进度。

**Goal:** 把原生壳播放链路的进度事件重新接回本地播放统计(`PlayStatsService`),使「设置 → 全局播放数据统计」恢复记录。

**Architecture:** 统计模块(SQLite 仓储 + `DefaultPlayStatsSessionController`)完好,只是迁移原生壳后无人调用。新增一个 `NativePlayStatsRecorder`(有状态单例),挂在 `NativePlayerBridge` 的三个收口点上:`launch`(起播开会话)、`resolvePlayback`/`reloadServerSession` 返回值(只缓存元数据——**不能**在这里切会话,因为下一集预取也走 resolvePlayback)、`recordProgress`(喂进度 + itemGuid 变化时切会话 + 周期 flush)。原生壳无「播放结束」信号,靠两件事补:Kotlin 侧暂停时放行心跳帧(区分「暂停」与「已退出」),Flutter 侧 30 秒无事件的看门狗收口会话。

**Tech Stack:** Flutter/Dart(`flutter_test` 单测)、Kotlin(`NativePlayerActivity.reportProgress` 一处小改)。

---

## 背景(根因,已查实)

- `DefaultPlayStatsSessionController.startPlayback/updateProgress/finishPlayback` 在全库**零调用点**;Android 侧对 play stats 零引用。旧 Flutter 播放器 controller 层删除时统计钩子一起没了。
- 现有进度链路:原生壳前台每 3s(暂停时静默,ts 同秒去重)`dispatch("recordProgress")` → `NativePlayerBridge.bindReentry` → 飞牛 `NativeReentrySupport.recordProgress`(NAS 续播位)/ 服务器族 `ServerPlaybackReporter`(PlaybackStart/Progress)。两条分支都不碰本地统计。
- `recordProgress` 载荷:`itemGuid/mediaGuid/videoGuid/audioGuid/subtitleGuid/resolution/bitrate/playLink/ts(秒)/duration(秒)`。**没有** isPaused、没有 seek 事件、没有结束信号。
- `resolvePlayback` 有三个原生调用点:选集切换(6007)、切版本(6045)、**下一集预取(7421)**——预取时条目还没真正播放,所以会话切换只能以 `recordProgress` 的 itemGuid 变化为准。
- `persistFinalizedSession` 按 historyId 读旧记录再差量应用(play_stats_repository_impl.dart:29),同一 historyId 反复 flush 是安全幂等的——控制器的 `flushPlayback` 就是为周期落盘设计的。

## 已知限制(本计划不解决,验收时不要当 bug)

- seek 计数、片头片尾(OP/ED)统计:原生壳不回传 seek 事件,恒为 0/未检出。
- 自动连播(autoNext)与手动切集无法区分,一律记 `manualSwitch`(原生壳未回传切换原因)。
- 后台纯听模式:原生壳 `onStop` 停周期上报,后台收听时长不计(与服务端进度回写行为一致)。
- 用户关闭「原生渲染器」走 Flutter 播放器的路径不在本计划范围。
- 外部本地视频(`externalLocalSource == true`)明确不入统计(无媒体库身份,会污染报表)。

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/services/play_stats/native_play_stats_recorder.dart` | 新建 | 有状态记录器:元数据缓存、会话开/切/收、进度换算、周期 flush、空闲看门狗 |
| `test/native_play_stats_recorder_test.dart` | 新建 | 记录器单测(fake 会话控制器) |
| `lib/services/native_player_bridge.dart` | 修改 | 四处挂点:launch / resolvePlayback / reloadServerSession / recordProgress |
| `android/.../NativePlayerActivity.kt` | 修改 | `reportProgress` 带 `isPaused` + 暂停心跳帧(`pausedHeartbeat` 标记) |
| `lib/services/native_reentry_support.dart` | 修改 | 飞牛回写跳过心跳帧(保持旧行为) |
| `lib/services/native_playback_reentry.dart` | 修改 | `ServerPlaybackReporter` 跳过心跳帧(保持旧行为) |

---

### Task 1: NativePlayStatsRecorder 失败单测

**Files:**
- Test: `test/native_play_stats_recorder_test.dart`(新建)

- [ ] **Step 1: 写失败测试**

```dart
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
    await recorder.onProgress(_progress(itemGuid: 'ep-1', ts: 30, duration: 1200));
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

    await recorder.onProgress(_progress(itemGuid: 'ep-2', ts: 3, duration: 1200));

    expect(controller.started, hasLength(2));
    expect(controller.started[1].startSource, PlayStartSource.manualSwitch);
    expect(controller.started[1].meta.title, '第 2 集');
    expect(controller.started[1].startPositionMs, 3 * 1000);
  });

  test('无 launch 的孤儿进度以最小元数据开 systemResume 会话', () async {
    await recorder.onProgress(_progress(itemGuid: 'ep-x', ts: 10, duration: 600));

    expect(controller.started, hasLength(1));
    expect(controller.started.single.startSource, PlayStartSource.systemResume);
    expect(controller.started.single.meta.videoId, 'ep-x');
  });

  test('每 5 个进度样本 flush 一次 periodic', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    for (var ts = 3; ts <= 15; ts += 3) {
      await recorder.onProgress(_progress(itemGuid: 'ep-1', ts: ts, duration: 1200));
    }
    expect(controller.flushReasons, ['periodic']);
  });

  test('空闲超时收口会话,后续进度重开会话', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    await recorder.onProgress(_progress(itemGuid: 'ep-1', ts: 3, duration: 1200));

    await recorder.handleIdleTimeout();

    expect(controller.finishReasons, ['idle_timeout']);

    await recorder.onProgress(_progress(itemGuid: 'ep-1', ts: 6, duration: 1200));
    expect(controller.started, hasLength(2));
    expect(controller.started[1].startSource, PlayStartSource.systemResume);
  });

  test('externalLocalSource 条目完全不入统计', () async {
    await recorder.onLaunch(
      _loadArgs(itemGuid: 'local-1', externalLocalSource: true),
    );
    await recorder.onProgress(_progress(itemGuid: 'local-1', ts: 3, duration: 600));

    expect(controller.started, isEmpty);
    expect(controller.progressUpdates, isEmpty);
  });

  test('cacheSourceFromLoadArgsJson 解析 JSON 字符串入缓存', () async {
    await recorder.onLaunch(_loadArgs(itemGuid: 'ep-1'));
    recorder.cacheSourceFromLoadArgsJson(
      '{"itemGuid":"ep-9","title":"第 9 集","seriesGuid":"series-1",'
      '"seriesTitle":"某剧","mediaType":"Episode","durationSeconds":900}',
    );
    await recorder.onProgress(_progress(itemGuid: 'ep-9', ts: 3, duration: 900));

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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/native_play_stats_recorder_test.dart`
Expected: 编译失败(`native_play_stats_recorder.dart` 不存在)。

### Task 2: NativePlayStatsRecorder 实现

**Files:**
- Create: `lib/services/play_stats/native_play_stats_recorder.dart`

- [ ] **Step 1: 写实现**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/swallowed_error_logger.dart';
import 'play_stats_identity.dart';
import 'play_stats_models.dart';
import 'play_stats_service.dart';
import 'play_stats_session_controller.dart';

/// 原生壳播放链路的本地统计记录器。
///
/// 旧 Flutter 播放器 controller(统计会话的原驱动方)随原生化删除后,统计写入链路断裂;
/// 本类在 [NativePlayerBridge] 的收口点重建链路:
/// - `launch`:起播即开 manual 会话(元数据来自 loadArgs);
/// - `resolvePlayback`/`reloadServerSession` 返回值:只进 [cacheSource] 缓存——下一集
///   预取也走 resolvePlayback,此时条目未必真正播放,不能当会话边界;
/// - `recordProgress`:唯一可信的「正在播放」信号。itemGuid 变化才切会话;每
///   [flushSampleInterval] 个样本 flush 一次落盘(persistFinalizedSession 按 historyId
///   幂等,重复 flush 安全)。
///
/// 原生壳没有显式「播放结束」信号:暂停期间 Kotlin 侧持续发心跳帧(isPaused=true),
/// 因此超过 [idleTimeout] 无任何事件即视为播放器已退出/退后台,看门狗收口会话。
/// 暂停不会误收口(有心跳),会话不被切碎,观看判定(单会话 20%/10% 门槛)不失真。
class NativePlayStatsRecorder {
  NativePlayStatsRecorder({
    PlayStatsSessionController? sessionController,
    this.idleTimeout = const Duration(seconds: 30),
    this.flushSampleInterval = 5,
  }) : _sessionControllerOverride = sessionController;

  static final NativePlayStatsRecorder instance = NativePlayStatsRecorder();

  static const int _metaCacheLimit = 16;

  final PlayStatsSessionController? _sessionControllerOverride;
  final Duration idleTimeout;
  final int flushSampleInterval;

  final Map<String, PlayStatsVideoMeta> _metaCache =
      <String, PlayStatsVideoMeta>{};
  final Set<String> _excludedGuids = <String>{};
  String _activeItemGuid = '';
  int _samplesSinceFlush = 0;
  Timer? _idleTimer;

  PlayStatsSessionController get _sessionController =>
      _sessionControllerOverride ?? PlayStatsService.instance.sessionController;

  /// 起播挂点:缓存元数据并开 manual 会话。
  Future<void> onLaunch(Map<String, dynamic> loadArgs) async {
    try {
      cacheSource(loadArgs);
      final itemGuid = (loadArgs['itemGuid'] ?? '').toString().trim();
      if (itemGuid.isEmpty || _excludedGuids.contains(itemGuid)) return;
      await _startSession(
        itemGuid,
        startSource: PlayStartSource.manual,
        startPositionMs: (loadArgs['startPositionMs'] as num?)?.toInt() ?? 0,
      );
    } catch (error, stackTrace) {
      _logSwallowed('onLaunch', error, stackTrace);
    }
  }

  /// 元数据缓存挂点(切集解析 / 预取 / 转码重载的 loadArgs)。只缓存,不动会话边界。
  void cacheSource(Map<String, dynamic> loadArgs) {
    final itemGuid = (loadArgs['itemGuid'] ?? '').toString().trim();
    if (itemGuid.isEmpty) return;
    // 外部本地视频无媒体库身份,入库只会污染报表。
    if (loadArgs['externalLocalSource'] == true) {
      _excludedGuids.add(itemGuid);
      _metaCache.remove(itemGuid);
      return;
    }
    _excludedGuids.remove(itemGuid);
    if (_metaCache.length >= _metaCacheLimit &&
        !_metaCache.containsKey(itemGuid)) {
      _metaCache.remove(_metaCache.keys.first);
    }
    final meta = _metaFromLoadArgs(itemGuid, loadArgs);
    _metaCache[itemGuid] = meta;
    // 当前条目的重载(如转码切换带回新时长)同步给活跃会话。
    if (itemGuid == _activeItemGuid) {
      _sessionController.updateMetadata(meta);
    }
  }

  /// [cacheSource] 的 JSON 字符串便利入口(桥上 resolved['loadArgs'] 是 jsonEncode 产物)。
  void cacheSourceFromLoadArgsJson(Object? rawJson) {
    if (rawJson is! String || rawJson.isEmpty) return;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        cacheSource(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (error, stackTrace) {
      _logSwallowed('cacheSourceFromLoadArgsJson', error, stackTrace);
    }
  }

  /// 进度挂点:喂样本、按 itemGuid 变化切会话、周期 flush、喂看门狗。
  Future<void> onProgress(Map<String, dynamic> progress) async {
    try {
      final itemGuid = (progress['itemGuid'] ?? '').toString().trim();
      if (itemGuid.isEmpty || _excludedGuids.contains(itemGuid)) return;
      final durationSec = (progress['duration'] as num?)?.toInt() ?? 0;
      if (durationSec <= 0) return;
      final tsSec = (progress['ts'] as num?)?.toInt() ?? 0;
      _restartIdleTimer();
      if (itemGuid != _activeItemGuid) {
        // 无活跃会话 = Flutter 引擎重建后的孤儿进度(原生壳还活着),按系统恢复记;
        // 有活跃会话 = 壳内切集/连播(autoNext 原生未回传原因,统一记 manualSwitch)。
        await _startSession(
          itemGuid,
          startSource: _activeItemGuid.isEmpty
              ? PlayStartSource.systemResume
              : PlayStartSource.manualSwitch,
          startPositionMs: tsSec * 1000,
        );
      }
      _sessionController.updateProgress(
        positionMs: tsSec * 1000,
        mediaDurationMs: durationSec * 1000,
        paused: progress['isPaused'] == true,
        now: DateTime.now(),
        playbackCompleted: false,
      );
      _samplesSinceFlush += 1;
      if (_samplesSinceFlush >= flushSampleInterval) {
        _samplesSinceFlush = 0;
        await _sessionController.flushPlayback(reason: 'periodic');
      }
    } catch (error, stackTrace) {
      _logSwallowed('onProgress', error, stackTrace);
    }
  }

  /// 看门狗触发:超过 [idleTimeout] 无事件(暂停有心跳,不会触发)视为播放器已退出。
  @visibleForTesting
  Future<void> handleIdleTimeout() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_activeItemGuid.isEmpty) return;
    _activeItemGuid = '';
    _samplesSinceFlush = 0;
    try {
      await _sessionController.finishPlayback(reason: 'idle_timeout');
    } catch (error, stackTrace) {
      _logSwallowed('handleIdleTimeout', error, stackTrace);
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> _startSession(
    String itemGuid, {
    required PlayStartSource startSource,
    required int startPositionMs,
  }) async {
    _activeItemGuid = itemGuid;
    _samplesSinceFlush = 0;
    _restartIdleTimer();
    // startPlayback 内部会先 finish 掉上一段会话(reason=item_switch)。
    await _sessionController.startPlayback(
      PlayStatsStartContext(
        startSource: startSource,
        meta: _metaCache[itemGuid] ?? _minimalMeta(itemGuid),
        startPositionMs: startPositionMs < 0 ? 0 : startPositionMs,
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => unawaited(handleIdleTimeout()));
  }

  PlayStatsVideoMeta _metaFromLoadArgs(
    String itemGuid,
    Map<String, dynamic> loadArgs,
  ) {
    final seriesGuid = (loadArgs['seriesGuid'] ?? '').toString().trim();
    final seasonGuid = (loadArgs['seasonGuid'] ?? '').toString().trim();
    final title = (loadArgs['title'] ?? '').toString().trim();
    final seriesTitle = (loadArgs['seriesTitle'] ?? '').toString().trim();
    final tmdbId = (loadArgs['tmdbId'] ?? '').toString().trim();
    final mediaType = (loadArgs['mediaType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final episodeNumber = (loadArgs['episodeNumber'] as num?)?.toInt() ?? 0;
    final durationSeconds = (loadArgs['durationSeconds'] as num?)?.toInt() ?? 0;
    final looksLikeEpisode =
        seriesGuid.isNotEmpty || seasonGuid.isNotEmpty || episodeNumber > 0;
    final videoKind = mediaType == 'movie'
        ? 'movie'
        : mediaType == 'episode'
        ? 'episode'
        : looksLikeEpisode
        ? 'episode'
        : 'movie';
    final identity = PlayStatsIdentityResolver.resolveAnimeIdentity(
      seriesGuid: seriesGuid,
      seriesTitle: seriesTitle,
      fallbackTitle: title,
    );
    // 电影没有 seriesGuid,按 PlayStatsIdentityResolver 的派生标识约定聚番剧维度。
    final animeId = identity.animeId.isNotEmpty
        ? identity.animeId
        : tmdbId.isNotEmpty
        ? 'tmdb:$tmdbId'
        : 'title:${title.toLowerCase()}';
    // 国家/年份/题材/演职员此处拿不到,留空由 PlayStatsMetadataBackfillService 回填
    // (metadata_enriched=0 的记录会被补全)。
    return PlayStatsVideoMeta(
      videoId: itemGuid,
      animeId: animeId,
      seasonId: seasonGuid,
      title: title,
      animeTitle: identity.animeTitle,
      seasonTitle: '',
      videoKind: videoKind,
      countsTowardCompletion: true,
      country: '',
      year: 0,
      mediaDurationMs: durationSeconds > 0 ? durationSeconds * 1000 : 0,
    );
  }

  PlayStatsVideoMeta _minimalMeta(String itemGuid) {
    return PlayStatsVideoMeta(
      videoId: itemGuid,
      animeId: '',
      seasonId: '',
      title: '',
      animeTitle: '',
      seasonTitle: '',
      videoKind: 'episode',
      countsTowardCompletion: true,
      country: '',
      year: 0,
      mediaDurationMs: 0,
    );
  }

  void _logSwallowed(String action, Object error, StackTrace stackTrace) {
    unawaited(
      logSwallowedError(
        action: 'play stats $action',
        id: _activeItemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'native_play_stats_recorder',
      ),
    );
  }
}
```

- [ ] **Step 2: 跑测试确认通过**

Run: `flutter test test/native_play_stats_recorder_test.dart`
Expected: 全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add lib/services/play_stats/native_play_stats_recorder.dart test/native_play_stats_recorder_test.dart
git commit -m "feat(stats): 原生壳播放统计记录器(会话开切收+周期flush+空闲看门狗)"
```

### Task 3: NativePlayerBridge 四处挂点

**Files:**
- Modify: `lib/services/native_player_bridge.dart`

- [ ] **Step 1: 加 import**

在 `import 'native_danmaku_prefetch.dart';`(第 13 行)后加:

```dart
import 'play_stats/native_play_stats_recorder.dart';
```

- [ ] **Step 2: launch 挂点(起播开会话)**

在 `launch()` 末尾的 `await _channel.invokeMethod<void>('launch', ...)` 调用**之后**加:

```dart
    // 本地播放统计:原生壳起播即开会话(旧 Flutter 播放器控制器已删,统计在桥收口)。
    unawaited(NativePlayStatsRecorder.instance.onLaunch(mergedArgs));
```

- [ ] **Step 3: resolvePlayback 挂点(只缓存元数据)**

`bindReentry` 的 `case 'resolvePlayback':` 中,`final resolved = await onResolvePlayback(...);` 之后、debugPrint 之前加:

```dart
          // 统计元数据缓存:预取/切集/切版本的解析结果都进缓存;会话切换只认 recordProgress。
          NativePlayStatsRecorder.instance.cacheSourceFromLoadArgsJson(
            resolved?['loadArgs'],
          );
```

- [ ] **Step 4: reloadServerSession 挂点(转码重载刷新缓存)**

把 `case 'reloadServerSession':` 里的:

```dart
          return await onReloadServerSession(
            current,
            MediaSessionReloadIntent(
```

改为捕获返回值、缓存后再 return:

```dart
          final reloaded = await onReloadServerSession(
            current,
            MediaSessionReloadIntent(
```

并在该调用结束的 `);` 之后(原 `return` 位置)加:

```dart
          NativePlayStatsRecorder.instance.cacheSourceFromLoadArgsJson(
            reloaded?['loadArgs'],
          );
          return reloaded;
```

- [ ] **Step 5: recordProgress 挂点(喂统计)**

把 `case 'recordProgress':` 整块:

```dart
        case 'recordProgress':
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          await onRecordProgress(
            args.map((key, value) => MapEntry(key.toString(), value)),
          );
          return null;
```

改为:

```dart
        case 'recordProgress':
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final progress = args.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          // 本地播放统计先行(内部吞错,不影响服务端进度回写)。
          unawaited(NativePlayStatsRecorder.instance.onProgress(progress));
          await onRecordProgress(progress);
          return null;
```

- [ ] **Step 6: 静态检查 + 全量测试**

Run: `flutter analyze`
Expected: No issues found。

Run: `flutter test`
Expected: 全绿(现有 461+ 测试不受影响)。

- [ ] **Step 7: 提交**

```bash
git add lib/services/native_player_bridge.dart
git commit -m "feat(stats): 桥收口点接线播放统计(launch/解析缓存/进度)"
```

### Task 4: 原生暂停心跳 + 服务端回写保持旧行为

暂停时原生现在完全静默(ts 同秒去重),Flutter 侧无法区分「暂停」和「已退出」,看门狗会把长暂停误判为退出、切碎会话导致观看数漏计。改法:暂停时放行心跳帧并打 `pausedHeartbeat` 标记;两条服务端回写分支按标记跳过——**它们的网络行为逐帧不变**(暂停期间原本就收不到事件),心跳只被本地统计消费。

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`(`reportProgress`,约 9581 行)
- Modify: `lib/services/native_reentry_support.dart`(`recordProgress`,约 129 行)
- Modify: `lib/services/native_playback_reentry.dart`(`ServerPlaybackReporter.report`,约 142 行)

- [ ] **Step 1: Kotlin reportProgress 改造**

把:

```kotlin
        val ts = (state.positionMs / 1000).coerceIn(0L, durationSec)
        if (ts == lastRecordedTs) return
        lastRecordedTs = ts
        val args = HashMap<String, Any?>()
```

改为:

```kotlin
        val ts = (state.positionMs / 1000).coerceIn(0L, durationSec)
        val paused = state.paused
        // 同秒去重只对播放态生效;暂停时放行为心跳,供 Flutter 统计端区分「暂停」与
        // 「已退出」。pausedHeartbeat 标记重复帧,服务端回写(飞牛/Emby)按它跳过。
        val pausedHeartbeat = paused && ts == lastRecordedTs
        if (ts == lastRecordedTs && !paused) return
        lastRecordedTs = ts
        val args = HashMap<String, Any?>()
        args["isPaused"] = paused
        args["pausedHeartbeat"] = pausedHeartbeat
```

- [ ] **Step 2: 飞牛回写跳过心跳帧**

`lib/services/native_reentry_support.dart` 的 `recordProgress` 方法体开头(`final itemGuid = ...` 之前)加:

```dart
    // 暂停心跳只服务本地统计;飞牛回写保持旧行为(暂停重复帧原本就不上报)。
    if (progress['pausedHeartbeat'] == true) return;
```

- [ ] **Step 3: 服务器族回写跳过心跳帧**

`lib/services/native_playback_reentry.dart` 的 `ServerPlaybackReporter.report` 方法体开头(`final itemGuid = ...` 之前)加:

```dart
    // 暂停心跳只服务本地统计;服务端回写保持旧行为(暂停重复帧原本就不上报)。
    if (progress['pausedHeartbeat'] == true) return;
```

- [ ] **Step 4: Kotlin 编译验证**

Run(PowerShell): `cd android; .\gradlew.bat :app:compileDebugKotlin; cd ..`
Expected: BUILD SUCCESSFUL(若 wrapper 不可用,改跑 `flutter build apk --debug`)。

- [ ] **Step 5: Dart 侧验证**

Run: `flutter analyze`
Expected: No issues found。

Run: `flutter test`
Expected: 全绿。

- [ ] **Step 6: 提交**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt lib/services/native_reentry_support.dart lib/services/native_playback_reentry.dart
git commit -m "feat(stats): 暂停心跳帧区分暂停/退出,服务端回写按标记跳过保持旧行为"
```

### Task 5: 实机验收

- [ ] **Step 1: 装机跑通主路径**

`flutter run` 后依次验证,每项都在「设置 → 全局播放数据统计」或统计调试页核对:

1. 播放任一剧集 ≥1 分钟后留在播放器 → 统计页出现该条目,观看时长 ≥40s(周期 flush 每 ~15s 落盘一次)。
2. 壳内切下一集播 ≥30s → 两条历史记录,第二条来源为「手动切换」。
3. 暂停 2 分钟再继续播 → 仍是同一条历史(心跳防拆分),暂停时长不计入观看时长。
4. 退出播放器等 40s → 会话收口(调试页该条历史 finishReason 为 idle_timeout)。
5. 看 20% 以上时长的剧集 → 观看次数 +1;不足 20% → 不计次。
6. 飞牛续播位回写不受影响(退出后详情页续播位置正确);Emby 播放同验一遍。

- [ ] **Step 2: 完成分支收尾**

全部通过后按 superpowers:finishing-a-development-branch 处理合并。

---

## Self-Review 记录

- 会话边界不用 resolvePlayback:已确认原生 7421 行预取也走该通道,只有 recordProgress 的 itemGuid 变化可信。
- `flushPlayback` 幂等性:`persistFinalizedSession` 按 historyId 读旧值做差量(repository_impl 31-40 行),重复 flush 安全。
- 服务端行为零变化:`pausedHeartbeat` 恰好标记「旧代码里会被 `ts == lastRecordedTs` 吞掉的帧」,两条服务端分支跳过它 = 逐帧等价旧行为;首个暂停帧(ts 有变化)照常上报。
- 类型一致性:`PlayStatsStartContext`/`PlayStatsVideoMeta` 字段与 play_stats_models.dart 逐一核对过;`state.paused` 在 MpvPlaybackModels.kt:239 存在。
- 3s 采样 delta 恰好压在控制器 `_maxContinuousProgressDeltaMs = 3000` 上限:样本抖到 4s 的帧不计观看时长(轻微低估),但该上限同时是无 seek 事件下唯一的 seek 过滤器,不放宽。
