import 'dart:ui';

class PlayerRuntimePreferences {
  final bool autoPlayEnabled;
  final bool nextEpisodePreloadEnabled;
  final bool autoRotateEnabled;
  final bool extremePlaybackEnabled;
  final bool performanceOverlayEnabled;
  final bool fpsOverlayEnabled;
  final String decoderMode;
  final String displayAspectRatioMode;
  final bool introOutroEnabled;
  final String introOutroSourceMode;
  final String chapterSkipMode;
  final int introDurationSeconds;
  final int outroDurationSeconds;
  final double subtitleDelaySeconds;
  final double subtitlePositionFactor;
  final double subtitleScaleFactor;
  final Map<String, String> mpvSettings;
  final Offset performanceOverlayOffset;

  const PlayerRuntimePreferences({
    required this.autoPlayEnabled,
    required this.nextEpisodePreloadEnabled,
    required this.autoRotateEnabled,
    required this.extremePlaybackEnabled,
    required this.performanceOverlayEnabled,
    required this.fpsOverlayEnabled,
    required this.decoderMode,
    required this.displayAspectRatioMode,
    required this.introOutroEnabled,
    required this.introOutroSourceMode,
    required this.chapterSkipMode,
    required this.introDurationSeconds,
    required this.outroDurationSeconds,
    required this.subtitleDelaySeconds,
    required this.subtitlePositionFactor,
    required this.subtitleScaleFactor,
    required this.mpvSettings,
    required this.performanceOverlayOffset,
  });
}
