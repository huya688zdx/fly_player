import 'package:flutter/material.dart';

import 'app_theme.dart';

@immutable
class DownloadSheetThemeData {
  final Color barrierColor;
  final Color panelBackground;
  final Color panelBorder;
  final Color handleColor;
  final Color titleColor;
  final Color subtitleColor;
  final Color mutedTextColor;
  final Color qualityValueColor;
  final Color qualityIconColor;
  final Color cardBackground;
  final Color cardBorder;
  final Color badgeBackground;
  final Color badgeTextColor;
  final Color secondaryButtonBackground;
  final Color secondaryButtonForeground;
  final Color optionBorderColor;
  final Color optionSelectedBorderColor;
  final Color optionSelectedBackground;
  final Color optionIndicatorBorderColor;
  final Color optionIndicatorFillColor;
  final Color optionIndicatorIconColor;
  final Color linkColor;

  const DownloadSheetThemeData({
    required this.barrierColor,
    required this.panelBackground,
    required this.panelBorder,
    required this.handleColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.mutedTextColor,
    required this.qualityValueColor,
    required this.qualityIconColor,
    required this.cardBackground,
    required this.cardBorder,
    required this.badgeBackground,
    required this.badgeTextColor,
    required this.secondaryButtonBackground,
    required this.secondaryButtonForeground,
    required this.optionBorderColor,
    required this.optionSelectedBorderColor,
    required this.optionSelectedBackground,
    required this.optionIndicatorBorderColor,
    required this.optionIndicatorFillColor,
    required this.optionIndicatorIconColor,
    required this.linkColor,
  });

  factory DownloadSheetThemeData.fromColors(AppThemeColors colors) {
    return DownloadSheetThemeData(
      barrierColor: colors.overlayScrim.withValues(alpha: 0.56),
      panelBackground: Color.alphaBlend(
        colors.accent.withValues(alpha: 0.085),
        Color.alphaBlend(
          colors.surface.withValues(alpha: 0.96),
          colors.backgroundElevated,
        ),
      ),
      panelBorder: Color.alphaBlend(
        colors.accent.withValues(alpha: 0.18),
        colors.borderSubtle,
      ),
      handleColor: colors.borderStrong,
      titleColor: colors.textPrimary,
      subtitleColor: colors.textSecondary,
      mutedTextColor: colors.textMuted,
      qualityValueColor: colors.textPrimary,
      qualityIconColor: colors.textSecondary,
      cardBackground: Color.alphaBlend(
        colors.accent.withValues(alpha: 0.045),
        Color.alphaBlend(
          colors.surfaceStrong.withValues(alpha: 0.22),
          colors.surface,
        ),
      ),
      cardBorder: colors.borderSubtle,
      badgeBackground: colors.overlayScrim.withValues(alpha: 0.72),
      badgeTextColor: colors.textPrimary,
      secondaryButtonBackground: Color.alphaBlend(
        colors.surfaceStrong.withValues(alpha: 0.78),
        colors.backgroundElevated,
      ),
      secondaryButtonForeground: colors.textPrimary,
      optionBorderColor: colors.borderStrong,
      optionSelectedBorderColor: colors.accent,
      optionSelectedBackground: colors.accentSoft.withValues(alpha: 0.14),
      optionIndicatorBorderColor: colors.borderStrong,
      optionIndicatorFillColor: colors.accent,
      optionIndicatorIconColor:
          ThemeData.estimateBrightnessForColor(colors.accent) ==
              Brightness.light
          ? const Color(0xFF172030)
          : Colors.white,
      linkColor: colors.accent,
    );
  }
}

extension DownloadSheetThemeBuildContextX on BuildContext {
  DownloadSheetThemeData get downloadSheetTheme =>
      DownloadSheetThemeData.fromColors(appColors);
}
