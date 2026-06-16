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
        colors.surface.withValues(alpha: 0.96),
        colors.backgroundElevated,
      ),
      panelBorder: colors.borderSubtle,
      handleColor: colors.borderStrong,
      titleColor: colors.textPrimary,
      subtitleColor: colors.textSecondary,
      mutedTextColor: colors.textMuted,
      qualityValueColor: colors.textPrimary,
      qualityIconColor: colors.textSecondary,
      cardBackground: Color.alphaBlend(
        colors.surfaceStrong.withValues(alpha: 0.22),
        colors.surface,
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

// 上一次构造的 (colors, theme) 缓存。`downloadSheetTheme` 在下载弹窗里被每个子 widget
// （行/海报/tab/清晰度 tile）各调一次，30 行可达 60+ 次；`fromColors` 是 ~22 次颜色运算
// （含 estimateBrightnessForColor），不缓存会全压在弹窗首帧。同一帧内 appColors 返回同一
// identical 对象，故按 identical 命中即可把 60+ 次重算降为 1 次。UI 单线程，无并发风险。
AppThemeColors? _cachedDownloadSheetColors;
DownloadSheetThemeData? _cachedDownloadSheetTheme;

extension DownloadSheetThemeBuildContextX on BuildContext {
  DownloadSheetThemeData get downloadSheetTheme {
    final colors = appColors;
    if (_cachedDownloadSheetTheme == null ||
        !identical(_cachedDownloadSheetColors, colors)) {
      _cachedDownloadSheetColors = colors;
      _cachedDownloadSheetTheme = DownloadSheetThemeData.fromColors(colors);
    }
    return _cachedDownloadSheetTheme!;
  }
}
