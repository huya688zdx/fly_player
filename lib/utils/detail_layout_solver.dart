import 'package:flutter/material.dart';

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
