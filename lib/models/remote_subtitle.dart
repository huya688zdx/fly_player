import 'stream_track_data.dart';

class RemoteSubtitleSearchResult {
  final String language;
  final List<RemoteSubtitleSearchItem> subtitles;

  const RemoteSubtitleSearchResult({
    required this.language,
    required this.subtitles,
  });

  factory RemoteSubtitleSearchResult.fromJson(Map<String, dynamic> json) {
    final rawSubtitles = json['subtitles'];
    final subtitles = <RemoteSubtitleSearchItem>[];
    if (rawSubtitles is List) {
      for (final entry in rawSubtitles) {
        if (entry is Map<String, dynamic>) {
          subtitles.add(RemoteSubtitleSearchItem.fromJson(entry));
        }
      }
    }
    return RemoteSubtitleSearchResult(
      language: (json['lan'] ?? '').toString(),
      subtitles: subtitles,
    );
  }
}

class RemoteSubtitleSearchItem {
  final String filename;
  final int download;
  final String sourceId;
  final String source;
  final String trimId;
  final String format;

  const RemoteSubtitleSearchItem({
    required this.filename,
    required this.download,
    required this.sourceId,
    required this.source,
    required this.trimId,
    required this.format,
  });

  factory RemoteSubtitleSearchItem.fromJson(Map<String, dynamic> json) {
    return RemoteSubtitleSearchItem(
      filename: (json['filename'] ?? '').toString(),
      download: _asInt(json['download']),
      sourceId: (json['source_id'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      trimId: (json['trim_id'] ?? '').toString(),
      format: (json['format'] ?? '').toString(),
    );
  }
}

class RemoteSubtitleDownloadResult {
  final String mediaGuid;
  final String title;
  final String guid;
  final String codecName;
  final String codecType;
  final String language;
  final int forced;
  final int index;
  final int isDefault;
  final int isExternal;
  final String format;
  final String trimId;
  final String sourceId;
  final String source;
  final int createTime;
  final int updateTime;
  final int extraFile;
  final int isBitmap;
  final int fileSize;

  const RemoteSubtitleDownloadResult({
    required this.mediaGuid,
    required this.title,
    required this.guid,
    required this.codecName,
    required this.codecType,
    required this.language,
    required this.forced,
    required this.index,
    required this.isDefault,
    required this.isExternal,
    required this.format,
    required this.trimId,
    required this.sourceId,
    required this.source,
    required this.createTime,
    required this.updateTime,
    required this.extraFile,
    required this.isBitmap,
    required this.fileSize,
  });

  factory RemoteSubtitleDownloadResult.fromJson(Map<String, dynamic> json) {
    return RemoteSubtitleDownloadResult(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      guid: (json['guid'] ?? '').toString(),
      codecName: (json['codec_name'] ?? '').toString(),
      codecType: (json['codec_type'] ?? '').toString(),
      language: (json['language'] ?? '').toString(),
      forced: _asInt(json['forced']),
      index: _asInt(json['index']),
      isDefault: _asInt(json['is_default']),
      isExternal: _asInt(json['is_external']),
      format: (json['format'] ?? '').toString(),
      trimId: (json['trim_id'] ?? '').toString(),
      sourceId: (json['source_id'] ?? '').toString(),
      source: (json['Source'] ?? json['source'] ?? '').toString(),
      createTime: _asInt(json['create_time']),
      updateTime: _asInt(json['update_time']),
      extraFile: _asInt(json['extra_file']),
      isBitmap: _asInt(json['is_bitmap']),
      fileSize: _asInt(json['file_size']),
    );
  }

  SubtitleTrackOption toTrack({String? fallbackMediaGuid}) {
    return SubtitleTrackOption(
      mediaGuid: mediaGuid.trim().isNotEmpty
          ? mediaGuid.trim()
          : (fallbackMediaGuid ?? ''),
      guid: guid,
      title: title,
      codecName: codecName,
      format: format,
      language: language,
      index: index,
      isDefault: isDefault,
      forced: forced,
      isExternal: isExternal,
      extraFile: extraFile,
      isBitmap: isBitmap,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
