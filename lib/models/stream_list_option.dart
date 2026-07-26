class StreamListOption {
  final String mediaGuid;
  final String videoGuid;
  final String resolutionType;
  final String colorRangeType;
  final String audioType;
  final String audioLanguage;
  final int duration;

  const StreamListOption({
    required this.mediaGuid,
    required this.videoGuid,
    required this.resolutionType,
    required this.colorRangeType,
    required this.audioType,
    required this.audioLanguage,
    required this.duration,
  });

  String get label {
    final resolution = _formatResolution(resolutionType);
    final color = _normalizeCapabilityBadge(colorRangeType);
    final parts = <String>[
      if (resolution.isNotEmpty) resolution,
      if (color.isNotEmpty) color,
    ];
    return parts.join(' ');
  }

  static String _formatResolution(String raw) {
    final normalized = _normalizeCapabilityBadge(raw);
    switch (normalized) {
      case '1080':
        return '1080P';
      case '720':
        return '720P';
      case '480':
        return '480P';
      default:
        return normalized;
    }
  }

  static List<StreamListOption> fromApiData(Map<String, dynamic> data) {
    final videoStreams = data['video_streams'];
    if (videoStreams is! List) return const [];

    final audioTypeByMediaGuid = <String, String>{};
    final audioLanguageByMediaGuid = <String, String>{};
    final audioStreams = data['audio_streams'];
    if (audioStreams is List) {
      for (final entry in audioStreams) {
        if (entry is! Map<String, dynamic>) continue;
        final mediaGuid = (entry['media_guid'] ?? '').toString();
        if (mediaGuid.isEmpty || audioTypeByMediaGuid.containsKey(mediaGuid)) {
          continue;
        }
        audioTypeByMediaGuid[mediaGuid] = (entry['audio_type'] ?? '')
            .toString();
        audioLanguageByMediaGuid[mediaGuid] = (entry['language'] ?? '')
            .toString();
      }
    }

    final options = <StreamListOption>[];
    for (final entry in videoStreams) {
      if (entry is! Map<String, dynamic>) continue;
      final mediaGuid = (entry['media_guid'] ?? '').toString();
      if (mediaGuid.isEmpty) continue;
      options.add(
        StreamListOption(
          mediaGuid: mediaGuid,
          videoGuid: (entry['guid'] ?? '').toString(),
          resolutionType: (entry['resolution_type'] ?? '').toString(),
          colorRangeType: (entry['color_range_type'] ?? '').toString(),
          audioType: audioTypeByMediaGuid[mediaGuid] ?? '',
          audioLanguage: audioLanguageByMediaGuid[mediaGuid] ?? '',
          duration: int.tryParse('${entry['duration']}') ?? 0,
        ),
      );
    }
    return options;
  }
}

String _normalizeCapabilityBadge(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
