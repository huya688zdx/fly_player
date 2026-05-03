import '../l10n/generated/app_localizations.dart';
import '../providers/app_theme_provider.dart';
import 'app_theme.dart';

class AppThemeL10n {
  const AppThemeL10n._();

  static String presetSubtitle(
    AppLocalizations l10n,
    AppThemePreset preset,
  ) {
    return switch (preset) {
      AppThemePreset.midnight => l10n.themePresetMidnightSubtitle,
      AppThemePreset.ocean => l10n.themePresetOceanSubtitle,
      AppThemePreset.forest => l10n.themePresetForestSubtitle,
      AppThemePreset.graphite => l10n.themePresetGraphiteSubtitle,
      AppThemePreset.sunset => l10n.themePresetSunsetSubtitle,
      AppThemePreset.aurora => l10n.themePresetAuroraSubtitle,
      AppThemePreset.latte => l10n.themePresetLatteSubtitle,
    };
  }

  static String accentToneTitle(
    AppLocalizations l10n,
    AppAccentTone tone,
  ) {
    return switch (tone) {
      AppAccentTone.blue => l10n.themeAccentBlue,
      AppAccentTone.cyan => l10n.themeAccentCyan,
      AppAccentTone.green => l10n.themeAccentGreen,
      AppAccentTone.amber => l10n.themeAccentAmber,
      AppAccentTone.rose => l10n.themeAccentRose,
      AppAccentTone.coral => l10n.themeAccentCoral,
      AppAccentTone.indigo => l10n.themeAccentIndigo,
      AppAccentTone.mint => l10n.themeAccentMint,
    };
  }

  static String backgroundToneTitle(
    AppLocalizations l10n,
    AppBackgroundTone tone,
  ) {
    return switch (tone) {
      AppBackgroundTone.night => l10n.themeBackgroundNight,
      AppBackgroundTone.slate => l10n.themeBackgroundSlate,
      AppBackgroundTone.ocean => l10n.themeBackgroundOcean,
      AppBackgroundTone.moss => l10n.themeBackgroundMoss,
      AppBackgroundTone.ember => l10n.themeBackgroundEmber,
      AppBackgroundTone.pearl => l10n.themeBackgroundPearl,
      AppBackgroundTone.linen => l10n.themeBackgroundLinen,
      AppBackgroundTone.ivory => l10n.themeBackgroundIvory,
    };
  }

  static String dynamicThemeModeTitle(
    AppLocalizations l10n,
    AppDynamicThemeMode mode,
  ) {
    return switch (mode) {
      AppDynamicThemeMode.off => l10n.themeDynamicModeOff,
      AppDynamicThemeMode.detailsAndPeople => l10n.themeDynamicModeDetailsAndPeople,
    };
  }

  static String dynamicThemeIntensityTitle(
    AppLocalizations l10n,
    AppDynamicThemeIntensity intensity,
  ) {
    return switch (intensity) {
      AppDynamicThemeIntensity.subtle => l10n.themeDynamicIntensitySubtle,
      AppDynamicThemeIntensity.medium => l10n.themeDynamicIntensityMedium,
      AppDynamicThemeIntensity.vivid => l10n.themeDynamicIntensityVivid,
    };
  }

  static String dynamicThemeIntensitySettingsTitle(
    AppLocalizations l10n,
    AppDynamicThemeIntensity intensity,
  ) {
    return switch (intensity) {
      AppDynamicThemeIntensity.subtle => l10n.themeDynamicIntensitySubtle,
      AppDynamicThemeIntensity.medium => l10n.themeDynamicIntensityMedium,
      AppDynamicThemeIntensity.vivid => l10n.themeDynamicIntensityAdvanced,
    };
  }

  static String dynamicThemeBehaviorDescription(
    AppLocalizations l10n,
    AppDynamicThemeIntensity intensity,
  ) {
    return switch (intensity) {
      AppDynamicThemeIntensity.subtle => l10n.themeDynamicBehaviorSubtle,
      AppDynamicThemeIntensity.medium => l10n.themeDynamicBehaviorMedium,
      AppDynamicThemeIntensity.vivid => l10n.themeDynamicBehaviorVivid,
    };
  }

  static String currentThemeTitle(
    AppLocalizations l10n,
    AppThemeProvider provider,
  ) {
    return switch (provider.themeSourceType) {
      AppThemeSourceType.preset => provider.preset.title,
      AppThemeSourceType.currentCustom => l10n.themeCurrentCustomTitle,
      AppThemeSourceType.savedCustomTheme =>
        provider.activeSavedTheme?.name ?? l10n.themeCurrentCustomTitle,
    };
  }

  static String currentThemeSubtitle(
    AppLocalizations l10n,
    AppThemeProvider provider,
  ) {
    return switch (provider.themeSourceType) {
      AppThemeSourceType.preset => presetSubtitle(l10n, provider.preset),
      AppThemeSourceType.currentCustom => l10n.themeCurrentCustomSubtitle,
      AppThemeSourceType.savedCustomTheme =>
        provider.activeSavedTheme?.description.trim().isNotEmpty == true
            ? provider.activeSavedTheme!.description
            : l10n.themeSavedDefaultSubtitle,
    };
  }
}
