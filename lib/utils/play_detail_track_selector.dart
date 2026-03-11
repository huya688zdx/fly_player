import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import 'media_language_mapper.dart';
import 'media_locale_store.dart';

class TrackSelectionSyncResult {
  final String? subtitleGuid;
  final String? audioGuid;

  const TrackSelectionSyncResult({
    required this.subtitleGuid,
    required this.audioGuid,
  });
}

class PlayDetailTrackSelector {
  static StreamListOption? currentStreamOption({
    required List<StreamListOption> options,
    required int? selectedIndex,
  }) {
    final index = selectedIndex;
    if (index == null) return null;
    if (index < 0 || index >= options.length) return null;
    return options[index];
  }

  static List<SubtitleTrackOption> subtitleTracksForCurrentMedia({
    required List<StreamListOption> options,
    required int? selectedIndex,
    required StreamTrackData? trackData,
  }) {
    final mediaGuid =
        currentStreamOption(
          options: options,
          selectedIndex: selectedIndex,
        )?.mediaGuid ??
        '';
    if (mediaGuid.isEmpty) return const [];
    return trackData?.subtitlesForMedia(mediaGuid) ?? const [];
  }

  static List<AudioTrackOption> audioTracksForCurrentMedia({
    required List<StreamListOption> options,
    required int? selectedIndex,
    required StreamTrackData? trackData,
  }) {
    final mediaGuid =
        currentStreamOption(
          options: options,
          selectedIndex: selectedIndex,
        )?.mediaGuid ??
        '';
    if (mediaGuid.isEmpty) return const [];
    return trackData?.audiosForMedia(mediaGuid) ?? const [];
  }

  static String currentAudioTypeForBadges({
    required String? selectedAudioGuid,
    required List<AudioTrackOption> audioTracks,
    required StreamListOption? selectedOption,
  }) {
    final selectedGuid = (selectedAudioGuid ?? '').trim();
    if (selectedGuid.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.guid == selectedGuid) return track.audioType;
      }
    }
    return selectedOption?.audioType ?? '';
  }

  static List<SubtitleTrackOption> mergeSubtitleTracks({
    required List<SubtitleTrackOption> primaryTracks,
    required List<SubtitleTrackOption> extraTracks,
  }) {
    if (primaryTracks.isEmpty) {
      return List<SubtitleTrackOption>.from(extraTracks);
    }
    if (extraTracks.isEmpty) {
      return List<SubtitleTrackOption>.from(primaryTracks);
    }

    final merged = <SubtitleTrackOption>[];
    final seenGuids = <String>{};

    void appendTracks(List<SubtitleTrackOption> tracks) {
      for (final track in tracks) {
        final guid = track.guid.trim();
        if (guid.isEmpty || !seenGuids.add(guid)) continue;
        merged.add(track);
      }
    }

    appendTracks(primaryTracks);
    appendTracks(extraTracks);
    return merged;
  }

  static TrackSelectionSyncResult syncTrackSelectionForCurrentMedia({
    required String? currentSubtitleGuid,
    required String? currentAudioGuid,
    required List<SubtitleTrackOption> subtitleTracks,
    required List<AudioTrackOption> audioTracks,
  }) {
    var nextSubtitle = currentSubtitleGuid;
    var nextAudio = currentAudioGuid;

    final hasSubtitle = subtitleTracks.any((e) => e.guid == nextSubtitle);
    if (!hasSubtitle) {
      nextSubtitle = pickInitialSubtitleGuid(
        preferred: null,
        tracks: subtitleTracks,
      );
    }

    final hasAudio = audioTracks.any((e) => e.guid == nextAudio);
    if (!hasAudio) {
      nextAudio = pickInitialAudioGuid(preferred: null, tracks: audioTracks);
    }

    return TrackSelectionSyncResult(
      subtitleGuid: nextSubtitle,
      audioGuid: nextAudio,
    );
  }

  static String subtitleLabelForCurrentMedia({
    required String? selectedSubtitleGuid,
    required List<SubtitleTrackOption> subtitleTracks,
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    final offLabel = MediaLocaleStore.text(
      localeMap,
      'stream.subtitle.hiddenSubtitle',
      fallback: '关闭字幕',
    );
    final fallbackLabel = MediaLocaleStore.text(
      localeMap,
      'stream.subtitle.noSubtitleTips',
      fallback: '无字幕',
    );
    if (selectedSubtitleGuid == null || selectedSubtitleGuid.isEmpty) {
      return offLabel;
    }
    for (final track in subtitleTracks) {
      if (track.guid == selectedSubtitleGuid) {
        return subtitleOptionTitle(track, localeMap: localeMap);
      }
    }
    if (subtitleTracks.isNotEmpty) {
      return subtitleOptionTitle(subtitleTracks.first, localeMap: localeMap);
    }
    return fallbackLabel;
  }

  static String audioLabelForCurrentMedia({
    required String? selectedAudioGuid,
    required List<AudioTrackOption> audioTracks,
    required StreamListOption? selectedOption,
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    final fallbackLabel = MediaLocaleStore.text(
      localeMap,
      'stream.audio.noAudioTips',
      fallback: '无音频',
    );
    for (final track in audioTracks) {
      if (track.guid == selectedAudioGuid) return track.displayLabel;
    }
    if (audioTracks.isNotEmpty) return audioTracks.first.displayLabel;
    if (selectedOption != null) return selectedOption.audioLabel;
    return fallbackLabel;
  }

  static String subtitleDisplayLabel(
    SubtitleTrackOption track, {
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    return subtitleOptionTitle(track, localeMap: localeMap);
  }

  static String subtitleDetailLabel(
    SubtitleTrackOption track, {
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    return subtitleOptionSubtitle(track, localeMap: localeMap);
  }

  static String subtitleOptionTitle(
    SubtitleTrackOption track, {
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    final language = MediaLanguageMapper.subtitleLabel(track.language).trim();
    final unknownSubtitle = MediaLocaleStore.text(
      localeMap,
      'stream.subtitle.unknownName',
      fallback: '未知语言',
    );
    final normalized =
        (language.isEmpty || language == '字幕' || language == '未知')
        ? unknownSubtitle
        : language;
    final suffix = track.isDefaultOption
        ? MediaLocaleStore.text(
            localeMap,
            'stream.subtitle.defaultSuffix',
            fallback: '默认',
          )
        : (track.isExternal == 1
              ? MediaLocaleStore.text(
                  localeMap,
                  'stream.subtitle.externalSuffix',
                  fallback: '外挂',
                )
              : '');
    return suffix.isEmpty ? normalized : '$normalized-$suffix';
  }

  static String subtitleOptionSubtitle(
    SubtitleTrackOption track, {
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) {
    final fmt = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toUpperCase();
    final title = track.title.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = <String>[
      if (fmt.isNotEmpty) fmt,
      if (title.isNotEmpty) title,
    ];
    if (parts.isNotEmpty) return parts.join('  ');
    return MediaLocaleStore.text(
      localeMap,
      'stream.subtitle.name',
      fallback: '字幕',
    );
  }

  static AudioTrackOption? selectedOrFirstAudio({
    required String? selectedAudioGuid,
    required List<AudioTrackOption> audioTracks,
  }) {
    final selectedGuid = (selectedAudioGuid ?? '').trim();
    if (selectedGuid.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.guid == selectedGuid) return track;
      }
    }
    return audioTracks.isNotEmpty ? audioTracks.first : null;
  }

  static SubtitleTrackOption? selectedOrFirstSubtitle({
    required String? selectedSubtitleGuid,
    required List<SubtitleTrackOption> subtitleTracks,
  }) {
    final selectedGuid = (selectedSubtitleGuid ?? '').trim();
    if (selectedGuid.isNotEmpty) {
      for (final track in subtitleTracks) {
        if (track.guid == selectedGuid) return track;
      }
    }
    return subtitleTracks.isNotEmpty ? subtitleTracks.first : null;
  }

  static String? pickInitialSubtitleGuid({
    required String? preferred,
    required List<SubtitleTrackOption> tracks,
  }) {
    final preferredGuid = (preferred ?? '').trim();
    if (preferredGuid.isNotEmpty) {
      for (final e in tracks) {
        if (e.guid == preferredGuid) return e.guid;
      }
    }
    for (final e in tracks) {
      if (e.isDefaultOption) return e.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : null;
  }

  static String? pickInitialAudioGuid({
    required String? preferred,
    required List<AudioTrackOption> tracks,
  }) {
    final preferredGuid = (preferred ?? '').trim();
    if (preferredGuid.isNotEmpty) {
      for (final e in tracks) {
        if (e.guid == preferredGuid) return e.guid;
      }
    }
    for (final e in tracks) {
      if (e.isDefaultOption) return e.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : null;
  }
}
