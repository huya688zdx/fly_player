import '../l10n/generated/app_localizations.dart';
import 'stores/mpv_settings_store.dart';

class MpvSettingsL10n {
  const MpvSettingsL10n._();

  static String savedPresetKindLabel(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
  ) {
    return switch (kind) {
      SavedMpvPresetKind.picture => l10n.mpvSavedPresetKindPicture,
      SavedMpvPresetKind.audio => l10n.mpvSavedPresetKindAudio,
    };
  }

  static String defaultLabel(AppLocalizations l10n) => l10n.mpvDefault;

  static String currentCustomLabel(AppLocalizations l10n) =>
      l10n.mpvCurrentCustom;

  static String notUsedLabel(AppLocalizations l10n) => l10n.mpvNotUsed;

  static String changedCount(AppLocalizations l10n, int count) =>
      l10n.mpvChangedCount(count);

  static String presetNameLabel(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
  ) => l10n.mpvPresetNameLabel(savedPresetKindLabel(l10n, kind));

  static String presetDuplicateName(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
  ) => l10n.mpvPresetDuplicateName(savedPresetKindLabel(l10n, kind));

  static String presetSavedMessage(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
    String name,
  ) => l10n.mpvPresetSavedMessage(savedPresetKindLabel(l10n, kind), name);

  static String presetDefaultBaseName(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
  ) => l10n.mpvPresetDefaultBaseName(savedPresetKindLabel(l10n, kind));

  static String presetRenameTitle(
    AppLocalizations l10n,
    SavedMpvPresetKind kind,
  ) => l10n.mpvPresetRenameTitle(savedPresetKindLabel(l10n, kind));

  static List<MpvSettingPreset> builtInPicturePresets(AppLocalizations l10n) =>
      MpvSettingsCatalog.builtInPicturePresets
          .map((preset) => picturePreset(l10n, preset))
          .toList(growable: false);

  static List<MpvSettingPreset> builtInAudioPresets(AppLocalizations l10n) =>
      MpvSettingsCatalog.builtInAudioPresets
          .map((preset) => audioPreset(l10n, preset))
          .toList(growable: false);

  static List<MpvScenePreset> builtInScenePresets(AppLocalizations l10n) =>
      MpvSettingsCatalog.builtInScenePresets
          .map((preset) => scenePreset(l10n, preset))
          .toList(growable: false);

  static MpvSettingPreset picturePreset(
    AppLocalizations l10n,
    MpvSettingPreset preset,
  ) {
    return MpvSettingPreset(
      id: preset.id,
      label: picturePresetLabel(l10n, preset.id, fallback: preset.label),
      description: picturePresetDescription(
        l10n,
        preset.id,
        fallback: preset.description,
      ),
      settings: preset.settings,
      videoAdjustments: preset.videoAdjustments,
    );
  }

  static MpvSettingPreset audioPreset(
    AppLocalizations l10n,
    MpvSettingPreset preset,
  ) {
    return MpvSettingPreset(
      id: preset.id,
      label: audioPresetLabel(l10n, preset.id, fallback: preset.label),
      description: audioPresetDescription(
        l10n,
        preset.id,
        fallback: preset.description,
      ),
      settings: preset.settings,
      videoAdjustments: preset.videoAdjustments,
    );
  }

  static MpvScenePreset scenePreset(
    AppLocalizations l10n,
    MpvScenePreset preset,
  ) {
    return MpvScenePreset(
      id: preset.id,
      label: scenePresetLabel(l10n, preset.id, fallback: preset.label),
      description: scenePresetDescription(
        l10n,
        preset.id,
        fallback: preset.description,
      ),
      picturePresetId: preset.picturePresetId,
      audioPresetId: preset.audioPresetId,
    );
  }

  static String picturePresetLabel(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'off' => l10n.mpvPicturePresetOffLabel,
      'anime' => l10n.mpvPicturePresetAnimeLabel,
      'cinema' => l10n.mpvPicturePresetCinemaLabel,
      'smooth' => l10n.mpvPicturePresetSmoothLabel,
      _ => fallback,
    };
  }

  static String picturePresetDescription(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'off' => l10n.mpvPicturePresetOffDescription,
      'anime' => l10n.mpvPicturePresetAnimeDescription,
      'cinema' => l10n.mpvPicturePresetCinemaDescription,
      'smooth' => l10n.mpvPicturePresetSmoothDescription,
      _ => fallback,
    };
  }

  static String audioPresetLabel(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'off' => l10n.mpvAudioPresetOffLabel,
      'hi_fi' => l10n.mpvAudioPresetHiFiLabel,
      'balanced' => l10n.mpvAudioPresetBalancedLabel,
      'dialogue' => l10n.mpvAudioPresetDialogueLabel,
      'speaker_clear' => l10n.mpvAudioPresetSpeakerClearLabel,
      'cinema_bass' => l10n.mpvAudioPresetCinemaBassLabel,
      'headphone_immersive' => l10n.mpvAudioPresetHeadphoneImmersiveLabel,
      'night' => l10n.mpvAudioPresetNightLabel,
      _ => fallback,
    };
  }

  static String audioPresetDescription(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'off' => l10n.mpvAudioPresetOffDescription,
      'hi_fi' => l10n.mpvAudioPresetHiFiDescription,
      'balanced' => l10n.mpvAudioPresetBalancedDescription,
      'dialogue' => l10n.mpvAudioPresetDialogueDescription,
      'speaker_clear' => l10n.mpvAudioPresetSpeakerClearDescription,
      'cinema_bass' => l10n.mpvAudioPresetCinemaBassDescription,
      'headphone_immersive' => l10n.mpvAudioPresetHeadphoneImmersiveDescription,
      'night' => l10n.mpvAudioPresetNightDescription,
      _ => fallback,
    };
  }

  static String scenePresetLabel(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'stable_clear' => l10n.mpvScenePresetStableClearLabel,
      'balanced_movie' => l10n.mpvScenePresetBalancedMovieLabel,
      'anime_dialogue' => l10n.mpvScenePresetAnimeDialogueLabel,
      'speaker_clear' => l10n.mpvScenePresetSpeakerClearLabel,
      'night_binge' => l10n.mpvScenePresetNightBingeLabel,
      'headphone_immersive' => l10n.mpvScenePresetHeadphoneImmersiveLabel,
      _ => fallback,
    };
  }

  static String scenePresetDescription(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      'stable_clear' => l10n.mpvScenePresetStableClearDescription,
      'balanced_movie' => l10n.mpvScenePresetBalancedMovieDescription,
      'anime_dialogue' => l10n.mpvScenePresetAnimeDialogueDescription,
      'speaker_clear' => l10n.mpvScenePresetSpeakerClearDescription,
      'night_binge' => l10n.mpvScenePresetNightBingeDescription,
      'headphone_immersive' => l10n.mpvScenePresetHeadphoneImmersiveDescription,
      _ => fallback,
    };
  }

  static String sceneRecommendationTitle(AppLocalizations l10n, String id) {
    return switch (id) {
      'stable_clear' => l10n.mpvSceneRecommendationStableTitle,
      'headphone_immersive' => l10n.mpvSceneRecommendationImmersiveTitle,
      'speaker_clear' => l10n.mpvSceneRecommendationSpeakerTitle,
      _ => l10n.mpvSceneRecommendationBalancedTitle,
    };
  }

  static String sceneRecommendationReason(AppLocalizations l10n, String id) {
    return switch (id) {
      'stable_clear' => l10n.mpvSceneRecommendationStableReason,
      'headphone_immersive' => l10n.mpvSceneRecommendationImmersiveReason,
      'speaker_clear' => l10n.mpvSceneRecommendationSpeakerReason,
      _ => l10n.mpvSceneRecommendationBalancedReason,
    };
  }

  static String videoAdjustmentTitle(AppLocalizations l10n, String key) {
    return switch (key) {
      MpvSettingsCatalog.brightnessKey => l10n.mpvVideoAdjustBrightnessTitle,
      MpvSettingsCatalog.contrastKey => l10n.mpvVideoAdjustContrastTitle,
      MpvSettingsCatalog.saturationKey => l10n.mpvVideoAdjustSaturationTitle,
      MpvSettingsCatalog.gammaKey => l10n.mpvVideoAdjustGammaTitle,
      MpvSettingsCatalog.hueKey => l10n.mpvVideoAdjustHueTitle,
      _ => l10n.mpvVideoAdjustGenericTitle,
    };
  }

  static String videoAdjustmentSubtitle(AppLocalizations l10n, String key) {
    return switch (key) {
      MpvSettingsCatalog.brightnessKey => l10n.mpvVideoAdjustBrightnessSubtitle,
      MpvSettingsCatalog.contrastKey => l10n.mpvVideoAdjustContrastSubtitle,
      MpvSettingsCatalog.saturationKey => l10n.mpvVideoAdjustSaturationSubtitle,
      MpvSettingsCatalog.gammaKey => l10n.mpvVideoAdjustGammaSubtitle,
      MpvSettingsCatalog.hueKey => l10n.mpvVideoAdjustHueSubtitle,
      _ => '',
    };
  }

  static List<MpvSettingDefinition> definitions(AppLocalizations l10n) =>
      MpvSettingsCatalog.definitions
          .map((definition) => definitionText(l10n, definition))
          .toList(growable: false);

  static List<MpvSettingCategory> categories(AppLocalizations l10n) =>
      MpvSettingsCatalog.categories
          .map((category) => categoryText(l10n, category))
          .toList(growable: false);

  static MpvSettingCategory categoryText(
    AppLocalizations l10n,
    MpvSettingCategory category,
  ) {
    return MpvSettingCategory(
      id: category.id,
      title: categoryTitle(l10n, category.id, fallback: category.title),
      subtitle: categorySubtitle(
        l10n,
        category.id,
        fallback: category.subtitle,
      ),
      description: categoryDescription(
        l10n,
        category.id,
        fallback: category.description,
      ),
      entries: category.entries
          .map((entry) {
            final definition = definitionByKey(l10n, entry.key);
            if (definition == null) return entry;
            return MpvSettingCategoryEntry(
              key: entry.key,
              title: definition.title,
              subtitle: definition.description,
            );
          })
          .toList(growable: false),
    );
  }

  static String categorySummaryLabel(
    AppLocalizations l10n,
    MpvSettingCategory category,
    Map<String, String> settings,
  ) {
    final changedEntries = category.entries
        .where((entry) {
          final fallback = MpvSettingsCatalog.defaults[entry.key];
          return fallback != null &&
              MpvSettingsCatalog.settingValue(entry.key, settings) != fallback;
        })
        .toList(growable: false);
    if (changedEntries.isEmpty) return l10n.mpvDefault;
    if (changedEntries.length == 1) {
      return labelForSetting(l10n, changedEntries.first.key, settings);
    }
    return changedCount(l10n, changedEntries.length);
  }

  static MpvSettingDefinition? definitionByKey(
    AppLocalizations l10n,
    String key,
  ) {
    final definition = MpvSettingsCatalog.definitionByKey(key);
    if (definition == null) return null;
    return definitionText(l10n, definition);
  }

  static MpvSettingDefinition definitionText(
    AppLocalizations l10n,
    MpvSettingDefinition definition,
  ) {
    return MpvSettingDefinition(
      key: definition.key,
      title: settingTitle(l10n, definition.key, fallback: definition.title),
      shortTitle: settingShortTitle(
        l10n,
        definition.key,
        fallback: definition.shortTitle,
      ),
      description: settingDescription(
        l10n,
        definition.key,
        fallback: definition.description,
      ),
      helperLabel: settingTitle(
        l10n,
        definition.key,
        fallback: definition.helperLabel,
      ),
      options: definition.options
          .map((option) => optionText(l10n, definition.key, option))
          .toList(growable: false),
    );
  }

  static MpvSettingOption optionText(
    AppLocalizations l10n,
    String key,
    MpvSettingOption option,
  ) {
    return MpvSettingOption(
      value: option.value,
      label: optionLabelForSetting(
        l10n,
        key,
        option.value,
        fallback: option.label,
      ),
      description: option.description,
    );
  }

  static String labelForSetting(
    AppLocalizations l10n,
    String key,
    Map<String, String> settings,
  ) {
    final value = MpvSettingsCatalog.settingValue(key, settings);
    if (key == MpvSettingsCatalog.cacheSizeMbKey) {
      return value == 'auto'
          ? l10n.mpvOptionAuto
          : MpvSettingsCatalog.formatCacheSizeLabel(value);
    }
    return optionLabelForSetting(l10n, key, value, fallback: value);
  }

  static String optionLabelForSetting(
    AppLocalizations l10n,
    String key,
    String value, {
    required String fallback,
  }) {
    if (key == MpvSettingsCatalog.compatibilityKey && value == 'default') {
      return l10n.mpvDefault;
    }
    return optionLabel(l10n, value, fallback: fallback);
  }

  static MpvPerformanceImpactWarning? performanceWarningForSelection(
    AppLocalizations l10n,
    String key,
    String value,
  ) {
    final warning = MpvSettingsCatalog.performanceWarningForSelection(
      key,
      value,
    );
    if (warning == null) return null;
    return MpvPerformanceImpactWarning(
      title: l10n.mpvPerformanceWarningTitle,
      message: performanceWarningMessage(l10n, key, value),
    );
  }

  static String performanceWarningMessage(
    AppLocalizations l10n,
    String key,
    String value,
  ) {
    return switch (key) {
      MpvSettingsCatalog.debandKey when value == 'medium' =>
        l10n.mpvPerformanceWarningDebandMedium,
      MpvSettingsCatalog.sharpenKey => l10n.mpvPerformanceWarningSharpen,
      MpvSettingsCatalog.denoiseKey => l10n.mpvPerformanceWarningDenoise,
      MpvSettingsCatalog.deinterlaceKey when value == 'force' =>
        l10n.mpvPerformanceWarningDeinterlaceForce,
      MpvSettingsCatalog.scaleProfileKey when value == 'quality' =>
        l10n.mpvPerformanceWarningScaleQuality,
      MpvSettingsCatalog.hdrModeKey => l10n.mpvPerformanceWarningHdr,
      MpvSettingsCatalog.frameInterpolationKey =>
        l10n.mpvPerformanceWarningFrameInterpolation,
      MpvSettingsCatalog.videoSyncKey when value == 'smooth' =>
        l10n.mpvPerformanceWarningVideoSyncSmooth,
      MpvSettingsCatalog.cacheProfileKey when value == 'network' =>
        l10n.mpvPerformanceWarningCacheNetwork,
      MpvSettingsCatalog.cacheSizeMbKey => l10n.mpvPerformanceWarningCacheSize,
      _ => l10n.mpvPerformanceWarningGeneric,
    };
  }

  static String settingTitle(
    AppLocalizations l10n,
    String key, {
    required String fallback,
  }) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => l10n.mpvSettingDebandTitle,
      MpvSettingsCatalog.sharpenKey => l10n.mpvSettingSharpenTitle,
      MpvSettingsCatalog.denoiseKey => l10n.mpvSettingDenoiseTitle,
      MpvSettingsCatalog.deinterlaceKey => l10n.mpvSettingDeinterlaceTitle,
      MpvSettingsCatalog.scaleProfileKey => l10n.mpvSettingScaleProfileTitle,
      MpvSettingsCatalog.hdrModeKey => l10n.mpvSettingHdrModeTitle,
      MpvSettingsCatalog.frameInterpolationKey =>
        l10n.mpvSettingFrameInterpolationTitle,
      MpvSettingsCatalog.videoSyncKey => l10n.mpvSettingVideoSyncTitle,
      MpvSettingsCatalog.cacheProfileKey => l10n.mpvSettingCacheProfileTitle,
      MpvSettingsCatalog.cacheSizeMbKey => l10n.mpvSettingCacheSizeTitle,
      MpvSettingsCatalog.volumeGainKey => l10n.mpvSettingVolumeGainTitle,
      MpvSettingsCatalog.audioHighFidelityKey =>
        l10n.mpvSettingAudioHighFidelityTitle,
      MpvSettingsCatalog.dynamicRangeKey => l10n.mpvSettingDynamicRangeTitle,
      MpvSettingsCatalog.audioEqKey => l10n.mpvSettingAudioEqTitle,
      MpvSettingsCatalog.audioLimiterKey => l10n.mpvSettingAudioLimiterTitle,
      MpvSettingsCatalog.audioBassBoostKey =>
        l10n.mpvSettingAudioBassBoostTitle,
      MpvSettingsCatalog.audioVoiceEnhanceKey =>
        l10n.mpvSettingAudioVoiceEnhanceTitle,
      MpvSettingsCatalog.channelMixKey => l10n.mpvSettingChannelMixTitle,
      MpvSettingsCatalog.compatibilityKey => l10n.mpvSettingCompatibilityTitle,
      _ => fallback,
    };
  }

  static String categoryTitle(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      MpvSettingsCatalog.videoFiltersCategoryId =>
        l10n.mpvVideoFiltersCategoryTitle,
      MpvSettingsCatalog.pictureRenderingCategoryId =>
        l10n.settingsMpvPictureSection,
      MpvSettingsCatalog.playbackSyncCategoryId =>
        l10n.settingsMpvPlaybackSection,
      MpvSettingsCatalog.audioProcessingCategoryId =>
        l10n.settingsMpvAudioSection,
      MpvSettingsCatalog.compatibilityCategoryId =>
        l10n.settingsMpvCompatibilitySection,
      _ => fallback,
    };
  }

  static String categorySubtitle(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      MpvSettingsCatalog.videoFiltersCategoryId =>
        l10n.mpvVideoFiltersCategorySubtitle,
      MpvSettingsCatalog.pictureRenderingCategoryId =>
        l10n.mpvPictureCategorySubtitle,
      MpvSettingsCatalog.playbackSyncCategoryId =>
        l10n.mpvPlaybackCategorySubtitle,
      MpvSettingsCatalog.audioProcessingCategoryId =>
        l10n.mpvAudioCategorySubtitle,
      MpvSettingsCatalog.compatibilityCategoryId =>
        l10n.mpvCompatibilityCategorySubtitle,
      _ => fallback,
    };
  }

  static String categoryDescription(
    AppLocalizations l10n,
    String id, {
    required String fallback,
  }) {
    return switch (id) {
      MpvSettingsCatalog.videoFiltersCategoryId =>
        l10n.mpvVideoFiltersCategoryDescription,
      MpvSettingsCatalog.pictureRenderingCategoryId =>
        l10n.mpvPictureCategoryDescription,
      MpvSettingsCatalog.playbackSyncCategoryId =>
        l10n.mpvPlaybackCategoryDescription,
      MpvSettingsCatalog.audioProcessingCategoryId =>
        l10n.mpvAudioCategoryDescription,
      MpvSettingsCatalog.compatibilityCategoryId =>
        l10n.mpvCompatibilityCategoryDescription,
      _ => fallback,
    };
  }

  static String settingShortTitle(
    AppLocalizations l10n,
    String key, {
    required String fallback,
  }) {
    return switch (key) {
      MpvSettingsCatalog.scaleProfileKey => l10n.mpvSettingScaleProfileTitle,
      MpvSettingsCatalog.cacheProfileKey => l10n.mpvSettingCacheProfileTitle,
      MpvSettingsCatalog.cacheSizeMbKey => l10n.mpvSettingCacheSizeTitle,
      MpvSettingsCatalog.audioHighFidelityKey =>
        l10n.mpvSettingAudioHighFidelityTitle,
      MpvSettingsCatalog.dynamicRangeKey => l10n.mpvSettingDynamicRangeTitle,
      MpvSettingsCatalog.audioLimiterKey => l10n.mpvSettingAudioLimiterTitle,
      MpvSettingsCatalog.audioBassBoostKey =>
        l10n.mpvSettingAudioBassBoostTitle,
      MpvSettingsCatalog.audioVoiceEnhanceKey =>
        l10n.mpvSettingAudioVoiceEnhanceTitle,
      _ => settingTitle(l10n, key, fallback: fallback),
    };
  }

  static String settingDescription(
    AppLocalizations l10n,
    String key, {
    required String fallback,
  }) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => l10n.mpvSettingDebandSubtitle,
      MpvSettingsCatalog.sharpenKey => l10n.mpvSettingSharpenSubtitle,
      MpvSettingsCatalog.denoiseKey => l10n.mpvSettingDenoiseSubtitle,
      MpvSettingsCatalog.deinterlaceKey => l10n.mpvSettingDeinterlaceSubtitle,
      MpvSettingsCatalog.scaleProfileKey => l10n.mpvSettingScaleProfileSubtitle,
      MpvSettingsCatalog.hdrModeKey => l10n.mpvSettingHdrModeSubtitle,
      MpvSettingsCatalog.frameInterpolationKey =>
        l10n.mpvSettingFrameInterpolationSubtitle,
      MpvSettingsCatalog.videoSyncKey => l10n.mpvSettingVideoSyncSubtitle,
      MpvSettingsCatalog.cacheProfileKey => l10n.mpvSettingCacheProfileSubtitle,
      MpvSettingsCatalog.cacheSizeMbKey => l10n.mpvSettingCacheSizeSubtitle,
      MpvSettingsCatalog.volumeGainKey => l10n.mpvSettingVolumeGainSubtitle,
      MpvSettingsCatalog.audioHighFidelityKey =>
        l10n.mpvSettingAudioHighFidelitySubtitle,
      MpvSettingsCatalog.dynamicRangeKey => l10n.mpvSettingDynamicRangeSubtitle,
      MpvSettingsCatalog.audioEqKey => l10n.mpvSettingAudioEqSubtitle,
      MpvSettingsCatalog.audioLimiterKey => l10n.mpvSettingAudioLimiterSubtitle,
      MpvSettingsCatalog.audioBassBoostKey =>
        l10n.mpvSettingAudioBassBoostSubtitle,
      MpvSettingsCatalog.audioVoiceEnhanceKey =>
        l10n.mpvSettingAudioVoiceEnhanceSubtitle,
      MpvSettingsCatalog.channelMixKey => l10n.mpvSettingChannelMixSubtitle,
      MpvSettingsCatalog.compatibilityKey =>
        l10n.mpvSettingCompatibilitySubtitle,
      _ => fallback,
    };
  }

  static String optionLabel(
    AppLocalizations l10n,
    String value, {
    required String fallback,
  }) {
    return switch (value) {
      'off' => l10n.mpvOptionOff,
      'on' => l10n.mpvOptionOn,
      'auto' => l10n.mpvOptionAuto,
      'low' => l10n.mpvOptionLow,
      'medium' => l10n.mpvOptionMedium,
      'strong' => l10n.mpvOptionStrong,
      'fast' => l10n.mpvOptionFast,
      'balanced' => l10n.mpvOptionBalanced,
      'quality' => l10n.mpvOptionQuality,
      'force' => l10n.mpvOptionForce,
      'sdr_map' => l10n.mpvOptionSdrMap,
      'conservative' => l10n.mpvOptionConservative,
      'enhanced' => l10n.mpvOptionEnhanced,
      'audio' => l10n.mpvOptionAudio,
      'display' => l10n.mpvOptionDisplay,
      'smooth' => l10n.mpvOptionSmooth,
      'default' => l10n.mpvOptionDefault,
      'low_latency' => l10n.mpvOptionLowLatency,
      'stable' => l10n.mpvOptionStable,
      'network' => l10n.mpvOptionNetwork,
      'light' => l10n.mpvOptionLight,
      'soft' => l10n.mpvOptionSoft,
      'clarity' => l10n.mpvOptionClarity,
      'cinema' => l10n.mpvOptionCinema,
      MpvSettingsCatalog.audioEqCustomValue => l10n.mpvOptionCustom,
      'stereo' => l10n.mpvOptionStereo,
      'surround' => l10n.mpvOptionSurround,
      'software_fallback' => l10n.mpvOptionSoftwareFallback,
      _ => fallback,
    };
  }
}
