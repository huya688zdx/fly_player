import 'stream_track_data.dart';

class PlaybackStreamData {
  final StreamFileInfo? fileStream;
  final VideoStreamInfo? videoStream;
  final List<AudioTrackOption> audioStreams;
  final List<SubtitleTrackOption> subtitleStreams;
  final List<PlaybackQualityOption> qualities;

  const PlaybackStreamData({
    required this.fileStream,
    required this.videoStream,
    required this.audioStreams,
    required this.subtitleStreams,
    required this.qualities,
  });

  factory PlaybackStreamData.fromJson(Map<String, dynamic> json) {
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

    final qualities = <PlaybackQualityOption>[];
    final rawQualities = json['qualities'];
    if (rawQualities is List) {
      for (final entry in rawQualities) {
        if (entry is Map<String, dynamic>) {
          qualities.add(PlaybackQualityOption.fromJson(entry));
        }
      }
    }

    return PlaybackStreamData(
      fileStream: fileStream,
      videoStream: videoStream,
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      qualities: qualities,
    );
  }
}

class PlaybackQualityOption {
  final String mediaGuid;
  final String videoGuid;
  final String resolution;
  final int bitrate;
  final int isDefault;

  const PlaybackQualityOption({
    required this.mediaGuid,
    required this.videoGuid,
    required this.resolution,
    required this.bitrate,
    required this.isDefault,
  });

  factory PlaybackQualityOption.fromJson(Map<String, dynamic> json) {
    return PlaybackQualityOption(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      videoGuid: (json['video_guid'] ?? json['guid'] ?? '').toString(),
      resolution:
          (json['resolution'] ?? json['resolution_type'] ?? json['label'] ?? '')
              .toString(),
      bitrate: _asInt(json['bitrate'] ?? json['bps']),
      isDefault: _asInt(json['is_default']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
