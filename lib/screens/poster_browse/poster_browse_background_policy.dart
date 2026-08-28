import 'package:flutter/material.dart';

import 'poster_browse_orientation_controller.dart';

@immutable
class PosterBrowseBackgroundSpec {
  const PosterBrowseBackgroundSpec({
    required this.usePosterImages,
    required this.fit,
    required this.alignment,
    required this.requestWidth,
    required this.cacheWidth,
    required this.prefetchRadius,
  });

  final bool usePosterImages;
  final BoxFit fit;
  final Alignment alignment;
  final int requestWidth;
  final int cacheWidth;
  final int prefetchRadius;
}

abstract final class PosterBrowseBackgroundPolicy {
  static PosterBrowseBackgroundSpec resolve({
    required Size logicalSize,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio.clamp(1.0, 3.0);
    final useMobileLayout = PosterBrowseWindowProfile.useMobileLayout(
      logicalSize,
    );

    if (useMobileLayout) {
      final width = (logicalSize.width * dpr).round().clamp(360, 960);
      return PosterBrowseBackgroundSpec(
        usePosterImages: true,
        // 全出血 cover：竖版海报、小图、横图一律裁切铺满整屏，杜绝旧 contain
        // 方案在海报下方露出的成片黑底。上偏对齐保住海报顶部的标题/主体。
        fit: BoxFit.cover,
        alignment: const Alignment(0.0, -0.20),
        requestWidth: width,
        cacheWidth: width,
        prefetchRadius: 1,
      );
    }

    final width = (logicalSize.width * dpr).round().clamp(560, 1440);
    return PosterBrowseBackgroundSpec(
      usePosterImages: false,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      requestWidth: width,
      cacheWidth: width,
      prefetchRadius: 2,
    );
  }
}
