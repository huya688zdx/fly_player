import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MpvSettingOption {
  final String value;
  final String label;
  final String description;

  const MpvSettingOption({
    required this.value,
    required this.label,
    required this.description,
  });
}

class MpvSettingDefinition {
  final String key;
  final String title;
  final String shortTitle;
  final String description;
  final String helperLabel;
  final List<MpvSettingOption> options;

  const MpvSettingDefinition({
    required this.key,
    required this.title,
    required this.shortTitle,
    required this.description,
    required this.helperLabel,
    required this.options,
  });
}

class MpvSettingCategoryEntry {
  final String key;
  final String title;
  final String subtitle;

  const MpvSettingCategoryEntry({
    required this.key,
    required this.title,
    required this.subtitle,
  });
}

class MpvSettingCategory {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final List<MpvSettingCategoryEntry> entries;

  const MpvSettingCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.entries,
  });
}

class MpvSettingPreset {
  final String id;
  final String label;
  final String description;
  final Map<String, String> settings;
  final Map<String, double> videoAdjustments;

  const MpvSettingPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.settings,
    this.videoAdjustments = const <String, double>{},
  });
}

class MpvScenePreset {
  final String id;
  final String label;
  final String description;
  final String picturePresetId;
  final String audioPresetId;

  const MpvScenePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.picturePresetId,
    required this.audioPresetId,
  });
}

class MpvScenePresetRecommendation {
  final MpvScenePreset preset;
  final String title;
  final String reason;

  const MpvScenePresetRecommendation({
    required this.preset,
    required this.title,
    required this.reason,
  });
}

enum SavedMpvPresetKind { picture, audio }

extension SavedMpvPresetKindX on SavedMpvPresetKind {
  String get storageValue => switch (this) {
    SavedMpvPresetKind.picture => 'picture',
    SavedMpvPresetKind.audio => 'audio',
  };

  String get label => switch (this) {
    SavedMpvPresetKind.picture => 'picture',
    SavedMpvPresetKind.audio => 'audio',
  };

  static SavedMpvPresetKind fromStorageValue(String? value) {
    return SavedMpvPresetKind.values.firstWhere(
      (kind) => kind.storageValue == value,
      orElse: () => SavedMpvPresetKind.picture,
    );
  }
}

class SavedMpvPreset {
  final String id;
  final SavedMpvPresetKind kind;
  final String name;
  final String description;
  final DateTime createdAt;
  final Map<String, String> settingsSnapshot;
  final Map<String, double> videoAdjustmentsSnapshot;

  const SavedMpvPreset({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.settingsSnapshot,
    this.videoAdjustmentsSnapshot = const <String, double>{},
  });

  SavedMpvPreset copyWith({
    String? id,
    SavedMpvPresetKind? kind,
    String? name,
    String? description,
    DateTime? createdAt,
    Map<String, String>? settingsSnapshot,
    Map<String, double>? videoAdjustmentsSnapshot,
  }) {
    return SavedMpvPreset(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      settingsSnapshot: settingsSnapshot ?? this.settingsSnapshot,
      videoAdjustmentsSnapshot:
          videoAdjustmentsSnapshot ?? this.videoAdjustmentsSnapshot,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.storageValue,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'settingsSnapshot': settingsSnapshot,
      'videoAdjustmentsSnapshot': videoAdjustmentsSnapshot.map(
        (key, value) => MapEntry(key, value),
      ),
    };
  }

  static SavedMpvPreset? fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final name = (map['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) return null;
    final rawSettings = map['settingsSnapshot'];
    if (rawSettings is! Map) return null;
    final rawVideoAdjustments = map['videoAdjustmentsSnapshot'];
    final videoAdjustments = <String, double>{};
    if (rawVideoAdjustments is Map) {
      for (final entry in rawVideoAdjustments.entries) {
        final parsed = double.tryParse('${entry.value}');
        if (parsed == null) continue;
        videoAdjustments['${entry.key}'.trim()] = parsed;
      }
    }
    final settings = <String, String>{};
    for (final entry in rawSettings.entries) {
      final key = '${entry.key}'.trim();
      final value = '${entry.value}'.trim();
      if (key.isEmpty || value.isEmpty) continue;
      settings[key] = value;
    }
    return SavedMpvPreset(
      id: id,
      kind: SavedMpvPresetKindX.fromStorageValue(
        (map['kind'] ?? '').toString().trim(),
      ),
      name: name,
      description: (map['description'] ?? '').toString().trim(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      settingsSnapshot: settings,
      videoAdjustmentsSnapshot: videoAdjustments,
    );
  }
}

class MpvSettingsBundle {
  final Map<String, String> settings;
  final Map<String, double> videoAdjustments;

  const MpvSettingsBundle({
    required this.settings,
    required this.videoAdjustments,
  });
}

class MpvPerformanceImpactWarning {
  final String title;
  final String message;

  const MpvPerformanceImpactWarning({
    required this.title,
    required this.message,
  });
}

class MpvAudioEqBand {
  final String key;
  final String label;
  final int frequency;

  const MpvAudioEqBand({
    required this.key,
    required this.label,
    required this.frequency,
  });
}

class MpvSettingsCatalog {
  static const String prefPrefix = 'player_mpv_setting_';
  static const String videoAdjustPrefPrefix = 'player_mpv_video_adjust_';
  static const String savedPicturePresetsKey =
      'player_mpv_saved_picture_presets_v1';
  static const String savedAudioPresetsKey =
      'player_mpv_saved_audio_presets_v1';

  static const String debandKey = 'deband';
  static const String sharpenKey = 'sharpen';
  static const String denoiseKey = 'denoise';
  static const String deinterlaceKey = 'deinterlace';
  static const String scaleProfileKey = 'scale_profile';
  static const String hdrModeKey = 'hdr_mode';
  static const String frameInterpolationKey = 'frame_interpolation';
  static const String videoSyncKey = 'video_sync';
  static const String cacheProfileKey = 'cache_profile';
  static const String cacheSizeMbKey = 'cache_size_mb';
  static const String volumeGainKey = 'volume_gain';
  static const String audioHighFidelityKey = 'audio_high_fidelity';
  static const String dynamicRangeKey = 'dynamic_range';
  static const String audioEqKey = 'audio_eq';
  static const String audioLimiterKey = 'audio_limiter';
  static const String audioBassBoostKey = 'audio_bass_boost';
  static const String audioVoiceEnhanceKey = 'audio_voice_enhance';
  static const String audioEqBand60Key = 'audio_eq_band_60';
  static const String audioEqBand170Key = 'audio_eq_band_170';
  static const String audioEqBand310Key = 'audio_eq_band_310';
  static const String audioEqBand1000Key = 'audio_eq_band_1000';
  static const String audioEqBand6000Key = 'audio_eq_band_6000';
  static const String channelMixKey = 'channel_mix';
  static const String compatibilityKey = 'compatibility_profile';
  static const String brightnessKey = 'brightness';
  static const String contrastKey = 'contrast';
  static const String saturationKey = 'saturation';
  static const String gammaKey = 'gamma';
  static const String hueKey = 'hue';

  static const String videoFiltersCategoryId = 'video_filters';
  static const String pictureRenderingCategoryId = 'picture_rendering';
  static const String playbackSyncCategoryId = 'playback_sync';
  static const String audioProcessingCategoryId = 'audio_processing';
  static const String compatibilityCategoryId = 'compatibility';

  static const int cacheSizeSliderMinMb = 64;
  static const int cacheSizeSliderMaxMb = 1984;
  static const int cacheSizeSliderStepMb = 64;
  static const int cacheSizeExtremeMinimumMb = 512;
  static const int cachePercentSliderMin = 0;
  static const int cachePercentSliderMax = 100;
  static const String audioEqCustomValue = 'custom';
  static const double audioEqBandMinDb = -12;
  static const double audioEqBandMaxDb = 12;
  static const double audioEqBandStepDb = 0.5;

  static const List<MpvAudioEqBand> audioEqBands = <MpvAudioEqBand>[
    MpvAudioEqBand(key: audioEqBand60Key, label: '60', frequency: 60),
    MpvAudioEqBand(key: audioEqBand170Key, label: '170', frequency: 170),
    MpvAudioEqBand(key: audioEqBand310Key, label: '310', frequency: 310),
    MpvAudioEqBand(key: audioEqBand1000Key, label: '1K', frequency: 1000),
    MpvAudioEqBand(key: audioEqBand6000Key, label: '6K', frequency: 6000),
  ];

  static const Map<String, String> defaults = <String, String>{
    debandKey: 'off',
    sharpenKey: 'off',
    denoiseKey: 'off',
    deinterlaceKey: 'auto',
    scaleProfileKey: 'balanced',
    hdrModeKey: 'auto',
    frameInterpolationKey: 'off',
    videoSyncKey: 'auto',
    cacheProfileKey: 'default',
    cacheSizeMbKey: 'auto',
    volumeGainKey: '100',
    audioHighFidelityKey: 'off',
    dynamicRangeKey: 'off',
    audioEqKey: 'off',
    audioLimiterKey: 'off',
    audioBassBoostKey: 'off',
    audioVoiceEnhanceKey: 'off',
    audioEqBand60Key: '0',
    audioEqBand170Key: '0',
    audioEqBand310Key: '0',
    audioEqBand1000Key: '0',
    audioEqBand6000Key: '0',
    channelMixKey: 'auto',
    compatibilityKey: 'default',
  };

  static const Map<String, double> videoAdjustmentDefaults = <String, double>{
    brightnessKey: 0,
    contrastKey: 0,
    saturationKey: 0,
    gammaKey: 0,
    hueKey: 0,
  };

  static const List<String> picturePresetKeys = <String>[
    debandKey,
    sharpenKey,
    denoiseKey,
    deinterlaceKey,
    scaleProfileKey,
    hdrModeKey,
    frameInterpolationKey,
    videoSyncKey,
    cacheProfileKey,
    cacheSizeMbKey,
    compatibilityKey,
  ];

  static const List<String> audioPresetKeys = <String>[
    volumeGainKey,
    audioHighFidelityKey,
    dynamicRangeKey,
    audioEqKey,
    audioLimiterKey,
    audioBassBoostKey,
    audioVoiceEnhanceKey,
    audioEqBand60Key,
    audioEqBand170Key,
    audioEqBand310Key,
    audioEqBand1000Key,
    audioEqBand6000Key,
    channelMixKey,
  ];

  static const List<MpvSettingPreset> builtInPicturePresets =
      <MpvSettingPreset>[
        MpvSettingPreset(
          id: 'off',
          label: 'Default',
          description: 'Disable extra picture enhancement.',
          settings: <String, String>{},
        ),
        MpvSettingPreset(
          id: 'anime',
          label: 'Anime Clear',
          description: 'Light contrast and saturation tuning for line art.',
          settings: <String, String>{},
          videoAdjustments: <String, double>{contrastKey: 4, saturationKey: 6},
        ),
        MpvSettingPreset(
          id: 'cinema',
          label: 'Cinema Soft',
          description: 'Softer brightness and saturation tuning for films.',
          settings: <String, String>{},
          videoAdjustments: <String, double>{
            contrastKey: -4,
            gammaKey: 6,
            saturationKey: -3,
          },
        ),
        MpvSettingPreset(
          id: 'smooth',
          label: 'Smooth First',
          description: 'Lightweight settings for stability and responsiveness.',
          settings: <String, String>{
            scaleProfileKey: 'fast',
            cacheProfileKey: 'stable',
            compatibilityKey: 'conservative',
          },
        ),
      ];

  static const List<MpvSettingPreset> builtInAudioPresets = <MpvSettingPreset>[
    MpvSettingPreset(
      id: 'off',
      label: 'Default',
      description: 'Disable extra audio enhancement.',
      settings: <String, String>{},
    ),
    MpvSettingPreset(
      id: 'hi_fi',
      label: 'Hi-Fi',
      description: 'Bypass EQ and enhancement for clean output.',
      settings: <String, String>{
        audioHighFidelityKey: 'on',
        volumeGainKey: '100',
      },
    ),
    MpvSettingPreset(
      id: 'balanced',
      label: 'Balanced Boost',
      description: 'Light voice and bass enhancement for everyday playback.',
      settings: <String, String>{
        volumeGainKey: '125',
        audioEqKey: 'soft',
        audioLimiterKey: 'light',
        audioBassBoostKey: 'low',
        audioVoiceEnhanceKey: 'low',
        channelMixKey: 'stereo',
      },
    ),
    MpvSettingPreset(
      id: 'dialogue',
      label: 'Dialogue Clear',
      description: 'Bring dialogue and mid-high details forward.',
      settings: <String, String>{
        volumeGainKey: '140',
        dynamicRangeKey: 'low',
        audioEqKey: 'clarity',
        audioLimiterKey: 'light',
        audioVoiceEnhanceKey: 'medium',
        channelMixKey: 'stereo',
      },
    ),
    MpvSettingPreset(
      id: 'speaker_clear',
      label: 'Speaker Clear',
      description: 'Improve dialogue clarity for phone and tablet speakers.',
      settings: <String, String>{
        volumeGainKey: '160',
        dynamicRangeKey: 'medium',
        audioEqKey: 'clarity',
        audioLimiterKey: 'strong',
        audioVoiceEnhanceKey: 'medium',
        channelMixKey: 'stereo',
      },
    ),
    MpvSettingPreset(
      id: 'cinema_bass',
      label: 'Cinema Bass',
      description: 'Enhance low-frequency weight for films and speakers.',
      settings: <String, String>{
        volumeGainKey: '135',
        audioEqKey: 'cinema',
        audioLimiterKey: 'light',
        audioBassBoostKey: 'medium',
        channelMixKey: 'auto',
      },
    ),
    MpvSettingPreset(
      id: 'headphone_immersive',
      label: 'Headphone Immersive',
      description: 'Keep dynamics with extra ambience and low-end weight.',
      settings: <String, String>{
        volumeGainKey: '120',
        audioEqKey: 'cinema',
        audioLimiterKey: 'light',
        audioBassBoostKey: 'low',
        channelMixKey: 'stereo',
      },
    ),
    MpvSettingPreset(
      id: 'night',
      label: 'Night Balance',
      description: 'Reduce peaks and bring dialogue forward for late playback.',
      settings: <String, String>{
        volumeGainKey: '140',
        dynamicRangeKey: 'medium',
        audioEqKey: 'soft',
        audioLimiterKey: 'strong',
        audioVoiceEnhanceKey: 'low',
        channelMixKey: 'stereo',
      },
    ),
  ];

  static const List<MpvScenePreset> builtInScenePresets = <MpvScenePreset>[
    MpvScenePreset(
      id: 'stable_clear',
      label: 'Stable Clear',
      description: 'Prefer decode stability and smooth system behavior.',
      picturePresetId: 'smooth',
      audioPresetId: 'balanced',
    ),
    MpvScenePreset(
      id: 'balanced_movie',
      label: 'Balanced Movie',
      description: 'Daily movie preset with light picture and audio tuning.',
      picturePresetId: 'cinema',
      audioPresetId: 'balanced',
    ),
    MpvScenePreset(
      id: 'anime_dialogue',
      label: 'Anime Dialogue',
      description: 'Keep anime line detail and bring dialogue forward.',
      picturePresetId: 'anime',
      audioPresetId: 'dialogue',
    ),
    MpvScenePreset(
      id: 'speaker_clear',
      label: 'Speaker Clear',
      description: 'Prioritize phone and tablet speaker clarity.',
      picturePresetId: 'smooth',
      audioPresetId: 'speaker_clear',
    ),
    MpvScenePreset(
      id: 'night_binge',
      label: 'Night Binge',
      description: 'Stable and softer late-night playback.',
      picturePresetId: 'smooth',
      audioPresetId: 'night',
    ),
    MpvScenePreset(
      id: 'headphone_immersive',
      label: 'Headphone Immersive',
      description: 'Soft picture with immersive headphone audio.',
      picturePresetId: 'cinema',
      audioPresetId: 'headphone_immersive',
    ),
  ];
  static const List<MpvSettingDefinition> definitions = <MpvSettingDefinition>[
    MpvSettingDefinition(
      key: debandKey,
      title: 'Deband',
      shortTitle: 'Deband',
      description: 'Smooth gradients and reduce banding.',
      helperLabel: 'Deband strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'No extra debanding.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Light debanding with more detail preserved.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'Stronger debanding for visible banding.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: sharpenKey,
      title: 'Sharpen',
      shortTitle: 'Sharpen',
      description: 'Increase edge clarity.',
      helperLabel: 'Sharpen strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep original detail.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Slightly sharper edges.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'More visible sharpening.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: denoiseKey,
      title: 'Denoise',
      shortTitle: 'Denoise',
      description: 'Reduce noise and grain.',
      helperLabel: 'Denoise strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'No extra denoise.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Light noise reduction.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'Stronger cleanup.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: deinterlaceKey,
      title: 'Deinterlace',
      shortTitle: 'Deinterlace',
      description: 'Handle interlaced sources.',
      helperLabel: 'Deinterlace mode',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Enable only when needed.',
        ),
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Always disable deinterlace.',
        ),
        MpvSettingOption(
          value: 'force',
          label: 'Force',
          description: 'Always run deinterlace processing.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: scaleProfileKey,
      title: 'Scale Profile',
      shortTitle: 'Scale',
      description: 'Choose scaling quality and performance balance.',
      helperLabel: 'Scaling strategy',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'fast',
          label: 'Fast',
          description: 'Prefer performance.',
        ),
        MpvSettingOption(
          value: 'balanced',
          label: 'Balanced',
          description: 'Balance quality and power usage.',
        ),
        MpvSettingOption(
          value: 'quality',
          label: 'Quality',
          description: 'Prefer higher quality scaling.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: hdrModeKey,
      title: 'HDR Mode',
      shortTitle: 'HDR',
      description: 'Control HDR to SDR mapping.',
      helperLabel: 'HDR mode',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Choose automatically.',
        ),
        MpvSettingOption(
          value: 'sdr_map',
          label: 'SDR Map',
          description: 'Prefer compatibility.',
        ),
        MpvSettingOption(
          value: 'conservative',
          label: 'Conservative',
          description: 'Tone-map more safely.',
        ),
        MpvSettingOption(
          value: 'enhanced',
          label: 'Enhanced',
          description: 'Emphasize contrast and highlights.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: frameInterpolationKey,
      title: 'Frame Interpolation',
      shortTitle: 'Interpolation',
      description: 'Improve motion smoothness at higher cost.',
      helperLabel: 'Interpolation mode',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep original frame rate.',
        ),
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Enable by scene.',
        ),
        MpvSettingOption(
          value: 'on',
          label: 'On',
          description: 'Maximize smoothness.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: videoSyncKey,
      title: 'Video Sync',
      shortTitle: 'Sync',
      description: 'Choose audio, display, and refresh sync behavior.',
      helperLabel: 'Sync preference',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Balance automatically.',
        ),
        MpvSettingOption(
          value: 'audio',
          label: 'Audio',
          description: 'Prefer continuous audio.',
        ),
        MpvSettingOption(
          value: 'display',
          label: 'Display',
          description: 'Prefer display refresh matching.',
        ),
        MpvSettingOption(
          value: 'smooth',
          label: 'Smooth',
          description: 'More actively fit display refresh.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: cacheProfileKey,
      title: 'Cache Profile',
      shortTitle: 'Cache',
      description: 'Choose buffering behavior.',
      helperLabel: 'Buffering profile',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'default',
          label: 'Default',
          description: 'Choose a suitable cache automatically.',
        ),
        MpvSettingOption(
          value: 'low_latency',
          label: 'Low Latency',
          description: 'Prefer quick seeking and switching.',
        ),
        MpvSettingOption(
          value: 'stable',
          label: 'Stable',
          description: 'Add more read-ahead for network jitter.',
        ),
        MpvSettingOption(
          value: 'network',
          label: 'Network',
          description: 'Use heavier buffering for remote sources.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: cacheSizeMbKey,
      title: 'Cache Size',
      shortTitle: 'Cache Size',
      description: 'Override maximum read-ahead cache size.',
      helperLabel: 'Cache limit',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Follow the selected cache profile.',
        ),
        MpvSettingOption(
          value: '64',
          label: '64 MB',
          description: 'Lower memory use.',
        ),
        MpvSettingOption(
          value: '128',
          label: '128 MB',
          description: 'Better for remote direct links.',
        ),
        MpvSettingOption(
          value: '256',
          label: '256 MB',
          description: 'Reduce network jitter.',
        ),
        MpvSettingOption(
          value: '512',
          label: '512 MB',
          description: 'For very high bitrate or unstable network.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: volumeGainKey,
      title: 'Volume Gain',
      shortTitle: 'Volume',
      description: 'Increase maximum output volume.',
      helperLabel: 'Volume cap',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: '100',
          label: '100%',
          description: 'Standard maximum volume.',
        ),
        MpvSettingOption(
          value: '150',
          label: '150%',
          description: 'For quieter dialogue.',
        ),
        MpvSettingOption(
          value: '200',
          label: '200%',
          description: 'Maximum boost, may distort.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioHighFidelityKey,
      title: 'High Fidelity',
      shortTitle: 'Hi-Fi',
      description: 'Bypass most audio post-processing.',
      helperLabel: 'Output mode',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep current audio processing.',
        ),
        MpvSettingOption(
          value: 'on',
          label: 'On',
          description: 'Prefer cleaner original output.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: dynamicRangeKey,
      title: 'Dynamic Range Compression',
      shortTitle: 'Dynamic Range',
      description: 'Compress peaks and bring dialogue forward.',
      helperLabel: 'Compression strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep original dynamic range.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Light dialogue lift.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'Friendlier for night playback.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioEqKey,
      title: 'EQ',
      shortTitle: 'EQ',
      description: 'Choose an equalizer preset.',
      helperLabel: 'EQ preset',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep original tone.',
        ),
        MpvSettingOption(
          value: 'soft',
          label: 'Soft',
          description: 'Light low-end and voice tuning.',
        ),
        MpvSettingOption(
          value: 'clarity',
          label: 'Clarity',
          description: 'Emphasize voice and high-frequency detail.',
        ),
        MpvSettingOption(
          value: 'cinema',
          label: 'Cinema',
          description: 'Balance low-end ambience and dialogue clarity.',
        ),
        MpvSettingOption(
          value: audioEqCustomValue,
          label: 'Custom',
          description: 'Open multi-band custom EQ.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioLimiterKey,
      title: 'Limiter',
      shortTitle: 'Limiter',
      description: 'Control sudden peaks and prevent clipping.',
      helperLabel: 'Limiter strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'No extra limiting.',
        ),
        MpvSettingOption(
          value: 'light',
          label: 'Light',
          description: 'Light peak control.',
        ),
        MpvSettingOption(
          value: 'strong',
          label: 'Strong',
          description: 'More active clipping prevention.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioBassBoostKey,
      title: 'Bass Boost',
      shortTitle: 'Bass',
      description: 'Increase low-frequency presence.',
      helperLabel: 'Bass strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep current bass.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Light bass boost.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'More obvious bass boost.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioVoiceEnhanceKey,
      title: 'Voice Enhance',
      shortTitle: 'Voice',
      description: 'Improve dialogue clarity.',
      helperLabel: 'Voice strength',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: 'Off',
          description: 'Keep original voice tone.',
        ),
        MpvSettingOption(
          value: 'low',
          label: 'Low',
          description: 'Light dialogue lift.',
        ),
        MpvSettingOption(
          value: 'medium',
          label: 'Medium',
          description: 'More focused dialogue.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: channelMixKey,
      title: 'Channel Mix',
      shortTitle: 'Channel',
      description: 'Control multi-channel output mixing.',
      helperLabel: 'Output mode',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: 'Auto',
          description: 'Choose by device and source.',
        ),
        MpvSettingOption(
          value: 'stereo',
          label: 'Stereo',
          description: 'Prefer stereo output.',
        ),
        MpvSettingOption(
          value: 'surround',
          label: 'Surround',
          description: 'Preserve more surround information.',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: compatibilityKey,
      title: 'Compatibility',
      shortTitle: 'Compatibility',
      description: 'Fallback behavior for device-specific playback issues.',
      helperLabel: 'Compatibility profile',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'default',
          label: 'Default',
          description: 'Use the normal profile.',
        ),
        MpvSettingOption(
          value: 'conservative',
          label: 'Conservative',
          description: 'Reduce aggressive rendering and filters.',
        ),
        MpvSettingOption(
          value: 'software_fallback',
          label: 'Software',
          description: 'Prefer stable software fallback when needed.',
        ),
      ],
    ),
  ];
  static MpvPerformanceImpactWarning? performanceWarningForSelection(
    String key,
    String value,
  ) {
    if (key == debandKey && value == 'medium') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Medium debanding adds extra video processing cost and may cause dropped frames, heat, or system stutter on some devices.',
      );
    }
    if (key == sharpenKey && value != 'off') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Sharpening increases filter workload and may cause playback drops or UI stutter on heavy sources or weaker devices.',
      );
    }
    if (key == denoiseKey && value != 'off') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Denoise is a heavy video filter and can easily cause dropped frames, heat, or system stutter on mobile devices.',
      );
    }
    if (key == deinterlaceKey && value == 'force') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Forced deinterlacing sends every source through extra processing. Progressive sources usually do not need it and playback may slow down.',
      );
    }
    if (key == scaleProfileKey && value == 'quality') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'High quality scaling increases GPU and rendering load, especially on high resolution or high bitrate sources.',
      );
    }
    if (key == hdrModeKey && (value == 'conservative' || value == 'enhanced')) {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'This HDR mode increases tone mapping load and may stutter on HDR, 10-bit, or high resolution sources.',
      );
    }
    if (key == frameInterpolationKey && (value == 'auto' || value == 'on')) {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Frame interpolation is one of the heaviest options and may cause video drops, UI stutter, and system slowdown.',
      );
    }
    if (key == videoSyncKey && value == 'smooth') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Smooth sync follows the display refresh rate more aggressively and can increase composition and sync load on some devices.',
      );
    }
    if (key == cacheProfileKey && value == 'network') {
      return const MpvPerformanceImpactWarning(
        title: 'Performance warning',
        message:
            'Network-heavy caching uses more memory and makes seek refill heavier. Use it mainly for high bitrate remote sources.',
      );
    }
    if (key == cacheSizeMbKey) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed >= cacheSizeExtremeMinimumMb) {
        return const MpvPerformanceImpactWarning(
          title: 'Performance warning',
          message:
              'Large buffers use more memory and make startup or seek refill heavier. Low-memory devices may feel less smooth.',
        );
      }
    }
    return null;
  }

  static const List<MpvSettingCategory> categories = <MpvSettingCategory>[
    MpvSettingCategory(
      id: videoFiltersCategoryId,
      title: 'Video filters',
      subtitle: 'Deband, sharpen, denoise, deinterlace, scaling',
      description: 'Controls image cleanup, edge clarity, and scaling feel.',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: debandKey,
          title: 'Deband',
          subtitle: 'Smooth gradients and dark color bands',
        ),
        MpvSettingCategoryEntry(
          key: sharpenKey,
          title: 'Sharpen',
          subtitle: 'Improve edge clarity',
        ),
        MpvSettingCategoryEntry(
          key: denoiseKey,
          title: 'Denoise',
          subtitle: 'Reduce noise and grain',
        ),
        MpvSettingCategoryEntry(
          key: deinterlaceKey,
          title: 'Deinterlace',
          subtitle: 'Handle interlaced sources',
        ),
        MpvSettingCategoryEntry(
          key: scaleProfileKey,
          title: 'Scaling',
          subtitle: 'Control upscale and downscale behavior',
        ),
      ],
    ),
    MpvSettingCategory(
      id: pictureRenderingCategoryId,
      title: 'Picture rendering',
      subtitle: 'HDR processing, frame interpolation',
      description: 'Picture-style and output-feel enhancements.',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: hdrModeKey,
          title: 'HDR processing',
          subtitle: 'Adjust HDR mapping and tone',
        ),
        MpvSettingCategoryEntry(
          key: frameInterpolationKey,
          title: 'Frame interpolation',
          subtitle: 'Improve motion smoothness with higher cost',
        ),
      ],
    ),
    MpvSettingCategory(
      id: playbackSyncCategoryId,
      title: 'Playback sync',
      subtitle: 'Sync mode, cache profile, buffer size',
      description:
          'Affects seeking response, network tolerance, and smoothness.',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: videoSyncKey,
          title: 'Sync mode',
          subtitle: 'Adjust audio/video and refresh sync preference',
        ),
        MpvSettingCategoryEntry(
          key: cacheProfileKey,
          title: 'Cache profile',
          subtitle: 'Adjust pre-read strength and buffer style',
        ),
        MpvSettingCategoryEntry(
          key: cacheSizeMbKey,
          title: 'Buffer size',
          subtitle: 'Manually override automatic cache limit',
        ),
      ],
    ),
    MpvSettingCategory(
      id: audioProcessingCategoryId,
      title: 'Audio processing',
      subtitle: 'Volume, EQ, limiter, bass, voice enhancement',
      description:
          'Affects dialogue clarity, tone balance, and channel output.',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: volumeGainKey,
          title: 'Volume gain',
          subtitle: 'Raise the output ceiling for quiet sources',
        ),
        MpvSettingCategoryEntry(
          key: audioHighFidelityKey,
          title: 'High fidelity',
          subtitle: 'Keep clean decoded output and bypass most post-processing',
        ),
        MpvSettingCategoryEntry(
          key: dynamicRangeKey,
          title: 'Dynamic range',
          subtitle: 'Bring dialogue forward and stabilize night playback',
        ),
        MpvSettingCategoryEntry(
          key: audioEqKey,
          title: 'EQ',
          subtitle: 'Adjust low, mid, and high frequency balance',
        ),
        MpvSettingCategoryEntry(
          key: audioLimiterKey,
          title: 'Limiter',
          subtitle: 'Prevent sudden peaks from clipping',
        ),
        MpvSettingCategoryEntry(
          key: audioBassBoostKey,
          title: 'Bass boost',
          subtitle: 'Add cinematic weight and low-end presence',
        ),
        MpvSettingCategoryEntry(
          key: audioVoiceEnhanceKey,
          title: 'Voice enhance',
          subtitle: 'Make speech and dialogue clearer',
        ),
        MpvSettingCategoryEntry(
          key: channelMixKey,
          title: 'Channel mix',
          subtitle: 'Control multichannel output preference',
        ),
      ],
    ),
    MpvSettingCategory(
      id: compatibilityCategoryId,
      title: 'Compatibility',
      subtitle: 'Fallbacks and diagnostics',
      description:
          'Use these fallbacks for black screen, artifacts, or device issues.',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: compatibilityKey,
          title: 'Compatibility mode',
          subtitle: 'Switch when black screen, artifacts, or errors appear',
        ),
      ],
    ),
  ];

  static Map<String, String> normalizeSettings(Map<String, String> raw) {
    final resolved = Map<String, String>.from(defaults);
    for (final entry in raw.entries) {
      if (!defaults.containsKey(entry.key)) continue;
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      resolved[entry.key] = value;
    }
    return resolved;
  }

  static MpvSettingDefinition? definitionByKey(String key) {
    for (final definition in definitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }

  static MpvSettingCategory? categoryById(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  static Map<String, String> snapshotForKind(
    SavedMpvPresetKind kind,
    Map<String, String> settings,
  ) {
    final normalized = normalizeSettings(settings);
    final keys = kind == SavedMpvPresetKind.picture
        ? picturePresetKeys
        : audioPresetKeys;
    final snapshot = <String, String>{};
    for (final key in keys) {
      snapshot[key] = normalized[key] ?? defaults[key] ?? '';
    }
    return snapshot;
  }

  static Map<String, double> normalizeVideoAdjustments(
    Map<String, double> raw,
  ) {
    final resolved = <String, double>{};
    for (final entry in videoAdjustmentDefaults.entries) {
      final value = raw[entry.key] ?? entry.value;
      resolved[entry.key] = _normalizeVideoAdjustmentValue(value);
    }
    return resolved;
  }

  static Map<String, double> pictureVideoAdjustmentSnapshot(
    Map<String, double> values,
  ) {
    return normalizeVideoAdjustments(values);
  }

  static MpvSettingPreset? builtInPicturePresetById(String id) {
    for (final preset in builtInPicturePresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static MpvSettingPreset? builtInAudioPresetById(String id) {
    for (final preset in builtInAudioPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static MpvScenePreset? builtInScenePresetById(String id) {
    for (final preset in builtInScenePresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static MpvScenePresetRecommendation? recommendScenePreset({
    required int videoWidth,
    required int videoHeight,
    required String resolution,
    required int bitrate,
    required String videoCodecName,
    required String videoProfile,
    required String colorSpace,
    required String colorTransfer,
    required String colorPrimaries,
    required int bitDepth,
    required bool isRemoteSource,
    required int audioChannels,
    required int audioBitrate,
    required int audioSampleRate,
  }) {
    final codec = videoCodecName.trim().toLowerCase();
    final profile = videoProfile.trim().toLowerCase();
    final transfer = colorTransfer.trim().toLowerCase();
    final space = colorSpace.trim().toLowerCase();
    final primaries = colorPrimaries.trim().toLowerCase();
    final resolutionText = resolution.trim().toLowerCase();
    final hdrTransfer =
        transfer.contains('pq') ||
        transfer.contains('2084') ||
        transfer.contains('hlg') ||
        transfer.contains('arib-std-b67');
    final hdrGamut =
        space.contains('2020') ||
        space.contains('2100') ||
        primaries.contains('2020') ||
        primaries.contains('2100');
    final isDolbyVision =
        codec.contains('dovi') ||
        codec.contains('dvhe') ||
        codec.contains('dvh1') ||
        profile.contains('dolby vision') ||
        profile.contains('dolbyvision');
    final isHdr =
        isDolbyVision || ((hdrTransfer || hdrGamut) && bitDepth >= 10);
    final isHevcLike =
        codec.contains('hevc') ||
        codec.contains('h265') ||
        codec.contains('hev1') ||
        codec.contains('hvc1') ||
        codec.contains('x265');
    final isUltraHighResolution =
        videoWidth >= 3840 ||
        videoHeight >= 2160 ||
        resolutionText.contains('2160');
    final isHeavySource =
        isHdr ||
        bitDepth >= 10 ||
        isUltraHighResolution ||
        videoWidth > 1920 ||
        videoHeight > 1080 ||
        bitrate >= 12000000 ||
        (isHevcLike && bitrate >= 8000000) ||
        isRemoteSource;
    if (isHeavySource) {
      final preset = builtInScenePresetById('stable_clear');
      if (preset == null) return null;
      final reasons = <String>[];
      if (isUltraHighResolution) reasons.add('high resolution');
      if (isHdr) reasons.add('HDR/high dynamic range');
      if (bitDepth >= 10) reasons.add('10-bit source');
      if (isHevcLike && bitrate >= 8000000) reasons.add('high bitrate HEVC');
      if (isRemoteSource) reasons.add('remote source');
      return MpvScenePresetRecommendation(
        preset: preset,
        title: 'Stable profile recommended',
        reason: reasons.isEmpty
            ? 'This source may be heavy. Use a lighter stable profile first.'
            : 'Detected ${reasons.join(', ')}. Use a lighter stable profile first.',
      );
    }
    if (audioChannels >= 6) {
      final preset = builtInScenePresetById('headphone_immersive');
      if (preset == null) return null;
      return MpvScenePresetRecommendation(
        preset: preset,
        title: 'Cinema immersion recommended',
        reason:
            'The current audio track is multichannel, so a cinematic mix can preserve space and low-end weight.',
      );
    }
    if (audioChannels > 0 &&
        audioChannels <= 2 &&
        audioBitrate > 0 &&
        audioBitrate <= 192000 &&
        audioSampleRate > 0 &&
        audioSampleRate <= 48000) {
      final preset = builtInScenePresetById('speaker_clear');
      if (preset == null) return null;
      return MpvScenePresetRecommendation(
        preset: preset,
        title: 'Speaker clarity recommended',
        reason:
            'The current audio track is light, so dialogue-forward speaker tuning is a safer default.',
      );
    }
    final preset = builtInScenePresetById('balanced_movie');
    if (preset == null) return null;
    return MpvScenePresetRecommendation(
      preset: preset,
      title: 'Balanced viewing recommended',
      reason:
          'The current source load looks normal. A balanced picture and audio profile is a stable default.',
    );
  }

  static int videoAdjustmentChangedCount(Map<String, double> values) {
    final normalized = normalizeVideoAdjustments(values);
    var count = 0;
    for (final entry in videoAdjustmentDefaults.entries) {
      if ((normalized[entry.key] ?? entry.value) != entry.value) {
        count += 1;
      }
    }
    return count;
  }

  static MpvSettingPreset? activeBuiltInPicturePreset(
    Map<String, String> settings,
    Map<String, double> videoAdjustments,
  ) {
    final settingsSnapshot = snapshotForKind(
      SavedMpvPresetKind.picture,
      settings,
    );
    final videoSnapshot = pictureVideoAdjustmentSnapshot(videoAdjustments);
    for (final preset in builtInPicturePresets) {
      if (_matchesBuiltInPicturePreset(
        settingsSnapshot,
        videoSnapshot,
        preset,
      )) {
        return preset;
      }
    }
    return null;
  }

  static MpvSettingPreset? activeBuiltInAudioPreset(
    Map<String, String> settings,
  ) {
    final settingsSnapshot = snapshotForKind(
      SavedMpvPresetKind.audio,
      settings,
    );
    for (final preset in builtInAudioPresets) {
      if (_matchesSettingsSnapshot(
        settingsSnapshot,
        preset.settings,
        audioPresetKeys,
      )) {
        return preset;
      }
    }
    return null;
  }

  static MpvScenePreset? activeBuiltInScenePreset(
    Map<String, String> settings,
    Map<String, double> videoAdjustments,
  ) {
    final picturePreset = activeBuiltInPicturePreset(
      settings,
      videoAdjustments,
    );
    final audioPreset = activeBuiltInAudioPreset(settings);
    if (picturePreset == null || audioPreset == null) return null;
    for (final preset in builtInScenePresets) {
      if (preset.picturePresetId == picturePreset.id &&
          preset.audioPresetId == audioPreset.id) {
        return preset;
      }
    }
    return null;
  }

  static SavedMpvPreset? activeSavedPreset(
    SavedMpvPresetKind kind,
    List<SavedMpvPreset> presets, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
  }) {
    final settingsSnapshot = snapshotForKind(kind, settings);
    final videoSnapshot = kind == SavedMpvPresetKind.picture
        ? pictureVideoAdjustmentSnapshot(videoAdjustments)
        : const <String, double>{};
    for (final preset in presets) {
      if (preset.kind != kind) continue;
      if (_matchesSavedPresetSnapshot(
        kind,
        settingsSnapshot,
        videoSnapshot,
        preset,
      )) {
        return preset;
      }
    }
    return null;
  }

  static bool isVideoAdjustmentKey(String key) {
    return videoAdjustmentDefaults.containsKey(key);
  }

  static String videoAdjustmentTitle(String key) {
    return switch (key) {
      brightnessKey => 'Brightness',
      contrastKey => 'Contrast',
      saturationKey => 'Saturation',
      gammaKey => 'Gamma',
      hueKey => 'Hue',
      _ => 'Video parameter',
    };
  }

  static String videoAdjustmentSubtitle(String key) {
    return switch (key) {
      brightnessKey => 'Brighten dark scenes or reduce overexposed images.',
      contrastKey => 'Separate light and dark levels; high values look harder.',
      saturationKey => 'Control overall color intensity.',
      gammaKey => 'Adjust midtones for haze and shadow detail.',
      hueKey =>
        'Shift overall color tone; use small corrections for color casts.',
      _ => '',
    };
  }

  static String formatVideoAdjustmentValue(double value) {
    final normalized = _normalizeVideoAdjustmentValue(value).round();
    if (normalized > 0) return '+$normalized';
    return '$normalized';
  }

  static double _normalizeVideoAdjustmentValue(double value) {
    return value.clamp(-100.0, 100.0).toDouble();
  }

  static MpvSettingPreset? activePreset(Map<String, String> settings) {
    final normalized = normalizeSettings(settings);
    for (final preset in builtInPicturePresets) {
      var matched = true;
      matched = _matchesSettingsSnapshot(
        normalized,
        preset.settings,
        picturePresetKeys,
      );
      if (matched) return preset;
    }
    return null;
  }

  static String settingValue(String key, Map<String, String> settings) {
    final normalized = normalizeSettings(settings);
    return normalized[key] ?? defaults[key] ?? '';
  }

  static String labelForSetting(String key, Map<String, String> settings) {
    final value = settingValue(key, settings);
    if (key == cacheSizeMbKey) return formatCacheSizeLabel(value);
    final definition = definitionByKey(key);
    if (definition == null) return value;
    for (final option in definition.options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  static int changedCount(Map<String, String> settings, [List<String>? keys]) {
    final normalized = normalizeSettings(settings);
    final targetKeys = keys ?? defaults.keys.toList(growable: false);
    var count = 0;
    for (final key in targetKeys) {
      if (!_shouldCompareKey(key, normalized)) continue;
      if (normalized[key] != defaults[key]) count += 1;
    }
    return count;
  }

  static bool isAudioEqBandKey(String key) {
    return audioEqBands.any((band) => band.key == key);
  }

  static bool _shouldCompareKey(String key, Map<String, String> settings) {
    if (!isAudioEqBandKey(key)) return true;
    return settingValue(audioEqKey, settings) == audioEqCustomValue;
  }

  static double audioEqBandValue(String key, Map<String, String> settings) {
    final raw = settingValue(key, settings);
    final parsed = double.tryParse(raw) ?? 0;
    return parsed.clamp(audioEqBandMinDb, audioEqBandMaxDb).toDouble();
  }

  static String formatAudioEqBandValue(double value) {
    final normalized = value.clamp(audioEqBandMinDb, audioEqBandMaxDb);
    if (normalized.abs() < 0.05) return '0 dB';
    final prefix = normalized > 0 ? '+' : '';
    return '$prefix${normalized.toStringAsFixed(1)} dB';
  }

  static String normalizeAudioEqBandValue(double value) {
    final clamped = value.clamp(audioEqBandMinDb, audioEqBandMaxDb);
    final stepped = (clamped / audioEqBandStepDb).round() * audioEqBandStepDb;
    final safe = stepped.clamp(audioEqBandMinDb, audioEqBandMaxDb);
    return safe.toStringAsFixed(1);
  }

  static String statusLabel(Map<String, String> settings) {
    final preset = activePreset(settings);
    if (preset != null) return preset.label;
    return changedCount(settings) == 0 ? 'Default' : 'Customized';
  }

  static String summaryText(Map<String, String> settings) {
    final preset = activePreset(settings);
    if (preset != null) return preset.description;
    final changed = changedCount(settings);
    if (changed == 0) return 'Default MPV parameters are active.';
    final labels = <String>[];
    for (final definition in definitions) {
      if (settingValue(definition.key, settings) == defaults[definition.key]) {
        continue;
      }
      labels.add(
        '${definition.shortTitle} ${labelForSetting(definition.key, settings)}',
      );
      if (labels.length == 3) break;
    }
    return labels.isEmpty
        ? '$changed MPV parameters adjusted.'
        : '$changed adjusted: ${labels.join(' / ')}';
  }

  static String categorySummaryLabel(
    MpvSettingCategory category,
    Map<String, String> settings,
  ) {
    final keys = category.entries
        .map((entry) => entry.key)
        .toList(growable: false);
    final changed = changedCount(settings, keys);
    if (changed == 0) return 'Default';
    if (changed == 1) {
      for (final key in keys) {
        if (settingValue(key, settings) != defaults[key]) {
          return labelForSetting(key, settings);
        }
      }
    }
    return '$changed changed';
  }

  static int normalizeCacheSizeMb(int value) {
    final clamped = value.clamp(cacheSizeSliderMinMb, cacheSizeSliderMaxMb);
    final steps = ((clamped - cacheSizeSliderMinMb) / cacheSizeSliderStepMb)
        .round();
    return cacheSizeSliderMinMb + (steps * cacheSizeSliderStepMb);
  }

  static int mbToCachePercent(int value) {
    final normalized = normalizeCacheSizeMb(value);
    const range = cacheSizeSliderMaxMb - cacheSizeSliderMinMb;
    if (range <= 0) return cachePercentSliderMax;
    final percent = ((normalized - cacheSizeSliderMinMb) * 100 / range).round();
    return percent.clamp(cachePercentSliderMin, cachePercentSliderMax);
  }

  static int cachePercentToMb(int percent) {
    final normalizedPercent = percent.clamp(
      cachePercentSliderMin,
      cachePercentSliderMax,
    );
    const range = cacheSizeSliderMaxMb - cacheSizeSliderMinMb;
    final mapped =
        cacheSizeSliderMinMb + (range * normalizedPercent / 100).round();
    return normalizeCacheSizeMb(mapped);
  }

  static String formatCachePercentLabel(int percent) {
    final normalized = percent.clamp(
      cachePercentSliderMin,
      cachePercentSliderMax,
    );
    return '$normalized%';
  }

  static String formatCacheSizeLabel(String value) {
    if (value == 'auto') return 'Auto';
    final parsed = int.tryParse(value);
    if (parsed == null) return value;
    return formatCachePercentLabel(mbToCachePercent(parsed));
  }

  static bool _matchesSettingsSnapshot(
    Map<String, String> snapshot,
    Map<String, String> presetSettings,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (!_shouldCompareKey(key, snapshot)) continue;
      final expected = presetSettings[key] ?? defaults[key] ?? '';
      if ((snapshot[key] ?? defaults[key] ?? '') != expected) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesBuiltInPicturePreset(
    Map<String, String> settingsSnapshot,
    Map<String, double> videoSnapshot,
    MpvSettingPreset preset,
  ) {
    if (!_matchesSettingsSnapshot(
      settingsSnapshot,
      preset.settings,
      picturePresetKeys,
    )) {
      return false;
    }
    final expectedVideo = normalizeVideoAdjustments(preset.videoAdjustments);
    for (final entry in videoAdjustmentDefaults.entries) {
      final expected = expectedVideo[entry.key] ?? entry.value;
      if ((videoSnapshot[entry.key] ?? entry.value) != expected) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesSavedPresetSnapshot(
    SavedMpvPresetKind kind,
    Map<String, String> settingsSnapshot,
    Map<String, double> videoSnapshot,
    SavedMpvPreset preset,
  ) {
    final keys = kind == SavedMpvPresetKind.picture
        ? picturePresetKeys
        : audioPresetKeys;
    if (!_matchesSettingsSnapshot(
      settingsSnapshot,
      preset.settingsSnapshot,
      keys,
    )) {
      return false;
    }
    if (kind != SavedMpvPresetKind.picture) return true;
    final expectedVideo = normalizeVideoAdjustments(
      preset.videoAdjustmentsSnapshot,
    );
    for (final entry in videoAdjustmentDefaults.entries) {
      final expected = expectedVideo[entry.key] ?? entry.value;
      if ((videoSnapshot[entry.key] ?? entry.value) != expected) {
        return false;
      }
    }
    return true;
  }
}

class MpvSettingsStore {
  const MpvSettingsStore();

  Future<MpvSettingsBundle> loadBundle() async {
    final settings = await load();
    final videoAdjustments = await loadVideoAdjustments();
    return MpvSettingsBundle(
      settings: settings,
      videoAdjustments: videoAdjustments,
    );
  }

  Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = Map<String, String>.from(MpvSettingsCatalog.defaults);
    for (final key in resolved.keys) {
      final stored = prefs.getString('${MpvSettingsCatalog.prefPrefix}$key');
      if (stored != null && stored.trim().isNotEmpty) {
        resolved[key] = stored.trim();
      }
    }
    return resolved;
  }

  Future<Map<String, double>> loadVideoAdjustments() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = Map<String, double>.from(
      MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    for (final key in resolved.keys) {
      final stored = prefs.getDouble(
        '${MpvSettingsCatalog.videoAdjustPrefPrefix}$key',
      );
      if (stored != null) {
        resolved[key] = stored;
        continue;
      }
      final asString = prefs.getString(
        '${MpvSettingsCatalog.videoAdjustPrefPrefix}$key',
      );
      final parsed = double.tryParse(asString ?? '');
      if (parsed != null) {
        resolved[key] = parsed;
      }
    }
    return MpvSettingsCatalog.normalizeVideoAdjustments(resolved);
  }

  Future<void> saveSetting(String key, String value) async {
    if (!MpvSettingsCatalog.defaults.containsKey(key)) return;
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${MpvSettingsCatalog.prefPrefix}$key', normalized);
  }

  Future<void> saveVideoAdjustment(String key, double value) async {
    if (!MpvSettingsCatalog.isVideoAdjustmentKey(key)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      '${MpvSettingsCatalog.videoAdjustPrefPrefix}$key',
      MpvSettingsCatalog.normalizeVideoAdjustments(<String, double>{
            key: value,
          })[key] ??
          0,
    );
  }

  Future<Map<String, String>> savePatch(Map<String, String> patch) async {
    final current = await load();
    final next = <String, String>{...current};
    for (final entry in patch.entries) {
      if (!MpvSettingsCatalog.defaults.containsKey(entry.key)) continue;
      final normalized = entry.value.trim();
      if (normalized.isEmpty) continue;
      next[entry.key] = normalized;
    }
    return saveAll(next);
  }

  Future<Map<String, String>> saveAll(Map<String, String> settings) async {
    final normalized = MpvSettingsCatalog.normalizeSettings(settings);
    final prefs = await SharedPreferences.getInstance();
    for (final entry in normalized.entries) {
      await prefs.setString(
        '${MpvSettingsCatalog.prefPrefix}${entry.key}',
        entry.value,
      );
    }
    return normalized;
  }

  Future<Map<String, double>> saveVideoAdjustments(
    Map<String, double> values,
  ) async {
    final normalized = MpvSettingsCatalog.normalizeVideoAdjustments(values);
    final prefs = await SharedPreferences.getInstance();
    for (final entry in normalized.entries) {
      await prefs.setDouble(
        '${MpvSettingsCatalog.videoAdjustPrefPrefix}${entry.key}',
        entry.value,
      );
    }
    return normalized;
  }

  Future<MpvSettingsBundle> saveBundle({
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
  }) async {
    final savedSettings = await saveAll(settings);
    final savedVideoAdjustments = await saveVideoAdjustments(videoAdjustments);
    return MpvSettingsBundle(
      settings: savedSettings,
      videoAdjustments: savedVideoAdjustments,
    );
  }

  Future<Map<String, String>> applyPreset(MpvSettingPreset preset) {
    final next = Map<String, String>.from(MpvSettingsCatalog.defaults)
      ..addAll(preset.settings);
    return saveAll(next);
  }

  Future<MpvSettingsBundle> applyBuiltInPreset(
    SavedMpvPresetKind kind,
    MpvSettingPreset preset, {
    Map<String, String>? currentSettings,
    Map<String, double>? currentVideoAdjustments,
  }) async {
    final bundle = await loadBundle();
    final nextSettings = Map<String, String>.from(
      currentSettings ?? bundle.settings,
    );
    final nextVideoAdjustments = Map<String, double>.from(
      currentVideoAdjustments ?? bundle.videoAdjustments,
    );
    if (kind == SavedMpvPresetKind.picture) {
      for (final key in MpvSettingsCatalog.picturePresetKeys) {
        nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
      }
      nextVideoAdjustments
        ..clear()
        ..addAll(MpvSettingsCatalog.videoAdjustmentDefaults)
        ..addAll(
          MpvSettingsCatalog.normalizeVideoAdjustments(preset.videoAdjustments),
        );
    } else {
      for (final key in MpvSettingsCatalog.audioPresetKeys) {
        nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
      }
    }
    nextSettings.addAll(preset.settings);
    return saveBundle(
      settings: nextSettings,
      videoAdjustments: nextVideoAdjustments,
    );
  }

  Future<MpvSettingsBundle> applyScenePreset(
    MpvScenePreset preset, {
    Map<String, String>? currentSettings,
    Map<String, double>? currentVideoAdjustments,
  }) async {
    final picturePreset = MpvSettingsCatalog.builtInPicturePresetById(
      preset.picturePresetId,
    );
    final audioPreset = MpvSettingsCatalog.builtInAudioPresetById(
      preset.audioPresetId,
    );
    if (picturePreset == null || audioPreset == null) {
      throw StateError('Scene preset references a missing built-in preset.');
    }
    final bundle = await loadBundle();
    final nextSettings = Map<String, String>.from(
      currentSettings ?? bundle.settings,
    );
    final nextVideoAdjustments = Map<String, double>.from(
      currentVideoAdjustments ?? bundle.videoAdjustments,
    );
    for (final key in MpvSettingsCatalog.picturePresetKeys) {
      nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
    }
    for (final key in MpvSettingsCatalog.audioPresetKeys) {
      nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
    }
    nextVideoAdjustments
      ..clear()
      ..addAll(MpvSettingsCatalog.videoAdjustmentDefaults)
      ..addAll(
        MpvSettingsCatalog.normalizeVideoAdjustments(
          picturePreset.videoAdjustments,
        ),
      );
    nextSettings
      ..addAll(picturePreset.settings)
      ..addAll(audioPreset.settings);
    return saveBundle(
      settings: nextSettings,
      videoAdjustments: nextVideoAdjustments,
    );
  }

  Future<List<SavedMpvPreset>> loadSavedPresets(SavedMpvPresetKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKeyForKind(kind));
    if (raw == null || raw.trim().isEmpty) return const <SavedMpvPreset>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SavedMpvPreset>[];
      final result = <SavedMpvPreset>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final preset = SavedMpvPreset.fromMap(item.cast<String, dynamic>());
        if (preset == null || preset.kind != kind) continue;
        result.add(preset);
      }
      return result;
    } catch (_) {
      return const <SavedMpvPreset>[];
    }
  }

  Future<bool> isSavedPresetNameAvailable(
    SavedMpvPresetKind kind,
    String name, {
    String? excludingId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;
    final presets = await loadSavedPresets(kind);
    for (final preset in presets) {
      if (preset.id == excludingId) continue;
      if (preset.name.trim().toLowerCase() == normalizedName.toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  Future<String> nextSavedPresetName(SavedMpvPresetKind kind) async {
    return nextSavedPresetNameFromBase(kind, '${kind.label}_preset');
  }

  Future<String> nextSavedPresetNameFromBase(
    SavedMpvPresetKind kind,
    String baseName,
  ) async {
    final normalizedBase = baseName.trim().isEmpty
        ? '${kind.label}_preset'
        : baseName.trim();
    var index = 1;
    while (true) {
      final candidate = '$normalizedBase$index';
      if (await isSavedPresetNameAvailable(kind, candidate)) {
        return candidate;
      }
      index += 1;
    }
  }

  Future<SavedMpvPreset> savePresetSnapshot({
    required SavedMpvPresetKind kind,
    required String name,
    String description = '',
    Map<String, String>? settings,
    Map<String, double>? videoAdjustments,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Preset name must not be empty.');
    }
    if (!await isSavedPresetNameAvailable(kind, normalizedName)) {
      throw StateError('Preset name already exists.');
    }
    final bundle = await loadBundle();
    final preset = SavedMpvPreset(
      id: 'saved_mpv_preset_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      name: normalizedName,
      description: description.trim(),
      createdAt: DateTime.now(),
      settingsSnapshot: MpvSettingsCatalog.snapshotForKind(
        kind,
        settings ?? bundle.settings,
      ),
      videoAdjustmentsSnapshot: kind == SavedMpvPresetKind.picture
          ? MpvSettingsCatalog.pictureVideoAdjustmentSnapshot(
              videoAdjustments ?? bundle.videoAdjustments,
            )
          : const <String, double>{},
    );
    final current = await loadSavedPresets(kind);
    final next = <SavedMpvPreset>[...current, preset];
    await _persistSavedPresets(kind, next);
    return preset;
  }

  Future<void> renameSavedPreset(
    SavedMpvPresetKind kind,
    String id, {
    required String name,
    String description = '',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Preset name must not be empty.');
    }
    if (!await isSavedPresetNameAvailable(
      kind,
      normalizedName,
      excludingId: id,
    )) {
      throw StateError('Preset name already exists.');
    }
    final presets = await loadSavedPresets(kind);
    final next = <SavedMpvPreset>[];
    var updated = false;
    for (final preset in presets) {
      if (preset.id == id) {
        next.add(
          preset.copyWith(
            name: normalizedName,
            description: description.trim(),
          ),
        );
        updated = true;
      } else {
        next.add(preset);
      }
    }
    if (!updated) return;
    await _persistSavedPresets(kind, next);
  }

  Future<void> deleteSavedPreset(SavedMpvPresetKind kind, String id) async {
    final presets = await loadSavedPresets(kind);
    final next = presets
        .where((preset) => preset.id != id)
        .toList(growable: false);
    if (next.length == presets.length) return;
    await _persistSavedPresets(kind, next);
  }

  Future<MpvSettingsBundle> applySavedPreset(
    SavedMpvPreset preset, {
    Map<String, String>? currentSettings,
    Map<String, double>? currentVideoAdjustments,
  }) async {
    final bundle = await loadBundle();
    final nextSettings = Map<String, String>.from(
      currentSettings ?? bundle.settings,
    );
    final nextVideoAdjustments = Map<String, double>.from(
      currentVideoAdjustments ?? bundle.videoAdjustments,
    );
    if (preset.kind == SavedMpvPresetKind.picture) {
      for (final key in MpvSettingsCatalog.picturePresetKeys) {
        nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
      }
      nextVideoAdjustments
        ..clear()
        ..addAll(MpvSettingsCatalog.videoAdjustmentDefaults)
        ..addAll(
          MpvSettingsCatalog.pictureVideoAdjustmentSnapshot(
            preset.videoAdjustmentsSnapshot,
          ),
        );
    } else {
      for (final key in MpvSettingsCatalog.audioPresetKeys) {
        nextSettings[key] = MpvSettingsCatalog.defaults[key] ?? '';
      }
    }
    nextSettings.addAll(preset.settingsSnapshot);
    return saveBundle(
      settings: nextSettings,
      videoAdjustments: nextVideoAdjustments,
    );
  }

  Future<MpvSettingsBundle> resetAll() {
    return saveBundle(
      settings: MpvSettingsCatalog.defaults,
      videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
    );
  }

  Future<Map<String, String>> reset() {
    return saveAll(MpvSettingsCatalog.defaults);
  }

  String _storageKeyForKind(SavedMpvPresetKind kind) {
    return kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.savedPicturePresetsKey
        : MpvSettingsCatalog.savedAudioPresetsKey;
  }

  Future<void> _persistSavedPresets(
    SavedMpvPresetKind kind,
    List<SavedMpvPreset> presets,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      presets.map((preset) => preset.toMap()).toList(growable: false),
    );
    await prefs.setString(_storageKeyForKind(kind), payload);
  }
}
