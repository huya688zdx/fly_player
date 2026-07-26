import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../utils/local_subtitle_bundle.dart';

int createMpvLoadNonce() {
  return DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
}

abstract final class MpvVideoOutputBackend {
  static const String texture = 'texture';
  static const String surface = 'surface';
  static const String defaultValue = String.fromEnvironment(
    'FLY_PLAYER_VIDEO_OUTPUT_BACKEND',
    defaultValue: texture,
  );

  static String normalize(String? value) {
    return switch (value?.trim().toLowerCase()) {
      surface => surface,
      texture => texture,
      _ => defaultValue,
    };
  }
}

/// 定义播放器当前使用的媒体加载链路模式。
enum PlayerPlaybackMode {
  originalQuality,
  directLinkQuality,
  serverSession;

  bool get isDirect => this != PlayerPlaybackMode.serverSession;

  bool get isOriginalQuality => this == PlayerPlaybackMode.originalQuality;

  bool get isDirectLink => this == PlayerPlaybackMode.directLinkQuality;

  bool get isServerManaged => this == PlayerPlaybackMode.serverSession;
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
  final int serverSessionHlsTimeSeconds;
  final String url;
  final Map<String, String> headers;
  final String title;
  final String seriesTitle;
  final int seasonNumber;
  final String tmdbId;
  final int episodeNumber;
  final Duration startPosition;
  final bool startPaused;
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
  final bool externalLocalSource;
  final bool danmakuAutoSearchAllowed;
  final int externalLocalFileSizeBytes;
  final bool preferExternalSubtitle;
  final bool forceNativeProxy;
  final bool extremePlaybackEnabled;
  final bool reliableSeek;
  final String? seekProbeSummary;
  final PlayerPlaybackMode playbackMode;
  final double playbackSpeed;
  final bool listenVideoModeEnabled;
  final String videoOutputBackend;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final List<PlaybackQualityOption> qualities;

  /// 拖动 seek 预览缩略图（按位置升序）。空 = 该条目无缩略图（飞牛恒空），原生壳退回纯时间药丸。
  final List<MpvSeekThumbnail> seekThumbnails;

  /// BIF 预览缩略图直链（Emby「视频预览缩略图提取」产物）。非空时原生壳后台下载解析、
  /// 拖动取帧优先于 [seekThumbnails]；404/解析失败自动退回章节图。空 = 无 BIF（飞牛恒空）。
  final String seekThumbnailBifUrl;

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
    this.serverSessionHlsTimeSeconds = 0,
    required this.url,
    required this.headers,
    required this.title,
    this.seriesTitle = '',
    this.seasonNumber = 0,
    this.tmdbId = '',
    this.episodeNumber = 0,
    this.startPosition = Duration.zero,
    this.startPaused = false,
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
    this.externalLocalSource = false,
    this.danmakuAutoSearchAllowed = true,
    this.externalLocalFileSizeBytes = 0,
    this.preferExternalSubtitle = false,
    this.forceNativeProxy = false,
    this.extremePlaybackEnabled = false,
    this.reliableSeek = true,
    this.seekProbeSummary,
    this.playbackMode = PlayerPlaybackMode.originalQuality,
    this.playbackSpeed = 1.0,
    this.listenVideoModeEnabled = false,
    this.videoOutputBackend = MpvVideoOutputBackend.defaultValue,
    this.audioTracks = const <AudioTrackOption>[],
    this.subtitleTracks = const <SubtitleTrackOption>[],
    this.qualities = const <PlaybackQualityOption>[],
    this.seekThumbnails = const <MpvSeekThumbnail>[],
    this.seekThumbnailBifUrl = '',
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
    int? serverSessionHlsTimeSeconds,
    String? url,
    Map<String, String>? headers,
    String? title,
    String? seriesTitle,
    int? seasonNumber,
    String? tmdbId,
    int? episodeNumber,
    Duration? startPosition,
    bool? startPaused,
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
    bool? externalLocalSource,
    bool? danmakuAutoSearchAllowed,
    int? externalLocalFileSizeBytes,
    bool? preferExternalSubtitle,
    bool? forceNativeProxy,
    bool? extremePlaybackEnabled,
    bool? reliableSeek,
    String? seekProbeSummary,
    bool clearSeekProbeSummary = false,
    PlayerPlaybackMode? playbackMode,
    double? playbackSpeed,
    bool? listenVideoModeEnabled,
    String? videoOutputBackend,
    List<AudioTrackOption>? audioTracks,
    List<SubtitleTrackOption>? subtitleTracks,
    List<PlaybackQualityOption>? qualities,
    List<MpvSeekThumbnail>? seekThumbnails,
    String? seekThumbnailBifUrl,
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
      serverSessionHlsTimeSeconds:
          serverSessionHlsTimeSeconds ?? this.serverSessionHlsTimeSeconds,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      title: title ?? this.title,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      tmdbId: tmdbId ?? this.tmdbId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      startPosition: startPosition ?? this.startPosition,
      startPaused: startPaused ?? this.startPaused,
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
      externalLocalSource: externalLocalSource ?? this.externalLocalSource,
      danmakuAutoSearchAllowed:
          danmakuAutoSearchAllowed ?? this.danmakuAutoSearchAllowed,
      externalLocalFileSizeBytes:
          externalLocalFileSizeBytes ?? this.externalLocalFileSizeBytes,
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
      videoOutputBackend: MpvVideoOutputBackend.normalize(
        videoOutputBackend ?? this.videoOutputBackend,
      ),
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      qualities: qualities ?? this.qualities,
      seekThumbnails: seekThumbnails ?? this.seekThumbnails,
      seekThumbnailBifUrl: seekThumbnailBifUrl ?? this.seekThumbnailBifUrl,
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
    bool startPaused = false,
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
    bool externalLocalSource = false,
    bool danmakuAutoSearchAllowed = true,
    int externalLocalFileSizeBytes = 0,
    List<AudioTrackOption> audioTracks = const <AudioTrackOption>[],
    List<SubtitleTrackOption> subtitleTracks = const <SubtitleTrackOption>[],
    List<PlaybackQualityOption> qualities = const <PlaybackQualityOption>[],
    LocalSubtitleBundle? localSubtitleBundle,
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
    final resolvedLocalSubtitleBundle =
        localSubtitleBundle ??
        discoverLocalSubtitleBundle(
          mediaGuid: normalizedMediaGuid,
          videoFilePath: normalizedPath,
        );
    final normalizedSubtitleGuid = subtitleTrackGuid?.trim() ?? '';
    final externalSubtitleTemplates = subtitleTracks
        .where(
          (track) =>
              !track.guid.startsWith('local:') &&
              (track.isExternal == 1 || track.extraFile == 1),
        )
        .toList(growable: false);
    SubtitleTrackOption? localSubtitleTemplate;
    if (resolvedLocalSubtitleBundle.tracks.length == 1 &&
        externalSubtitleTemplates.isNotEmpty) {
      if (normalizedSubtitleGuid.isNotEmpty) {
        for (final track in externalSubtitleTemplates) {
          if (track.guid == normalizedSubtitleGuid) {
            localSubtitleTemplate = track;
            break;
          }
        }
      }
      localSubtitleTemplate ??= externalSubtitleTemplates.length == 1
          ? externalSubtitleTemplates.first
          : null;
    }
    final resolvedLocalSubtitleTracks = localSubtitleTemplate == null
        ? resolvedLocalSubtitleBundle.tracks
        : <SubtitleTrackOption>[
            SubtitleTrackOption(
              mediaGuid: resolvedLocalSubtitleBundle.tracks.first.mediaGuid,
              guid: resolvedLocalSubtitleBundle.tracks.first.guid,
              title: localSubtitleTemplate.title.trim().isNotEmpty
                  ? localSubtitleTemplate.title
                  : resolvedLocalSubtitleBundle.tracks.first.title,
              codecName: resolvedLocalSubtitleBundle.tracks.first.codecName,
              format: resolvedLocalSubtitleBundle.tracks.first.format,
              language: localSubtitleTemplate.language.trim().isNotEmpty
                  ? localSubtitleTemplate.language
                  : resolvedLocalSubtitleBundle.tracks.first.language,
              index: resolvedLocalSubtitleBundle.tracks.first.index,
              isDefault: resolvedLocalSubtitleBundle.tracks.first.isDefault,
              forced: resolvedLocalSubtitleBundle.tracks.first.forced,
              isExternal: resolvedLocalSubtitleBundle.tracks.first.isExternal,
              extraFile: resolvedLocalSubtitleBundle.tracks.first.extraFile,
              isBitmap: resolvedLocalSubtitleBundle.tracks.first.isBitmap,
            ),
          ];
    final mergedSubtitleTracks = <SubtitleTrackOption>[];
    final seenSubtitleGuids = <String>{};

    void addSubtitleTrack(SubtitleTrackOption track) {
      final guid = track.guid.trim();
      if (guid.isEmpty || !seenSubtitleGuids.add(guid)) {
        return;
      }
      mergedSubtitleTracks.add(track);
    }

    for (final track in resolvedLocalSubtitleTracks) {
      addSubtitleTrack(track);
    }
    final shouldSkipExternalTemplateTrack =
        resolvedLocalSubtitleBundle.tracks.isNotEmpty &&
        externalSubtitleTemplates.isNotEmpty;
    for (final track in subtitleTracks) {
      if (shouldSkipExternalTemplateTrack &&
          !track.guid.startsWith('local:') &&
          (track.isExternal == 1 || track.extraFile == 1)) {
        continue;
      }
      addSubtitleTrack(track);
    }
    final shouldPreferDiscoveredLocalSubtitle =
        normalizedSubtitleGuid.isEmpty &&
        subtitleTrackIndex == null &&
        resolvedLocalSubtitleBundle.preferredGuid?.trim().isNotEmpty == true;
    final shouldMapExplicitExternalSubtitleToLocal =
        subtitleTrackIndex == null &&
        normalizedSubtitleGuid.isNotEmpty &&
        resolvedLocalSubtitleBundle.preferredGuid?.trim().isNotEmpty == true &&
        externalSubtitleTemplates.any(
          (track) => track.guid.trim() == normalizedSubtitleGuid,
        );
    final shouldPreferDefaultExternalSubtitle =
        normalizedSubtitleGuid.isEmpty &&
        subtitleTrackIndex == null &&
        resolvedLocalSubtitleBundle.preferredGuid?.trim().isNotEmpty != true &&
        externalSubtitleTemplates.isNotEmpty;
    String? defaultExternalSubtitleGuid() {
      for (final track in externalSubtitleTemplates) {
        final guid = track.guid.trim();
        if (guid.isNotEmpty && track.isDefaultOption) {
          return guid;
        }
      }
      for (final track in externalSubtitleTemplates) {
        final guid = track.guid.trim();
        if (guid.isNotEmpty) {
          return guid;
        }
      }
      return null;
    }

    final resolvedSubtitleTrackGuid = shouldPreferDiscoveredLocalSubtitle
        ? resolvedLocalSubtitleBundle.preferredGuid!.trim()
        : shouldMapExplicitExternalSubtitleToLocal
        ? resolvedLocalSubtitleBundle.preferredGuid!.trim()
        : shouldPreferDefaultExternalSubtitle
        ? defaultExternalSubtitleGuid()
        : (normalizedSubtitleGuid.isNotEmpty ? normalizedSubtitleGuid : null);
    final resolvedSubtitleUsesExternalFile =
        resolvedSubtitleTrackGuid != null &&
        (resolvedSubtitleTrackGuid.startsWith('local:') ||
            externalSubtitleTemplates.any(
              (track) => track.guid.trim() == resolvedSubtitleTrackGuid,
            ));
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
      startPaused: startPaused,
      audioTrackIndex: audioTrackIndex,
      subtitleTrackIndex: subtitleTrackIndex,
      audioTrackGuid: audioTrackGuid,
      subtitleTrackGuid: resolvedSubtitleTrackGuid,
      resolution: resolution,
      bitrate: bitrate,
      durationSeconds: durationSeconds,
      localSubtitleFiles: resolvedLocalSubtitleBundle.fileByGuid,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoCodecName: videoCodecName,
      videoProfile: videoProfile,
      colorSpace: colorSpace,
      colorTransfer: colorTransfer,
      colorPrimaries: colorPrimaries,
      bitDepth: bitDepth,
      isDownloadedFile: true,
      externalLocalSource: externalLocalSource,
      danmakuAutoSearchAllowed: danmakuAutoSearchAllowed,
      externalLocalFileSizeBytes: externalLocalFileSizeBytes,
      preferExternalSubtitle: resolvedSubtitleUsesExternalFile,
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
      'serverSessionHlsTimeSeconds': serverSessionHlsTimeSeconds,
      'url': url,
      'headers': headers,
      'title': title,
      'seriesTitle': seriesTitle,
      'seasonNumber': seasonNumber,
      'tmdbId': tmdbId,
      'episodeNumber': episodeNumber,
      'startPositionMs': startPosition.inMilliseconds,
      'startPaused': startPaused,
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
      'externalLocalSource': externalLocalSource,
      'danmakuAutoSearchAllowed': danmakuAutoSearchAllowed,
      'externalLocalFileSizeBytes': externalLocalFileSizeBytes,
      'preferExternalSubtitle': preferExternalSubtitle,
      'forceNativeProxy': forceNativeProxy,
      'extremePlaybackEnabled': extremePlaybackEnabled,
      'reliableSeek': reliableSeek,
      'seekProbeSummary': seekProbeSummary,
      'playbackMode': playbackMode.name,
      'serverPlaybackManaged': serverPlaybackManaged,
      'playbackSpeed': playbackSpeed,
      'listenVideoModeEnabled': listenVideoModeEnabled,
      'videoOutputBackend': MpvVideoOutputBackend.normalize(videoOutputBackend),
      'audioTracks': audioTracks.map(_audioTrackToMap).toList(),
      'subtitleTracks': subtitleTracks.map(_subtitleTrackToMap).toList(),
      'qualities': qualities.map(_qualityToMap).toList(),
      'seekThumbnails': seekThumbnails.map((t) => t.toMap()).toList(),
      'seekThumbnailBifUrl': seekThumbnailBifUrl,
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
              sourceFileName: (entry['fileName'] ?? '').toString(),
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
      serverSessionHlsTimeSeconds: intOf(raw['serverSessionHlsTimeSeconds']),
      url: (raw['url'] ?? '').toString(),
      headers: headers,
      title: (raw['title'] ?? '').toString(),
      seriesTitle: (raw['seriesTitle'] ?? '').toString(),
      seasonNumber: intOf(raw['seasonNumber']),
      tmdbId: (raw['tmdbId'] ?? '').toString(),
      episodeNumber: intOf(raw['episodeNumber']),
      startPosition: Duration(milliseconds: intOf(raw['startPositionMs'])),
      startPaused: raw['startPaused'] == true,
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
      externalLocalSource: raw['externalLocalSource'] == true,
      danmakuAutoSearchAllowed: raw['danmakuAutoSearchAllowed'] != false,
      externalLocalFileSizeBytes: intOf(raw['externalLocalFileSizeBytes']),
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
      videoOutputBackend: MpvVideoOutputBackend.normalize(
        raw['videoOutputBackend']?.toString(),
      ),
      audioTracks: parseAudioTracks(raw['audioTracks']),
      subtitleTracks: parseSubtitleTracks(raw['subtitleTracks']),
      qualities: parseQualities(raw['qualities']),
      seekThumbnails: () {
        final value = raw['seekThumbnails'];
        if (value is! List) return const <MpvSeekThumbnail>[];
        return value
            .map(MpvSeekThumbnail.fromMap)
            .whereType<MpvSeekThumbnail>()
            .toList(growable: false);
      }(),
      seekThumbnailBifUrl: raw['seekThumbnailBifUrl']?.toString() ?? '',
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
      // extraFile/isBitmap 供原生壳复刻 Flutter 的字幕三态判定：
      // extraFile==1（服务端转码/抽取出的外挂文件）走 sub-add；isBitmap/PGS/SUP
      // 等位图字幕强制留在 mpv 内置轨（不可转文本）。
      'extraFile': track.extraFile,
      'isBitmap': track.isBitmap,
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
      'fileName': quality.sourceFileName,
    };
  }
}
