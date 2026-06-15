import 'stream_track_data.dart';

enum PlaybackQualitySource { originalProxy, serverSession, directLink }

enum PlaybackCloudStorageType {
  unknown,
  baiduPan,
  aliPan,
  cloud115Pan,
  quarkPan,
  cloud123Pan,
  strm,
}

class PlaybackResponseHeaders {
  final List<String> cookies;
  final List<String> userAgents;

  const PlaybackResponseHeaders({
    this.cookies = const <String>[],
    this.userAgents = const <String>[],
  });

  factory PlaybackResponseHeaders.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PlaybackResponseHeaders();
    }
    return PlaybackResponseHeaders(
      cookies: _stringList(json['Cookie'] ?? json['cookie'] ?? json['cookies']),
      userAgents: _stringList(
        json['User-Agent'] ??
            json['UserAgent'] ??
            json['user_agent'] ??
            json['userAgent'],
      ),
    );
  }

  String get cookieHeader => cookies
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join('; ');

  String get primaryUserAgent {
    for (final value in userAgents) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }
}

class PlaybackCloudStorageInfo {
  final PlaybackCloudStorageType type;
  final int rawTypeCode;

  const PlaybackCloudStorageInfo({
    required this.type,
    required this.rawTypeCode,
  });

  factory PlaybackCloudStorageInfo.fromJson(Map<String, dynamic> json) {
    final rawTypeCode = _asInt(
      json['cloud_storage_type'] ?? json['cloudStorageType'] ?? json['type'],
    );
    return PlaybackCloudStorageInfo(
      type: _parseCloudStorageType(rawTypeCode),
      rawTypeCode: rawTypeCode,
    );
  }

  bool get isQuarkPan => type == PlaybackCloudStorageType.quarkPan;

  bool get isStrm => type == PlaybackCloudStorageType.strm;
}

class DirectLinkQualitySource {
  final int index;
  final String mediaGuid;
  final String videoGuid;
  final String resolution;
  final int bitrate;
  final String url;

  const DirectLinkQualitySource({
    required this.index,
    required this.mediaGuid,
    required this.videoGuid,
    required this.resolution,
    required this.bitrate,
    required this.url,
  });

  factory DirectLinkQualitySource.fromJson(
    Map<String, dynamic> json, {
    required int fallbackIndex,
  }) {
    return DirectLinkQualitySource(
      index:
          _asNullableInt(
            json['direct_link_quality_index'] ??
                json['quality_index'] ??
                json['index'],
          ) ??
          fallbackIndex,
      mediaGuid: (json['media_guid'] ?? '').toString(),
      videoGuid: (json['video_guid'] ?? json['guid'] ?? '').toString(),
      resolution:
          (json['resolution'] ?? json['resolution_type'] ?? json['label'] ?? '')
              .toString(),
      bitrate: _asInt(json['bitrate'] ?? json['bps']),
      url: _pickDirectLinkUrl(json),
    );
  }
}

class DirectLinkPlaybackTarget {
  final String url;
  final Map<String, String> headers;
  final bool forceNativeProxy;
  final String debugSummary;

  const DirectLinkPlaybackTarget({
    required this.url,
    required this.headers,
    required this.forceNativeProxy,
    required this.debugSummary,
  });
}

class PlaybackStreamData {
  final StreamFileInfo? fileStream;
  final VideoStreamInfo? videoStream;
  final List<AudioTrackOption> audioStreams;
  final List<SubtitleTrackOption> subtitleStreams;
  final List<PlaybackQualityOption> qualities;
  final List<DirectLinkQualitySource> directLinkQualities;
  final PlaybackCloudStorageInfo? cloudStorageInfo;
  final PlaybackResponseHeaders responseHeaders;
  final String requestUserAgent;

  const PlaybackStreamData({
    required this.fileStream,
    required this.videoStream,
    required this.audioStreams,
    required this.subtitleStreams,
    required this.qualities,
    required this.directLinkQualities,
    required this.cloudStorageInfo,
    required this.responseHeaders,
    this.requestUserAgent = '',
  });

  factory PlaybackStreamData.fromJson(
    Map<String, dynamic> json, {
    String requestUserAgent = '',
  }) {
    StreamFileInfo? fileStream;
    final rawFile = json['file_stream'];
    if (rawFile is Map<String, dynamic>) {
      fileStream = StreamFileInfo.fromJson(rawFile);
    }

    VideoStreamInfo? videoStream;
    final rawVideo = json['video_stream'];
    if (rawVideo is Map<String, dynamic>) {
      videoStream = VideoStreamInfo.fromJson(rawVideo);
    }

    final audioStreams = <AudioTrackOption>[];
    final rawAudios = json['audio_streams'];
    if (rawAudios is List) {
      for (final entry in rawAudios) {
        if (entry is Map<String, dynamic>) {
          audioStreams.add(AudioTrackOption.fromJson(entry));
        }
      }
    }

    final subtitleStreams = <SubtitleTrackOption>[];
    final rawSubtitles = json['subtitle_streams'];
    if (rawSubtitles is List) {
      for (final entry in rawSubtitles) {
        if (entry is Map<String, dynamic>) {
          subtitleStreams.add(SubtitleTrackOption.fromJson(entry));
        }
      }
    }

    final responseHeaders = PlaybackResponseHeaders.fromJson(
      json['header'] as Map<String, dynamic>?,
    );
    PlaybackCloudStorageInfo? cloudStorageInfo;
    final rawCloudStorageInfo = json['cloud_storage_info'];
    if (rawCloudStorageInfo is Map<String, dynamic>) {
      cloudStorageInfo = PlaybackCloudStorageInfo.fromJson(rawCloudStorageInfo);
    }

    final qualities = <PlaybackQualityOption>[];
    final serverQualities = <PlaybackQualityOption>[];
    final rawQualities = json['qualities'];
    if (rawQualities is List) {
      for (final entry in rawQualities) {
        if (entry is Map<String, dynamic>) {
          serverQualities.add(
            PlaybackQualityOption.fromJson(
              entry,
              source: _inferQualitySource(entry),
            ),
          );
        }
      }
    }

    final directLinkQualities = <DirectLinkQualitySource>[];
    var hasDirectLinkDefault = false;
    final rawDirectLinkQualities = json['direct_link_qualities'];
    if (rawDirectLinkQualities is List) {
      for (var i = 0; i < rawDirectLinkQualities.length; i++) {
        final entry = rawDirectLinkQualities[i];
        if (entry is Map<String, dynamic>) {
          final quality = DirectLinkQualitySource.fromJson(
            entry,
            fallbackIndex: i,
          );
          if (!_shouldIncludeDirectLinkQuality(cloudStorageInfo, quality.url)) {
            continue;
          }
          directLinkQualities.add(quality);
          final directLinkOption = PlaybackQualityOption.fromJson(
            entry,
            source: PlaybackQualitySource.directLink,
            fallbackDirectLinkQualityIndex: i,
          );
          final normalizedDirectLinkOption =
              cloudStorageInfo?.isStrm == true &&
                  !hasDirectLinkDefault &&
                  directLinkOption.isDefault != 1
              ? PlaybackQualityOption(
                  mediaGuid: directLinkOption.mediaGuid,
                  videoGuid: directLinkOption.videoGuid,
                  resolution: directLinkOption.resolution,
                  bitrate: directLinkOption.bitrate,
                  isDefault: 1,
                  source: directLinkOption.source,
                  directLinkQualityIndex:
                      directLinkOption.directLinkQualityIndex,
                )
              : directLinkOption;
          hasDirectLinkDefault =
              hasDirectLinkDefault || normalizedDirectLinkOption.isDefault == 1;
          qualities.add(normalizedDirectLinkOption);
        }
      }
    }

    final preferDirectLinkOnly =
        cloudStorageInfo?.isStrm == true && directLinkQualities.isNotEmpty;
    if (!preferDirectLinkOnly) {
      qualities.addAll(serverQualities);
    }

    final originalMediaGuid = fileStream?.mediaGuid.trim().isNotEmpty == true
        ? fileStream!.mediaGuid.trim()
        : (videoStream?.mediaGuid.trim() ?? '');
    if (originalMediaGuid.isNotEmpty && !preferDirectLinkOnly) {
      final isQuarkOriginal = cloudStorageInfo?.isQuarkPan == true;
      qualities.add(
        PlaybackQualityOption(
          mediaGuid: originalMediaGuid,
          videoGuid: videoStream?.guid.trim() ?? '',
          resolution: isQuarkOriginal
              ? 'Original'
              : (videoStream?.resolutionType.trim() ?? ''),
          bitrate: videoStream?.bps ?? 0,
          isDefault: isQuarkOriginal ? 0 : 1,
          source: PlaybackQualitySource.originalProxy,
          directLinkQualityIndex: null,
        ),
      );
    }

    final dedupedQualities = <PlaybackQualityOption>[];
    final seenQualityKeys = <String>{};
    for (final quality in qualities) {
      final key = quality.dedupKey;
      if (seenQualityKeys.add(key)) {
        dedupedQualities.add(quality);
      }
    }

    return PlaybackStreamData(
      fileStream: fileStream,
      videoStream: videoStream,
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      qualities: dedupedQualities,
      directLinkQualities: directLinkQualities,
      cloudStorageInfo: cloudStorageInfo,
      responseHeaders: responseHeaders,
      requestUserAgent: requestUserAgent.trim(),
    );
  }

  DirectLinkPlaybackTarget? buildDirectLinkTarget(int? directLinkQualityIndex) {
    if (directLinkQualities.isEmpty) return null;
    DirectLinkQualitySource? selected;
    if (directLinkQualityIndex != null) {
      for (final candidate in directLinkQualities) {
        if (candidate.index == directLinkQualityIndex) {
          selected = candidate;
          break;
        }
      }
    }
    selected ??= directLinkQualities.first;
    final url = selected.url.trim();
    if (url.isEmpty) return null;

    final headers = <String, String>{};
    final cookieHeader = responseHeaders.cookieHeader;
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    final userAgent = responseHeaders.primaryUserAgent.isNotEmpty
        ? responseHeaders.primaryUserAgent
        : requestUserAgent;
    if (userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }
    const debugSummary = 'cloud-direct';
    return DirectLinkPlaybackTarget(
      url: url,
      headers: headers,
      forceNativeProxy: false,
      debugSummary: debugSummary,
    );
  }
}

class PlaybackQualityOption {
  final String mediaGuid;
  final String videoGuid;
  final String resolution;
  final int bitrate;
  final int isDefault;
  final PlaybackQualitySource source;
  final int? directLinkQualityIndex;

  /// 源文件名（来自 StreamTrackData 的 file_name），用于「多版本」卡片展示。
  final String sourceFileName;

  const PlaybackQualityOption({
    required this.mediaGuid,
    required this.videoGuid,
    required this.resolution,
    required this.bitrate,
    required this.isDefault,
    required this.source,
    required this.directLinkQualityIndex,
    this.sourceFileName = '',
  });

  /// 返回带上源文件名的副本（其余字段不变）。
  PlaybackQualityOption withSourceFileName(String name) =>
      PlaybackQualityOption(
        mediaGuid: mediaGuid,
        videoGuid: videoGuid,
        resolution: resolution,
        bitrate: bitrate,
        isDefault: isDefault,
        source: source,
        directLinkQualityIndex: directLinkQualityIndex,
        sourceFileName: name,
      );

  factory PlaybackQualityOption.fromJson(
    Map<String, dynamic> json, {
    required PlaybackQualitySource source,
    int? fallbackDirectLinkQualityIndex,
  }) {
    return PlaybackQualityOption(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      videoGuid: (json['video_guid'] ?? json['guid'] ?? '').toString(),
      resolution:
          (json['resolution'] ?? json['resolution_type'] ?? json['label'] ?? '')
              .toString(),
      bitrate: _asInt(json['bitrate'] ?? json['bps']),
      isDefault: _asInt(json['is_default']),
      source: source,
      directLinkQualityIndex:
          _asNullableInt(
            json['direct_link_quality_index'] ??
                json['quality_index'] ??
                json['index'],
          ) ??
          (source == PlaybackQualitySource.directLink
              ? fallbackDirectLinkQualityIndex
              : null),
      sourceFileName: (json['file_name'] ?? json['fileName'] ?? '').toString(),
    );
  }

  bool get isOriginalProxy => source == PlaybackQualitySource.originalProxy;

  bool get isServerSession => source == PlaybackQualitySource.serverSession;

  bool get isDirectLink => source == PlaybackQualitySource.directLink;

  String get dedupKey {
    return [
      source.name,
      mediaGuid,
      videoGuid,
      resolution.trim(),
      bitrate.toString(),
      directLinkQualityIndex?.toString() ?? '',
    ].join('|');
  }
}

List<PlaybackQualityOption> mergePlaybackQualitiesWithStreamTrackData(
  List<PlaybackQualityOption> playbackQualities,
  StreamTrackData? trackData,
) {
  if (trackData == null || trackData.options.isEmpty) {
    return List<PlaybackQualityOption>.from(playbackQualities);
  }

  // 用 mediaGuid 对应的源文件名补全已有档（「多版本」卡片要展示源文件名）。
  String fileNameFor(String mediaGuid) =>
      trackData.fileForMedia(mediaGuid)?.fileName.trim() ?? '';

  final merged = <PlaybackQualityOption>[];
  for (final quality in playbackQualities) {
    if (quality.sourceFileName.isNotEmpty) {
      merged.add(quality);
      continue;
    }
    final name = fileNameFor(quality.mediaGuid);
    merged.add(name.isEmpty ? quality : quality.withSourceFileName(name));
  }
  final seenKeys = merged.map((quality) => quality.dedupKey).toSet();

  for (final option in trackData.options) {
    final resolution = option.label.trim().isNotEmpty
        ? option.label.trim()
        : option.resolutionType.trim();
    final videoInfo = trackData.videoForMedia(option.mediaGuid);
    final quality = PlaybackQualityOption(
      mediaGuid: option.mediaGuid,
      videoGuid: option.videoGuid,
      resolution: resolution,
      bitrate: videoInfo?.bps ?? 0,
      isDefault: 0,
      source: PlaybackQualitySource.serverSession,
      directLinkQualityIndex: null,
      sourceFileName: fileNameFor(option.mediaGuid),
    );
    if (seenKeys.add(quality.dedupKey)) {
      merged.add(quality);
    }
  }

  return merged;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse('$value');
}

PlaybackQualitySource _inferQualitySource(Map<String, dynamic> json) {
  final directLinkQualityIndex = _asNullableInt(
    json['direct_link_quality_index'] ?? json['quality_index'] ?? json['index'],
  );
  if (directLinkQualityIndex != null) {
    return PlaybackQualitySource.directLink;
  }
  if (_asInt(json['is_default']) == 1) {
    return PlaybackQualitySource.originalProxy;
  }
  return PlaybackQualitySource.serverSession;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  if (value == null) return const <String>[];
  final single = value.toString().trim();
  if (single.isEmpty) return const <String>[];
  return <String>[single];
}

String _pickDirectLinkUrl(Map<String, dynamic> json) {
  for (final candidate in <dynamic>[
    json['play_url'],
    json['url'],
    json['download_url'],
  ]) {
    final normalized = _normalizeDirectLinkUrl(candidate?.toString() ?? '');
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String _normalizeDirectLinkUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final suspiciousTrailingIndex = RegExp(r':\d+$').firstMatch(trimmed);
  if (suspiciousTrailingIndex == null) {
    return trimmed;
  }
  final schemeIndex = trimmed.indexOf('://');
  if (schemeIndex < 0) {
    return trimmed;
  }
  final authorityEnd = trimmed.indexOf('/', schemeIndex + 3);
  if (authorityEnd < 0 || suspiciousTrailingIndex.start <= authorityEnd) {
    return trimmed;
  }
  return trimmed.substring(0, suspiciousTrailingIndex.start);
}

PlaybackCloudStorageType _parseCloudStorageType(int code) {
  switch (code) {
    case 1:
      return PlaybackCloudStorageType.baiduPan;
    case 2:
      return PlaybackCloudStorageType.aliPan;
    case 3:
      return PlaybackCloudStorageType.cloud115Pan;
    case 4:
      return PlaybackCloudStorageType.quarkPan;
    case 5:
      return PlaybackCloudStorageType.cloud123Pan;
    case 9001:
      return PlaybackCloudStorageType.strm;
    default:
      return PlaybackCloudStorageType.unknown;
  }
}

bool _shouldIncludeDirectLinkQuality(
  PlaybackCloudStorageInfo? cloudStorageInfo,
  String url,
) {
  if (cloudStorageInfo?.isQuarkPan != true) {
    return true;
  }
  return _isQuarkPlaybackUrl(url);
}

bool _isQuarkPlaybackUrl(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  return host.contains('video-play-') && host.contains('drive.quark.cn');
}
