class MediaInfo {
  final FileStream? fileStream;
  final VideoStream? videoStream;
  final List<AudioStream> audioStreams;
  final List<SubtitleStream> subtitleStreams;
  final List<QualityOption> qualities;

  MediaInfo({
    this.fileStream,
    this.videoStream,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.qualities = const [],
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    final rawFileStream = _asStringKeyMap(json['file_stream']);
    final rawVideoStream = _asStringKeyMap(json['video_stream']);
    return MediaInfo(
      fileStream: rawFileStream == null
          ? null
          : FileStream.fromJson(rawFileStream),
      videoStream: rawVideoStream == null
          ? null
          : VideoStream.fromJson(rawVideoStream),
      audioStreams: _decodeMapList(json['audio_streams'], AudioStream.fromJson),
      subtitleStreams: _decodeMapList(
        json['subtitle_streams'],
        SubtitleStream.fromJson,
      ),
      qualities: _decodeMapList(json['qualities'], QualityOption.fromJson),
    );
  }
}

class FileStream {
  final String filename;
  final int size;

  FileStream({required this.filename, required this.size});

  factory FileStream.fromJson(Map<String, dynamic> json) {
    return FileStream(
      filename: (json['filename'] ?? '').toString(),
      size: _asInt(json['size']),
    );
  }
}

class VideoStream {
  final String codec;
  final int width;
  final int height;

  VideoStream({required this.codec, required this.width, required this.height});

  factory VideoStream.fromJson(Map<String, dynamic> json) {
    return VideoStream(
      codec: (json['codec'] ?? '').toString(),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
    );
  }
}

class AudioStream {
  final int index;
  final String codec;
  final String? language;

  AudioStream({required this.index, required this.codec, this.language});

  factory AudioStream.fromJson(Map<String, dynamic> json) {
    return AudioStream(
      index: _asInt(json['index']),
      codec: (json['codec'] ?? '').toString(),
      language: json['language']?.toString(),
    );
  }
}

class SubtitleStream {
  final int index;
  final String codec;
  final String? language;

  SubtitleStream({required this.index, required this.codec, this.language});

  factory SubtitleStream.fromJson(Map<String, dynamic> json) {
    return SubtitleStream(
      index: _asInt(json['index']),
      codec: (json['codec'] ?? '').toString(),
      language: json['language']?.toString(),
    );
  }
}

class QualityOption {
  final String id;
  final String name;

  QualityOption({required this.id, required this.name});

  factory QualityOption.fromJson(Map<String, dynamic> json) {
    return QualityOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry('$key', value));
}

List<T> _decodeMapList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) decode,
) {
  if (value is! List) return <T>[];
  final result = <T>[];
  for (final entry in value) {
    final json = _asStringKeyMap(entry);
    if (json != null) {
      result.add(decode(json));
    }
  }
  return result;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
