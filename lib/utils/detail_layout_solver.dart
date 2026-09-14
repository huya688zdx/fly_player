import 'package:flutter/material.dart';

import '../desktop/desktop_environment.dart';
import '../theme/detail_tokens.dart';

class DetailLayoutMetrics {
  final double infoStart;
  final double contentTopPadding;
  final double topGradientHeight;
  final double titleTopDistance;

  const DetailLayoutMetrics({
    required this.infoStart,
    required this.contentTopPadding,
    required this.topGradientHeight,
    required this.titleTopDistance,
  });
}

class DetailLayoutSolver {
  const DetailLayoutSolver._();

  static const desktopPosterWidth = 168.0;
  static const desktopActionWidth = 360.0;
  static const desktopControlHeight = 42.0;
  static const desktopInlineControlsWidth = 1000.0;

  static bool usesDesktopLayout(double width) =>
      DesktopEnvironment.isDesktopPlatform && width >= 800;

  static double desktopPosterWidthFor(double width) =>
      width < 1180 ? 152.0 : desktopPosterWidth;

  /// 正文、标题和骨架共用边距，背景仍铺满窗口。
  static double horizontalPadding(double width) => usesDesktopLayout(width)
      ? ((width - 1180) / 2).clamp(32.0, double.infinity)
      : DetailTokens.screenHorizontalPadding;

  static double desktopHeroHeight(Size size) =>
      (size.height * 0.50).clamp(300.0, 420.0);

  static double desktopSeasonHeaderTop(Size size, double safeTop) =>
      (desktopHeroHeight(size) - desktopPosterWidthFor(size.width) * 1.45 - 24)
          .clamp(safeTop + 72, double.infinity);

  static double _safeClamp(double value, double a, double b) {
    final min = a <= b ? a : b;
    final max = a <= b ? b : a;
    return value.clamp(min, max).toDouble();
  }

  static DetailLayoutMetrics solve({
    required Size screenSize,
    required EdgeInsets safePadding,
    required double posterHeight,
  }) {
    final titleTop = _safeClamp(
      posterHeight - 170.0,
      safePadding.top + 100.0,
      posterHeight - 80.0,
    );

    final topGradient = _safeClamp(screenSize.height * 0.12, 72.0, 120.0);

    return DetailLayoutMetrics(
      // Content begins below the hero image.
      infoStart: posterHeight,
      // Keep title in hero layer rather than pushing content down.
      contentTopPadding: 0.0,
      topGradientHeight: topGradient,
      titleTopDistance: titleTop,
    );
  }
}
