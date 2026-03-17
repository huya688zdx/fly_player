import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_runtime_preferences.dart';

class PlayerRuntimePreferencesStore {
  final String autoPlayPrefKey;
  final String autoRotatePrefKey;
  final String extremePlaybackPrefKey;
  final String performanceOverlayPrefKey;
  final String fpsOverlayPrefKey;
  final String performanceOverlayOffsetXPrefKey;
  final String performanceOverlayOffsetYPrefKey;
  final String decoderModePrefKey;
  final String displayAspectRatioPrefKey;
  final String introOutroEnabledPrefKey;
  final String introOutroSourceModePrefKey;
  final String introOutroChapterModePrefKey;
  final String introOutroIntroMaxPrefKey;
  final String introOutroOutroMaxPrefKey;
  final String mpvSettingPrefPrefix;
  final String decoderModeHardware;
  final String decoderModeSoftware;
  final String displayAspectRatioFit;
  final Set<String> supportedDisplayAspectRatioModes;
  final String introOutroSourceModeOff;
  final Set<String> supportedIntroOutroSourceModes;
  final String chapterSkipModeAuto;
  final Set<String> supportedChapterSkipModes;
  final Map<String, String> defaultMpvSettings;
  final Offset defaultPerformanceOverlayOffset;
  final int introDurationMinSeconds;
  final int introDurationMaxSeconds;
  final int outroDurationMinSeconds;
  final int outroDurationMaxSeconds;

  const PlayerRuntimePreferencesStore({
    required this.autoPlayPrefKey,
    required this.autoRotatePrefKey,
    required this.extremePlaybackPrefKey,
    required this.performanceOverlayPrefKey,
    required this.fpsOverlayPrefKey,
    required this.performanceOverlayOffsetXPrefKey,
    required this.performanceOverlayOffsetYPrefKey,
    required this.decoderModePrefKey,
    required this.displayAspectRatioPrefKey,
    required this.introOutroEnabledPrefKey,
    required this.introOutroSourceModePrefKey,
    required this.introOutroChapterModePrefKey,
    required this.introOutroIntroMaxPrefKey,
    required this.introOutroOutroMaxPrefKey,
    required this.mpvSettingPrefPrefix,
    required this.decoderModeHardware,
    required this.decoderModeSoftware,
    required this.displayAspectRatioFit,
    required this.supportedDisplayAspectRatioModes,
    required this.introOutroSourceModeOff,
    required this.supportedIntroOutroSourceModes,
    required this.chapterSkipModeAuto,
    required this.supportedChapterSkipModes,
    required this.defaultMpvSettings,
    required this.defaultPerformanceOverlayOffset,
    required this.introDurationMinSeconds,
    required this.introDurationMaxSeconds,
    required this.outroDurationMinSeconds,
    required this.outroDurationMaxSeconds,
  });

  Future<PlayerRuntimePreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final introOutroEnabled = prefs.getBool(introOutroEnabledPrefKey) ?? false;
    final introOutroSourceMode = _normalizeIntroOutroSourceMode(
      prefs.getString(introOutroSourceModePrefKey),
    );
    final chapterSkipMode = _normalizeChapterSkipMode(
      prefs.getString(introOutroChapterModePrefKey),
    );
    final overlayDx = prefs.getDouble(performanceOverlayOffsetXPrefKey);
    final overlayDy = prefs.getDouble(performanceOverlayOffsetYPrefKey);
    final resolvedMpvSettings = Map<String, String>.from(defaultMpvSettings);
    for (final key in resolvedMpvSettings.keys) {
      final stored = prefs.getString('$mpvSettingPrefPrefix$key');
      if (stored != null && stored.trim().isNotEmpty) {
        resolvedMpvSettings[key] = stored.trim();
      }
    }
    return PlayerRuntimePreferences(
      autoPlayEnabled: prefs.getBool(autoPlayPrefKey) ?? true,
      autoRotateEnabled: prefs.getBool(autoRotatePrefKey) ?? true,
      extremePlaybackEnabled: prefs.getBool(extremePlaybackPrefKey) ?? false,
      performanceOverlayEnabled:
          prefs.getBool(performanceOverlayPrefKey) ?? false,
      fpsOverlayEnabled: prefs.getBool(fpsOverlayPrefKey) ?? false,
      decoderMode: _normalizeDecoderMode(prefs.getString(decoderModePrefKey)),
      displayAspectRatioMode: _normalizeDisplayAspectRatioMode(
        prefs.getString(displayAspectRatioPrefKey),
      ),
      introOutroEnabled: introOutroEnabled,
      introOutroSourceMode: introOutroEnabled
          ? introOutroSourceMode
          : introOutroSourceModeOff,
      chapterSkipMode: chapterSkipMode,
      introDurationSeconds: (prefs.getInt(introOutroIntroMaxPrefKey) ?? 180)
          .clamp(introDurationMinSeconds, introDurationMaxSeconds),
      outroDurationSeconds: (prefs.getInt(introOutroOutroMaxPrefKey) ?? 180)
          .clamp(outroDurationMinSeconds, outroDurationMaxSeconds),
      mpvSettings: resolvedMpvSettings,
      performanceOverlayOffset: overlayDx != null && overlayDy != null
          ? Offset(overlayDx, overlayDy)
          : defaultPerformanceOverlayOffset,
    );
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> setDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> persistPerformanceOverlayOffset(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(performanceOverlayOffsetXPrefKey, offset.dx);
    await prefs.setDouble(performanceOverlayOffsetYPrefKey, offset.dy);
  }

  String _normalizeDecoderMode(String? value) {
    return value == decoderModeSoftware
        ? decoderModeSoftware
        : decoderModeHardware;
  }

  String _normalizeDisplayAspectRatioMode(String? value) {
    return supportedDisplayAspectRatioModes.contains(value)
        ? value!
        : displayAspectRatioFit;
  }

  String _normalizeIntroOutroSourceMode(String? value) {
    return supportedIntroOutroSourceModes.contains(value)
        ? value!
        : introOutroSourceModeOff;
  }

  String _normalizeChapterSkipMode(String? value) {
    return supportedChapterSkipModes.contains(value)
        ? value!
        : chapterSkipModeAuto;
  }
}
