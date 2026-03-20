enum DownloadTaskStatus { downloading, downloaded, failed }

extension DownloadTaskStatusX on DownloadTaskStatus {
  String get storageValue => switch (this) {
    DownloadTaskStatus.downloading => 'downloading',
    DownloadTaskStatus.downloaded => 'downloaded',
    DownloadTaskStatus.failed => 'failed',
  };

  static DownloadTaskStatus fromStorage(String raw) {
    return DownloadTaskStatus.values.firstWhere(
      (value) => value.storageValue == raw,
      orElse: () => DownloadTaskStatus.failed,
    );
  }
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
  final DownloadTaskStatus status;
  final String errorMessage;
  final int createdAtMs;
  final int updatedAtMs;

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
    required this.status,
    required this.errorMessage,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get isDownloaded => status == DownloadTaskStatus.downloaded;
  bool get isDownloading => status == DownloadTaskStatus.downloading;

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
    DownloadTaskStatus? status,
    String? errorMessage,
    int? createdAtMs,
    int? updatedAtMs,
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
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
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
      status: DownloadTaskStatusX.fromStorage(
        (json['status'] ?? '').toString(),
      ),
      errorMessage: (json['errorMessage'] ?? '').toString(),
      createdAtMs: _asInt(json['createdAtMs']),
      updatedAtMs: _asInt(json['updatedAtMs']),
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
      'status': status.storageValue,
      'errorMessage': errorMessage,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  static int _asInt(dynamic value) => int.tryParse('$value') ?? 0;
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

  const DownloadActionState({
    this.downloading = false,
    this.downloaded = false,
    this.failed = false,
  });

  String label({
    String downloadLabel = '下载',
    String downloadingLabel = '下载中',
    String downloadedLabel = '已下载',
  }) {
    if (downloaded) return downloadedLabel;
    if (downloading) return downloadingLabel;
    return downloadLabel;
  }

  bool get canStart => !downloading && !downloaded;

  static const DownloadActionState idle = DownloadActionState();
}
