import '../models/player_runtime_preferences.dart';

class PlayerSettingsController {
  static const double defaultSubtitlePositionFactor = 0.08;
  PlayerSettingsController({
    required Map<String, String> defaultMpvSettings,
    required Map<String, double> defaultVideoAdjustments,
  }) : mpvSettings = Map<String, String>.from(defaultMpvSettings),
       videoAdjustments = Map<String, double>.from(defaultVideoAdjustments);

  bool autoPlayEnabled = true;
  bool nextEpisodePreloadEnabled = false;
  bool autoRotateEnabled = true;
  bool extremePlaybackEnabled = false;
  bool performanceOverlayEnabled = false;
  bool fpsOverlayEnabled = false;
  bool introOutroEnabled = false;
  bool introOutroConfigLoaded = false;
  bool introOutroSkipInFlight = false;
  bool pendingReloadAutoplayRefresh = false;
  bool watchedMarkedForCurrentItem = false;

  int officialIntroDurationSeconds = 0;
  int officialOutroDurationSeconds = 0;
  int introDurationSeconds = 180;
  int outroDurationSeconds = 180;
  int skipPromptCountdownSeconds = 0;
  int? introChapterIndex;
  int? outroChapterIndex;

  String decoderMode = '';
  String displayAspectRatioMode = '';
  String introOutroSourceMode = '';
  String chapterSkipMode = '';
  String introOutroMode = '';
  String introOutroConfigGuid = '';

  Map<String, String> mpvSettings;
  Map<String, double> videoAdjustments;

  double audioDelaySeconds = 0;
  double subtitleDelaySeconds = 0;
  double subtitlePositionFactor = defaultSubtitlePositionFactor;
  double subtitleScaleFactor = 0;

  void applyRuntimePreferences(PlayerRuntimePreferences preferences) {
    autoPlayEnabled = preferences.autoPlayEnabled;
    nextEpisodePreloadEnabled = preferences.nextEpisodePreloadEnabled;
    autoRotateEnabled = preferences.autoRotateEnabled;
    extremePlaybackEnabled = preferences.extremePlaybackEnabled;
    performanceOverlayEnabled = preferences.performanceOverlayEnabled;
    fpsOverlayEnabled = preferences.fpsOverlayEnabled;
    decoderMode = preferences.decoderMode;
    displayAspectRatioMode = preferences.displayAspectRatioMode;
    introOutroEnabled = preferences.introOutroEnabled;
    introOutroSourceMode = preferences.introOutroSourceMode;
    chapterSkipMode = preferences.chapterSkipMode;
    introOutroMode = preferences.chapterSkipMode;
    introDurationSeconds = preferences.introDurationSeconds;
    outroDurationSeconds = preferences.outroDurationSeconds;
    introOutroConfigLoaded = true;
    mpvSettings = Map<String, String>.from(preferences.mpvSettings);
  }

  String playbackMonitorStatusLabel() {
    return performanceOverlayEnabled ? '部分开启' : '已关闭';
  }

  String decoderSwitchMessage(String modeLabel) {
    return '正在切换为 $modeLabel，请稍等...';
  }
}
