import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 弹层统一表面：使用当前页面的动态取色语义色做低饱和晕染，避免纯色大面板。
class AppModalSurface extends StatelessWidget {
  final Widget child;
  final bool floating;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const AppModalSurface({
    super.key,
    required this.child,
    this.floating = false,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = colors.backgroundBase.computeLuminance() >= 0.58;
    final radius =
        borderRadius ??
        BorderRadius.vertical(
          top: const Radius.circular(26),
          bottom: Radius.circular(floating ? 26 : 0),
        );
    final topTint = Color.alphaBlend(
      colors.accent.withValues(alpha: isLight ? 0.08 : 0.12),
      colors.backgroundElevated,
    );
    final middleTint = Color.alphaBlend(
      colors.selection.withValues(alpha: isLight ? 0.045 : 0.075),
      colors.surface,
    );
    final bottomTint = Color.alphaBlend(
      colors.accentSoft.withValues(alpha: isLight ? 0.035 : 0.055),
      colors.backgroundElevated,
    );
    final outline = Color.alphaBlend(
      colors.accent.withValues(alpha: isLight ? 0.16 : 0.24),
      colors.borderSubtle,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const <double>[0, 0.52, 1],
          colors: <Color>[topTint, middleTint, bottomTint],
        ),
        border: Border.all(color: outline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.32),
            blurRadius: 28,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

Color appModalTileColor(
  AppThemeColors colors, {
  bool selected = false,
  bool stronger = false,
}) {
  final base = stronger ? colors.surfaceStrong : colors.surfaceSubtle;
  return Color.alphaBlend(
    colors.accent.withValues(alpha: selected ? 0.16 : 0.055),
    base,
  );
}

Color appModalTileBorderColor(AppThemeColors colors, {bool selected = false}) {
  return Color.alphaBlend(
    colors.accent.withValues(alpha: selected ? 0.42 : 0.14),
    colors.borderSubtle,
  );
}
