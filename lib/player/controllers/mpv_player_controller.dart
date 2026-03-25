import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../danmaku/models/danmaku_dynamic_occlusion.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import 'player_source_controller.dart';
import '../stores/screenshot_settings_store.dart';
import '../../utils/local_subtitle_bundle.dart';

int createMpvLoadNonce() {
  return DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
}

class MpvMediaSource {
  final int loadNonce;
  final String itemGuid;
  final String seriesGuid;
  final String seasonGuid;
  final String posterPath;
  final String mediaGuid;
  final String mediaType;
  final String ancestorName;
  final String videoGuid;
  final int? directLinkQualityIndex;
  final int videoWidth;
  final int videoHeight;
  final String? proxySessionId;
  final String? playLink;
  final String url;
  final Map<String, String> headers;
  final String title;
  final String seriesTitle;
  final int seasonNumber;
  final String tmdbId;
  final int episodeNumber;
  final Duration startPosition;
  final int? audioTrackIndex;
  final int? subtitleTrackIndex;
  final String? audioTrackGuid;
  final String? subtitleTrackGuid;
  final String resolution;
  final int bitrate;
  final int durationSeconds;
  final Map<String, String> localSubtitleFiles;
  final String videoCodecName;
  final String videoProfile;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final int bitDepth;
  final bool isDownloadedFile;
  final bool preferExternalSubtitle;
  final bool forceNativeProxy;
  final bool extremePlaybackEnabled;
  final bool reliableSeek;
  final String? seekProbeSummary;
  final PlayerPlaybackMode playbackMode;
  final double playbackSpeed;
  final bool listenVideoModeEnabled;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final List<PlaybackQualityOption> qualities;

  bool get serverPlaybackManaged => playbackMode.isServerManaged;

  const MpvMediaSource({
    this.loadNonce = 0,
    required this.itemGuid,
    this.seriesGuid = '',
    this.seasonGuid = '',
    this.posterPath = '',
    required this.mediaGuid,
    this.mediaType = '',
    this.ancestorName = '',
    required this.videoGuid,
    this.directLinkQualityIndex,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.proxySessionId,
    this.playLink,
    required this.url,
    required this.headers,
    required this.title,
    this.seriesTitle = '',
    this.seasonNumber = 0,
    this.tmdbId = '',
    this.episodeNumber = 0,
    this.startPosition = Duration.zero,
    this.audioTrackIndex,
    this.subtitleTrackIndex,
    this.audioTrackGuid,
    this.subtitleTrackGuid,
    this.resolution = '',
    this.bitrate = 0,
    this.durationSeconds = 0,
    this.localSubtitleFiles = const <String, String>{},
    this.videoCodecName = '',
    this.videoProfile = '',
    this.colorSpace = '',
    this.colorTransfer = '',
    this.colorPrimaries = '',
    this.bitDepth = 0,
    this.isDownloadedFile = false,
    this.preferExternalSubtitle = false,
    this.forceNativeProxy = false,
    this.extremePlaybackEnabled = false,
    this.reliableSeek = true,
    this.seekProbeSummary,
    this.playbackMode = PlayerPlaybackMode.originalQuality,
    this.playbackSpeed = 1.0,
    this.listenVideoModeEnabled = false,
    this.audioTracks = const <AudioTrackOption>[],
    this.subtitleTracks = const <SubtitleTrackOption>[],
    this.qualities = const <PlaybackQualityOption>[],
  });

  MpvMediaSource copyWith({
    int? loadNonce,
    String? itemGuid,
    String? seriesGuid,
    String? seasonGuid,
    String? posterPath,
    String? mediaGuid,
    String? mediaType,
    String? ancestorName,
    String? videoGuid,
    int? directLinkQualityIndex,
    bool clearDirectLinkQualityIndex = false,
    int? videoWidth,
    int? videoHeight,
    String? proxySessionId,
    String? playLink,
    String? url,
    Map<String, String>? headers,
    String? title,
    String? seriesTitle,
    int? seasonNumber,
    String? tmdbId,
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
    Map<String, String>? localSubtitleFiles,
    String? videoCodecName,
    String? videoProfile,
    String? colorSpace,
    String? colorTransfer,
    String? colorPrimaries,
    int? bitDepth,
    bool? isDownloadedFile,
    bool? preferExternalSubtitle,
    bool? forceNativeProxy,
    bool? extremePlaybackEnabled,
    bool? reliableSeek,
    String? seekProbeSummary,
    bool clearSeekProbeSummary = false,
    PlayerPlaybackMode? playbackMode,
    double? playbackSpeed,
    bool? listenVideoModeEnabled,
    List<AudioTrackOption>? audioTracks,
    List<SubtitleTrackOption>? subtitleTracks,
    List<PlaybackQualityOption>? qualities,
  }) {
    return MpvMediaSource(
      loadNonce: loadNonce ?? this.loadNonce,
      itemGuid: itemGuid ?? this.itemGuid,
      seriesGuid: seriesGuid ?? this.seriesGuid,
      seasonGuid: seasonGuid ?? this.seasonGuid,
      posterPath: posterPath ?? this.posterPath,
      mediaGuid: mediaGuid ?? this.mediaGuid,
      mediaType: mediaType ?? this.mediaType,
      ancestorName: ancestorName ?? this.ancestorName,
      videoGuid: videoGuid ?? this.videoGuid,
      directLinkQualityIndex: clearDirectLinkQualityIndex
          ? null
          : directLinkQualityIndex ?? this.directLinkQualityIndex,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      proxySessionId: proxySessionId ?? this.proxySessionId,
      playLink: playLink ?? this.playLink,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      title: title ?? this.title,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      tmdbId: tmdbId ?? this.tmdbId,
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
      localSubtitleFiles: localSubtitleFiles ?? this.localSubtitleFiles,
      videoCodecName: videoCodecName ?? this.videoCodecName,
      videoProfile: videoProfile ?? this.videoProfile,
      colorSpace: colorSpace ?? this.colorSpace,
      colorTransfer: colorTransfer ?? this.colorTransfer,
      colorPrimaries: colorPrimaries ?? this.colorPrimaries,
      bitDepth: bitDepth ?? this.bitDepth,
      isDownloadedFile: isDownloadedFile ?? this.isDownloadedFile,
      preferExternalSubtitle:
          preferExternalSubtitle ?? this.preferExternalSubtitle,
      forceNativeProxy: forceNativeProxy ?? this.forceNativeProxy,
      extremePlaybackEnabled:
          extremePlaybackEnabled ?? this.extremePlaybackEnabled,
      reliableSeek: reliableSeek ?? this.reliableSeek,
      seekProbeSummary: clearSeekProbeSummary
          ? null
          : seekProbeSummary ?? this.seekProbeSummary,
      playbackMode: playbackMode ?? this.playbackMode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      listenVideoModeEnabled:
          listenVideoModeEnabled ?? this.listenVideoModeEnabled,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      qualities: qualities ?? this.qualities,
    );
  }

  factory MpvMediaSource.localFile({
    required String filePath,
    required String itemGuid,
    required String mediaGuid,
    required String title,
    String seriesGuid = '',
    String seasonGuid = '',
    String posterPath = '',
    String mediaType = '',
    String ancestorName = '',
    String videoGuid = '',
    String seriesTitle = '',
    int seasonNumber = 0,
    String tmdbId = '',
    int episodeNumber = 0,
    Duration startPosition = Duration.zero,
    String resolution = '',
    int bitrate = 0,
    int durationSeconds = 0,
    int? audioTrackIndex,
    int? subtitleTrackIndex,
    String? audioTrackGuid,
    String? subtitleTrackGuid,
    int? directLinkQualityIndex,
    int videoWidth = 0,
    int videoHeight = 0,
    String videoCodecName = '',
    String videoProfile = '',
    String colorSpace = '',
    String colorTransfer = '',
    String colorPrimaries = '',
    int bitDepth = 0,
    double playbackSpeed = 1.0,
    bool listenVideoModeEnabled = false,
    List<AudioTrackOption> audioTracks = const <AudioTrackOption>[],
    List<SubtitleTrackOption> subtitleTracks = const <SubtitleTrackOption>[],
    List<PlaybackQualityOption> qualities = const <PlaybackQualityOption>[],
    int? loadNonce,
  }) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedMediaGuid = mediaGuid.trim().isNotEmpty
        ? mediaGuid.trim()
        : normalizedItemGuid;
    final normalizedVideoGuid = videoGuid.trim().isNotEmpty
        ? videoGuid.trim()
        : normalizedMediaGuid;
    final normalizedPath = filePath.trim();
    final localSubtitleBundle = discoverLocalSubtitleBundle(
      mediaGuid: normalizedMediaGuid,
      videoFilePath: normalizedPath,
    );
    final mergedSubtitleTracks = <SubtitleTrackOption>[];
    final seenSubtitleGuids = <String>{};

    void addSubtitleTrack(SubtitleTrackOption track) {
      final guid = track.guid.trim();
      if (guid.isEmpty || !seenSubtitleGuids.add(guid)) {
        return;
      }
      mergedSubtitleTracks.add(track);
    }

    for (final track in localSubtitleBundle.tracks) {
      addSubtitleTrack(track);
    }
    for (final track in subtitleTracks) {
      addSubtitleTrack(track);
    }
    final normalizedSubtitleGuid = subtitleTrackGuid?.trim() ?? '';
    final resolvedSubtitleTrackGuid =
        normalizedSubtitleGuid.startsWith('local:')
        ? normalizedSubtitleGuid
        : (localSubtitleBundle.preferredGuid?.trim().isNotEmpty == true
              ? localSubtitleBundle.preferredGuid!.trim()
              : (normalizedSubtitleGuid.isNotEmpty
                    ? normalizedSubtitleGuid
                    : null));
    return MpvMediaSource(
      loadNonce: loadNonce ?? createMpvLoadNonce(),
      itemGuid: normalizedItemGuid,
      seriesGuid: seriesGuid,
      seasonGuid: seasonGuid,
      posterPath: posterPath,
      mediaGuid: normalizedMediaGuid,
      mediaType: mediaType,
      ancestorName: ancestorName,
      videoGuid: normalizedVideoGuid,
      directLinkQualityIndex: directLinkQualityIndex,
      url: Uri.file(normalizedPath).toString(),
      headers: const <String, String>{},
      title: title,
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      tmdbId: tmdbId,
      episodeNumber: episodeNumber,
      startPosition: startPosition,
      audioTrackIndex: audioTrackIndex,
      subtitleTrackIndex: subtitleTrackIndex,
      audioTrackGuid: audioTrackGuid,
      subtitleTrackGuid: resolvedSubtitleTrackGuid,
      resolution: resolution,
      bitrate: bitrate,
      durationSeconds: durationSeconds,
      localSubtitleFiles: localSubtitleBundle.fileByGuid,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoCodecName: videoCodecName,
      videoProfile: videoProfile,
      colorSpace: colorSpace,
      colorTransfer: colorTransfer,
      colorPrimaries: colorPrimaries,
      bitDepth: bitDepth,
      isDownloadedFile: true,
      preferExternalSubtitle: localSubtitleBundle.tracks.isNotEmpty,
      reliableSeek: true,
      seekProbeSummary: 'local-download',
      playbackMode: PlayerPlaybackMode.originalQuality,
      playbackSpeed: playbackSpeed,
      listenVideoModeEnabled: listenVideoModeEnabled,
      audioTracks: audioTracks,
      subtitleTracks: mergedSubtitleTracks,
      qualities: qualities,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'loadNonce': loadNonce,
      'itemGuid': itemGuid,
      'seriesGuid': seriesGuid,
      'seasonGuid': seasonGuid,
      'posterPath': posterPath,
      'mediaGuid': mediaGuid,
      'mediaType': mediaType,
      'ancestorName': ancestorName,
      'videoGuid': videoGuid,
      'directLinkQualityIndex': directLinkQualityIndex,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'proxySessionId': proxySessionId,
      'playLink': playLink,
      'url': url,
      'headers': headers,
      'title': title,
      'seriesTitle': seriesTitle,
      'seasonNumber': seasonNumber,
      'tmdbId': tmdbId,
      'episodeNumber': episodeNumber,
      'startPositionMs': startPosition.inMilliseconds,
      'audioTrackIndex': audioTrackIndex,
      'subtitleTrackIndex': subtitleTrackIndex,
      'audioTrackGuid': audioTrackGuid,
      'subtitleTrackGuid': subtitleTrackGuid,
      'resolution': resolution,
      'bitrate': bitrate,
      'durationSeconds': durationSeconds,
      'localSubtitleFiles': localSubtitleFiles,
      'videoCodecName': videoCodecName,
      'videoProfile': videoProfile,
      'colorSpace': colorSpace,
      'colorTransfer': colorTransfer,
      'colorPrimaries': colorPrimaries,
      'bitDepth': bitDepth,
      'isDownloadedFile': isDownloadedFile,
      'preferExternalSubtitle': preferExternalSubtitle,
      'forceNativeProxy': forceNativeProxy,
      'extremePlaybackEnabled': extremePlaybackEnabled,
      'reliableSeek': reliableSeek,
      'seekProbeSummary': seekProbeSummary,
      'playbackMode': playbackMode.name,
      'serverPlaybackManaged': serverPlaybackManaged,
      'playbackSpeed': playbackSpeed,
      'listenVideoModeEnabled': listenVideoModeEnabled,
      'audioTracks': audioTracks.map(_audioTrackToMap).toList(),
      'subtitleTracks': subtitleTracks.map(_subtitleTrackToMap).toList(),
      'qualities': qualities.map(_qualityToMap).toList(),
    };
  }

  factory MpvMediaSource.fromMap(Map<String, dynamic> raw) {
    int intOf(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    double doubleOf(Object? value) =>
        value is double ? value : double.tryParse('$value') ?? 0;
    String? stringOrNull(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final rawHeaders = raw['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        headers[key.toString()] = value?.toString() ?? '';
      });
    }

    final rawLocalSubtitleFiles = raw['localSubtitleFiles'];
    final localSubtitleFiles = <String, String>{};
    if (rawLocalSubtitleFiles is Map) {
      rawLocalSubtitleFiles.forEach((key, value) {
        final normalizedKey = key.toString().trim();
        final normalizedValue = value?.toString().trim() ?? '';
        if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
        localSubtitleFiles[normalizedKey] = normalizedValue;
      });
    }

    List<AudioTrackOption> parseAudioTracks(Object? value) {
      if (value is! List) return const <AudioTrackOption>[];
      return value
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
                  (entry['isDefault'] == true || intOf(entry['isDefault']) == 1)
                  ? 1
                  : 0,
            ),
          )
          .toList(growable: false);
    }

    List<SubtitleTrackOption> parseSubtitleTracks(Object? value) {
      if (value is! List) return const <SubtitleTrackOption>[];
      return value
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
                  (entry['isDefault'] == true || intOf(entry['isDefault']) == 1)
                  ? 1
                  : 0,
              forced: (entry['forced'] == true || intOf(entry['forced']) == 1)
                  ? 1
                  : 0,
              isExternal:
                  (entry['isExternal'] == true ||
                      intOf(entry['isExternal']) == 1)
                  ? 1
                  : 0,
              extraFile:
                  (entry['extraFile'] == true || intOf(entry['extraFile']) == 1)
                  ? 1
                  : 0,
              isBitmap:
                  (entry['isBitmap'] == true || intOf(entry['isBitmap']) == 1)
                  ? 1
                  : 0,
            ),
          )
          .toList(growable: false);
    }

    List<PlaybackQualityOption> parseQualities(Object? value) {
      if (value is! List) return const <PlaybackQualityOption>[];
      return value
          .whereType<Map>()
          .map(
            (entry) => PlaybackQualityOption(
              mediaGuid: (entry['mediaGuid'] ?? '').toString(),
              videoGuid: (entry['videoGuid'] ?? '').toString(),
              resolution: (entry['resolution'] ?? '').toString(),
              bitrate: intOf(entry['bitrate']),
              isDefault:
                  (entry['isDefault'] == true || intOf(entry['isDefault']) == 1)
                  ? 1
                  : 0,
              source: PlaybackQualitySource.values.firstWhere(
                (candidate) =>
                    candidate.name == (entry['source'] ?? '').toString(),
                orElse: () => PlaybackQualitySource.originalProxy,
              ),
              directLinkQualityIndex: entry['directLinkQualityIndex'] == null
                  ? null
                  : intOf(entry['directLinkQualityIndex']),
            ),
          )
          .toList(growable: false);
    }

    return MpvMediaSource(
      loadNonce: intOf(raw['loadNonce']),
      itemGuid: (raw['itemGuid'] ?? '').toString(),
      seriesGuid: (raw['seriesGuid'] ?? '').toString(),
      seasonGuid: (raw['seasonGuid'] ?? '').toString(),
      posterPath: (raw['posterPath'] ?? '').toString(),
      mediaGuid: (raw['mediaGuid'] ?? '').toString(),
      mediaType: (raw['mediaType'] ?? '').toString(),
      ancestorName: (raw['ancestorName'] ?? '').toString(),
      videoGuid: (raw['videoGuid'] ?? '').toString(),
      directLinkQualityIndex: raw['directLinkQualityIndex'] == null
          ? null
          : intOf(raw['directLinkQualityIndex']),
      videoWidth: intOf(raw['videoWidth']),
      videoHeight: intOf(raw['videoHeight']),
      proxySessionId: stringOrNull(raw['proxySessionId']),
      playLink: stringOrNull(raw['playLink']),
      url: (raw['url'] ?? '').toString(),
      headers: headers,
      title: (raw['title'] ?? '').toString(),
      seriesTitle: (raw['seriesTitle'] ?? '').toString(),
      seasonNumber: intOf(raw['seasonNumber']),
      tmdbId: (raw['tmdbId'] ?? '').toString(),
      episodeNumber: intOf(raw['episodeNumber']),
      startPosition: Duration(milliseconds: intOf(raw['startPositionMs'])),
      audioTrackIndex: raw['audioTrackIndex'] == null
          ? null
          : intOf(raw['audioTrackIndex']),
      subtitleTrackIndex: raw['subtitleTrackIndex'] == null
          ? null
          : intOf(raw['subtitleTrackIndex']),
      audioTrackGuid: stringOrNull(raw['audioTrackGuid']),
      subtitleTrackGuid: stringOrNull(raw['subtitleTrackGuid']),
      resolution: (raw['resolution'] ?? '').toString(),
      bitrate: intOf(raw['bitrate']),
      durationSeconds: intOf(raw['durationSeconds']),
      localSubtitleFiles: localSubtitleFiles,
      videoCodecName: (raw['videoCodecName'] ?? '').toString(),
      videoProfile: (raw['videoProfile'] ?? '').toString(),
      colorSpace: (raw['colorSpace'] ?? '').toString(),
      colorTransfer: (raw['colorTransfer'] ?? '').toString(),
      colorPrimaries: (raw['colorPrimaries'] ?? '').toString(),
      bitDepth: intOf(raw['bitDepth']),
      isDownloadedFile: raw['isDownloadedFile'] == true,
      preferExternalSubtitle: raw['preferExternalSubtitle'] == true,
      forceNativeProxy: raw['forceNativeProxy'] == true,
      extremePlaybackEnabled: raw['extremePlaybackEnabled'] == true,
      reliableSeek: raw['reliableSeek'] != false,
      seekProbeSummary: stringOrNull(raw['seekProbeSummary']),
      playbackMode: PlayerPlaybackMode.values.firstWhere(
        (candidate) => candidate.name == (raw['playbackMode'] ?? '').toString(),
        orElse: () => PlayerPlaybackMode.originalQuality,
      ),
      playbackSpeed: doubleOf(raw['playbackSpeed']).clamp(0.0, 16.0),
      listenVideoModeEnabled: raw['listenVideoModeEnabled'] == true,
      audioTracks: parseAudioTracks(raw['audioTracks']),
      subtitleTracks: parseSubtitleTracks(raw['subtitleTracks']),
      qualities: parseQualities(raw['qualities']),
    );
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
      'source': quality.source.name,
      'directLinkQualityIndex': quality.directLinkQualityIndex,
    };
  }
}

@immutable
class MpvPlayerValue {
  final int loadNonce;
  final bool ready;
  final bool nativeLibLoaded;
  final bool paused;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final bool listenVideoModeEnabled;
  final String statusText;
  final String? error;
  final String? nativeProxySessionId;
  final String? cacheResourceKey;

  const MpvPlayerValue({
    required this.loadNonce,
    required this.ready,
    required this.nativeLibLoaded,
    required this.paused,
    required this.position,
    required this.bufferedPosition,
    required this.duration,
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
      paused = true,
      position = Duration.zero,
      bufferedPosition = Duration.zero,
      duration = Duration.zero,
      listenVideoModeEnabled = false,
      statusText = 'Preparing player',
      error = null,
      nativeProxySessionId = null,
      cacheResourceKey = null;

  MpvPlayerValue copyWith({
    int? loadNonce,
    bool? ready,
    bool? nativeLibLoaded,
    bool? paused,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
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
      paused: paused ?? this.paused,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
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
      paused: event['paused'] as bool?,
      position: durationFrom(event['positionMs']),
      bufferedPosition: durationFrom(event['bufferedPositionMs']),
      duration: durationFrom(event['durationMs']),
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
  static const Duration _positionUpdateThreshold = Duration(milliseconds: 400);
  static const Duration _bufferedUpdateThreshold = Duration(milliseconds: 800);
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
  final ValueNotifier<DanmakuDynamicOcclusionState> danmakuOcclusionState =
      ValueNotifier<DanmakuDynamicOcclusionState>(
        DanmakuDynamicOcclusionState.disabled,
      );

  MethodChannel? _methodChannel;
  EventChannel? _eventChannel;
  EventChannel? _danmakuAiEventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<dynamic>? _danmakuAiEventSubscription;
  bool _suppressNativeStateUntilCurrentLoad = false;
  int _pendingLoadNonce = 0;
  Duration _pendingLoadPosition = Duration.zero;
  Duration _pendingLoadDuration = Duration.zero;

  void attach(int viewId) {
    _methodChannel = MethodChannel('fly_player/mpv_view_$viewId/methods');
    _eventChannel = EventChannel('fly_player/mpv_view_$viewId/events');
    _danmakuAiEventChannel = EventChannel(
      'fly_player/mpv_view_$viewId/danmaku_ai_events',
    );
    final previousSubscription = _eventSubscription;
    final previousDanmakuAiSubscription = _danmakuAiEventSubscription;
    if (previousSubscription != null) {
      unawaited(_cancelSubscription(previousSubscription));
    }
    if (previousDanmakuAiSubscription != null) {
      unawaited(_cancelSubscription(previousDanmakuAiSubscription));
    }
    danmakuOcclusionState.value = DanmakuDynamicOcclusionState.disabled;
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleError,
    );
    _danmakuAiEventSubscription = _danmakuAiEventChannel!
        .receiveBroadcastStream()
        .listen(_handleDanmakuAiEvent, onError: _handleError);
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
      paused: paused ?? value.value.paused,
      position: source.startPosition,
      bufferedPosition: source.startPosition,
      duration: source.durationSeconds > 0
          ? Duration(seconds: source.durationSeconds)
          : Duration.zero,
      listenVideoModeEnabled: source.listenVideoModeEnabled,
      statusText: statusText,
      error: null,
      nativeProxySessionId: null,
      cacheResourceKey: null,
    );
  }

  Future<void> reload(MpvMediaSource source) async {
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
        message: '播放器未就绪',
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
        message: '播放器未就绪',
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
      return const <String, Object?>{'success': false, 'message': '播放器未就绪'};
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
        return const <String, Object?>{'success': false, 'message': '截图失败'};
      }
      return _normalizeMap(result);
    } on MissingPluginException {
      rethrow;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      return <String, Object?>{
        'success': false,
        'message': error.message ?? '截图失败',
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
      final normalized = DanmakuDynamicOcclusionState.fromMap(state);
      _publishDanmakuOcclusionState(normalized);
      return normalized;
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
    _handleNativeState(MpvPlayerValue.fromEvent(event, fallback: value.value));
  }

  void _handleDanmakuAiEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) return;
    _publishDanmakuOcclusionState(DanmakuDynamicOcclusionState.fromMap(event));
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
    if (next.loadNonce != _pendingLoadNonce) {
      return false;
    }
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
    if (next.ready && next.nativeLibLoaded) {
      return _matchesPendingLoad(next);
    }
    if (statusText == 'playback resumed' ||
        statusText == 'playback paused' ||
        statusText == 'seek applied' ||
        statusText == 'audio track changed' ||
        statusText == 'subtitle track changed' ||
        statusText == 'external subtitle loaded') {
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

  void _publishDanmakuOcclusionState(DanmakuDynamicOcclusionState next) {
    if (danmakuOcclusionState.value == next) {
      return;
    }
    danmakuOcclusionState.value = next;
  }

  bool _shouldPublishValue(MpvPlayerValue previous, MpvPlayerValue next) {
    if (previous.ready != next.ready ||
        previous.nativeLibLoaded != next.nativeLibLoaded ||
        previous.paused != next.paused ||
        previous.listenVideoModeEnabled != next.listenVideoModeEnabled ||
        previous.duration != next.duration ||
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
    _suppressNativeStateUntilCurrentLoad = false;
    final subscription = _eventSubscription;
    final danmakuAiSubscription = _danmakuAiEventSubscription;
    _eventSubscription = null;
    _danmakuAiEventSubscription = null;
    if (subscription != null) {
      await _cancelSubscription(subscription);
    }
    if (danmakuAiSubscription != null) {
      await _cancelSubscription(danmakuAiSubscription);
    }
    _eventChannel = null;
    _danmakuAiEventChannel = null;
    _methodChannel = null;
    danmakuOcclusionState.dispose();
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
