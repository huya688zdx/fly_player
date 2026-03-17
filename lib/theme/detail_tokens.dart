import 'package:flutter/material.dart';

import 'app_theme.dart';

class DetailTokens {
  DetailTokens._();

  static const Color pageBackground = Color(0xFF07101B);
  static const Color panelBackground = Color(0xFF102034);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB8C5D6);
  static const Color textMuted = Color(0xFF8FA2BA);

  static const Color topButtonBackground = Color(0x55111B2A);
  static const Color topButtonBorder = Color(0x446E8DB1);
  static const Color circleButtonBackground = Color(0x2A1B2C45);
  static const Color circleButtonBorder = Color(0x5A6E8DB1);

  static const Color progressTrack = Color(0x222D87FF);
  static const Color progressActive = Color(0xFF2D87FF);

  static const Color primaryButton = Color(0xFF2D87FF);
  static const Color primaryButtonDisabled = Color(0x66385878);

  static const Color chipBackground = Color(0xFF132236);
  static const Color chipBorder = Color(0x29566B88);
  static const Color chipSelectedBorder = Color(0xFF2D87FF);
  static const Color chipText = Color(0xC9DCEBFF);
  static const Color chipSelectedText = Color(0xFF66B1FF);
  static const Color selectorText = Color(0xFFEAF2FF);
  static const Color selectorIcon = Color(0xFFB6C8DE);

  static const double screenHorizontalPadding = 16;
  static const double contentBottomPadding = 24;
  static const double headerExpandedHeight = 300;
  static const double headerMaxBlur = 30;
  static const double headerFadeStart = 0.25;

  static const double topButtonSize = 36;
  static const double topButtonIconSize = 18;
  static const double topButtonRadius = 18;

  static const double circleButtonSize = 56;
  static const double circleButtonIconSize = 22;
  static const double circleButtonRadius = 28;

  static const double playButtonHeight = 56;
  static const double playButtonRadius = 28;
  static const double playButtonIconSize = 20;

  static const double progressHeight = 6;
  static const double progressRadius = 999;
  static const double chipHeight = 32;
  static const double compactChipHeight = 18;
  static const double compactBadgeHeight = 14;
  static const double titleFontSize = 24;
  static const double metaFontSize = 14;
  static const double remainFontSize = 13;
  static const double playTextFontSize = 15;
  static const double selectorFontSize = 12;
  static const double selectorArrowSize = 14;

  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(9));
  static const BorderRadius compactChipRadius = BorderRadius.all(
    Radius.circular(4),
  );
  static const BorderRadius playButtonBorderRadius = BorderRadius.all(
    Radius.circular(playButtonRadius),
  );
  static const BorderRadius glassPanelRadius = BorderRadius.vertical(
    top: Radius.circular(24),
  );

  static const EdgeInsets pageContentPadding = EdgeInsets.fromLTRB(
    screenHorizontalPadding,
    6,
    screenHorizontalPadding,
    contentBottomPadding,
  );

  static const LinearGradient heroOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x10000000), Color(0x4D000000), Color(0xCC07101B)],
    stops: [0.0, 0.6, 1.0],
  );

  static const LinearGradient glassPanelGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59223550), Color(0xCC07101B), Color(0xEE07101B)],
    stops: [0.0, 0.56, 1.0],
  );

  static Color pageBackgroundOf(BuildContext context) {
    return context.appColors.backgroundBase;
  }

  static Color panelBackgroundOf(BuildContext context) {
    return context.appColors.surface;
  }

  static Color topButtonBackgroundOf(BuildContext context) {
    final colors = context.appColors;
    return Color.alphaBlend(
      colors.surfaceSubtle.withValues(alpha: 0.74),
      colors.overlayScrim.withValues(alpha: 0.42),
    );
  }

  static Color topButtonBorderOf(BuildContext context) {
    return context.appColors.borderStrong;
  }

  static Color circleButtonBackgroundOf(BuildContext context) {
    final colors = context.appColors;
    return Color.alphaBlend(
      colors.surface.withValues(alpha: 0.62),
      colors.overlayScrim.withValues(alpha: 0.18),
    );
  }

  static Color circleButtonBorderOf(BuildContext context) {
    return context.appColors.borderStrong;
  }

  static Color progressTrackOf(BuildContext context) {
    final isLight = context.appColors.backgroundBase.computeLuminance() >= 0.58;
    return isLight ? const Color(0x22172030) : const Color(0x33FFFFFF);
  }

  static Color imageProgressTrackOf(BuildContext context) {
    return const Color(0x52FFFFFF);
  }

  static Color imageProgressBorderOf(BuildContext context) {
    return const Color(0x7AFFFFFF);
  }

  static Color progressActiveOf(BuildContext context) {
    return context.appColors.accent;
  }

  static Color primaryButtonOf(BuildContext context) {
    return context.appColors.accent;
  }

  static Color primaryButtonDisabledOf(BuildContext context) {
    return context.appColors.textMuted.withValues(alpha: 0.42);
  }

  static Color chipBackgroundOf(BuildContext context) {
    return context.appColors.chipBackground;
  }

  static Color chipBorderOf(BuildContext context) {
    return context.appColors.chipBorder;
  }

  static Color chipSelectedBorderOf(BuildContext context) {
    return context.appColors.selection;
  }

  static Color chipTextOf(BuildContext context) {
    return context.appColors.chipText;
  }

  static Color chipSelectedTextOf(BuildContext context) {
    return context.appColors.selectionStrong;
  }

  static Color selectorTextOf(BuildContext context) {
    return context.appColors.textPrimary;
  }

  static Color selectorIconOf(BuildContext context) {
    return context.appColors.textSecondary;
  }

  static LinearGradient heroOverlayGradientOf(BuildContext context) {
    final colors = context.appColors;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        colors.overlayScrim.withValues(alpha: 0.30),
        colors.backgroundBase,
      ],
      stops: const [0.0, 0.6, 1.0],
    );
  }

  static LinearGradient glassPanelGradientOf(BuildContext context) {
    final colors = context.appColors;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors.surfaceStrong.withValues(alpha: 0.42),
        colors.backgroundElevated.withValues(alpha: 0.88),
        colors.backgroundBase.withValues(alpha: 0.94),
      ],
      stops: const [0.0, 0.56, 1.0],
    );
  }
}
