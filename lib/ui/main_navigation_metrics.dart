abstract final class MainNavigationMetrics {
  static const barHeight = 72.0;
  static const fallbackBottomMargin = 8.0;
  static const contentGap = 16.0;

  static double outerBottomPadding(double safeBottom) {
    return safeBottom > 0 ? safeBottom : fallbackBottomMargin;
  }

  static double contentBottomInset(double safeBottom) {
    return barHeight + outerBottomPadding(safeBottom) + contentGap;
  }
}
