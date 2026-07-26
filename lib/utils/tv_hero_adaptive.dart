import 'package:flutter/material.dart';

class TvHeroAdaptiveMetrics {
  final double posterHeightRatio;
  final double imageScale;
  final double imageAlignX;
  final double imageAlignY;
  final double fadeStart;
  final double fadeMid;

  const TvHeroAdaptiveMetrics({
    required this.posterHeightRatio,
    required this.imageScale,
    required this.imageAlignX,
    required this.imageAlignY,
    required this.fadeStart,
    required this.fadeMid,
  });
}

class TvHeroAdaptive {
  const TvHeroAdaptive._();

  static TvHeroAdaptiveMetrics resolve(
    Size screenSize, {
    required double devicePixelRatio,
  }) {
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = screenSize.shortestSide >= 600;
    final aspectRatio = screenSize.width / screenSize.height;
    final widthNorm = ((screenSize.width - 360.0) / 600.0).clamp(0.0, 1.0);

    if (!isTablet) {
      // Phone: adaptive by screen width/aspect ratio (not fixed crop presets).
      if (isLandscape) {
        final posterHeightRatio =
            (0.44 - widthNorm * 0.04 - (aspectRatio - 1.8) * 0.02).clamp(
              0.38,
              0.46,
            );
        final imageScale =
            (1.00 - widthNorm * 0.04 - (aspectRatio - 1.8) * 0.02).clamp(
              1.00,
              1.06,
            );
        final imageAlignX = (0.34 + widthNorm * 0.10).clamp(0.30, 0.46);
        return TvHeroAdaptiveMetrics(
          posterHeightRatio: posterHeightRatio.toDouble(),
          imageScale: imageScale.toDouble(),
          imageAlignX: imageAlignX.toDouble(),
          imageAlignY: -0.18,
          fadeStart: 0.64,
          fadeMid: 0.86,
        );
      }

      final posterHeightRatio =
          (0.46 - widthNorm * 0.03 - (aspectRatio - 0.50) * 0.04).clamp(
            0.40,
            0.48,
          );
      final imageScale = (1.03 - widthNorm * 0.01 - (aspectRatio - 0.50) * 0.02)
          .clamp(1.00, 1.07);
      final imageAlignX = (0.14 + widthNorm * 0.10).clamp(0.10, 0.24);
      return TvHeroAdaptiveMetrics(
        posterHeightRatio: posterHeightRatio.toDouble(),
        imageScale: imageScale.toDouble(),
        imageAlignX: imageAlignX.toDouble(),
        imageAlignY: -0.08,
        fadeStart: 0.64,
        fadeMid: 0.88,
      );
    }

    // Tablet baseline.
    if (isLandscape) {
      return const TvHeroAdaptiveMetrics(
        posterHeightRatio: 0.44,
        imageScale: 1.00,
        imageAlignX: 0.50,
        imageAlignY: -0.10,
        fadeStart: 0.62,
        fadeMid: 0.84,
      );
    }

    final posterHeightRatio = (0.60 - (aspectRatio - 0.56) * 0.10).clamp(
      0.48,
      0.62,
    );
    final imageScale = (1.00 - (aspectRatio - 0.56) * 0.06).clamp(0.88, 1.03);
    final imageAlignX = (0.32 + (aspectRatio - 0.56) * 0.20).clamp(0.18, 0.62);
    final fadeStart = (0.58 + (aspectRatio - 0.56) * 0.04).clamp(0.54, 0.68);
    final fadeMid = (fadeStart + 0.22).clamp(0.76, 0.90);

    return TvHeroAdaptiveMetrics(
      posterHeightRatio: posterHeightRatio.toDouble(),
      imageScale: imageScale.toDouble(),
      imageAlignX: imageAlignX.toDouble(),
      imageAlignY: -0.12,
      fadeStart: fadeStart.toDouble(),
      fadeMid: fadeMid.toDouble(),
    );
  }
}
