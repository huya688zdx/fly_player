/// 页面视觉表现的用户选择。取色强度仍由动态主题设置独立控制。
enum AppVisualPerformanceMode { automatic, smooth, balanced, full }

/// 当前真正生效的表现档位。
enum AppVisualPerformanceTier { smooth, balanced, full }

extension AppVisualPerformanceModeX on AppVisualPerformanceMode {
  String get storageValue => name;

  static AppVisualPerformanceMode fromStorageValue(String? value) {
    for (final mode in AppVisualPerformanceMode.values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return AppVisualPerformanceMode.automatic;
  }

  AppVisualPerformanceTier resolve({required bool isLowRamDevice}) {
    return switch (this) {
      AppVisualPerformanceMode.automatic =>
        isLowRamDevice
            ? AppVisualPerformanceTier.smooth
            : AppVisualPerformanceTier.balanced,
      AppVisualPerformanceMode.smooth => AppVisualPerformanceTier.smooth,
      AppVisualPerformanceMode.balanced => AppVisualPerformanceTier.balanced,
      AppVisualPerformanceMode.full => AppVisualPerformanceTier.full,
    };
  }
}

extension AppVisualPerformanceTierX on AppVisualPerformanceTier {
  int get atmosphereTextureMaxDimension => switch (this) {
    AppVisualPerformanceTier.smooth => 768,
    AppVisualPerformanceTier.balanced => 1280,
    AppVisualPerformanceTier.full => 1920,
  };

  bool get allowsGlobalRuntimeThemeSync =>
      this == AppVisualPerformanceTier.full;

  bool get allowsPullDownZoom => this == AppVisualPerformanceTier.full;

  double detailParallaxFactor(double requested) {
    final normalized = requested.clamp(0.0, 1.0).toDouble();
    return switch (this) {
      // 1.0 代表图片与正文正常同步滚动，不是冻结图片。
      AppVisualPerformanceTier.smooth => 1.0,
      AppVisualPerformanceTier.balanced => normalized < .72 ? .72 : normalized,
      AppVisualPerformanceTier.full => normalized,
    };
  }

  double desktopBlurSigma(double requested, {bool overVideo = false}) {
    final normalized = requested < 0 ? 0.0 : requested;
    return switch (this) {
      AppVisualPerformanceTier.smooth => 0.0,
      AppVisualPerformanceTier.balanced =>
        overVideo ? 0.0 : (normalized > 8 ? 8.0 : normalized),
      AppVisualPerformanceTier.full => normalized,
    };
  }
}
