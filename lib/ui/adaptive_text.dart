import 'package:flutter/widgets.dart';

enum AdaptiveFontRole { title, body, button, caption }

class AdaptiveTextConfig {
  final double phoneBaseWidth;
  final double phoneMinScale;
  final double phoneMaxScale;
  final double smallTabletScale;
  final double midTabletScale;
  final double largeTabletScale;
  final double globalMinScale;
  final double globalMaxScale;

  // Role multipliers let you tune specific text groups without hardcoding
  // size overrides in each widget.
  final double titleMultiplier;
  final double bodyMultiplier;
  final double buttonMultiplier;
  final double captionMultiplier;

  const AdaptiveTextConfig({
    this.phoneBaseWidth = 411,
    this.phoneMinScale = 0.98,
    this.phoneMaxScale = 1.08,
    this.smallTabletScale = 1.14,
    this.midTabletScale = 1.20,
    this.largeTabletScale = 1.26,
    this.globalMinScale = 0.95,
    this.globalMaxScale = 1.35,
    this.titleMultiplier = 1.20,
    this.bodyMultiplier = 1.0,
    this.buttonMultiplier = 1.03,
    this.captionMultiplier = 0.96,
  });
}

class AdaptiveText {
  static const AdaptiveTextConfig config = AdaptiveTextConfig();

  static double globalScale(
    MediaQueryData media, {
    AdaptiveTextConfig cfg = config,
  }) {
    final shortest = media.size.shortestSide;
    final width = media.size.width;
    final systemScale = media.textScaler.scale(16) / 16;

    double screenScale;
    if (shortest >= 900) {
      screenScale = cfg.largeTabletScale;
    } else if (shortest >= 720) {
      screenScale = cfg.midTabletScale;
    } else if (shortest >= 600) {
      screenScale = cfg.smallTabletScale;
    } else {
      screenScale = (width / cfg.phoneBaseWidth).clamp(
        cfg.phoneMinScale,
        cfg.phoneMaxScale,
      );
    }

    return (systemScale * screenScale).clamp(
      cfg.globalMinScale,
      cfg.globalMaxScale,
    );
  }

  static double roleSize(
    double base, {
    AdaptiveFontRole role = AdaptiveFontRole.body,
    AdaptiveTextConfig cfg = config,
  }) {
    switch (role) {
      case AdaptiveFontRole.title:
        return base * cfg.titleMultiplier;
      case AdaptiveFontRole.button:
        return base * cfg.buttonMultiplier;
      case AdaptiveFontRole.caption:
        return base * cfg.captionMultiplier;
      case AdaptiveFontRole.body:
        return base * cfg.bodyMultiplier;
    }
  }
}
