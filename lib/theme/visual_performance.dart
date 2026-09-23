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

  /// 首页缩略图在流畅档降低解码尺寸，减少首次滚入新内容时的图片上传量。
  /// 均衡和完整档保持现有清晰度；详情主图不走此策略。
  int homeThumbnailDecodeWidth(int requested) {
    if (this != AppVisualPerformanceTier.smooth || requested <= 0) {
      return requested;
    }
    return ((requested * .72 / 32).round() * 32).clamp(64, requested).toInt();
  }

  /// 首页只为随后可能进入的海报浏览页预取素材；降低档位时压缩这批推测性请求，
  /// 避免详情、演职员和季列表解析与启动及首次交互争用资源。
  int posterBrowseHomePrewarmLimit(int requested) {
    if (requested <= 0) return 0;
    return switch (this) {
      AppVisualPerformanceTier.smooth => 0,
      AppVisualPerformanceTier.balanced => requested.clamp(0, 2),
      AppVisualPerformanceTier.full => requested,
    };
  }

  /// 海报浏览页进入后只补全当前真正需要的续播卡片。
  ///
  /// 流畅档只补当前项，均衡档补当前项和相邻项，完整档保留整行补全。
  int posterBrowseContinueWarmupLimit(int requested) {
    if (requested <= 0) return 0;
    return switch (this) {
      AppVisualPerformanceTier.smooth => 1,
      AppVisualPerformanceTier.balanced => requested.clamp(0, 3),
      AppVisualPerformanceTier.full => requested,
    };
  }

  /// 焦点切换时允许在后台预取的邻近条目范围。
  int posterBrowseNeighborPrefetchRadius(int requested) {
    if (requested <= 0) return 0;
    return switch (this) {
      AppVisualPerformanceTier.smooth => 0,
      AppVisualPerformanceTier.balanced => requested.clamp(0, 1),
      AppVisualPerformanceTier.full => requested,
    };
  }

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
