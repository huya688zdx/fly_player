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
