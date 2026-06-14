/// 弹幕源类型。
/// - [localFile]：用户**主动从文件导入**的弹幕（高优先，排在网络源之上）。
/// - [danDanPlay]：在线 DanDanPlay 网络源。
/// - [downloadedFile]：**随片下载**的弹幕缓存（最低优先，仅在网络源拿不到时兜底，
///   离线可用）。与 [localFile] 区分，避免下载缓存把网络源顶掉。
enum DanmakuSavedSourceType { localFile, danDanPlay, downloadedFile }

class DanmakuSavedSource {
  final DanmakuSavedSourceType type;
  final String mediaKey;
  final String sourceKey;
  final String label;
  final int commentCount;
  final int updatedAtMs;
  final String detail;
  final String ancestorName;
  final String seriesTitle;
  final String itemTitle;
  final String itemGuid;
  final String seasonGuid;
  final String mediaGuid;
  final int seasonNumber;
  final int episodeNumber;
  final String mediaType;

  const DanmakuSavedSource({
    required this.type,
    required this.mediaKey,
    required this.sourceKey,
    required this.label,
    required this.commentCount,
    required this.updatedAtMs,
    this.detail = '',
    this.ancestorName = '',
    this.seriesTitle = '',
    this.itemTitle = '',
    this.itemGuid = '',
    this.seasonGuid = '',
    this.mediaGuid = '',
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.mediaType = '',
  });

  bool get isLocalFile => type == DanmakuSavedSourceType.localFile;
  bool get isDanDanPlay => type == DanmakuSavedSourceType.danDanPlay;
  bool get isDownloadedFile => type == DanmakuSavedSourceType.downloadedFile;

  /// 是否按本地文件解析（用户导入 + 随片下载都从文件路径读）。
  bool get isFileBased => type != DanmakuSavedSourceType.danDanPlay;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'mediaKey': mediaKey,
      'sourceKey': sourceKey,
      'label': label,
      'commentCount': commentCount,
      'updatedAtMs': updatedAtMs,
      'detail': detail,
      'ancestorName': ancestorName,
      'seriesTitle': seriesTitle,
      'itemTitle': itemTitle,
      'itemGuid': itemGuid,
      'seasonGuid': seasonGuid,
      'mediaGuid': mediaGuid,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'mediaType': mediaType,
    };
  }

  factory DanmakuSavedSource.fromJson(Map<String, dynamic> json) {
    final path = (json['path'] ?? '').toString();
    final rawType = (json['type'] ?? '').toString();
    return DanmakuSavedSource(
      type: switch (rawType) {
        'danDanPlay' => DanmakuSavedSourceType.danDanPlay,
        'dandanplay' => DanmakuSavedSourceType.danDanPlay,
        'downloadedFile' => DanmakuSavedSourceType.downloadedFile,
        _ => DanmakuSavedSourceType.localFile,
      },
      mediaKey: (json['mediaKey'] ?? '').toString(),
      sourceKey: (json['sourceKey'] ?? path).toString(),
      label: (json['label'] ?? '').toString(),
      commentCount: _readInt(json['commentCount']),
      updatedAtMs: _readInt(json['updatedAtMs']),
      detail: (json['detail'] ?? '').toString(),
      ancestorName: (json['ancestorName'] ?? '').toString(),
      seriesTitle: (json['seriesTitle'] ?? '').toString(),
      itemTitle: (json['itemTitle'] ?? '').toString(),
      itemGuid: (json['itemGuid'] ?? '').toString(),
      seasonGuid: (json['seasonGuid'] ?? '').toString(),
      mediaGuid: (json['mediaGuid'] ?? '').toString(),
      seasonNumber: _readInt(json['seasonNumber']),
      episodeNumber: _readInt(json['episodeNumber']),
      mediaType: (json['mediaType'] ?? '').toString(),
    );
  }

  static int _readInt(dynamic value) {
    return switch (value) {
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
  }
}
