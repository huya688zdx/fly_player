import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../danmaku/models/danmaku_dynamic_occlusion.dart';
import '../../playback/playback_source.dart';
import '../../models/stream_track_data.dart';
import '../../playback/screenshots/screenshot_settings_store.dart';

enum MpvPlaybackPhase {
  idle,
  preparing,
  buffering,
  playing,
  paused,
  seeking,
  ended,
  error;

  static MpvPlaybackPhase fromWire(Object? raw, {MpvPlaybackPhase? fallback}) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    for (final phase in values) {
      if (phase.name == normalized) {
        return phase;
      }
    }
    return fallback ?? MpvPlaybackPhase.idle;
  }
}

@immutable
class MpvPlayerValue {
  final int loadNonce;
  final bool ready;
  final bool nativeLibLoaded;
  final bool visualPlaybackReady;
  final bool paused;
  final MpvPlaybackPhase playbackPhase;
  final bool buffering;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final bool weakNetworkMode;
  final int networkSpeedBytesPerSecond;
  final Duration rebufferTarget;
  final Duration? estimatedResumeWait;
  final bool listenVideoModeEnabled;
  final String statusText;
  final String? error;
  final String? nativeProxySessionId;
  final String? cacheResourceKey;

  const MpvPlayerValue({
    required this.loadNonce,
    required this.ready,
    required this.nativeLibLoaded,
    required this.visualPlaybackReady,
    required this.paused,
    required this.playbackPhase,
    required this.buffering,
    required this.position,
    required this.bufferedPosition,
    required this.duration,
    required this.weakNetworkMode,
    required this.networkSpeedBytesPerSecond,
    required this.rebufferTarget,
    required this.estimatedResumeWait,
    required this.listenVideoModeEnabled,
    required this.statusText,
    required this.error,
    required this.nativeProxySessionId,
    required this.cacheResourceKey,
  });

  const MpvPlayerValue.initial()
    : loadNonce = 0,
      ready = false,
      nativeLibLoaded = false,
      visualPlaybackReady = false,
      paused = true,
      playbackPhase = MpvPlaybackPhase.idle,
      buffering = false,
      position = Duration.zero,
      bufferedPosition = Duration.zero,
      duration = Duration.zero,
      weakNetworkMode = false,
      networkSpeedBytesPerSecond = 0,
      rebufferTarget = Duration.zero,
      estimatedResumeWait = null,
      listenVideoModeEnabled = false,
      statusText = 'Preparing player',
      error = null,
      nativeProxySessionId = null,
      cacheResourceKey = null;

  MpvPlayerValue copyWith({
    int? loadNonce,
    bool? ready,
    bool? nativeLibLoaded,
    bool? visualPlaybackReady,
    bool? paused,
    MpvPlaybackPhase? playbackPhase,
    bool? buffering,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    bool? weakNetworkMode,
    int? networkSpeedBytesPerSecond,
    Duration? rebufferTarget,
    Duration? estimatedResumeWait,
    bool clearEstimatedResumeWait = false,
    bool? listenVideoModeEnabled,
    String? statusText,
    String? error,
    bool clearError = false,
    String? nativeProxySessionId,
    bool clearNativeProxySessionId = false,
    String? cacheResourceKey,
    bool clearCacheResourceKey = false,
  }) {
    return MpvPlayerValue(
      loadNonce: loadNonce ?? this.loadNonce,
      ready: ready ?? this.ready,
      nativeLibLoaded: nativeLibLoaded ?? this.nativeLibLoaded,
      visualPlaybackReady: visualPlaybackReady ?? this.visualPlaybackReady,
      paused: paused ?? this.paused,
      playbackPhase: playbackPhase ?? this.playbackPhase,
      buffering: buffering ?? this.buffering,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      weakNetworkMode: weakNetworkMode ?? this.weakNetworkMode,
      networkSpeedBytesPerSecond:
          networkSpeedBytesPerSecond ?? this.networkSpeedBytesPerSecond,
      rebufferTarget: rebufferTarget ?? this.rebufferTarget,
      estimatedResumeWait: clearEstimatedResumeWait
          ? null
          : estimatedResumeWait ?? this.estimatedResumeWait,
      listenVideoModeEnabled:
          listenVideoModeEnabled ?? this.listenVideoModeEnabled,
      statusText: statusText ?? this.statusText,
      error: clearError ? null : error ?? this.error,
      nativeProxySessionId: clearNativeProxySessionId
          ? null
          : nativeProxySessionId ?? this.nativeProxySessionId,
      cacheResourceKey: clearCacheResourceKey
          ? null
          : cacheResourceKey ?? this.cacheResourceKey,
    );
  }

  factory MpvPlayerValue.fromEvent(
    Map<Object?, Object?> event, {
    required MpvPlayerValue fallback,
  }) {
    Duration durationFrom(dynamic value) {
      final raw = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return Duration(milliseconds: raw);
    }

    return fallback.copyWith(
      loadNonce: event['loadNonce'] is num
          ? (event['loadNonce'] as num).toInt()
          : int.tryParse('${event['loadNonce']}'),
      ready: event['ready'] as bool?,
      nativeLibLoaded: event['nativeLibLoaded'] as bool?,
      visualPlaybackReady: event['visualPlaybackReady'] as bool?,
      paused: event['paused'] as bool?,
      playbackPhase: MpvPlaybackPhase.fromWire(
        event['playbackPhase'],
        fallback: fallback.playbackPhase,
      ),
      buffering:
          (event['playbackPhase']?.toString().trim().toLowerCase() ==
              MpvPlaybackPhase.buffering.name)
          ? true
          : event['buffering'] as bool?,
      position: durationFrom(event['positionMs']),
      bufferedPosition: durationFrom(event['bufferedPositionMs']),
      duration: durationFrom(event['durationMs']),
      weakNetworkMode: event['weakNetworkMode'] as bool?,
      networkSpeedBytesPerSecond: event['networkSpeedBytesPerSecond'] is num
          ? (event['networkSpeedBytesPerSecond'] as num).toInt()
          : int.tryParse('${event['networkSpeedBytesPerSecond']}'),
      rebufferTarget: durationFrom(event['rebufferTargetMs']),
      estimatedResumeWait: event['estimatedResumeWaitMs'] == null
          ? null
          : durationFrom(event['estimatedResumeWaitMs']),
      clearEstimatedResumeWait:
          event.containsKey('estimatedResumeWaitMs') &&
          event['estimatedResumeWaitMs'] == null,
      listenVideoModeEnabled: event['listenVideoModeEnabled'] as bool?,
      statusText: event['statusText']?.toString(),
      error: event['error']?.toString(),
      clearError: event.containsKey('error') && event['error'] == null,
      nativeProxySessionId: event['nativeProxySessionId']?.toString(),
      clearNativeProxySessionId:
          event.containsKey('nativeProxySessionId') &&
          event['nativeProxySessionId'] == null,
      cacheResourceKey: event['cacheResourceKey']?.toString(),
      clearCacheResourceKey:
          event.containsKey('cacheResourceKey') &&
          event['cacheResourceKey'] == null,
    );
  }

  bool get isPlaybackAdvancing => playbackPhase == MpvPlaybackPhase.playing;

  bool get isPlaybackStopped => playbackPhase != MpvPlaybackPhase.playing;

  bool get isTransientLoadingPhase =>
      playbackPhase == MpvPlaybackPhase.preparing ||
      playbackPhase == MpvPlaybackPhase.buffering ||
      playbackPhase == MpvPlaybackPhase.seeking;
}

@immutable
class MpvRuntimeTrackSnapshot {
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final String selectedAudioGuid;
  final String selectedSubtitleGuid;

  const MpvRuntimeTrackSnapshot({
    required this.audioTracks,
    required this.subtitleTracks,
    required this.selectedAudioGuid,
    required this.selectedSubtitleGuid,
  });

  static const empty = MpvRuntimeTrackSnapshot(
    audioTracks: <AudioTrackOption>[],
    subtitleTracks: <SubtitleTrackOption>[],
    selectedAudioGuid: '',
    selectedSubtitleGuid: '',
  );

  factory MpvRuntimeTrackSnapshot.fromMap(Map<String, Object?> raw) {
    int intOf(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;

    final audioTracks = (raw['audioTracks'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => AudioTrackOption(
            mediaGuid: (entry['mediaGuid'] ?? '').toString(),
            guid: (entry['guid'] ?? '').toString(),
            title: (entry['title'] ?? '').toString(),
            codecName: (entry['codecName'] ?? '').toString(),
            profile: (entry['profile'] ?? '').toString(),
            language: (entry['language'] ?? '').toString(),
            audioType: (entry['audioType'] ?? '').toString(),
            channelLayout: (entry['channelLayout'] ?? '').toString(),
            channels: intOf(entry['channels']),
            sampleRate: intOf(entry['sampleRate']),
            bps: intOf(entry['bps']),
            index: intOf(entry['index']),
            isDefault:
                ((entry['isDefault'] == true || intOf(entry['isDefault']) == 1)
                ? 1
                : 0),
          ),
        )
        .toList(growable: false);
    final subtitleTracks = (raw['subtitleTracks'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => SubtitleTrackOption(
            mediaGuid: (entry['mediaGuid'] ?? '').toString(),
            guid: (entry['guid'] ?? '').toString(),
            title: (entry['title'] ?? '').toString(),
            codecName: (entry['codecName'] ?? '').toString(),
            format: (entry['format'] ?? '').toString(),
            language: (entry['language'] ?? '').toString(),
            index: intOf(entry['index']),
            isDefault:
                ((entry['isDefault'] == true || intOf(entry['isDefault']) == 1)
                ? 1
                : 0),
            forced: ((entry['forced'] == true || intOf(entry['forced']) == 1)
                ? 1
                : 0),
            isExternal:
                ((entry['isExternal'] == true ||
                    intOf(entry['isExternal']) == 1)
                ? 1
                : 0),
            extraFile:
                ((entry['extraFile'] == true || intOf(entry['extraFile']) == 1)
                ? 1
                : 0),
            isBitmap:
                ((entry['isBitmap'] == true || intOf(entry['isBitmap']) == 1)
                ? 1
                : 0),
          ),
        )
        .toList(growable: false);
    return MpvRuntimeTrackSnapshot(
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      selectedAudioGuid: (raw['selectedAudioGuid'] ?? '').toString().trim(),
      selectedSubtitleGuid: (raw['selectedSubtitleGuid'] ?? '')
          .toString()
          .trim(),
    );
  }
}

@immutable
class MpvChapterItem {
  final int index;
  final String title;
  final Duration time;

  const MpvChapterItem({
    required this.index,
    required this.title,
    required this.time,
  });
}

@immutable
class MpvPerformanceOverlayStats {
  final double? cpuUsagePercent;
  final int? appMemoryUsedBytes;
  final int? systemMemoryTotalBytes;

  const MpvPerformanceOverlayStats({
    this.cpuUsagePercent,
    this.appMemoryUsedBytes,
    this.systemMemoryTotalBytes,
  });

  static const empty = MpvPerformanceOverlayStats();

  factory MpvPerformanceOverlayStats.fromMap(Map<Object?, Object?> raw) {
    double? numberOf(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    int? intOf(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value');
    }

    return MpvPerformanceOverlayStats(
      cpuUsagePercent: numberOf(raw['cpuUsagePercent']),
      appMemoryUsedBytes: intOf(raw['appMemoryUsedBytes']),
      systemMemoryTotalBytes: intOf(raw['systemMemoryTotalBytes']),
    );
  }
}

class MpvPlayerController {
  static const Duration _positionUpdateThreshold = Duration(milliseconds: 160);
  static const Duration _bufferedUpdateThreshold = Duration(milliseconds: 800);
  static const Duration _seekSettleTolerance = Duration(seconds: 3);
  static const Duration _seekGuardWindow = Duration(milliseconds: 4200);
  static const Duration _playbackCommandPositionGuardWindow = Duration(
    milliseconds: 1400,
  );
  static const Duration _positionRollbackTolerance = Duration(
    milliseconds: 240,
  );
  static const Set<MpvPlaybackPhase> _pendingLoadAnchorPhases =
      <MpvPlaybackPhase>{
        MpvPlaybackPhase.playing,
        MpvPlaybackPhase.paused,
        MpvPlaybackPhase.ended,
      };
  static const Set<MpvPlaybackPhase> _pendingLoadSetupPhases =
      <MpvPlaybackPhase>{
        MpvPlaybackPhase.preparing,
        MpvPlaybackPhase.buffering,
        MpvPlaybackPhase.seeking,
        MpvPlaybackPhase.error,
      };

  final ValueNotifier<MpvPlayerValue> value = ValueNotifier<MpvPlayerValue>(
    const MpvPlayerValue.initial(),
  );
  final ValueNotifier<DanmakuDynamicOcclusionState> danmakuOcclusionState =
      ValueNotifier<DanmakuDynamicOcclusionState>(
        DanmakuDynamicOcclusionState.disabled,
      );

  MethodChannel? _methodChannel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _disposed = false;
  bool _suppressNativeStateUntilCurrentLoad = false;
  int _pendingLoadNonce = 0;
  Duration _pendingLoadPosition = Duration.zero;
  Duration _pendingLoadDuration = Duration.zero;
  Duration? _pendingSeekTarget;
  DateTime? _pendingSeekGuardUntil;
  Duration? _positionFloorGuard;
  DateTime? _positionFloorGuardUntil;
  Timer? _coalescedSeekTimer;
  Duration _coalescedSeekTarget = Duration.zero;
  static const Duration _seekCoalesceInterval = Duration(milliseconds: 64);

  void attach(int viewId) {
    _disposed = false;
    _methodChannel = MethodChannel('fly_player/mpv_view_$viewId/methods');
    _eventChannel = EventChannel('fly_player/mpv_view_$viewId/events');
    final previousSubscription = _eventSubscription;
    if (previousSubscription != null) {
      unawaited(_cancelSubscription(previousSubscription));
    }
    danmakuOcclusionState.value = DanmakuDynamicOcclusionState.disabled;
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleError,
    );
    unawaited(_primeDanmakuOcclusionState());
  }

  Future<void> refreshState() async {
    final channel = _methodChannel;
    if (channel == null) return;
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>('getState');
      if (state == null) return;
      _handleNativeState(
        MpvPlayerValue.fromEvent(state, fallback: value.value),
        force: true,
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
    }
  }

  Future<void> play() {
    _armPlaybackCommandPositionGuard();
    return _invoke('play');
  }

  Future<void> pause() {
    _armPlaybackCommandPositionGuard();
    return _invoke('pause');
  }

  Future<void> togglePlayback() async {
    if (value.value.playbackPhase == MpvPlaybackPhase.paused) {
      await play();
      return;
    }
    await pause();
  }

  Future<void> seek(Duration position) {
    final normalized = position < Duration.zero ? Duration.zero : position;
    _armPendingSeekGuard(normalized);
    _publishValue(
      value.value.copyWith(
        position: normalized,
        bufferedPosition: value.value.bufferedPosition < normalized
            ? normalized
            : value.value.bufferedPosition,
        playbackPhase: MpvPlaybackPhase.seeking,
        statusText: 'Seeking',
        clearError: true,
      ),
      force: true,
    );
    _coalescedSeekTarget = normalized;
    _coalescedSeekTimer?.cancel();
    _coalescedSeekTimer = Timer(_seekCoalesceInterval, () {
      _coalescedSeekTimer = null;
      final payload = <String, Object?>{
        'positionMs': _coalescedSeekTarget.inMilliseconds,
      };
      unawaited(_invoke('hintNativeDanmakuSeek', payload));
      unawaited(_invoke('seek', payload));
    });
    return Future<void>.value();
  }

  void prepareForSourceLoad(
    MpvMediaSource source, {
    bool? paused,
    String statusText = 'Preparing player',
  }) {
    final resolvedPaused = paused ?? source.startPaused;
    _clearTransientPositionGuards();
    _suppressNativeStateUntilCurrentLoad = true;
    _pendingLoadNonce = source.loadNonce;
    _pendingLoadPosition = source.startPosition;
    _pendingLoadDuration = source.durationSeconds > 0
        ? Duration(seconds: source.durationSeconds)
        : Duration.zero;
    _publishDanmakuOcclusionState(DanmakuDynamicOcclusionState.disabled);
    value.value = MpvPlayerValue(
      loadNonce: source.loadNonce,
      ready: false,
      nativeLibLoaded: false,
      visualPlaybackReady: false,
      paused: resolvedPaused,
      playbackPhase: MpvPlaybackPhase.preparing,
      buffering: false,
      position: source.startPosition,
      bufferedPosition: source.startPosition,
      duration: source.durationSeconds > 0
          ? Duration(seconds: source.durationSeconds)
          : Duration.zero,
      weakNetworkMode: false,
      networkSpeedBytesPerSecond: 0,
      rebufferTarget: Duration.zero,
      estimatedResumeWait: null,
      listenVideoModeEnabled: source.listenVideoModeEnabled,
      statusText: statusText,
      error: null,
      nativeProxySessionId: null,
      cacheResourceKey: null,
    );
  }

  Future<void> reload(MpvMediaSource source) async {
    _clearTransientPositionGuards();
    _suppressNativeStateUntilCurrentLoad = true;
    _pendingLoadNonce = source.loadNonce;
    _publishDanmakuOcclusionState(DanmakuDynamicOcclusionState.disabled);
    await _invoke('load', source.toMap());
  }

  Future<void> setAudioTrack({int? trackIndex, String? trackGuid}) {
    return _invoke('setAudioTrack', <String, Object?>{
      'trackIndex': trackIndex,
      'trackGuid': trackGuid,
    });
  }

  Future<void> setSubtitleTrack({int? trackIndex, String? trackGuid}) {
    return _invoke('setSubtitleTrack', <String, Object?>{
      'trackIndex': trackIndex,
      'trackGuid': trackGuid,
    });
  }

  Future<void> setExternalSubtitleFile(String path) {
    return _invoke('setExternalSubtitleFile', <String, Object?>{'path': path});
  }

  Future<void> setSubtitleDelay(double delay) {
    return _invoke('setSubtitleDelay', <String, Object?>{'delay': delay});
  }

  Future<void> setAudioDelay(double delay) {
    return _invoke('setAudioDelay', <String, Object?>{'delay': delay});
  }

  Future<void> setSubtitlePosition(int position) {
    return _invoke('setSubtitlePosition', <String, Object?>{
      'position': position,
    });
  }

  Future<void> setSubtitleScale(double scale) {
    return _invoke('setSubtitleScale', <String, Object?>{'scale': scale});
  }

  Future<void> resetSubtitleStyle() {
    return _invoke('resetSubtitleStyle');
  }

  Future<void> setDecoderMode(String mode) {
    return _invoke('setDecoderMode', <String, Object?>{'mode': mode});
  }

  Future<void> setDisplayAspectRatioMode(String mode) {
    return _invoke('setDisplayAspectRatioMode', <String, Object?>{
      'mode': mode,
    });
  }

  Future<void> setSpeed(double speed) {
    return _invoke('setSpeed', <String, Object?>{'speed': speed});
  }

  Future<void> setVideoAdjustments(Map<String, double> settings) {
    return _invoke('setVideoAdjustments', <String, Object?>{
      'settings': settings,
    });
  }

  Future<void> setMpvAdvancedSettings(Map<String, String> settings) {
    return _invoke('setMpvAdvancedSettings', <String, Object?>{
      'settings': settings,
    });
  }

  Future<MpvListenVideoModeResult> setListenVideoMode(bool enabled) async {
    final channel = _methodChannel;
    if (channel == null) {
      return MpvListenVideoModeResult(
        success: false,
        enabled: value.value.listenVideoModeEnabled,
        message: 'player not ready',
      );
    }
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'setListenVideoMode',
        <String, Object?>{'enabled': enabled},
      );
      final normalized = result == null
          ? const <String, Object?>{}
          : _normalizeMap(result);
      final success = normalized['success'] == true;
      final resolvedEnabled = normalized['enabled'] == true;
      final message = normalized['message']?.toString().trim();
      if (success) {
        _publishValue(
          value.value.copyWith(
            listenVideoModeEnabled: resolvedEnabled,
            clearError: true,
          ),
          force: true,
        );
      }
      return MpvListenVideoModeResult(
        success: success,
        enabled: resolvedEnabled,
        message: message == null || message.isEmpty ? null : message,
      );
    } on MissingPluginException {
      return MpvListenVideoModeResult(
        success: false,
        enabled: value.value.listenVideoModeEnabled,
        message: 'player not ready',
      );
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return MpvListenVideoModeResult(
        success: false,
        enabled: value.value.listenVideoModeEnabled,
        message: error.message ?? error.code,
      );
    }
  }

  Future<Map<String, Object?>> captureFrame({
    bool includeSubtitles = false,
    String savePathMode = ScreenshotSettingsStore.defaultSavePathMode,
  }) async {
    final channel = _methodChannel;
    if (channel == null) {
      return const <String, Object?>{
        'success': false,
        'message': 'player not ready',
      };
    }
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'captureFrame',
        <String, Object?>{
          'includeSubtitles': includeSubtitles,
          'savePathMode': savePathMode,
        },
      );
      if (result == null) {
        return const <String, Object?>{
          'success': false,
          'message': 'capture failed',
        };
      }
      return _normalizeMap(result);
    } on MissingPluginException {
      rethrow;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return <String, Object?>{
        'success': false,
        'message': error.message ?? 'capture failed',
      };
    }
  }

  Future<Map<String, Object?>> getPlaybackDiagnostics() async {
    final channel = _methodChannel;
    if (channel == null) return const <String, Object?>{};
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>(
        'getPlaybackDiagnostics',
      );
      if (state == null) return const <String, Object?>{};
      return _normalizeMap(state);
    } on MissingPluginException {
      return const <String, Object?>{};
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return const <String, Object?>{};
    }
  }

  Future<List<MpvChapterItem>> getChapters() async {
    final channel = _methodChannel;
    if (channel == null) return const <MpvChapterItem>[];
    try {
      final result = await channel.invokeMethod<List<Object?>>('getChapters');
      if (result == null) return const <MpvChapterItem>[];
      final chapters = result
          .whereType<Map<Object?, Object?>>()
          .map((raw) {
            final index = (raw['index'] as num?)?.toInt() ?? 0;
            final title = raw['title']?.toString() ?? '';
            final timeMs = (raw['timeMs'] as num?)?.toInt() ?? 0;
            return MpvChapterItem(
              index: index,
              title: title,
              time: Duration(milliseconds: timeMs),
            );
          })
          .toList(growable: false);
      return _filterZeroTimeChapters(chapters);
    } on MissingPluginException {
      return const <MpvChapterItem>[];
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return const <MpvChapterItem>[];
    }
  }

  Future<MpvPerformanceOverlayStats> getPerformanceOverlayStats() async {
    final channel = _methodChannel;
    if (channel == null) return MpvPerformanceOverlayStats.empty;
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>(
        'getPerformanceOverlayStats',
      );
      if (state == null) return MpvPerformanceOverlayStats.empty;
      return MpvPerformanceOverlayStats.fromMap(state);
    } on MissingPluginException {
      return MpvPerformanceOverlayStats.empty;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return MpvPerformanceOverlayStats.empty;
    }
  }

  Future<MpvRuntimeTrackSnapshot> getTrackSnapshot() async {
    final channel = _methodChannel;
    if (channel == null) return MpvRuntimeTrackSnapshot.empty;
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>(
        'getTrackSnapshot',
      );
      if (state == null) return MpvRuntimeTrackSnapshot.empty;
      return MpvRuntimeTrackSnapshot.fromMap(_normalizeMap(state));
    } on MissingPluginException {
      return MpvRuntimeTrackSnapshot.empty;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return MpvRuntimeTrackSnapshot.empty;
    }
  }

  Future<DanmakuDynamicOcclusionState> getDanmakuOcclusionState() async {
    final channel = _methodChannel;
    if (channel == null) return DanmakuDynamicOcclusionState.disabled;
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>(
        'getDanmakuOcclusionState',
      );
      if (state == null) return DanmakuDynamicOcclusionState.disabled;
      final next = DanmakuDynamicOcclusionState.fromMap(_normalizeMap(state));
      _publishDanmakuOcclusionState(next);
      return next;
    } on MissingPluginException {
      return DanmakuDynamicOcclusionState.disabled;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return DanmakuDynamicOcclusionState.disabled;
    }
  }

  Future<void> setDanmakuOcclusionConfig(Map<String, Object?> config) {
    return _invoke('setDanmakuOcclusionConfig', config);
  }

  Future<void> setNativeDanmakuOcclusion(Map<String, Object?> payload) {
    return _invoke('setNativeDanmakuOcclusion', payload);
  }

  Future<void> setDanmakuPayload(Map<String, Object?> payload) {
    return _invoke('setDanmakuPayload', payload);
  }

  Future<void> clearDanmaku() {
    return _invoke('clearDanmaku');
  }

  List<MpvChapterItem> _filterZeroTimeChapters(List<MpvChapterItem> chapters) {
    if (chapters.isEmpty) return chapters;
    bool seenZero = false;
    final filtered = <MpvChapterItem>[];
    for (final chapter in chapters) {
      if (chapter.time == Duration.zero) {
        if (seenZero) continue;
        seenZero = true;
      }
      filtered.add(chapter);
    }
    return filtered;
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    final channel = _methodChannel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) return;
    final eventType = event['eventType']?.toString().trim();
    if (eventType == 'playerState') {
      final state = event['state'];
      if (state is Map<Object?, Object?>) {
        _handleNativeState(
          MpvPlayerValue.fromEvent(state, fallback: value.value),
        );
      }
      return;
    }
    if (eventType == 'danmakuOcclusionState') {
      final state = event['state'];
      if (state is Map<Object?, Object?>) {
        _publishDanmakuOcclusionState(
          DanmakuDynamicOcclusionState.fromMap(_normalizeMap(state)),
        );
      }
      return;
    }
    _handleNativeState(MpvPlayerValue.fromEvent(event, fallback: value.value));
  }

  void _handleError(Object error) {
    _setError(error.toString());
  }

  void _setError(String message) {
    _clearTransientPositionGuards();
    _suppressNativeStateUntilCurrentLoad = false;
    _publishValue(
      value.value.copyWith(
        error: message,
        statusText: 'Player error',
        playbackPhase: MpvPlaybackPhase.error,
      ),
      force: true,
    );
  }

  void _handleNativeState(MpvPlayerValue next, {bool force = false}) {
    if (_suppressNativeStateUntilCurrentLoad) {
      if (!_shouldAcceptNativeStateDuringPendingLoad(next)) {
        return;
      }
      _suppressNativeStateUntilCurrentLoad = false;
    }
    _publishValue(
      _stabilizeTransientPosition(previous: value.value, next: next),
      force: force,
    );
  }

  bool _shouldAcceptNativeStateDuringPendingLoad(MpvPlayerValue next) {
    if (next.loadNonce != _pendingLoadNonce) {
      return false;
    }
    if ((next.error ?? '').trim().isNotEmpty) {
      return true;
    }
    if (_pendingLoadSetupPhases.contains(next.playbackPhase)) {
      return true;
    }
    if (_pendingLoadAnchorPhases.contains(next.playbackPhase)) {
      return _matchesPendingLoad(next);
    }
    if (next.ready && next.nativeLibLoaded) {
      return _matchesPendingLoad(next);
    }
    return false;
  }

  bool _matchesPendingLoad(MpvPlayerValue next) {
    final expectedDuration = _pendingLoadDuration;
    if (expectedDuration > Duration.zero && next.duration > Duration.zero) {
      final toleranceMs = (expectedDuration.inMilliseconds * 0.02)
          .round()
          .clamp(1500, 5000);
      final delta = (next.duration - expectedDuration).abs();
      if (delta > Duration(milliseconds: toleranceMs)) {
        return false;
      }
    }
    if (_pendingLoadPosition > Duration.zero &&
        next.position > Duration.zero &&
        next.position < _pendingLoadPosition - const Duration(seconds: 3)) {
      return false;
    }
    return true;
  }

  void _publishValue(MpvPlayerValue next, {bool force = false}) {
    if (_disposed) {
      return;
    }
    final previous = value.value;
    if (!force && !_shouldPublishValue(previous, next)) {
      return;
    }
    value.value = next;
  }

  MpvPlayerValue _stabilizeTransientPosition({
    required MpvPlayerValue previous,
    required MpvPlayerValue next,
  }) {
    _expireTransientPositionGuards();
    if (next.playbackPhase == MpvPlaybackPhase.error) {
      _clearTransientPositionGuards();
      return next;
    }

    var stabilized = next;
    final pendingSeekTarget = _pendingSeekTarget;
    final pendingSeekGuardUntil = _pendingSeekGuardUntil;
    if (pendingSeekTarget != null && pendingSeekGuardUntil != null) {
      final nextDelta = _durationDistance(
        stabilized.position,
        pendingSeekTarget,
      );
      if (nextDelta <= _seekSettleTolerance) {
        _clearPendingSeekGuard();
      } else if (DateTime.now().isBefore(pendingSeekGuardUntil)) {
        final previousDelta = _durationDistance(
          previous.position,
          pendingSeekTarget,
        );
        if (nextDelta > previousDelta + _positionRollbackTolerance) {
          stabilized = _clampPosition(stabilized, previous.position);
        }
      } else {
        _clearPendingSeekGuard();
      }
    }

    final positionFloorGuard = _positionFloorGuard;
    final positionFloorGuardUntil = _positionFloorGuardUntil;
    if (positionFloorGuard != null && positionFloorGuardUntil != null) {
      if (DateTime.now().isBefore(positionFloorGuardUntil)) {
        if (stabilized.position + _positionRollbackTolerance <
            positionFloorGuard) {
          stabilized = _clampPosition(stabilized, positionFloorGuard);
        } else if (stabilized.position >=
            positionFloorGuard - _positionRollbackTolerance) {
          _clearPlaybackCommandPositionGuard();
        }
      } else {
        _clearPlaybackCommandPositionGuard();
      }
    }

    return stabilized;
  }

  MpvPlayerValue _clampPosition(MpvPlayerValue value, Duration position) {
    final nextBufferedPosition = value.bufferedPosition < position
        ? position
        : value.bufferedPosition;
    return value.copyWith(
      position: position,
      bufferedPosition: nextBufferedPosition,
    );
  }

  Duration _durationDistance(Duration left, Duration right) {
    return left >= right ? left - right : right - left;
  }

  void _armPendingSeekGuard(Duration target) {
    _pendingSeekTarget = target;
    _pendingSeekGuardUntil = DateTime.now().add(_seekGuardWindow);
    _clearPlaybackCommandPositionGuard();
  }

  void _clearPendingSeekGuard() {
    _pendingSeekTarget = null;
    _pendingSeekGuardUntil = null;
  }

  void _armPlaybackCommandPositionGuard() {
    if (_pendingSeekTarget != null) {
      return;
    }
    _positionFloorGuard = value.value.position;
    _positionFloorGuardUntil = DateTime.now().add(
      _playbackCommandPositionGuardWindow,
    );
  }

  void _clearPlaybackCommandPositionGuard() {
    _positionFloorGuard = null;
    _positionFloorGuardUntil = null;
  }

  void _expireTransientPositionGuards() {
    final now = DateTime.now();
    final pendingSeekGuardUntil = _pendingSeekGuardUntil;
    if (pendingSeekGuardUntil != null && !now.isBefore(pendingSeekGuardUntil)) {
      _clearPendingSeekGuard();
    }
    final positionFloorGuardUntil = _positionFloorGuardUntil;
    if (positionFloorGuardUntil != null &&
        !now.isBefore(positionFloorGuardUntil)) {
      _clearPlaybackCommandPositionGuard();
    }
  }

  void _clearTransientPositionGuards() {
    _clearPendingSeekGuard();
    _clearPlaybackCommandPositionGuard();
    _coalescedSeekTimer?.cancel();
    _coalescedSeekTimer = null;
  }

  void _publishDanmakuOcclusionState(DanmakuDynamicOcclusionState next) {
    if (_disposed) {
      return;
    }
    if (danmakuOcclusionState.value == next) {
      return;
    }
    danmakuOcclusionState.value = next;
  }

  bool _shouldPublishValue(MpvPlayerValue previous, MpvPlayerValue next) {
    if (previous.ready != next.ready ||
        previous.nativeLibLoaded != next.nativeLibLoaded ||
        previous.visualPlaybackReady != next.visualPlaybackReady ||
        previous.paused != next.paused ||
        previous.playbackPhase != next.playbackPhase ||
        previous.buffering != next.buffering ||
        previous.listenVideoModeEnabled != next.listenVideoModeEnabled ||
        previous.duration != next.duration ||
        previous.weakNetworkMode != next.weakNetworkMode ||
        previous.networkSpeedBytesPerSecond !=
            next.networkSpeedBytesPerSecond ||
        previous.rebufferTarget != next.rebufferTarget ||
        previous.estimatedResumeWait != next.estimatedResumeWait ||
        previous.statusText != next.statusText ||
        previous.error != next.error ||
        previous.nativeProxySessionId != next.nativeProxySessionId ||
        previous.cacheResourceKey != next.cacheResourceKey) {
      return true;
    }
    final bufferedDelta = (next.bufferedPosition - previous.bufferedPosition)
        .abs();
    if (bufferedDelta >= _bufferedUpdateThreshold) {
      return true;
    }
    final positionDelta = (next.position - previous.position).abs();
    if (positionDelta >= _positionUpdateThreshold) {
      return true;
    }
    return next.position == Duration.zero && previous.position != next.position;
  }

  Future<void> _cancelSubscription(
    StreamSubscription<dynamic> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on MissingPluginException {
      // PlatformView teardown can outpace EventChannel cancellation.
    } on PlatformException {
      // Ignore native stream races during orientation changes.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _clearTransientPositionGuards();
    _suppressNativeStateUntilCurrentLoad = false;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription != null) {
      await _cancelSubscription(subscription);
    }
    _eventChannel = null;
    _methodChannel = null;
    danmakuOcclusionState.dispose();
    value.dispose();
  }

  Future<void> _primeDanmakuOcclusionState() async {
    final next = await getDanmakuOcclusionState();
    _publishDanmakuOcclusionState(next);
  }

  Map<String, Object?> _normalizeMap(Map<Object?, Object?> raw) {
    final normalized = <String, Object?>{};
    raw.forEach((key, value) {
      normalized[key?.toString() ?? ''] = _normalizeValue(value);
    });
    return normalized;
  }

  Object? _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }
}

@immutable
class MpvListenVideoModeResult {
  final bool success;
  final bool enabled;
  final String? message;

  const MpvListenVideoModeResult({
    required this.success,
    required this.enabled,
    this.message,
  });
}
