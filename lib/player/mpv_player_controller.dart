import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';

class MpvMediaSource {
  final String itemGuid;
  final String seasonGuid;
  final String mediaGuid;
  final String videoGuid;
  final int videoWidth;
  final int videoHeight;
  final String? proxySessionId;
  final String? playLink;
  final String url;
  final Map<String, String> headers;
  final String title;
  final int episodeNumber;
  final Duration startPosition;
  final int? audioTrackIndex;
  final int? subtitleTrackIndex;
  final String? audioTrackGuid;
  final String? subtitleTrackGuid;
  final String resolution;
  final int bitrate;
  final int durationSeconds;
  final String videoCodecName;
  final String videoProfile;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final int bitDepth;
  final bool preferExternalSubtitle;
  final bool reliableSeek;
  final String? seekProbeSummary;
  final bool serverPlaybackManaged;
  final double playbackSpeed;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final List<PlaybackQualityOption> qualities;

  const MpvMediaSource({
    required this.itemGuid,
    this.seasonGuid = '',
    required this.mediaGuid,
    required this.videoGuid,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.proxySessionId,
    this.playLink,
    required this.url,
    required this.headers,
    required this.title,
    this.episodeNumber = 0,
    this.startPosition = Duration.zero,
    this.audioTrackIndex,
    this.subtitleTrackIndex,
    this.audioTrackGuid,
    this.subtitleTrackGuid,
    this.resolution = '',
    this.bitrate = 0,
    this.durationSeconds = 0,
    this.videoCodecName = '',
    this.videoProfile = '',
    this.colorSpace = '',
    this.colorTransfer = '',
    this.colorPrimaries = '',
    this.bitDepth = 0,
    this.preferExternalSubtitle = false,
    this.reliableSeek = true,
    this.seekProbeSummary,
    this.serverPlaybackManaged = false,
    this.playbackSpeed = 1.0,
    this.audioTracks = const <AudioTrackOption>[],
    this.subtitleTracks = const <SubtitleTrackOption>[],
    this.qualities = const <PlaybackQualityOption>[],
  });

  MpvMediaSource copyWith({
    String? itemGuid,
    String? seasonGuid,
    String? mediaGuid,
    String? videoGuid,
    int? videoWidth,
    int? videoHeight,
    String? proxySessionId,
    String? playLink,
    String? url,
    Map<String, String>? headers,
    String? title,
    int? episodeNumber,
    Duration? startPosition,
    int? audioTrackIndex,
    bool clearAudioTrackIndex = false,
    int? subtitleTrackIndex,
    bool clearSubtitleTrackIndex = false,
    String? audioTrackGuid,
    bool clearAudioTrackGuid = false,
    String? subtitleTrackGuid,
    bool clearSubtitleTrackGuid = false,
    String? resolution,
    int? bitrate,
    int? durationSeconds,
    String? videoCodecName,
    String? videoProfile,
    String? colorSpace,
    String? colorTransfer,
    String? colorPrimaries,
    int? bitDepth,
    bool? preferExternalSubtitle,
    bool? reliableSeek,
    String? seekProbeSummary,
    bool clearSeekProbeSummary = false,
    bool? serverPlaybackManaged,
    double? playbackSpeed,
    List<AudioTrackOption>? audioTracks,
    List<SubtitleTrackOption>? subtitleTracks,
    List<PlaybackQualityOption>? qualities,
  }) {
    return MpvMediaSource(
      itemGuid: itemGuid ?? this.itemGuid,
      seasonGuid: seasonGuid ?? this.seasonGuid,
      mediaGuid: mediaGuid ?? this.mediaGuid,
      videoGuid: videoGuid ?? this.videoGuid,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      proxySessionId: proxySessionId ?? this.proxySessionId,
      playLink: playLink ?? this.playLink,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      title: title ?? this.title,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      startPosition: startPosition ?? this.startPosition,
      audioTrackIndex: clearAudioTrackIndex
          ? null
          : audioTrackIndex ?? this.audioTrackIndex,
      subtitleTrackIndex: clearSubtitleTrackIndex
          ? null
          : subtitleTrackIndex ?? this.subtitleTrackIndex,
      audioTrackGuid: clearAudioTrackGuid
          ? null
          : audioTrackGuid ?? this.audioTrackGuid,
      subtitleTrackGuid: clearSubtitleTrackGuid
          ? null
          : subtitleTrackGuid ?? this.subtitleTrackGuid,
      resolution: resolution ?? this.resolution,
      bitrate: bitrate ?? this.bitrate,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      videoCodecName: videoCodecName ?? this.videoCodecName,
      videoProfile: videoProfile ?? this.videoProfile,
      colorSpace: colorSpace ?? this.colorSpace,
      colorTransfer: colorTransfer ?? this.colorTransfer,
      colorPrimaries: colorPrimaries ?? this.colorPrimaries,
      bitDepth: bitDepth ?? this.bitDepth,
      preferExternalSubtitle:
          preferExternalSubtitle ?? this.preferExternalSubtitle,
      reliableSeek: reliableSeek ?? this.reliableSeek,
      seekProbeSummary: clearSeekProbeSummary
          ? null
          : seekProbeSummary ?? this.seekProbeSummary,
      serverPlaybackManaged:
          serverPlaybackManaged ?? this.serverPlaybackManaged,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      qualities: qualities ?? this.qualities,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemGuid': itemGuid,
      'seasonGuid': seasonGuid,
      'mediaGuid': mediaGuid,
      'videoGuid': videoGuid,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'proxySessionId': proxySessionId,
      'playLink': playLink,
      'url': url,
      'headers': headers,
      'title': title,
      'episodeNumber': episodeNumber,
      'startPositionMs': startPosition.inMilliseconds,
      'audioTrackIndex': audioTrackIndex,
      'subtitleTrackIndex': subtitleTrackIndex,
      'audioTrackGuid': audioTrackGuid,
      'subtitleTrackGuid': subtitleTrackGuid,
      'resolution': resolution,
      'bitrate': bitrate,
      'durationSeconds': durationSeconds,
      'videoCodecName': videoCodecName,
      'videoProfile': videoProfile,
      'colorSpace': colorSpace,
      'colorTransfer': colorTransfer,
      'colorPrimaries': colorPrimaries,
      'bitDepth': bitDepth,
      'preferExternalSubtitle': preferExternalSubtitle,
      'reliableSeek': reliableSeek,
      'seekProbeSummary': seekProbeSummary,
      'serverPlaybackManaged': serverPlaybackManaged,
      'playbackSpeed': playbackSpeed,
      'audioTracks': audioTracks.map(_audioTrackToMap).toList(),
      'subtitleTracks': subtitleTracks.map(_subtitleTrackToMap).toList(),
      'qualities': qualities.map(_qualityToMap).toList(),
    };
  }

  static Map<String, Object?> _audioTrackToMap(AudioTrackOption track) {
    return <String, Object?>{
      'mediaGuid': track.mediaGuid,
      'guid': track.guid,
      'title': track.title,
      'codecName': track.codecName,
      'profile': track.profile,
      'language': track.language,
      'audioType': track.audioType,
      'channelLayout': track.channelLayout,
      'channels': track.channels,
      'sampleRate': track.sampleRate,
      'bps': track.bps,
      'index': track.index,
      'isDefault': track.isDefault,
    };
  }

  static Map<String, Object?> _subtitleTrackToMap(SubtitleTrackOption track) {
    return <String, Object?>{
      'mediaGuid': track.mediaGuid,
      'guid': track.guid,
      'title': track.title,
      'codecName': track.codecName,
      'format': track.format,
      'language': track.language,
      'index': track.index,
      'isDefault': track.isDefault,
      'forced': track.forced,
      'isExternal': track.isExternal,
    };
  }

  static Map<String, Object?> _qualityToMap(PlaybackQualityOption quality) {
    return <String, Object?>{
      'mediaGuid': quality.mediaGuid,
      'videoGuid': quality.videoGuid,
      'resolution': quality.resolution,
      'bitrate': quality.bitrate,
      'isDefault': quality.isDefault,
    };
  }
}

@immutable
class MpvPlayerValue {
  final bool ready;
  final bool nativeLibLoaded;
  final bool paused;
  final Duration position;
  final Duration duration;
  final String statusText;
  final String? error;

  const MpvPlayerValue({
    required this.ready,
    required this.nativeLibLoaded,
    required this.paused,
    required this.position,
    required this.duration,
    required this.statusText,
    required this.error,
  });

  const MpvPlayerValue.initial()
    : ready = false,
      nativeLibLoaded = false,
      paused = true,
      position = Duration.zero,
      duration = Duration.zero,
      statusText = 'Preparing player',
      error = null;

  MpvPlayerValue copyWith({
    bool? ready,
    bool? nativeLibLoaded,
    bool? paused,
    Duration? position,
    Duration? duration,
    String? statusText,
    String? error,
    bool clearError = false,
  }) {
    return MpvPlayerValue(
      ready: ready ?? this.ready,
      nativeLibLoaded: nativeLibLoaded ?? this.nativeLibLoaded,
      paused: paused ?? this.paused,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      statusText: statusText ?? this.statusText,
      error: clearError ? null : error ?? this.error,
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
      ready: event['ready'] as bool?,
      nativeLibLoaded: event['nativeLibLoaded'] as bool?,
      paused: event['paused'] as bool?,
      position: durationFrom(event['positionMs']),
      duration: durationFrom(event['durationMs']),
      statusText: event['statusText']?.toString(),
      error: event['error']?.toString(),
      clearError: event.containsKey('error') && event['error'] == null,
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

class MpvPlayerController {
  static const Duration _positionUpdateThreshold = Duration(milliseconds: 250);
  static const Set<String> _pendingLoadAnchorStatuses = <String>{
    'source loaded',
    'playback started',
  };
  static const Set<String> _pendingLoadSetupStatuses = <String>{
    'waiting for playback source',
    'waiting for video surface',
    'preparing video renderer',
    'video output unavailable',
    'video track unavailable',
    'native player unavailable',
    'failed to initialize mpv',
    'failed to attach mpv surface',
    'failed to restore video track',
    'failed to configure video output',
    'proxy stream open failed',
    'mpv-android runtime rejected source',
  };

  final ValueNotifier<MpvPlayerValue> value = ValueNotifier<MpvPlayerValue>(
    const MpvPlayerValue.initial(),
  );

  MethodChannel? _methodChannel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _suppressNativeStateUntilCurrentLoad = false;
  Duration _pendingLoadPosition = Duration.zero;
  Duration _pendingLoadDuration = Duration.zero;

  void attach(int viewId) {
    _methodChannel = MethodChannel('fly_player/mpv_view_$viewId/methods');
    _eventChannel = EventChannel('fly_player/mpv_view_$viewId/events');
    final previousSubscription = _eventSubscription;
    if (previousSubscription != null) {
      unawaited(_cancelSubscription(previousSubscription));
    }
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleError,
    );
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

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> togglePlayback() async {
    if (value.value.paused) {
      await play();
      return;
    }
    await pause();
  }

  Future<void> seek(Duration position) {
    return _invoke('seek', <String, Object?>{
      'positionMs': position.inMilliseconds,
    });
  }

  void prepareForSourceLoad(
    MpvMediaSource source, {
    bool? paused,
    String statusText = 'Preparing player',
  }) {
    _suppressNativeStateUntilCurrentLoad = true;
    _pendingLoadPosition = source.startPosition;
    _pendingLoadDuration = source.durationSeconds > 0
        ? Duration(seconds: source.durationSeconds)
        : Duration.zero;
    value.value = MpvPlayerValue(
      ready: false,
      nativeLibLoaded: false,
      paused: paused ?? value.value.paused,
      position: source.startPosition,
      duration: source.durationSeconds > 0
          ? Duration(seconds: source.durationSeconds)
          : Duration.zero,
      statusText: statusText,
      error: null,
    );
  }

  Future<void> reload(MpvMediaSource source) async {
    _suppressNativeStateUntilCurrentLoad = true;
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

  List<MpvChapterItem> _filterZeroTimeChapters(
    List<MpvChapterItem> chapters,
  ) {
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
    _handleNativeState(MpvPlayerValue.fromEvent(event, fallback: value.value));
  }

  void _handleError(Object error) {
    _setError(error.toString());
  }

  void _setError(String message) {
    _suppressNativeStateUntilCurrentLoad = false;
    _publishValue(
      value.value.copyWith(error: message, statusText: 'Player error'),
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
    _publishValue(next, force: force);
  }

  bool _shouldAcceptNativeStateDuringPendingLoad(MpvPlayerValue next) {
    if ((next.error ?? '').trim().isNotEmpty) {
      return true;
    }
    final statusText = next.statusText.trim().toLowerCase();
    if (_pendingLoadSetupStatuses.contains(statusText)) {
      return true;
    }
    if (_pendingLoadAnchorStatuses.contains(statusText)) {
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
    final previous = value.value;
    if (!force && !_shouldPublishValue(previous, next)) {
      return;
    }
    value.value = next;
  }

  bool _shouldPublishValue(MpvPlayerValue previous, MpvPlayerValue next) {
    if (previous.ready != next.ready ||
        previous.nativeLibLoaded != next.nativeLibLoaded ||
        previous.paused != next.paused ||
        previous.duration != next.duration ||
        previous.statusText != next.statusText ||
        previous.error != next.error) {
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
    _suppressNativeStateUntilCurrentLoad = false;
    await _invoke('pause');
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription != null) {
      await _cancelSubscription(subscription);
    }
    _eventChannel = null;
    _methodChannel = null;
    value.dispose();
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
