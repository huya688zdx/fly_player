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
    SavedMpvPresetKind.picture => '画质',
    SavedMpvPresetKind.audio => '音频',
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
          label: '默认',
          description: '关闭额外画质增强，优先保证兼容性和稳定性。',
          settings: <String, String>{},
        ),
        MpvSettingPreset(
          id: 'anime',
          label: '动画清晰',
          description: '通过轻微对比度和饱和度调整突出线条感，不再默认带入重滤镜。',
          settings: <String, String>{},
          videoAdjustments: <String, double>{contrastKey: 4, saturationKey: 6},
        ),
        MpvSettingPreset(
          id: 'cinema',
          label: '影院柔和',
          description: '用较轻的亮暗和饱和调整偏向影院观感，避免额外画面计算。',
          settings: <String, String>{},
          videoAdjustments: <String, double>{
            contrastKey: -4,
            gammaKey: 6,
            saturationKey: -3,
          },
        ),
        MpvSettingPreset(
          id: 'smooth',
          label: '流畅优先',
          description: '偏向稳定和响应的轻量流畅方案，不再默认带入插帧。',
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
      label: '默认',
      description: '关闭额外音频增强，保留基础播放参数。',
      settings: <String, String>{},
    ),
    MpvSettingPreset(
      id: 'hi_fi',
      label: '原声保真',
      description: '打开高保真，旁路 EQ 和增强，适合耳机和高质量片源。',
      settings: <String, String>{
        audioHighFidelityKey: 'on',
        volumeGainKey: '100',
      },
    ),
    MpvSettingPreset(
      id: 'balanced',
      label: '通用增强',
      description: '轻度提亮人声和低频，适合大多数普通剧集、综艺和日常看片。',
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
      label: '人声清晰',
      description: '抬前对白和中高频细节，适合台词偏轻的片源。',
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
      label: '外放清晰',
      description: '针对手机和平板外放，压住爆点、把对白往前推，减少糊成一团。',
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
      label: '影院低频',
      description: '增强低频氛围和厚度，适合动作片、配乐片和外放。',
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
      label: '耳机沉浸',
      description: '保留动态感，补一点氛围和厚度，适合耳机听电影和演唱会现场。',
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
      label: '夜间均衡',
      description: '压低爆点、抬前对白，适合深夜外放和追剧。',
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
      label: '省电稳定',
      description: '优先照顾解码稳定和系统流畅度，适合 4K、HDR、HEVC 和高码率片源。',
      picturePresetId: 'smooth',
      audioPresetId: 'balanced',
    ),
    MpvScenePreset(
      id: 'balanced_movie',
      label: '通用观影',
      description: '用轻量画质和通用增强音频组成的日常观影片方案，适合大多数普通片源。',
      picturePresetId: 'cinema',
      audioPresetId: 'balanced',
    ),
    MpvScenePreset(
      id: 'anime_dialogue',
      label: '追番对白',
      description: '保留动画线条感并把对白往前提，适合动画、综艺和日常追番。',
      picturePresetId: 'anime',
      audioPresetId: 'dialogue',
    ),
    MpvScenePreset(
      id: 'speaker_clear',
      label: '外放清晰',
      description: '优先照顾手机和平板外放，把爆点压住并把对白往前推。',
      picturePresetId: 'smooth',
      audioPresetId: 'speaker_clear',
    ),
    MpvScenePreset(
      id: 'night_binge',
      label: '夜间追剧',
      description: '偏向稳定和夜间聆听，压低爆点并减少长时间观看的刺耳感。',
      picturePresetId: 'smooth',
      audioPresetId: 'night',
    ),
    MpvScenePreset(
      id: 'headphone_immersive',
      label: '耳机沉浸',
      description: '画面保持轻柔层次，耳机下保留氛围感和低频厚度。',
      picturePresetId: 'cinema',
      audioPresetId: 'headphone_immersive',
    ),
  ];

  static const List<MpvSettingDefinition> definitions = <MpvSettingDefinition>[
    MpvSettingDefinition(
      key: debandKey,
      title: '去色带',
      shortTitle: '去色带',
      description: '处理渐变断层和暗部条带，适合高压缩或低码率片源。',
      helperLabel: '去色带强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '不额外处理色带。'),
        MpvSettingOption(
          value: 'low',
          label: '轻度',
          description: '轻微去除色带，兼顾细节。',
        ),
        MpvSettingOption(
          value: 'medium',
          label: '标准',
          description: '更明显地平滑色带。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: sharpenKey,
      title: '锐化',
      shortTitle: '锐化',
      description: '提升边缘清晰度，但过强可能带来噪点和轮廓感。',
      helperLabel: '锐化强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持原始画面细节。'),
        MpvSettingOption(value: 'low', label: '轻度', description: '轻微提升边缘锐利度。'),
        MpvSettingOption(
          value: 'medium',
          label: '标准',
          description: '更明显的锐化效果。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: denoiseKey,
      title: '降噪',
      shortTitle: '降噪',
      description: '压制噪点和颗粒感，适合老片源或码率偏低的视频。',
      helperLabel: '降噪强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '不做额外降噪。'),
        MpvSettingOption(
          value: 'low',
          label: '轻度',
          description: '轻微压制噪点，保留较多细节。',
        ),
        MpvSettingOption(value: 'medium', label: '标准', description: '更强调干净画面。'),
      ],
    ),
    MpvSettingDefinition(
      key: deinterlaceKey,
      title: '反交错',
      shortTitle: '反交错',
      description: '针对隔行扫描片源，普通网络视频建议保持自动。',
      helperLabel: '处理方式',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: '自动',
          description: '检测到隔行源时才启用。',
        ),
        MpvSettingOption(value: 'off', label: '关闭', description: '始终关闭反交错。'),
        MpvSettingOption(
          value: 'force',
          label: '强制开启',
          description: '无论片源类型都执行反交错。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: scaleProfileKey,
      title: '缩放算法',
      shortTitle: '缩放',
      description: '控制放大和缩小时的画面取向，在画质和性能之间取舍。',
      helperLabel: '缩放策略',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'fast',
          label: '快速',
          description: '优先性能，适合低端设备。',
        ),
        MpvSettingOption(
          value: 'balanced',
          label: '标准',
          description: '画质和功耗更均衡。',
        ),
        MpvSettingOption(
          value: 'quality',
          label: '高质量',
          description: '追求更细腻的缩放效果。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: hdrModeKey,
      title: 'HDR 处理',
      shortTitle: 'HDR',
      description: '控制 HDR 到 SDR 的映射和整体色彩倾向。',
      helperLabel: 'HDR 模式',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: '自动',
          description: '按片源和设备能力自动选择。',
        ),
        MpvSettingOption(
          value: 'sdr_map',
          label: 'SDR 映射',
          description: '更偏兼容和稳定。',
        ),
        MpvSettingOption(
          value: 'conservative',
          label: '保守映射',
          description: '更稳地压制高光。',
        ),
        MpvSettingOption(
          value: 'enhanced',
          label: '增强映射',
          description: '更强调对比和高光层次。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: frameInterpolationKey,
      title: '插帧',
      shortTitle: '插帧',
      description: '通过补帧提升运动流畅度，但会增加功耗，也可能改变观感。',
      helperLabel: '插帧策略',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持原始帧率输出。'),
        MpvSettingOption(value: 'auto', label: '自动', description: '按场景决定是否启用。'),
        MpvSettingOption(
          value: 'on',
          label: '始终开启',
          description: '最大化流畅度，性能开销最高。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: videoSyncKey,
      title: '同步模式',
      shortTitle: '同步',
      description: '只控制音画与刷新率的同步取向，不负责缓冲大小和缓存风格。',
      helperLabel: '同步取向',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: '智能平衡',
          description: '按当前设备能力自动平衡音画稳定与刷新率匹配。',
        ),
        MpvSettingOption(
          value: 'audio',
          label: '音频优先',
          description: '优先保证音频连续稳定。',
        ),
        MpvSettingOption(
          value: 'display',
          label: '显示优先',
          description: '更重视刷新率匹配。',
        ),
        MpvSettingOption(
          value: 'smooth',
          label: '平滑同步',
          description: '更积极地贴合显示刷新率，适合更在意观感流畅的场景。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: cacheProfileKey,
      title: '缓存策略',
      shortTitle: '缓存',
      description: '只决定缓冲风格和预读力度，不会改动同步模式。',
      helperLabel: '缓冲取向',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'default',
          label: '智能分配',
          description: '按片源类型自动选择更合适的缓冲强度。',
        ),
        MpvSettingOption(
          value: 'low_latency',
          label: '极速响应',
          description: '尽量减轻预读，优先拖动和切换响应。',
        ),
        MpvSettingOption(
          value: 'stable',
          label: '稳定缓冲',
          description: '适当增加预读，优先减轻网络抖动。',
        ),
        MpvSettingOption(
          value: 'network',
          label: '网盘 / STRM / NAS',
          description: '适合网盘、STRM 和 NAS 里的高码率片源。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: cacheSizeMbKey,
      title: '缓冲大小',
      shortTitle: '缓冲大小',
      description: '直接控制播放器最多预读多少数据，数值越大越稳，但起播和拖动后的回填会更重。',
      helperLabel: '缓冲上限',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: '自动',
          description: '跟随当前缓存策略自动分配。',
        ),
        MpvSettingOption(
          value: '64',
          label: '64 MB',
          description: '较省内存，适合普通码率。',
        ),
        MpvSettingOption(
          value: '128',
          label: '128 MB',
          description: '更适合远程直链和高码率文件。',
        ),
        MpvSettingOption(
          value: '256',
          label: '256 MB',
          description: '优先减少网络抖动带来的卡顿。',
        ),
        MpvSettingOption(
          value: '512',
          label: '512 MB',
          description: '适合超高码率和不稳定网络，但占用更高。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: volumeGainKey,
      title: '音量放大',
      shortTitle: '音量',
      description: '为偏小声音片源提供更高的音量上限。',
      helperLabel: '音量上限',
      options: <MpvSettingOption>[
        MpvSettingOption(value: '100', label: '100%', description: '标准音量上限。'),
        MpvSettingOption(
          value: '150',
          label: '150%',
          description: '适合对白偏轻的片源。',
        ),
        MpvSettingOption(
          value: '200',
          label: '200%',
          description: '最大放大，可能带来失真。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioHighFidelityKey,
      title: '高保真模式',
      shortTitle: '高保真',
      description: '关闭 EQ、限幅、低音增强、人声增强和动态压缩，尽量保持更干净的解码输出。',
      helperLabel: '输出取向',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'off',
          label: '关闭',
          description: '继续按当前音频处理设置应用增强和滤镜链。',
        ),
        MpvSettingOption(
          value: 'on',
          label: '开启',
          description: '优先保留原始音色，统一旁路大部分音频后处理。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: dynamicRangeKey,
      title: '动态范围压缩',
      shortTitle: '动态范围',
      description: '压低爆点和高动态差异，让对白更靠前。',
      helperLabel: '压缩强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持原始动态范围。'),
        MpvSettingOption(value: 'low', label: '轻度', description: '轻微提升对白可听性。'),
        MpvSettingOption(value: 'medium', label: '标准', description: '夜间播放更友好。'),
      ],
    ),
    MpvSettingDefinition(
      key: audioEqKey,
      title: 'EQ 均衡器',
      shortTitle: 'EQ',
      description: '用不同的均衡预设调整低频、中频和高频的听感平衡。',
      helperLabel: '均衡预设',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持原始音色。'),
        MpvSettingOption(
          value: 'soft',
          label: '柔和',
          description: '轻微修整低频和人声，适合普通观看。',
        ),
        MpvSettingOption(
          value: 'clarity',
          label: '清晰',
          description: '更强调人声和高频细节，适合对白偏轻的片源。',
        ),
        MpvSettingOption(
          value: 'cinema',
          label: '影院',
          description: '更均衡地兼顾低频氛围和台词清晰度。',
        ),
        MpvSettingOption(
          value: audioEqCustomValue,
          label: '高级自定义',
          description: '进入多频段页，自己上下拖动每个频带。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioLimiterKey,
      title: '峰值限幅',
      shortTitle: '限幅',
      description: '在不改变整体听感的情况下压住瞬时过高的声音，防止破音。',
      helperLabel: '限幅强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '不额外做峰值压制。'),
        MpvSettingOption(
          value: 'light',
          label: '轻度',
          description: '轻微压低突然的大音量，尽量保留动态。',
        ),
        MpvSettingOption(
          value: 'strong',
          label: '标准',
          description: '更积极地防止破音，适合增强较多时使用。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioBassBoostKey,
      title: '低音增强',
      shortTitle: '低音',
      description: '为影院氛围感、地鸣和配乐的低频部分提供更强烈的存在感。',
      helperLabel: '低音强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持当前低频表现。'),
        MpvSettingOption(value: 'low', label: '轻度', description: '轻微提升低频厚度。'),
        MpvSettingOption(
          value: 'medium',
          label: '标准',
          description: '更明显的低音增强效果。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: audioVoiceEnhanceKey,
      title: '人声增强',
      shortTitle: '人声',
      description: '通过人声去除低频混浊，提升台词和对白的清晰度。',
      helperLabel: '人声强度',
      options: <MpvSettingOption>[
        MpvSettingOption(value: 'off', label: '关闭', description: '保持原始人声表现。'),
        MpvSettingOption(
          value: 'low',
          label: '轻度',
          description: '轻微提升台词，不太改变整体音色。',
        ),
        MpvSettingOption(
          value: 'medium',
          label: '标准',
          description: '更适合对白偏轻或后景音偏响的片源。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: channelMixKey,
      title: '声道混合',
      shortTitle: '声道',
      description: '控制多声道到当前输出设备的混合策略。',
      helperLabel: '输出方式',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'auto',
          label: '自动',
          description: '按设备和片源自动选择。',
        ),
        MpvSettingOption(
          value: 'stereo',
          label: '立体声优先',
          description: '更适合耳机和普通外放。',
        ),
        MpvSettingOption(
          value: 'surround',
          label: '环绕优先',
          description: '尽量保留更多多声道信息。',
        ),
      ],
    ),
    MpvSettingDefinition(
      key: compatibilityKey,
      title: '兼容模式',
      shortTitle: '兼容',
      description: '遇到黑屏、花屏或特殊机型问题时，用来快速回退策略。',
      helperLabel: '兼容策略',
      options: <MpvSettingOption>[
        MpvSettingOption(
          value: 'default',
          label: '默认',
          description: '保持当前常规配置。',
        ),
        MpvSettingOption(
          value: 'conservative',
          label: '保守兼容',
          description: '减少激进渲染和滤镜行为。',
        ),
        MpvSettingOption(
          value: 'software_fallback',
          label: '软件优先',
          description: '更强调稳定性，必要时回退到软解策略。',
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
        title: '性能提醒',
        message: '中档去色带会增加额外画面处理开销，部分设备可能出现掉帧、发热或系统卡顿。',
      );
    }
    if (key == sharpenKey && value != 'off') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '锐化会增加滤镜计算量，片源较重或设备较弱时可能导致播放掉帧和界面不流畅。',
      );
    }
    if (key == denoiseKey && value != 'off') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '降噪属于较重的视频滤镜，移动设备上很容易带来明显掉帧、发热甚至系统卡顿。',
      );
    }
    if (key == deinterlaceKey && value == 'force') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '强制反交错会让所有片源都走额外处理链路，普通逐行片源通常没有必要，且可能拖慢播放。',
      );
    }
    if (key == scaleProfileKey && value == 'quality') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '高质量缩放会增加 GPU 和渲染压力，高分辨率或高码率片源上更容易出现掉帧。',
      );
    }
    if (key == hdrModeKey && (value == 'conservative' || value == 'enhanced')) {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '这个 HDR 模式会增加色调映射压力，HDR、10-bit 或高分辨率片源上可能导致明显卡顿。',
      );
    }
    if (key == frameInterpolationKey && (value == 'auto' || value == 'on')) {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '插帧是最容易拖慢播放和系统流畅度的选项之一，开启后可能出现视频掉帧、UI 掉帧和系统卡顿。',
      );
    }
    if (key == videoSyncKey && value == 'smooth') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '平滑同步会更积极地贴合屏幕刷新率，部分设备上会增加合成与同步压力。',
      );
    }
    if (key == cacheProfileKey && value == 'network') {
      return const MpvPerformanceImpactWarning(
        title: '性能提醒',
        message: '网络重缓存会占用更多内存，并让拖动回填更重，只建议在高码率远程片源上使用。',
      );
    }
    if (key == cacheSizeMbKey) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed >= cacheSizeExtremeMinimumMb) {
        return const MpvPerformanceImpactWarning(
          title: '性能提醒',
          message: '较大的缓冲会占用更多内存，并让起播、拖动后的回填更重；低内存设备上可能影响系统流畅度。',
        );
      }
    }
    return null;
  }

  static const List<MpvSettingCategory> categories = <MpvSettingCategory>[
    MpvSettingCategory(
      id: videoFiltersCategoryId,
      title: '视频滤镜',
      subtitle: '去色带、锐化、降噪、反交错、缩放算法',
      description: '主要针对画面净化、边缘锐度和缩放观感。',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: debandKey,
          title: '去色带',
          subtitle: '处理渐变断层和暗部条带',
        ),
        MpvSettingCategoryEntry(
          key: sharpenKey,
          title: '锐化',
          subtitle: '提升边缘清晰度',
        ),
        MpvSettingCategoryEntry(
          key: denoiseKey,
          title: '降噪',
          subtitle: '压制噪点和颗粒感',
        ),
        MpvSettingCategoryEntry(
          key: deinterlaceKey,
          title: '反交错',
          subtitle: '处理隔行扫描片源',
        ),
        MpvSettingCategoryEntry(
          key: scaleProfileKey,
          title: '缩放算法',
          subtitle: '控制放大和缩小时的取向',
        ),
      ],
    ),
    MpvSettingCategory(
      id: pictureRenderingCategoryId,
      title: '画质渲染',
      subtitle: 'HDR 处理、插帧',
      description: '更偏向画面风格和输出观感的增强项。',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: hdrModeKey,
          title: 'HDR 处理',
          subtitle: '调整 HDR 映射和整体色调',
        ),
        MpvSettingCategoryEntry(
          key: frameInterpolationKey,
          title: '插帧',
          subtitle: '改善运动流畅度，性能开销更高',
        ),
      ],
    ),
    MpvSettingCategory(
      id: playbackSyncCategoryId,
      title: '播放同步',
      subtitle: '同步模式、缓存策略、缓冲大小',
      description: '主要影响拖动响应、网络稳定性和播放流畅度。',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: videoSyncKey,
          title: '同步模式',
          subtitle: '只调整音画与刷新率的同步取向',
        ),
        MpvSettingCategoryEntry(
          key: cacheProfileKey,
          title: '缓存策略',
          subtitle: '只调整预读力度和缓冲风格',
        ),
        MpvSettingCategoryEntry(
          key: cacheSizeMbKey,
          title: '缓冲大小',
          subtitle: '手动覆盖自动缓存上限',
        ),
      ],
    ),
    MpvSettingCategory(
      id: audioProcessingCategoryId,
      title: '音频处理',
      subtitle: '音量、EQ、限幅、低音和人声增强',
      description: '主要影响对白可听性、音色重心和多声道输出适配。',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: volumeGainKey,
          title: '音量放大',
          subtitle: '提高偏小声音源的音量上限',
        ),
        MpvSettingCategoryEntry(
          key: audioHighFidelityKey,
          title: '高保真模式',
          subtitle: '优先保留干净解码输出，统一旁路大部分后处理',
        ),
        MpvSettingCategoryEntry(
          key: dynamicRangeKey,
          title: '动态范围压缩',
          subtitle: '让对白更靠前，夜间播放更稳',
        ),
        MpvSettingCategoryEntry(
          key: audioEqKey,
          title: 'EQ 均衡器',
          subtitle: '调整低频、中频和高频的听感平衡',
        ),
        MpvSettingCategoryEntry(
          key: audioLimiterKey,
          title: '峰值限幅',
          subtitle: '防止瞬时音量过高导致破音',
        ),
        MpvSettingCategoryEntry(
          key: audioBassBoostKey,
          title: '低音增强',
          subtitle: '增强影院氛围和低频存在感',
        ),
        MpvSettingCategoryEntry(
          key: audioVoiceEnhanceKey,
          title: '人声增强',
          subtitle: '让台词和对白更清晰更靠前',
        ),
        MpvSettingCategoryEntry(
          key: channelMixKey,
          title: '声道混合',
          subtitle: '控制多声道输出取向',
        ),
      ],
    ),
    MpvSettingCategory(
      id: compatibilityCategoryId,
      title: '兼容模式',
      subtitle: '兼容回退与问题排查',
      description: '遇到黑屏、花屏或特殊机型时，优先从这里回退。',
      entries: <MpvSettingCategoryEntry>[
        MpvSettingCategoryEntry(
          key: compatibilityKey,
          title: '兼容模式',
          subtitle: '遇到黑屏、花屏或异常时切换',
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
      if (isUltraHighResolution) reasons.add('分辨率偏高');
      if (isHdr) reasons.add('HDR/高动态范围');
      if (bitDepth >= 10) reasons.add('10-bit 片源');
      if (isHevcLike && bitrate >= 8000000) reasons.add('HEVC 高码率');
      if (isRemoteSource) reasons.add('远程网络片源');
      return MpvScenePresetRecommendation(
        preset: preset,
        title: '推荐稳定优先',
        reason: reasons.isEmpty
            ? '当前片源负载偏高，先用更稳的轻量场景，避免播放器和系统一起掉帧。'
            : '检测到${reasons.join('、')}，建议先用更稳的轻量场景，避免播放器和系统一起掉帧。',
      );
    }
    if (audioChannels >= 6) {
      final preset = builtInScenePresetById('headphone_immersive');
      if (preset == null) return null;
      return MpvScenePresetRecommendation(
        preset: preset,
        title: '推荐电影沉浸',
        reason: '当前音轨是多声道，适合保留氛围感和低频厚度的电影向组合。',
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
        title: '推荐清晰外放',
        reason: '当前音轨偏轻，优先把对白和主体声推前，普通剧集和外放更省心。',
      );
    }
    final preset = builtInScenePresetById('balanced_movie');
    if (preset == null) return null;
    return MpvScenePresetRecommendation(
      preset: preset,
      title: '推荐通用观影',
      reason: '当前片源负载正常，先用平衡一些的画质和音频组合最稳妥。',
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
      brightnessKey => '亮度',
      contrastKey => '对比度',
      saturationKey => '饱和度',
      gammaKey => 'Gamma',
      hueKey => '色相',
      _ => '画面参数',
    };
  }

  static String videoAdjustmentSubtitle(String key) {
    return switch (key) {
      brightnessKey => '提亮暗场或压暗过曝画面。',
      contrastKey => '拉开明暗层次，数值过高会更硬。',
      saturationKey => '控制整体颜色浓度。',
      gammaKey => '偏向中间调修正，适合微调灰雾感。',
      hueKey => '整体色调偏移，建议小幅修正偏色片源。',
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
    return changedCount(settings) == 0 ? '默认' : '已自定义';
  }

  static String summaryText(Map<String, String> settings) {
    final preset = activePreset(settings);
    if (preset != null) return preset.description;
    final changed = changedCount(settings);
    if (changed == 0) return '当前使用默认 MPV 参数。';
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
        ? '已调整 $changed 项 MPV 参数。'
        : '已调整 $changed 项：${labels.join(' / ')}';
  }

  static String categorySummaryLabel(
    MpvSettingCategory category,
    Map<String, String> settings,
  ) {
    final keys = category.entries
        .map((entry) => entry.key)
        .toList(growable: false);
    final changed = changedCount(settings, keys);
    if (changed == 0) return '默认';
    if (changed == 1) {
      for (final key in keys) {
        if (settingValue(key, settings) != defaults[key]) {
          return labelForSetting(key, settings);
        }
      }
    }
    return '$changed 项';
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
    if (value == 'auto') return '自动';
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
    return nextSavedPresetNameFromBase(kind, '${kind.label}预设');
  }

  Future<String> nextSavedPresetNameFromBase(
    SavedMpvPresetKind kind,
    String baseName,
  ) async {
    final normalizedBase = baseName.trim().isEmpty
        ? '${kind.label}预设'
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
