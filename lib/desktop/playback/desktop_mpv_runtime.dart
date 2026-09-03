import 'package:media_kit/media_kit.dart';

import '../../models/playback_stream.dart';
import '../../playback/playback_source.dart';
import '../../playback/settings/mpv_settings_store.dart';
import '../../utils/media_language_mapper.dart';

class DesktopQualityChoice {
  const DesktopQualityChoice({
    required this.sourceIndex,
    required this.quality,
    required this.displayTier,
    required this.isOriginal,
  });

  final int sourceIndex;
  final PlaybackQualityOption quality;
  final String displayTier;
  final bool isOriginal;
}

class DesktopQualityMenu {
  const DesktopQualityMenu({
    required this.mainChoices,
    required this.customGroups,
  });

  final List<DesktopQualityChoice> mainChoices;
  final Map<String, List<DesktopQualityChoice>> customGroups;
}

abstract final class DesktopMpvRuntime {
  static Media mediaFor(MpvMediaSource source, {Duration? startPosition}) {
    return Media(
      source.url,
      httpHeaders: source.headers,
      start: startPosition ?? source.startPosition,
    );
  }

  static List<AudioTrack> selectableAudioTracks(List<AudioTrack> tracks) {
    return tracks
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
  }

  static AudioTrack? selectedAudioTrack(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) {
    for (final track in tracks) {
      if (track.id == current.id) return track;
    }
    if (current.id != 'auto') return null;
    for (final track in tracks) {
      if (track.isDefault == true) return track;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  static String audioTrackTitle(AudioTrack track, String fallback) {
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) {
      final mapped = MediaLanguageMapper.languageName(title).trim();
      return mapped.isNotEmpty ? mapped : title;
    }
    final language = track.language?.trim() ?? '';
    if (language.isNotEmpty) {
      final mapped = MediaLanguageMapper.languageName(language).trim();
      return mapped.isNotEmpty ? mapped : language;
    }
    return fallback;
  }

  static List<SubtitleTrack> selectableSubtitleTracks(
    List<SubtitleTrack> tracks,
  ) {
    return tracks
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
  }

  static SubtitleTrack? selectedSubtitleTrack(
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) {
    for (final track in tracks) {
      if (track.id == current.id) return track;
    }
    if (current.id != 'auto') return null;
    for (final track in tracks) {
      if (track.isDefault == true) return track;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  static String subtitleTrackTitle(SubtitleTrack track, String fallback) {
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) {
      final mapped = MediaLanguageMapper.subtitleLabel(title).trim();
      return mapped.isNotEmpty ? mapped : title;
    }
    final language = track.language?.trim() ?? '';
    if (language.isNotEmpty) {
      final mapped = MediaLanguageMapper.subtitleLabel(language).trim();
      return mapped.isNotEmpty ? mapped : language;
    }
    return fallback;
  }

  static DesktopQualityMenu qualityMenu(MpvMediaSource source) {
    final all = <DesktopQualityChoice>[
      for (var index = 0; index < source.qualities.length; index++)
        DesktopQualityChoice(
          sourceIndex: index,
          quality: source.qualities[index],
          displayTier: _qualityChoiceTier(source, source.qualities[index]),
          isOriginal:
              source.qualities[index].isOriginalProxy ||
              source.qualities[index].isDefault == 1,
        ),
    ];
    final currentVersion = source.mediaGuid.trim().isEmpty
        ? all
        : all
              .where(
                (choice) =>
                    choice.quality.mediaGuid.trim().isEmpty ||
                    choice.quality.mediaGuid.trim() == source.mediaGuid.trim(),
              )
              .toList(growable: false);
    final versionChoices = currentVersion.isEmpty ? all : currentVersion;
    final filtered = versionChoices
        .where((choice) {
          if (choice.quality.isOriginalProxy) return true;
          return source.playbackMode.isDirectLink
              ? !choice.quality.isServerSession
              : !choice.quality.isDirectLink;
        })
        .toList(growable: false);
    final visible = filtered.isEmpty ? versionChoices : filtered;

    final originalChoices = visible
        .where((choice) => choice.isOriginal)
        .toList();
    final original = originalChoices.isEmpty
        ? null
        : originalChoices.reduce(
            (current, choice) =>
                _preferQuality(source, choice, current) ? choice : current,
          );
    final byTier = <String, DesktopQualityChoice>{};
    for (final choice in visible.where((choice) => !choice.isOriginal)) {
      if (choice.displayTier == original?.displayTier) continue;
      final current = byTier[choice.displayTier];
      if (current == null || _preferQuality(source, choice, current)) {
        byTier[choice.displayTier] = choice;
      }
    }
    final tiers = byTier.values.toList()
      ..sort(
        (left, right) => _qualityTierRank(
          right.quality.resolution,
        ).compareTo(_qualityTierRank(left.quality.resolution)),
      );
    final main = <DesktopQualityChoice>[
      if (original != null) original,
      ...tiers,
    ];

    final rawGroups = <String, List<DesktopQualityChoice>>{};
    for (final choice in visible) {
      rawGroups.putIfAbsent(choice.displayTier, () => []).add(choice);
    }
    final groupNames = rawGroups.keys.toList()
      ..sort(
        (left, right) =>
            _qualityTierRank(right).compareTo(_qualityTierRank(left)),
      );
    final groups = <String, List<DesktopQualityChoice>>{};
    for (final name in groupNames) {
      final byBitrate = <int, DesktopQualityChoice>{};
      for (final choice in rawGroups[name]!) {
        final current = byBitrate[choice.quality.bitrate];
        if (current == null || _preferQuality(source, choice, current)) {
          byBitrate[choice.quality.bitrate] = choice;
        }
      }
      groups[name] = byBitrate.values.toList()
        ..sort(
          (left, right) =>
              right.quality.bitrate.compareTo(left.quality.bitrate),
        );
    }
    return DesktopQualityMenu(mainChoices: main, customGroups: groups);
  }

  static String currentQualityLabel(
    MpvMediaSource source,
    String originalLabel,
  ) {
    if (source.playbackMode.isOriginalQuality) return originalLabel;
    final tier = _qualityTierLabel(source.resolution);
    return tier.isEmpty ? originalLabel : tier;
  }

  static String qualityBitrateLabel(int bitrate) {
    if (bitrate <= 0) return '';
    if (bitrate < 1000000) return '${(bitrate / 1000).round()} Kbps';
    final mbps = (bitrate / 1000000).toStringAsFixed(2);
    return '${mbps.replaceFirst(RegExp(r'\.0+$'), '').replaceFirst(RegExp(r'(\.\d)0$'), r'$1')} Mbps';
  }

  static bool isCurrentQuality(
    MpvMediaSource source,
    DesktopQualityChoice choice,
  ) {
    final quality = choice.quality;
    if (source.playbackMode.isOriginalQuality) return choice.isOriginal;
    if (quality.directLinkQualityIndex != null &&
        quality.directLinkQualityIndex == source.directLinkQualityIndex) {
      return true;
    }
    return _qualityTierRank(quality.resolution) ==
            _qualityTierRank(source.resolution) &&
        (source.bitrate <= 0 ||
            quality.bitrate <= 0 ||
            quality.bitrate == source.bitrate);
  }

  static bool _preferQuality(
    MpvMediaSource source,
    DesktopQualityChoice candidate,
    DesktopQualityChoice current,
  ) {
    final candidateCurrent = isCurrentQuality(source, candidate);
    final currentCurrent = isCurrentQuality(source, current);
    if (candidateCurrent != currentCurrent) return candidateCurrent;
    if (candidate.isOriginal != current.isOriginal) return candidate.isOriginal;
    return candidate.quality.bitrate > current.quality.bitrate;
  }

  static String _qualityTierLabel(String resolution) {
    final rank = _qualityTierRank(resolution);
    if (rank >= 4320) return '8K';
    if (rank == 2160) return '4K';
    if (rank >= 1430 && rank <= 1450) return '2K';
    if (rank > 0) return '${rank}P';
    return resolution.trim();
  }

  static String _qualityChoiceTier(
    MpvMediaSource source,
    PlaybackQualityOption quality,
  ) {
    if (quality.isOriginalProxy && _qualityTierRank(quality.resolution) == 0) {
      final currentTier = _qualityTierLabel(source.resolution);
      if (_qualityTierRank(currentTier) > 0) return currentTier;
      if (source.videoHeight > 0) return '${source.videoHeight}P';
    }
    return _qualityTierLabel(quality.resolution);
  }

  static int _qualityTierRank(String resolution) {
    final value = resolution.trim().toLowerCase();
    final dimensions = RegExp(
      r'(\d{2,5})\s*[x×]\s*(\d{2,5})',
    ).firstMatch(value);
    if (dimensions != null) {
      final width = int.tryParse(dimensions.group(1) ?? '') ?? 0;
      final height = int.tryParse(dimensions.group(2) ?? '') ?? 0;
      if (width > 0 && height > 0) return width < height ? width : height;
    }
    final number = RegExp(r'\d{3,4}').firstMatch(value);
    if (number != null) return int.tryParse(number.group(0) ?? '') ?? 0;
    if (value.contains('8k')) return 4320;
    if (value.contains('4k')) return 2160;
    if (value.contains('2k')) return 1440;
    return 0;
  }

  static int volumeMax(Map<String, String> settings) {
    if (settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on') return 100;
    return int.tryParse(
          settings[MpvSettingsCatalog.volumeGainKey] ?? '',
        )?.clamp(100, 200) ??
        100;
  }

  static String audioChannels(Map<String, String> settings) {
    return switch (settings[MpvSettingsCatalog.channelMixKey]) {
      'stereo' => 'stereo',
      'surround' => '5.1',
      _ => 'auto-safe',
    };
  }

  static String passthroughCodecs(Map<String, String> settings) {
    final value = settings[MpvSettingsCatalog.audioPassthroughKey] ?? 'off';
    return value == 'off' ? '' : 'ac3,eac3,dts,dts-hd,truehd';
  }

  static String audioFilters(Map<String, String> settings) {
    if (settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on' ||
        passthroughCodecs(settings).isNotEmpty) {
      return '';
    }
    final filters = <String>[];
    switch (settings[MpvSettingsCatalog.audioEqKey]) {
      case 'soft':
        filters
          ..add('lavfi=[equalizer=f=120:t=q:w=1.0:g=1.2]')
          ..add('lavfi=[equalizer=f=2400:t=q:w=1.0:g=1.0]');
      case 'clarity':
        filters
          ..add('lavfi=[equalizer=f=160:t=q:w=1.0:g=-1.0]')
          ..add('lavfi=[equalizer=f=2800:t=q:w=1.1:g=2.4]')
          ..add('lavfi=[equalizer=f=6800:t=q:w=1.1:g=1.4]');
      case 'cinema':
        filters
          ..add('lavfi=[equalizer=f=90:t=q:w=1.0:g=1.4]')
          ..add('lavfi=[equalizer=f=2200:t=q:w=1.0:g=1.2]')
          ..add('lavfi=[equalizer=f=5600:t=q:w=1.0:g=0.8]');
      case MpvSettingsCatalog.audioEqCustomValue:
        for (final band in MpvSettingsCatalog.audioEqBands) {
          final gain = MpvSettingsCatalog.audioEqBandValue(band.key, settings);
          if (gain.abs() < 0.05) continue;
          filters.add(
            'lavfi=[equalizer=f=${band.frequency}:t=q:w=1.0:g=${gain.toStringAsFixed(1)}]',
          );
        }
    }
    switch (settings[MpvSettingsCatalog.audioBassBoostKey]) {
      case 'low':
        filters.add('lavfi=[bass=g=3:f=110:w=0.6]');
      case 'medium':
        filters.add('lavfi=[bass=g=5:f=105:w=0.7]');
    }
    switch (settings[MpvSettingsCatalog.audioVoiceEnhanceKey]) {
      case 'low':
        filters
          ..add('lavfi=[highpass=f=120]')
          ..add('lavfi=[equalizer=f=2600:t=q:w=1.1:g=1.8]')
          ..add('lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.0]');
      case 'medium':
        filters
          ..add('lavfi=[highpass=f=140]')
          ..add('lavfi=[equalizer=f=2600:t=q:w=1.0:g=2.6]')
          ..add('lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.5]');
    }
    switch (settings[MpvSettingsCatalog.dynamicRangeKey]) {
      case 'low':
        filters.add(
          'lavfi=[acompressor=threshold=-20dB:ratio=2.0:attack=20:release=250]',
        );
      case 'medium':
        filters.add(
          'lavfi=[acompressor=threshold=-24dB:ratio=3.0:attack=15:release=220]',
        );
    }
    switch (settings[MpvSettingsCatalog.audioLimiterKey]) {
      case 'light':
        filters.add('lavfi=[alimiter=limit=0.95:attack=5:release=45]');
      case 'strong':
        filters.add('lavfi=[alimiter=limit=0.90:attack=3:release=60]');
    }
    return filters.join(',');
  }
}
