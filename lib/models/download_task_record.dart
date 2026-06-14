import 'stream_track_data.dart';

enum DownloadTaskStatus { downloading, downloaded, failed, paused }

extension DownloadTaskStatusX on DownloadTaskStatus {
  String get storageValue => switch (this) {
    DownloadTaskStatus.downloading => 'downloading',
    DownloadTaskStatus.downloaded => 'downloaded',
    DownloadTaskStatus.failed => 'failed',
    DownloadTaskStatus.paused => 'paused',
  };

  static DownloadTaskStatus fromStorage(String raw) {
    return DownloadTaskStatus.values.firstWhere(
      (value) => value.storageValue == raw,
      orElse: () => DownloadTaskStatus.failed,
    );
  }
}

int compareDownloadTaskRecordsForDisplay(
  DownloadTaskRecord lhs,
  DownloadTaskRecord rhs, {
  DownloadTaskStatus? statusHint,
}) {
  final keepCreationOrder =
      statusHint == DownloadTaskStatus.downloading ||
      statusHint == DownloadTaskStatus.paused ||
      (statusHint == null &&
          (lhs.status == DownloadTaskStatus.downloading ||
              lhs.status == DownloadTaskStatus.paused) &&
          (rhs.status == DownloadTaskStatus.downloading ||
              rhs.status == DownloadTaskStatus.paused));
  if (keepCreationOrder) {
    final createdAtCompare = rhs.createdAtMs.compareTo(lhs.createdAtMs);
    if (createdAtCompare != 0) return createdAtCompare;
    final idCompare = rhs.id.compareTo(lhs.id);
    if (idCompare != 0) return idCompare;
    return rhs.updatedAtMs.compareTo(lhs.updatedAtMs);
  }
  final updatedAtCompare = rhs.updatedAtMs.compareTo(lhs.updatedAtMs);
  if (updatedAtCompare != 0) return updatedAtCompare;
  final createdAtCompare = rhs.createdAtMs.compareTo(lhs.createdAtMs);
  if (createdAtCompare != 0) return createdAtCompare;
  return rhs.id.compareTo(lhs.id);
}

class DownloadTaskRecord {
  final String id;
  final String remoteTaskId;
  final String itemGuid;
  final String mediaGuid;
  final String groupId;
  final String groupTitle;
  final String title;
  final String durationText;
  final List<String> posterUrls;
  final List<String> groupPosterUrls;
  final String resolution;
  final String fileName;
  final String filePath;
  final int totalBytes;
  final int downloadedBytes;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final DownloadTaskStatus status;
  final String errorMessage;
  final int createdAtMs;
  final int updatedAtMs;

  /// TMDB 标识（`tm12345` 或纯数字）。下载时写入，离线时仍可用于弹幕 tmid 精确搜索。
  final String tmdbId;

  /// 剧集季号/集号。下载时写入，离线选集与弹幕集匹配用（playItem 离线拿不到时兜底）。
  final int seasonNumber;
  final int episodeNumber;

  const DownloadTaskRecord({
    required this.id,
    required this.remoteTaskId,
    required this.itemGuid,
    required this.mediaGuid,
    required this.groupId,
    required this.groupTitle,
    required this.title,
    required this.durationText,
    required this.posterUrls,
    required this.groupPosterUrls,
    required this.resolution,
    required this.fileName,
    required this.filePath,
    required this.totalBytes,
    required this.downloadedBytes,
    this.audioTracks = const <AudioTrackOption>[],
    this.subtitleTracks = const <SubtitleTrackOption>[],
    required this.status,
    required this.errorMessage,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.tmdbId = '',
    this.seasonNumber = 0,
    this.episodeNumber = 0,
  });

  bool get isDownloaded => status == DownloadTaskStatus.downloaded;
  bool get isDownloading => status == DownloadTaskStatus.downloading;
  bool get isPaused => status == DownloadTaskStatus.paused;
  bool get isActive => isDownloading || isPaused;

  DownloadTaskRecord copyWith({
    String? id,
    String? remoteTaskId,
    String? itemGuid,
    String? mediaGuid,
    String? groupId,
    String? groupTitle,
    String? title,
    String? durationText,
    List<String>? posterUrls,
    List<String>? groupPosterUrls,
    String? resolution,
    String? fileName,
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    List<AudioTrackOption>? audioTracks,
    List<SubtitleTrackOption>? subtitleTracks,
    DownloadTaskStatus? status,
    String? errorMessage,
    int? createdAtMs,
    int? updatedAtMs,
    String? tmdbId,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    return DownloadTaskRecord(
      id: id ?? this.id,
      remoteTaskId: remoteTaskId ?? this.remoteTaskId,
      itemGuid: itemGuid ?? this.itemGuid,
      mediaGuid: mediaGuid ?? this.mediaGuid,
      groupId: groupId ?? this.groupId,
      groupTitle: groupTitle ?? this.groupTitle,
      title: title ?? this.title,
      durationText: durationText ?? this.durationText,
      posterUrls: posterUrls ?? this.posterUrls,
      groupPosterUrls: groupPosterUrls ?? this.groupPosterUrls,
      resolution: resolution ?? this.resolution,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      tmdbId: tmdbId ?? this.tmdbId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
    );
  }

  factory DownloadTaskRecord.fromJson(Map<String, dynamic> json) {
    final rawPosterUrls = json['posterUrls'];
    final rawGroupPosterUrls = json['groupPosterUrls'];
    return DownloadTaskRecord(
      id: (json['id'] ?? '').toString(),
      remoteTaskId: (json['remoteTaskId'] ?? '').toString(),
      itemGuid: (json['itemGuid'] ?? '').toString(),
      mediaGuid: (json['mediaGuid'] ?? '').toString(),
      groupId: (json['groupId'] ?? '').toString(),
      groupTitle: (json['groupTitle'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      durationText: (json['durationText'] ?? '').toString(),
      posterUrls: rawPosterUrls is List
          ? rawPosterUrls.map((value) => '$value').toList(growable: false)
          : const <String>[],
      groupPosterUrls: rawGroupPosterUrls is List
          ? rawGroupPosterUrls.map((value) => '$value').toList(growable: false)
          : const <String>[],
      resolution: (json['resolution'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      totalBytes: _asInt(json['totalBytes']),
      downloadedBytes: _asInt(json['downloadedBytes']),
      audioTracks: _parseAudioTracks(json['audioTracks']),
      subtitleTracks: _parseSubtitleTracks(json['subtitleTracks']),
      status: DownloadTaskStatusX.fromStorage(
        (json['status'] ?? '').toString(),
      ),
      errorMessage: (json['errorMessage'] ?? '').toString(),
      createdAtMs: _asInt(json['createdAtMs']),
      updatedAtMs: _asInt(json['updatedAtMs']),
      tmdbId: (json['tmdbId'] ?? '').toString(),
      seasonNumber: _asInt(json['seasonNumber']),
      episodeNumber: _asInt(json['episodeNumber']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'remoteTaskId': remoteTaskId,
      'itemGuid': itemGuid,
      'mediaGuid': mediaGuid,
      'groupId': groupId,
      'groupTitle': groupTitle,
      'title': title,
      'durationText': durationText,
      'posterUrls': posterUrls,
      'groupPosterUrls': groupPosterUrls,
      'resolution': resolution,
      'fileName': fileName,
      'filePath': filePath,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
      'audioTracks': audioTracks
          .map<Map<String, dynamic>>(_audioTrackToJson)
          .toList(growable: false),
      'subtitleTracks': subtitleTracks
          .map<Map<String, dynamic>>(_subtitleTrackToJson)
          .toList(growable: false),
      'status': status.storageValue,
      'errorMessage': errorMessage,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'tmdbId': tmdbId,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
    };
  }

  static int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  static List<AudioTrackOption> _parseAudioTracks(dynamic value) {
    if (value is! List) return const <AudioTrackOption>[];
    return value
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return AudioTrackOption(
            mediaGuid: (map['mediaGuid'] ?? map['media_guid'] ?? '').toString(),
            guid: (map['guid'] ?? '').toString(),
            title: (map['title'] ?? '').toString(),
            codecName: (map['codecName'] ?? map['codec_name'] ?? '').toString(),
            profile: (map['profile'] ?? '').toString(),
            language: (map['language'] ?? '').toString(),
            audioType: (map['audioType'] ?? map['audio_type'] ?? '').toString(),
            channelLayout: (map['channelLayout'] ?? map['channel_layout'] ?? '')
                .toString(),
            channels: _asInt(map['channels']),
            sampleRate: _asInt(map['sampleRate'] ?? map['sample_rate']),
            bps: _asInt(map['bps']),
            index: _asInt(map['index']),
            isDefault: _asInt(map['isDefault'] ?? map['is_default']),
          );
        })
        .toList(growable: false);
  }

  static List<SubtitleTrackOption> _parseSubtitleTracks(dynamic value) {
    if (value is! List) return const <SubtitleTrackOption>[];
    return value
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return SubtitleTrackOption(
            mediaGuid: (map['mediaGuid'] ?? map['media_guid'] ?? '').toString(),
            guid: (map['guid'] ?? '').toString(),
            title: (map['title'] ?? '').toString(),
            codecName: (map['codecName'] ?? map['codec_name'] ?? '').toString(),
            format: (map['format'] ?? '').toString(),
            language: (map['language'] ?? '').toString(),
            index: _asInt(map['index']),
            isDefault: _asInt(map['isDefault'] ?? map['is_default']),
            forced: _asInt(map['forced']),
            isExternal: _asInt(map['isExternal'] ?? map['is_external']),
            extraFile: _asInt(map['extraFile'] ?? map['extra_file']),
            isBitmap: _asInt(map['isBitmap'] ?? map['is_bitmap']),
          );
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> _audioTrackToJson(AudioTrackOption track) {
    return <String, dynamic>{
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

  static Map<String, dynamic> _subtitleTrackToJson(SubtitleTrackOption track) {
    return <String, dynamic>{
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
      'extraFile': track.extraFile,
      'isBitmap': track.isBitmap,
    };
  }
}

class DownloadTaskGroup {
  final String id;
  final String title;
  final List<DownloadTaskRecord> records;

  const DownloadTaskGroup({
    required this.id,
    required this.title,
    required this.records,
  });

  int get totalBytes =>
      records.fold<int>(0, (sum, record) => sum + record.totalBytes);

  int get downloadedBytes =>
      records.fold<int>(0, (sum, record) => sum + record.downloadedBytes);

  int get itemCount => records.length;

  DownloadTaskRecord get leadRecord => records.first;
}

class DownloadActionState {
  final bool downloading;
  final bool downloaded;
  final bool failed;
  final bool paused;

  const DownloadActionState({
    this.downloading = false,
    this.downloaded = false,
    this.failed = false,
    this.paused = false,
  });

  String label({
    String downloadLabel = 'Download',
    String downloadingLabel = 'Downloading',
    String downloadedLabel = 'Downloaded',
    String pausedLabel = 'Paused',
  }) {
    if (downloaded) return downloadedLabel;
    if (downloading) return downloadingLabel;
    if (paused) return pausedLabel;
    return downloadLabel;
  }

  bool get canStart => !downloading && !downloaded;

  static const DownloadActionState idle = DownloadActionState();
}
