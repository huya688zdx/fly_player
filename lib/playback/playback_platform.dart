import 'package:flutter/foundation.dart';

/// Playback capabilities are separate from desktop layout breakpoints.
abstract final class PlaybackPlatform {
  static bool supportsMediaKit(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.iOS => true,
    _ => false,
  };

  static bool get usesMediaKit =>
      !kIsWeb && supportsMediaKit(defaultTargetPlatform);

  static bool get usesAndroidHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isSupported => usesMediaKit || usesAndroidHost;

  static bool get usesTouchControls =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
