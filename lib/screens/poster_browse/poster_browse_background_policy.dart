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
    final isPhone = PosterBrowseDeviceProfile.isPhone(logicalSize);
    final usePosterImages = isPhone && logicalSize.width > logicalSize.height;

    if (usePosterImages) {
      final width = ((logicalSize.height / 1.5) * dpr).round().clamp(360, 720);
      return PosterBrowseBackgroundSpec(
        usePosterImages: true,
        fit: BoxFit.contain,
        alignment: Alignment.centerRight,
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
