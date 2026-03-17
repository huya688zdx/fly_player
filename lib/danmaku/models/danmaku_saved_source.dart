enum DanmakuSavedSourceType { localFile, danDanPlay }

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
  final int seasonNumber;
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
    this.seasonNumber = 0,
    this.mediaType = '',
  });

  bool get isLocalFile => type == DanmakuSavedSourceType.localFile;
  bool get isDanDanPlay => type == DanmakuSavedSourceType.danDanPlay;

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
      'seasonNumber': seasonNumber,
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
      seasonNumber: _readInt(json['seasonNumber']),
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
