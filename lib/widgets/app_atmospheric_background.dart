import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

@immutable
class AppAtmospherePalette {
  const AppAtmospherePalette({
    required this.base,
    required this.accentGlow,
    required this.selectionGlow,
    required this.linkGlow,
    required this.hasDynamicTheme,
  });

  final Color base;
  final Color accentGlow;
  final Color selectionGlow;
  final Color linkGlow;
  final bool hasDynamicTheme;

  factory AppAtmospherePalette.resolve({
    required AppThemeColors baseColors,
    required AppThemeColors effectiveColors,
    required bool hasDynamicTheme,
  }) {
    final isLight = baseColors.backgroundBase.computeLuminance() >= .58;
    if (!hasDynamicTheme) {
      return AppAtmospherePalette(
        base: baseColors.backgroundBase,
        accentGlow: baseColors.accent.withValues(alpha: isLight ? .08 : .15),
        selectionGlow: baseColors.selection.withValues(
          alpha: isLight ? .06 : .11,
        ),
        linkGlow: baseColors.link.withValues(alpha: isLight ? .05 : .08),
        hasDynamicTheme: false,
      );
    }

    return AppAtmospherePalette(
      base: Color.alphaBlend(
        effectiveColors.backgroundBase.withValues(alpha: isLight ? .06 : .10),
        baseColors.backgroundBase,
      ),
      accentGlow: effectiveColors.accent.withValues(alpha: isLight ? .16 : .30),
      selectionGlow: effectiveColors.selection.withValues(
        alpha: isLight ? .13 : .24,
      ),
      linkGlow: effectiveColors.link.withValues(alpha: isLight ? .10 : .18),
      hasDynamicTheme: true,
    );
  }
}

/// 以中性底承载主题和动态取色的多层氛围背景。
class AppAtmosphericBackground extends StatelessWidget {
  const AppAtmosphericBackground({
    super.key,
    required this.palette,
    required this.child,
  });

  final AppAtmospherePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            key: const ValueKey<String>('app-atmosphere-static-layer'),
            child: ColoredBox(
              key: const ValueKey<String>('app-atmosphere-base'),
              color: palette.base,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _AtmosphereGlow(
                    glowKey: const ValueKey<String>('app-atmosphere-accent'),
                    color: palette.accentGlow,
                    center: const Alignment(-1.02, -.92),
                    radius: .92,
                  ),
                  _AtmosphereGlow(
                    glowKey: const ValueKey<String>('app-atmosphere-selection'),
                    color: palette.selectionGlow,
                    center: const Alignment(1.04, -.16),
                    radius: .96,
                  ),
                  _AtmosphereGlow(
                    glowKey: const ValueKey<String>('app-atmosphere-link'),
                    color: palette.linkGlow,
                    center: const Alignment(-.72, .74),
                    radius: 1.02,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey<String>('app-atmosphere-vignette'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              palette.base.withValues(alpha: .06),
                              palette.base.withValues(alpha: .32),
                            ],
                            stops: const <double>[0, .64, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 图标按钮使用的协调色组，避免把高饱和取色直接铺到边框和图标。
@immutable
class AppTonalControlPalette {
  const AppTonalControlPalette({
    required this.fill,
    required this.border,
    required this.foreground,
  });

  final Color fill;
  final Color border;
  final Color foreground;

  factory AppTonalControlPalette.resolve({
    required AppThemeColors colors,
    required bool active,
  }) {
    if (!active) {
      return AppTonalControlPalette(
        fill: colors.surfaceSubtle,
        border: colors.borderSubtle,
        foreground: colors.textSecondary,
      );
    }
    return AppTonalControlPalette(
      fill: Color.alphaBlend(
        colors.selection.withValues(alpha: .14),
        colors.surface,
      ),
      border: Color.alphaBlend(
        colors.selection.withValues(alpha: .30),
        colors.borderStrong,
      ),
      foreground: Color.lerp(colors.textPrimary, colors.selection, .34)!,
    );
  }
}

class _AtmosphereGlow extends StatelessWidget {
  const _AtmosphereGlow({
    required this.glowKey,
    required this.color,
    required this.center,
    required this.radius,
  });

  final Key glowKey;
  final Color color;
  final Alignment center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          key: glowKey,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: center,
              radius: radius,
              colors: <Color>[color, Colors.transparent],
              stops: const <double>[0, 1],
            ),
          ),
        ),
      ),
    );
  }
}
