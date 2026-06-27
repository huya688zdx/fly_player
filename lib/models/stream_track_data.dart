import 'package:fly_player/utils/media_language_mapper.dart';
import 'stream_list_option.dart';

class StreamTrackData {
  final List<StreamListOption> options;
  final Map<String, StreamFileInfo> fileByMediaGuid;
  final Map<String, VideoStreamInfo> videoByMediaGuid;
  final Map<String, List<AudioTrackOption>> audioByMediaGuid;
  final Map<String, List<SubtitleTrackOption>> subtitleByMediaGuid;

  const StreamTrackData({
    required this.options,
    required this.fileByMediaGuid,
    required this.videoByMediaGuid,
    required this.audioByMediaGuid,
    required this.subtitleByMediaGuid,
  });

  factory StreamTrackData.fromApiData(Map<String, dynamic> data) {
    final options = StreamListOption.fromApiData(data);
    final fileByMediaGuid = <String, StreamFileInfo>{};
    final videoByMediaGuid = <String, VideoStreamInfo>{};
    final audioByMediaGuid = <String, List<AudioTrackOption>>{};
    final subtitleByMediaGuid = <String, List<SubtitleTrackOption>>{};

    final files = data['files'];
    if (files is List) {
      for (final entry in files) {
        if (entry is! Map<String, dynamic>) continue;
        final file = StreamFileInfo.fromJson(entry);
        if (file.mediaGuid.isEmpty) continue;
        fileByMediaGuid[file.mediaGuid] = file;
      }
    }

    final videoStreams = data['video_streams'];
    if (videoStreams is List) {
      for (final entry in videoStreams) {
        if (entry is! Map<String, dynamic>) continue;
        final video = VideoStreamInfo.fromJson(entry);
        if (video.mediaGuid.isEmpty) continue;
        // Use the first stream per media as the "main" one.
        videoByMediaGuid.putIfAbsent(video.mediaGuid, () => video);
      }
    }

    final audioStreams = data['audio_streams'];
    if (audioStreams is List) {
      for (final entry in audioStreams) {
        if (entry is! Map<String, dynamic>) continue;
        final option = AudioTrackOption.fromJson(entry);
        if (option.mediaGuid.isEmpty || option.guid.isEmpty) continue;
        audioByMediaGuid.putIfAbsent(
          option.mediaGuid,
          () => <AudioTrackOption>[],
        );
        audioByMediaGuid[option.mediaGuid]!.add(option);
      }
      for (final mediaGuid in audioByMediaGuid.keys) {
        final rawList = audioByMediaGuid[mediaGuid]!
          ..sort((a, b) => a.index.compareTo(b.index));
        var hasDefault = false;
        final normalized = <AudioTrackOption>[];
        for (final item in rawList) {
          if (item.isDefaultOption && !hasDefault) {
            normalized.add(item.copyWith(isDefault: 1));
            hasDefault = true;
          } else {
            normalized.add(item.copyWith(isDefault: 0));
          }
        }
        if (!hasDefault && normalized.isNotEmpty) {
          normalized[0] = normalized[0].copyWith(isDefault: 1);
        }
        audioByMediaGuid[mediaGuid] = normalized;
      }
    }

    final subtitleStreams = data['subtitle_streams'];
    if (subtitleStreams is List) {
      for (final entry in subtitleStreams) {
        if (entry is! Map<String, dynamic>) continue;
        final option = SubtitleTrackOption.fromJson(entry);
        if (option.mediaGuid.isEmpty || option.guid.isEmpty) continue;
        subtitleByMediaGuid.putIfAbsent(
          option.mediaGuid,
          () => <SubtitleTrackOption>[],
        );
        subtitleByMediaGuid[option.mediaGuid]!.add(option);
      }
      for (final mediaGuid in subtitleByMediaGuid.keys) {
        final rawList = subtitleByMediaGuid[mediaGuid]!
          ..sort((a, b) => a.index.compareTo(b.index));
        final normalized = List<SubtitleTrackOption>.from(rawList);
        final hasDefault = normalized.any((item) => item.isDefaultOption);
        if (!hasDefault && normalized.isNotEmpty) {
          normalized[0] = normalized[0].copyWith(isDefault: 1);
        }
        subtitleByMediaGuid[mediaGuid] = normalized;
      }
    }

    return StreamTrackData(
      options: options,
      fileByMediaGuid: fileByMediaGuid,
      videoByMediaGuid: videoByMediaGuid,
      audioByMediaGuid: audioByMediaGuid,
      subtitleByMediaGuid: subtitleByMediaGuid,
    );
  }

  StreamFileInfo? fileForMedia(String mediaGuid) {
    return fileByMediaGuid[mediaGuid];
  }

  VideoStreamInfo? videoForMedia(String mediaGuid) {
    return videoByMediaGuid[mediaGuid];
  }

  List<AudioTrackOption> audiosForMedia(String mediaGuid) {
    return audioByMediaGuid[mediaGuid] ?? const [];
  }

  List<SubtitleTrackOption> subtitlesForMedia(String mediaGuid) {
    return subtitleByMediaGuid[mediaGuid] ?? const [];
  }
}

class StreamFileInfo {
  final String mediaGuid;
  final String path;
  final String fileName;
  final int size;
  final int fileBirthTime;
  final int createTime;
  final int updateTime;

  const StreamFileInfo({
    required this.mediaGuid,
    required this.path,
    required this.fileName,
    required this.size,
    required this.fileBirthTime,
    required this.createTime,
    required this.updateTime,
  });

  factory StreamFileInfo.fromJson(Map<String, dynamic> json) {
    return StreamFileInfo(
      mediaGuid: (json['guid'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      fileName: (json['file_name'] ?? '').toString(),
      size: _asInt(json['size']),
      fileBirthTime: _asInt(json['file_birth_time']),
      createTime: _asInt(json['create_time']),
      updateTime: _asInt(json['update_time']),
    );
  }
}

class VideoStreamInfo {
  final String mediaGuid;
  final String guid;
  final String resolutionType;
  final String colorRangeType;
  final String codecName;
  final String profile;
  final String level;
  final String displayAspectRatio;
  final String pixFmt;
  final String rFrameRate;
  final String colorRange;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final int bps;
  final int bitDepth;
  final int refs;
  final int progressive;
  final int width;
  final int height;

  const VideoStreamInfo({
    required this.mediaGuid,
    required this.guid,
    required this.resolutionType,
    required this.colorRangeType,
    required this.codecName,
    required this.profile,
    required this.level,
    required this.displayAspectRatio,
    required this.pixFmt,
    required this.rFrameRate,
    required this.colorRange,
    required this.colorSpace,
    required this.colorTransfer,
    required this.colorPrimaries,
    required this.bps,
    required this.bitDepth,
    required this.refs,
    required this.progressive,
    required this.width,
    required this.height,
  });

  factory VideoStreamInfo.fromJson(Map<String, dynamic> json) {
    return VideoStreamInfo(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      guid: (json['guid'] ?? '').toString(),
      resolutionType: (json['resolution_type'] ?? '').toString(),
      colorRangeType: (json['color_range_type'] ?? '').toString(),
      codecName: (json['codec_name'] ?? '').toString(),
      profile: (json['profile'] ?? '').toString(),
      level: (json['level'] ?? '').toString(),
      displayAspectRatio: (json['display_aspect_ratio'] ?? '').toString(),
      pixFmt: (json['pix_fmt'] ?? '').toString(),
      rFrameRate: (json['r_frame_rate'] ?? '').toString(),
      colorRange: (json['color_range'] ?? '').toString(),
      colorSpace: (json['color_space'] ?? '').toString(),
      colorTransfer: (json['color_transfer'] ?? '').toString(),
      colorPrimaries: (json['color_primaries'] ?? '').toString(),
      bps: _asInt(json['bps']),
      bitDepth: _asInt(json['bit_depth']),
      refs: _asInt(json['refs']),
      progressive: _asInt(json['progressive']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
    );
  }
}

class AudioTrackOption {
  final String mediaGuid;
  final String guid;
  final String title;
  final String codecName;
  final String profile;
  final String language;
  final String audioType;
  final String channelLayout;
  final int channels;
  final int sampleRate;
  final int bps;
  final int index;
  final int isDefault;

  const AudioTrackOption({
    required this.mediaGuid,
    required this.guid,
    required this.title,
    required this.codecName,
    required this.profile,
    required this.language,
    required this.audioType,
    required this.channelLayout,
    required this.channels,
    required this.sampleRate,
    required this.bps,
    required this.index,
    required this.isDefault,
  });

  factory AudioTrackOption.fromJson(Map<String, dynamic> json) {
    return AudioTrackOption(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      guid: (json['guid'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      codecName: (json['codec_name'] ?? '').toString(),
      profile: (json['profile'] ?? '').toString(),
      language: (json['language'] ?? '').toString(),
      audioType: (json['audio_type'] ?? '').toString(),
      channelLayout: (json['channel_layout'] ?? '').toString(),
      channels: _asInt(json['channels']),
      sampleRate: _asInt(json['sample_rate']),
      bps: _asInt(json['bps']),
      index: _asInt(json['index']),
      isDefault: _asInt(json['is_default']),
    );
  }

  AudioTrackOption copyWith({int? isDefault}) {
    return AudioTrackOption(
      mediaGuid: mediaGuid,
      guid: guid,
      title: title,
      codecName: codecName,
      profile: profile,
      language: language,
      audioType: audioType,
      channelLayout: channelLayout,
      channels: channels,
      sampleRate: sampleRate,
      bps: bps,
      index: index,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  bool get isDefaultOption => isDefault == 1;

  String get displayLabel {
    return MediaLanguageMapper.audioLabel(language);
  }

  String get detailLabel {
    final parts = <String>[
      if (codecName.trim().isNotEmpty) codecName.trim().toLowerCase(),
      if (profile.trim().isNotEmpty) profile.trim(),
      if (channelLayout.trim().isNotEmpty)
        channelLayout.trim()
      else
        _channelText(channels),
      if (title.trim().isNotEmpty) title.trim(),
    ];
    if (parts.isNotEmpty) return parts.join('  ');
    if (audioType.trim().isNotEmpty) return audioType.trim();
    return '\u672a\u77e5\u97f3\u9891';
  }
}

class SubtitleTrackOption {
  final String mediaGuid;
  final String guid;
  final String title;
  final String codecName;
  final String format;
  final String language;
  final int index;
  final int isDefault;
  final int forced;
  final int isExternal;
  final int extraFile;
  final int isBitmap;

  const SubtitleTrackOption({
    required this.mediaGuid,
    required this.guid,
    required this.title,
    required this.codecName,
    required this.format,
    required this.language,
    required this.index,
    required this.isDefault,
    required this.forced,
    required this.isExternal,
    required this.extraFile,
    required this.isBitmap,
  });

  factory SubtitleTrackOption.fromJson(Map<String, dynamic> json) {
    return SubtitleTrackOption(
      mediaGuid: (json['media_guid'] ?? '').toString(),
      guid: (json['guid'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      codecName: (json['codec_name'] ?? '').toString(),
      format: (json['format'] ?? '').toString(),
      language: (json['language'] ?? '').toString(),
      index: _asInt(json['index']),
      isDefault: _asInt(json['is_default']),
      forced: _asInt(json['forced']),
      isExternal: _asInt(json['is_external']),
      extraFile: _asInt(json['extra_file']),
      isBitmap: _asInt(json['is_bitmap']),
    );
  }

  SubtitleTrackOption copyWith({int? isDefault}) {
    return SubtitleTrackOption(
      mediaGuid: mediaGuid,
      guid: guid,
      title: title,
      codecName: codecName,
      format: format,
      language: language,
      index: index,
      isDefault: isDefault ?? this.isDefault,
      forced: forced,
      isExternal: isExternal,
      extraFile: extraFile,
      isBitmap: isBitmap,
    );
  }

  bool get isDefaultOption => isDefault == 1;

  String get displayLabel {
    return _subtitleTitleLabel(language, title);
  }

  String get detailLabel {
    final fmt = (format.isNotEmpty ? format : codecName).trim().toUpperCase();
    final style = _subtitleStyleLabel(title);
    final parts = <String>[
      if (fmt.isNotEmpty) fmt,
      if (style.isNotEmpty) style,
    ];
    if (parts.isNotEmpty) return parts.join('  ');
    return '\u5b57\u5e55';
  }
}

/// 拖动 seek 预览缩略图（播放器层）：某播放位置 → 一张缩略图直链。
///
/// 由播放桥接器从后端中立的 `MediaSeekThumbnail` 映射而来，随 `MpvMediaSource.toMap()`
/// 进 loadArgs 传给原生壳。原生壳拖动 seek 时按目标位置取最近一张显示；空列表 = 该条目
/// 无缩略图（飞牛恒空），退回纯时间药丸。
class MpvSeekThumbnail {
  const MpvSeekThumbnail({required this.positionMs, required this.url});

  final int positionMs;
  final String url;

  Map<String, Object?> toMap() => <String, Object?>{
    'positionMs': positionMs,
    'url': url,
  };

  static MpvSeekThumbnail? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['url'] ?? '').toString();
    if (url.isEmpty) return null;
    final pos = raw['positionMs'];
    final positionMs = pos is int
        ? pos
        : (pos is num ? pos.toInt() : int.tryParse('$pos') ?? 0);
    return MpvSeekThumbnail(
      positionMs: positionMs < 0 ? 0 : positionMs,
      url: url,
    );
  }
}

String _channelText(int channels) {
  if (channels <= 0) return '';
  if (channels == 1) return '1.0ch';
  if (channels == 2) return '2.0ch';
  if (channels == 6) return '5.1ch';
  if (channels == 8) return '7.1ch';
  return '$channels ch';
}

String _subtitleTitleLabel(String language, String title) {
  final t = title.trim().toLowerCase();
  if (t.contains('cht') || t.contains('trad')) return '中文';
  if (t.contains('chs') || t.contains('simp')) return '中文';
  return MediaLanguageMapper.subtitleLabel(language);
}

String _subtitleStyleLabel(String title) {
  final t = title.trim().toLowerCase();
  if (t.isEmpty) return '';
  if (t.contains('traditional_dsnp')) return 'Traditional_DSNP';
  if (t.contains('simplified_dsnp')) return 'Simplified_DSNP';
  if (t.contains('cht') || t.contains('trad')) return 'Traditional';
  if (t.contains('chs') || t.contains('simp')) return 'Simplified';
  return title.trim().replaceAll(RegExp(r'\s+'), ' ');
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
