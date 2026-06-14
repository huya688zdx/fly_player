import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Data classes — mirror the Kotlin-side serialization.
// ---------------------------------------------------------------------------

@immutable
class NativePlayerLaunchArgs {
  final String url;
  final String title;
  final Map<String, String> headers;
  final Duration startPosition;
  final String? audioTrackId;
  final String? subtitleTrackId;
  final bool autoPlay;
  final String? decoderMode;
  final String? preferredAudioLanguage;
  final String? preferredSubtitleLanguage;

  const NativePlayerLaunchArgs({
    required this.url,
    required this.title,
    this.headers = const <String, String>{},
    this.startPosition = Duration.zero,
    this.audioTrackId,
    this.subtitleTrackId,
    this.autoPlay = true,
    this.decoderMode,
    this.preferredAudioLanguage,
    this.preferredSubtitleLanguage,
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'url': url,
      'title': title,
      'headers': headers,
      'startPositionMs': startPosition.inMilliseconds,
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
      'autoPlay': autoPlay,
      'decoderMode': decoderMode,
      'preferredAudioLanguage': preferredAudioLanguage,
      'preferredSubtitleLanguage': preferredSubtitleLanguage,
    };
  }

  factory NativePlayerLaunchArgs.fromMap(Map<String, dynamic> raw) {
    final rawHeaders = raw['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        headers[key.toString()] = value?.toString() ?? '';
      });
    }

    return NativePlayerLaunchArgs(
      url: (raw['url'] ?? '').toString(),
      title: (raw['title'] ?? '').toString(),
      headers: headers,
      startPosition: Duration(milliseconds: _intOf(raw['startPositionMs'])),
      audioTrackId: _stringOrNull(raw['audioTrackId']),
      subtitleTrackId: _stringOrNull(raw['subtitleTrackId']),
      autoPlay: raw['autoPlay'] as bool? ?? true,
      decoderMode: _stringOrNull(raw['decoderMode']),
      preferredAudioLanguage: _stringOrNull(raw['preferredAudioLanguage']),
      preferredSubtitleLanguage: _stringOrNull(
        raw['preferredSubtitleLanguage'],
      ),
    );
  }
}

@immutable
class NativePlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;
  final bool isBuffering;
  final String playbackPhase;
  final String? error;
  final String? audioTrackId;
  final String? subtitleTrackId;

  const NativePlayerState({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.speed,
    required this.volume,
    required this.isBuffering,
    required this.playbackPhase,
    this.error,
    this.audioTrackId,
    this.subtitleTrackId,
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'isPlaying': isPlaying,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'bufferedPositionMs': bufferedPosition.inMilliseconds,
      'speed': speed,
      'volume': volume,
      'isBuffering': isBuffering,
      'playbackPhase': playbackPhase,
      'error': error,
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
    };
  }

  factory NativePlayerState.fromMap(Map<String, dynamic> raw) {
    return NativePlayerState(
      isPlaying: raw['isPlaying'] as bool? ?? false,
      position: Duration(milliseconds: _intOf(raw['positionMs'])),
      duration: Duration(milliseconds: _intOf(raw['durationMs'])),
      bufferedPosition: Duration(
        milliseconds: _intOf(raw['bufferedPositionMs']),
      ),
      speed: _doubleOf(raw['speed']).clamp(0.0, 16.0),
      volume: _doubleOf(raw['volume']).clamp(0.0, 1.0),
      isBuffering: raw['isBuffering'] as bool? ?? false,
      playbackPhase: (raw['playbackPhase'] ?? '').toString(),
      error: _stringOrNull(raw['error']),
      audioTrackId: _stringOrNull(raw['audioTrackId']),
      subtitleTrackId: _stringOrNull(raw['subtitleTrackId']),
    );
  }
}

@immutable
class NativeEpisodeData {
  final String seasonGuid;
  final List<Map<String, Object?>> episodes;
  final List<Map<String, Object?>> seasonOptions;

  const NativeEpisodeData({
    required this.seasonGuid,
    this.episodes = const <Map<String, Object?>>[],
    this.seasonOptions = const <Map<String, Object?>>[],
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'seasonGuid': seasonGuid,
      'episodes': episodes,
      'seasonOptions': seasonOptions,
    };
  }

  factory NativeEpisodeData.fromMap(Map<String, dynamic> raw) {
    return NativeEpisodeData(
      seasonGuid: (raw['seasonGuid'] ?? '').toString(),
      episodes:
          (raw['episodes'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>()
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
      seasonOptions:
          (raw['seasonOptions'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>()
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
    );
  }
}

@immutable
class NativeSettingsState {
  final bool autoRotate;
  final bool autoPlay;
  final String decoderMode;
  final String aspectRatio;
  final double subtitleDelay;
  final double audioDelay;
  final double subtitleScale;
  final int subtitlePosition;

  const NativeSettingsState({
    this.autoRotate = true,
    this.autoPlay = true,
    this.decoderMode = '',
    this.aspectRatio = '',
    this.subtitleDelay = 0.0,
    this.audioDelay = 0.0,
    this.subtitleScale = 1.0,
    this.subtitlePosition = 0,
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'autoRotate': autoRotate,
      'autoPlay': autoPlay,
      'decoderMode': decoderMode,
      'aspectRatio': aspectRatio,
      'subtitleDelay': subtitleDelay,
      'audioDelay': audioDelay,
      'subtitleScale': subtitleScale,
      'subtitlePosition': subtitlePosition,
    };
  }

  factory NativeSettingsState.fromMap(Map<String, dynamic> raw) {
    return NativeSettingsState(
      autoRotate: raw['autoRotate'] as bool? ?? true,
      autoPlay: raw['autoPlay'] as bool? ?? true,
      decoderMode: (raw['decoderMode'] ?? '').toString(),
      aspectRatio: (raw['aspectRatio'] ?? '').toString(),
      subtitleDelay: _doubleOf(raw['subtitleDelay']),
      audioDelay: _doubleOf(raw['audioDelay']),
      subtitleScale: _doubleOf(raw['subtitleScale']).clamp(0.5, 4.0),
      subtitlePosition: _intOf(raw['subtitlePosition']),
    );
  }
}

// ---------------------------------------------------------------------------
// Bridge — wraps the MethodChannel and EventChannel.
// ---------------------------------------------------------------------------

class NativePlayerBridge {
  NativePlayerBridge._();

  static final NativePlayerBridge instance = NativePlayerBridge._();

  final MethodChannel _methodChannel = const MethodChannel(
    'fly_player/native_player',
  );
  final EventChannel _eventChannel = const EventChannel(
    'fly_player/native_player/events',
  );

  Stream<NativePlayerState>? _stateStream;

  /// Broadcast stream of [NativePlayerState] updates emitted by the native
  /// Android player host.
  Stream<NativePlayerState> get stateStream {
    _stateStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((dynamic e) => e is Map)
        .map((dynamic e) => _normalizeMap(e as Map<Object?, Object?>))
        .map((m) => NativePlayerState.fromMap(m));
    return _stateStream!;
  }

  // -- Command methods ----------------------------------------------------------

  Future<void> launchPlayer(NativePlayerLaunchArgs args) async {
    if (args.url.trim().isEmpty || args.title.trim().isEmpty) {
      throw PlatformException(
        code: 'INVALID_ARGS',
        message: 'url and title are required',
      );
    }
    try {
      await _methodChannel.invokeMethod<void>('launchPlayer', args.toMap());
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<NativeEpisodeData?> getEpisodeData(String seasonGuid) async {
    final normalizedGuid = seasonGuid.trim();
    if (normalizedGuid.isEmpty) {
      throw PlatformException(
        code: 'INVALID_ARGS',
        message: 'seasonGuid is required',
      );
    }
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getEpisodeData',
        <String, Object?>{'seasonGuid': normalizedGuid},
      );
      if (result == null) return null;
      return NativeEpisodeData.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> applyMpvSetting(String key, dynamic value) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'key is required');
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'applyMpvSetting',
        <String, Object?>{'key': normalizedKey, 'value': value},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod<void>('pause');
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> resume() async {
    try {
      await _methodChannel.invokeMethod<void>('resume');
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> seek(Duration position) async {
    final normalizedMs = position < Duration.zero ? 0 : position.inMilliseconds;
    try {
      await _methodChannel.invokeMethod<void>('seek', <String, Object?>{
        'positionMs': normalizedMs,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> setSpeed(double speed) async {
    if (!speed.isFinite || speed <= 0.0) {
      throw PlatformException(
        code: 'INVALID_ARGS',
        message: 'speed must be a positive finite number',
      );
    }
    final clamped = speed.clamp(0.25, 16.0);
    try {
      await _methodChannel.invokeMethod<void>('setSpeed', <String, Object?>{
        'speed': clamped,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> setAudioTrack(String? trackId) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setAudioTrack',
        <String, Object?>{'trackId': trackId},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> setSubtitleTrack(String? trackId) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setSubtitleTrack',
        <String, Object?>{'trackId': trackId},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await _methodChannel.invokeMethod<void>('close');
    } on MissingPluginException {
      return;
    } on PlatformException {
      rethrow;
    }
  }

  // -- Helpers -----------------------------------------------------------------

  Map<String, dynamic> _normalizeMap(Map<Object?, Object?> raw) {
    final normalized = <String, dynamic>{};
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

// -- File-private parse helpers ------------------------------------------------

int _intOf(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

double _doubleOf(Object? value) =>
    value is double ? value : double.tryParse('$value') ?? 0;

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
