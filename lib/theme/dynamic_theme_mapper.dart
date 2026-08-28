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
  // Each sampled page warms two schemes (accent + background), and light/dark
  // brightness double the key space. 96 keeps a full session's browsing depth
  // resident so re-entering a page is a pure cache hit with zero HCT solving
  // (~16ms per cold solve; ColorScheme objects are tiny, memory cost is
  // negligible). The persistent seed cache preloads up to 256 seeds at startup
  // while this scheme cache starts cold — a larger window narrows that gap.
  static const int _schemeCacheMaxSize = 96;

  /// Pre-computes (and caches) the [ColorScheme]s that [map]/[ambientTint] will
  /// need for this seed, so the work happens off the render frame. Calling this
  /// from an idle microtask right after a seed resolves means the subsequent
  /// build that applies the theme hits the cache instead of running the
  /// ~16ms HCT solver inside the frame — which showed up as a dropped frame on
  /// page open in the CPU profile.
  static void warmUp({
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
    required AppDynamicThemeIntensity intensity,
  }) {
    final brightness = _brightnessFor(baseColors);
    _schemeFromSeed(
      seedColor: seed.accentSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    _schemeFromSeed(
      seedColor: seed.selectionSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    _schemeFromSeed(
      seedColor: seed.linkSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    _schemeFromSeed(
      seedColor: seed.backgroundSeed,
      brightness: brightness,
      variant: DynamicSchemeVariant.tonalSpot,
      contrastLevel: -0.05,
    );
  }

  /// True when both schemes [map] needs for this (base, seed, intensity) tuple
  /// are already cached, so [map] will be a pure cache hit with no in-frame HCT
  /// solving. Callers use this to decide whether they can apply the theme
  /// synchronously this frame, or should warm up off-frame first.
  static bool isWarm({
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
    required AppDynamicThemeIntensity intensity,
  }) {
    final brightness = _brightnessFor(baseColors);
    return _isSchemeCached(
          seedColor: seed.accentSeed,
          brightness: brightness,
          variant: _variantFor(intensity),
          contrastLevel: _contrastLevelFor(intensity),
        ) &&
        _isSchemeCached(
          seedColor: seed.selectionSeed,
          brightness: brightness,
          variant: _variantFor(intensity),
          contrastLevel: _contrastLevelFor(intensity),
        ) &&
        _isSchemeCached(
          seedColor: seed.linkSeed,
          brightness: brightness,
          variant: _variantFor(intensity),
          contrastLevel: _contrastLevelFor(intensity),
        ) &&
        _isSchemeCached(
          seedColor: seed.backgroundSeed,
          brightness: brightness,
          variant: DynamicSchemeVariant.tonalSpot,
          contrastLevel: -0.05,
        );
  }

  static bool _isSchemeCached({
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
    return _schemeCache.containsKey(key);
  }

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
    final selectionScheme = _schemeFromSeed(
      seedColor: seed.selectionSeed,
      brightness: brightness,
      variant: DynamicSchemeVariant.tonalSpot,
      contrastLevel: -0.15,
    );
    final linkScheme = _schemeFromSeed(
      seedColor: seed.linkSeed,
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
      selection: selectionScheme.primary,
      selectionSoft: _toneSurface(
        baseColors.selectionSoft,
        tint: selectionScheme.primaryContainer,
        alpha: isLight ? 0.14 : 0.18,
      ),
      selectionStrong: Color.lerp(
        baseColors.textPrimary,
        selectionScheme.primary,
        .46,
      ),
      link: linkScheme.primary,
      chipBackground: _toneSurface(
        baseColors.chipBackground,
        tint: linkScheme.primaryContainer,
        alpha: isLight ? 0.14 : 0.18,
      ),
      chipBorder: _toneSurface(
        baseColors.chipBorder,
        tint: scheme.outlineVariant,
        alpha: isLight ? 0.18 : 0.22,
      ),
      // 徽章会同时出现在正文、列表卡和版本 chip 上，不能跟随海报链接色漂移；
      // 保留基础主题已经校准过的亮暗前景，动态色只负责底色和边框。
      chipText: baseColors.chipText,
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
    // 动态图像只提供氛围和交互色，不再把整套页面底色改成海报主色。
    // 这样首页、收藏、分类和详情页都保持主题本身的中性层级。
    final backdropColors = baseColors;
    final scheme = _schemeFromSeed(
      seedColor: seed.accentSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    final selectionScheme = _schemeFromSeed(
      seedColor: seed.selectionSeed,
      brightness: brightness,
      variant: _variantFor(intensity),
      contrastLevel: _contrastLevelFor(intensity),
    );
    final linkScheme = _schemeFromSeed(
      seedColor: seed.linkSeed,
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
    final backgroundTintAlpha = isLight ? 0.02 : 0.04;
    final elevatedTintAlpha = isLight ? 0.04 : 0.07;
    final surfaceTintAlpha = isLight ? 0.06 : 0.10;
    final subtleSurfaceTintAlpha = isLight ? 0.05 : 0.08;
    final strongSurfaceTintAlpha = isLight ? 0.09 : 0.14;
    final navBlendAlpha = isLight ? 0.03 : 0.05;
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
      selection: selectionScheme.primary,
      selectionSoft: _toneSurface(
        backdropColors.selectionSoft,
        tint: selectionScheme.primaryContainer,
        alpha: isLight ? 0.20 : 0.24,
      ),
      selectionStrong: Color.lerp(
        baseColors.textPrimary,
        selectionScheme.primary,
        .46,
      ),
      link: linkScheme.primary,
      chipBackground: _toneSurface(
        backdropColors.chipBackground,
        tint: linkScheme.primaryContainer,
        alpha: isLight ? 0.20 : 0.22,
      ),
      chipBorder: _toneSurface(
        backdropColors.chipBorder,
        tint: backdropScheme.outlineVariant,
        alpha: borderSubtleAlpha,
      ),
      // 海报取色可能让 onPrimaryContainer 与当前中性表面同亮度，造成规格文字
      // 在亮/暗主题下分别发白或发黑。可读性语义色保持基础主题值。
      chipText: baseColors.chipText,
      textPrimary: Color.lerp(baseColors.textPrimary, scheme.onSurface, .22),
      textSecondary: Color.lerp(
        baseColors.textSecondary,
        scheme.onSurfaceVariant,
        .28,
      ),
      textMuted: Color.lerp(
        baseColors.textMuted,
        scheme.onSurfaceVariant,
        .24,
      )!.withValues(alpha: isLight ? 0.76 : 0.84),
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

  static Color _toneSurface(
    Color base, {
    required Color tint,
    required double alpha,
  }) {
    return Color.alphaBlend(tint.withValues(alpha: alpha), base);
  }
}
