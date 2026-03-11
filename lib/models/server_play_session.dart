class ServerPlaySessionData {
  final String mediaGuid;
  final String videoGuid;
  final int videoIndex;
  final String audioGuid;
  final int audioIndex;
  final String subtitleGuid;
  final int subtitleIndex;
  final int isSubtitleExternal;
  final String playLink;
  final String subtitleLink;
  final int hlsTime;
  final String videoEncoder;
  final String notSupportedResolution;
  final String supportedHighestResolution;

  const ServerPlaySessionData({
    required this.mediaGuid,
    required this.videoGuid,
    required this.videoIndex,
    required this.audioGuid,
    required this.audioIndex,
    required this.subtitleGuid,
    required this.subtitleIndex,
    required this.isSubtitleExternal,
    required this.playLink,
    required this.subtitleLink,
    required this.hlsTime,
    required this.videoEncoder,
    required this.notSupportedResolution,
    required this.supportedHighestResolution,
  });

  factory ServerPlaySessionData.fromJson(Map<String, dynamic> json) {
    return ServerPlaySessionData(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      videoGuid: (json['video_guid'] ?? '').toString(),
      videoIndex: _asInt(json['video_index']),
      audioGuid: (json['audio_guid'] ?? '').toString(),
      audioIndex: _asInt(json['audio_index']),
      subtitleGuid: (json['subtitle_guid'] ?? '').toString(),
      subtitleIndex: _asInt(json['subtitle_index']),
      isSubtitleExternal: _asInt(json['is_subtitle_external']),
      playLink: (json['play_link'] ?? '').toString(),
      subtitleLink: (json['subtitle_link'] ?? '').toString(),
      hlsTime: _asInt(json['hls_time']),
      videoEncoder: (json['video_encoder'] ?? '').toString(),
      notSupportedResolution: (json['not_supported_resolution'] ?? '')
          .toString(),
      supportedHighestResolution: (json['supported_highest_resolution'] ?? '')
          .toString(),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
