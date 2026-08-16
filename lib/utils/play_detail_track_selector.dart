import '../l10n/generated/app_localizations.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../ui/audio_track_label_localizer.dart';
import 'media_language_mapper.dart';

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
    required AppLocalizations l10n,
  }) {
    final offLabel = l10n.trackSubtitleOff;
    final fallbackLabel = l10n.trackSubtitleNone;
    if (selectedSubtitleGuid == null || selectedSubtitleGuid.isEmpty) {
      return offLabel;
    }
    for (final track in subtitleTracks) {
      if (track.guid == selectedSubtitleGuid) {
        return subtitleOptionTitle(track, l10n: l10n);
      }
    }
    if (subtitleTracks.isNotEmpty) {
      return subtitleOptionTitle(subtitleTracks.first, l10n: l10n);
    }
    return fallbackLabel;
  }

  static String audioLabelForCurrentMedia({
    required String? selectedAudioGuid,
    required List<AudioTrackOption> audioTracks,
    required StreamListOption? selectedOption,
    required AppLocalizations l10n,
  }) {
    final fallbackLabel = l10n.trackAudioNone;
    for (final track in audioTracks) {
      if (track.guid == selectedAudioGuid) return audioOptionTitle(track);
    }
    if (audioTracks.isNotEmpty) return audioOptionTitle(audioTracks.first);
    if (selectedOption != null) {
      return audioTrackLabel(l10n, selectedOption.audioLanguage);
    }
    return fallbackLabel;
  }

  static String audioOptionTitle(AudioTrackOption track) {
    final mapped = MediaLanguageMapper.languageName(track.language).trim();
    if (mapped.isNotEmpty) return mapped;
    final raw = track.language.trim();
    final normalized = raw.toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'und' ||
        normalized == 'unknown' ||
        normalized == 'zz-unknow') {
      return '';
    }
    return raw;
  }

  static String subtitleDisplayLabel(
    SubtitleTrackOption track, {
    required AppLocalizations l10n,
  }) {
    return subtitleOptionTitle(track, l10n: l10n);
  }

  static String subtitleDetailLabel(
    SubtitleTrackOption track, {
    required AppLocalizations l10n,
  }) {
    return subtitleOptionSubtitle(track, l10n: l10n);
  }

  static String subtitleOptionTitle(
    SubtitleTrackOption track, {
    required AppLocalizations l10n,
  }) {
    final language = MediaLanguageMapper.subtitleLabel(track.language).trim();
    final unknownSubtitle = l10n.trackSubtitleUnknownLanguage;
    final normalized =
        (language.isEmpty || language == '字幕' || language == '未知')
        ? unknownSubtitle
        : language;
    final suffix = track.isDefaultOption
        ? l10n.trackSubtitleDefaultSuffix
        : track.guid.startsWith('local:sub:')
        ? l10n.trackSubtitleLocalImportedSuffix
        : (track.isExternal == 1 ? l10n.trackSubtitleExternalSuffix : '');
    return suffix.isEmpty ? normalized : '$normalized-$suffix';
  }

  static String subtitleOptionSubtitle(
    SubtitleTrackOption track, {
    required AppLocalizations l10n,
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
    return l10n.trackSubtitleName;
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

  static bool subtitlePrefersExternalFile(SubtitleTrackOption? track) {
    return track != null &&
        (track.isExternal == 1 ||
            track.extraFile == 1 ||
            track.guid.startsWith('local:'));
  }

  static int? embeddedSubtitleTrackIndex({
    required SubtitleTrackOption? selectedSubtitle,
    required List<SubtitleTrackOption> subtitleTracks,
  }) {
    if (selectedSubtitle == null ||
        subtitlePrefersExternalFile(selectedSubtitle)) {
      return null;
    }
    final embeddedTracks = subtitleTracks
        .where((track) {
          if (track.guid.trim().isEmpty) return false;
          if (track.guid.startsWith('local:')) return false;
          return track.isExternal != 1 && track.extraFile != 1;
        })
        .toList(growable: false);
    final ordinal = embeddedTracks.indexWhere(
      (track) => track.guid == selectedSubtitle.guid,
    );
    if (ordinal < 0) return null;
    return ordinal + 1;
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
