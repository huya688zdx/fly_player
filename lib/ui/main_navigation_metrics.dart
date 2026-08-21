abstract final class MainNavigationMetrics {
  static const barHeight = 60.0;
  static const fallbackBottomMargin = 8.0;
  static const contentGap = 12.0;
  static const compactBarWidth = 236.0;
  static const wideBarWidth = 276.0;

  static double outerBottomPadding(double safeBottom) {
    return safeBottom > 0 ? safeBottom : fallbackBottomMargin;
  }

  static double contentBottomInset(double safeBottom) {
    return barHeight + outerBottomPadding(safeBottom) + contentGap;
  }

  static double barWidthFor(double viewportWidth) {
    if (!viewportWidth.isFinite || viewportWidth <= 32) return 0;
    final target = viewportWidth >= 700 ? wideBarWidth : compactBarWidth;
    return (viewportWidth - 32).clamp(0, target).toDouble();
  }
}
