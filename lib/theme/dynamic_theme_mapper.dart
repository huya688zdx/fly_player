import 'dart:collection';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'dynamic_theme_seed_extractor.dart';

class DynamicThemeMapper {
  const DynamicThemeMapper._();

  // Cache [ColorScheme.fromSeed] results — the same (seedColor, brightness,
  // variant, contrastLevel) tuple produces the identical scheme every time.
  static final LinkedHashMap<int, ColorScheme> _schemeCache =
      LinkedHashMap<int, ColorScheme>();
  static const int _schemeCacheMaxSize = 16;

  static ColorScheme _schemeFromSeed({
    required Color seedColor,
    required Brightness brightness,
    required DynamicSchemeVariant variant,
    required double contrastLevel,
  }) {
    final key = Object.hash(
      seedColor.toARGB32(),
      brightness.index,
      variant.index,
      (contrastLevel * 100).round(),
    );
    final cached = _schemeCache.remove(key);
    if (cached != null) {
      _schemeCache[key] = cached;
      return cached;
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: variant,
      contrastLevel: contrastLevel,
    );
    if (_schemeCache.length >= _schemeCacheMaxSize) {
      _schemeCache.remove(_schemeCache.keys.first);
    }
    _schemeCache[key] = scheme;
    return scheme;
  }

  static AppThemeColors mapSubtle({
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
  }) {
    final brightness = _brightnessFor(baseColors);
    final scheme = _schemeFromSeed(
      seedColor: seed.accentSeed,
      brightness: brightness,
      variant: DynamicSchemeVariant.tonalSpot,
      contrastLevel: -0.15,
    );
    final isLight = brightness == Brightness.light;
    return baseColors.copyWith(
      surfaceStrong: _toneSurface(
        baseColors.surfaceStrong,
        tint: scheme.primaryContainer,
        alpha: isLight ? 0.08 : 0.12,
      ),
      borderSubtle: _toneSurface(
        baseColors.borderSubtle,
        tint: scheme.outlineVariant,
        alpha: isLight ? 0.18 : 0.24,
      ),
      borderStrong: _toneSurface(
        baseColors.borderStrong,
        tint: scheme.outline,
        alpha: isLight ? 0.22 : 0.30,
      ),
      accent: scheme.primary,
      accentSoft: _toneSurface(
        baseColors.accentSoft,
        tint: scheme.primaryContainer,
        alpha: isLight ? 0.16 : 0.20,
      ),
      accentStrong: scheme.primary,
      selection: scheme.secondary,
      selectionSoft: _toneSurface(
        baseColors.selectionSoft,
        tint: scheme.secondaryContainer,
        alpha: isLight ? 0.14 : 0.18,
      ),
      selectionStrong: scheme.secondary,
      link: scheme.tertiary,
      chipBackground: _toneSurface(
        baseColors.chipBackground,
        tint: scheme.tertiaryContainer,
        alpha: isLight ? 0.14 : 0.18,
      ),
      chipBorder: _toneSurface(
        baseColors.chipBorder,
        tint: scheme.outlineVariant,
        alpha: isLight ? 0.18 : 0.22,
      ),
      chipText: isLight ? scheme.onTertiaryContainer : baseColors.chipText,
      overlayScrim: _toneSurface(
        baseColors.overlayScrim,
        tint: scheme.scrim,
        alpha: isLight ? 0.06 : 0.10,
      ),
    );
  }

  static AppThemeColors map({
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
    required AppDynamicThemeIntensity intensity,
  }) {
    final brightness = _brightnessFor(baseColors);
    final backdropColors = _baseSurfacesFor(seed, brightness: brightness);
    final scheme = _schemeFromSeed(
      seedColor: seed.accentSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    final backdropScheme = _schemeFromSeed(
      seedColor: seed.backgroundSeed,
      brightness: brightness,
      variant: DynamicSchemeVariant.tonalSpot,
      contrastLevel: -0.05,
    );

    final isLight = brightness == Brightness.light;
    final backgroundTintAlpha = isLight ? 0.04 : 0.10;
    final elevatedTintAlpha = isLight ? 0.06 : 0.12;
    final surfaceTintAlpha = isLight ? 0.08 : 0.14;
    final subtleSurfaceTintAlpha = isLight ? 0.06 : 0.12;
    final strongSurfaceTintAlpha = isLight ? 0.12 : 0.18;
    final navBlendAlpha = isLight ? 0.04 : 0.08;
    final borderSubtleAlpha = isLight ? 0.22 : 0.28;
    final borderStrongAlpha = isLight ? 0.30 : 0.38;

    return backdropColors.copyWith(
      backgroundBase: _toneSurface(
        backdropColors.backgroundBase,
        tint: backdropScheme.primary,
        alpha: backgroundTintAlpha,
      ),
      backgroundElevated: _toneSurface(
        backdropColors.backgroundElevated,
        tint: backdropScheme.primaryContainer,
        alpha: elevatedTintAlpha,
      ),
      surface: _toneSurface(
        backdropColors.surface,
        tint: backdropScheme.secondaryContainer,
        alpha: surfaceTintAlpha,
      ),
      surfaceSubtle: _toneSurface(
        backdropColors.surfaceSubtle,
        tint: backdropScheme.tertiaryContainer,
        alpha: subtleSurfaceTintAlpha,
      ),
      surfaceStrong: _toneSurface(
        backdropColors.surfaceStrong,
        tint: scheme.primaryContainer,
        alpha: strongSurfaceTintAlpha,
      ),
      navBarBackground: _toneSurface(
        backdropColors.navBarBackground,
        tint: backdropScheme.primary,
        alpha: navBlendAlpha,
      ),
      borderSubtle: _toneSurface(
        backdropColors.borderSubtle,
        tint: backdropScheme.outlineVariant,
        alpha: borderSubtleAlpha,
      ),
      borderStrong: _toneSurface(
        backdropColors.borderStrong,
        tint: backdropScheme.outline,
        alpha: borderStrongAlpha,
      ),
      accent: scheme.primary,
      accentSoft: _toneSurface(
        backdropColors.accentSoft,
        tint: scheme.primaryContainer,
        alpha: isLight ? 0.24 : 0.28,
      ),
      accentStrong: scheme.primary,
      selection: scheme.secondary,
      selectionSoft: _toneSurface(
        backdropColors.selectionSoft,
        tint: scheme.secondaryContainer,
        alpha: isLight ? 0.20 : 0.24,
      ),
      selectionStrong: scheme.secondary,
      link: scheme.tertiary,
      chipBackground: _toneSurface(
        backdropColors.chipBackground,
        tint: scheme.tertiaryContainer,
        alpha: isLight ? 0.20 : 0.22,
      ),
      chipBorder: _toneSurface(
        backdropColors.chipBorder,
        tint: backdropScheme.outlineVariant,
        alpha: borderSubtleAlpha,
      ),
      chipText: scheme.onTertiaryContainer,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textMuted: scheme.onSurfaceVariant.withValues(
        alpha: isLight ? 0.76 : 0.84,
      ),
      overlayScrim: scheme.scrim.withValues(alpha: isLight ? 0.30 : 0.68),
    );
  }

  static Color ambientTint({
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
    required AppDynamicThemeIntensity intensity,
  }) {
    final brightness = _brightnessFor(baseColors);
    final scheme = _schemeFromSeed(
      seedColor: seed.accentSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    final isLight = brightness == Brightness.light;
    return (isLight ? scheme.primaryContainer : scheme.primary).withValues(
      alpha: isLight ? 0.34 : 0.28,
    );
  }

  static DynamicSchemeVariant _variantFor(AppDynamicThemeIntensity intensity) {
    return switch (intensity) {
      AppDynamicThemeIntensity.subtle => DynamicSchemeVariant.tonalSpot,
      AppDynamicThemeIntensity.medium => DynamicSchemeVariant.content,
      AppDynamicThemeIntensity.vivid => DynamicSchemeVariant.fidelity,
    };
  }

  static double _contrastLevelFor(AppDynamicThemeIntensity intensity) {
    return switch (intensity) {
      AppDynamicThemeIntensity.subtle => -0.15,
      AppDynamicThemeIntensity.medium => 0.0,
      AppDynamicThemeIntensity.vivid => 0.12,
    };
  }

  static Brightness _brightnessFor(AppThemeColors baseColors) {
    return baseColors.backgroundBase.computeLuminance() >= 0.58
        ? Brightness.light
        : Brightness.dark;
  }

  static AppThemeColors _baseSurfacesFor(
    DynamicThemeSeed seed, {
    required Brightness brightness,
  }) {
    final neutralColors = AppThemePalette.neutralForBrightness(brightness);
    final source = HSLColor.fromColor(seed.backgroundSeed);
    final isLight = brightness == Brightness.light;
    final saturation = isLight
        ? (source.saturation * 0.34).clamp(0.04, 0.16)
        : (source.saturation * 0.52).clamp(0.08, 0.26);
    final toned = source.withSaturation(saturation);

    Color tone(double lightness) => toned.withLightness(lightness).toColor();

    if (isLight) {
      final baseLightness = source.lightness.clamp(0.76, 0.90);
      return neutralColors.copyWith(
        backgroundBase: tone((baseLightness + 0.06).clamp(0.84, 0.94)),
        backgroundElevated: tone((baseLightness + 0.03).clamp(0.82, 0.92)),
        surface: tone((baseLightness + 0.09).clamp(0.88, 0.97)),
        surfaceSubtle: tone((baseLightness + 0.05).clamp(0.84, 0.93)),
        surfaceStrong: tone((baseLightness - 0.02).clamp(0.76, 0.88)),
        navBarBackground: tone((baseLightness + 0.01).clamp(0.81, 0.90)),
        chipBackground: tone((baseLightness + 0.02).clamp(0.82, 0.91)),
      );
    }

    final baseLightness = source.lightness.clamp(0.16, 0.38);
    return neutralColors.copyWith(
      backgroundBase: tone((baseLightness - 0.06).clamp(0.10, 0.24)),
      backgroundElevated: tone((baseLightness - 0.01).clamp(0.13, 0.28)),
      surface: tone((baseLightness + 0.03).clamp(0.16, 0.32)),
      surfaceSubtle: tone((baseLightness + 0.06).clamp(0.19, 0.36)),
      surfaceStrong: tone((baseLightness + 0.10).clamp(0.23, 0.42)),
      navBarBackground: tone((baseLightness - 0.02).clamp(0.12, 0.26)),
      chipBackground: tone((baseLightness + 0.04).clamp(0.18, 0.34)),
    );
  }

  static Color _toneSurface(
    Color base, {
    required Color tint,
    required double alpha,
  }) {
    return Color.alphaBlend(tint.withValues(alpha: alpha), base);
  }
}
