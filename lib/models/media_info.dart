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
    return MediaInfo(
      fileStream: json['file_stream'] != null ? FileStream.fromJson(json['file_stream']) : null,
      videoStream: json['video_stream'] != null ? VideoStream.fromJson(json['video_stream']) : null,
      audioStreams: (json['audio_streams'] as List?)?.map((e) => AudioStream.fromJson(e)).toList() ?? [],
      subtitleStreams: (json['subtitle_streams'] as List?)?.map((e) => SubtitleStream.fromJson(e)).toList() ?? [],
      qualities: (json['qualities'] as List?)?.map((e) => QualityOption.fromJson(e)).toList() ?? [],
    );
  }
}

class FileStream {
  final String filename;
  final int size;

  FileStream({required this.filename, required this.size});

  factory FileStream.fromJson(Map<String, dynamic> json) {
    return FileStream(
      filename: json['filename'] ?? '',
      size: json['size'] ?? 0,
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
      codec: json['codec'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
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
      index: json['index'] ?? 0,
      codec: json['codec'] ?? '',
      language: json['language'],
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
      index: json['index'] ?? 0,
      codec: json['codec'] ?? '',
      language: json['language'],
    );
  }
}

class QualityOption {
  final String id;
  final String name;

  QualityOption({required this.id, required this.name});

  factory QualityOption.fromJson(Map<String, dynamic> json) {
    return QualityOption(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}
