import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_runtime_preferences.dart';

class PlayerRuntimePreferencesStore {
  final String autoPlayPrefKey;
  final String nextEpisodePreloadPrefKey;
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
  final String subtitleDelayPrefKey;
  final String subtitlePositionFactorPrefKey;
  final String subtitleScaleFactorPrefKey;
  final String subtitleAdjustmentRecordsPrefKey;
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
  final double defaultSubtitleDelaySeconds;
  final double defaultSubtitlePositionFactor;
  final double defaultSubtitleScaleFactor;
  final double subtitleDelayMinSeconds;
  final double subtitleDelayMaxSeconds;
  final int introDurationMinSeconds;
  final int introDurationMaxSeconds;
  final int outroDurationMinSeconds;
  final int outroDurationMaxSeconds;

  const PlayerRuntimePreferencesStore({
    required this.autoPlayPrefKey,
    required this.nextEpisodePreloadPrefKey,
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
    required this.subtitleDelayPrefKey,
    required this.subtitlePositionFactorPrefKey,
    required this.subtitleScaleFactorPrefKey,
    required this.subtitleAdjustmentRecordsPrefKey,
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
    required this.defaultSubtitleDelaySeconds,
    required this.defaultSubtitlePositionFactor,
    required this.defaultSubtitleScaleFactor,
    required this.subtitleDelayMinSeconds,
    required this.subtitleDelayMaxSeconds,
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
      nextEpisodePreloadEnabled:
          prefs.getBool(nextEpisodePreloadPrefKey) ?? false,
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
      subtitleDelaySeconds: _normalizeSubtitleDelaySeconds(
        prefs.getDouble(subtitleDelayPrefKey),
      ),
      subtitlePositionFactor: _normalizeUnitFactor(
        prefs.getDouble(subtitlePositionFactorPrefKey),
        defaultValue: defaultSubtitlePositionFactor,
      ),
      subtitleScaleFactor: _normalizeUnitFactor(
        prefs.getDouble(subtitleScaleFactorPrefKey),
        defaultValue: defaultSubtitleScaleFactor,
      ),
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

  Future<PlayerSubtitleAdjustmentRecord?> loadSubtitleAdjustmentRecord(
    String key,
  ) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeSubtitleAdjustmentRecords(
      prefs.getString(subtitleAdjustmentRecordsPrefKey),
    );
    final raw = records[normalizedKey];
    if (raw is! Map<String, Object?>) return null;
    return _subtitleAdjustmentRecordFromMap(normalizedKey, raw);
  }

  Future<void> saveSubtitleAdjustmentRecord({
    required String key,
    required String title,
    required double subtitleDelaySeconds,
    required double subtitlePositionFactor,
    required double subtitleScaleFactor,
  }) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeSubtitleAdjustmentRecords(
      prefs.getString(subtitleAdjustmentRecordsPrefKey),
    );
    records[normalizedKey] = <String, Object?>{
      'title': title.trim(),
      'subtitleDelaySeconds': _normalizeSubtitleDelaySeconds(
        subtitleDelaySeconds,
      ),
      'subtitlePositionFactor': _normalizeUnitFactor(
        subtitlePositionFactor,
        defaultValue: defaultSubtitlePositionFactor,
      ),
      'subtitleScaleFactor': _normalizeUnitFactor(
        subtitleScaleFactor,
        defaultValue: defaultSubtitleScaleFactor,
      ),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    _trimSubtitleAdjustmentRecords(records);
    await prefs.setString(
      subtitleAdjustmentRecordsPrefKey,
      jsonEncode(records),
    );
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

  double _normalizeSubtitleDelaySeconds(double? value) {
    final normalized = (value ?? defaultSubtitleDelaySeconds)
        .clamp(subtitleDelayMinSeconds, subtitleDelayMaxSeconds)
        .toDouble();
    return double.parse(normalized.toStringAsFixed(1));
  }

  double _normalizeUnitFactor(double? value, {required double defaultValue}) {
    return (value ?? defaultValue).clamp(0.0, 1.0).toDouble();
  }

  Map<String, Object?> _decodeSubtitleAdjustmentRecords(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Object?>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), _normalizeRecordMap(value)),
      );
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<String, Object?> _normalizeRecordMap(Object? value) {
    if (value is! Map) return <String, Object?>{};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  PlayerSubtitleAdjustmentRecord? _subtitleAdjustmentRecordFromMap(
    String key,
    Map<String, Object?> raw,
  ) {
    final delay = _numberToDouble(raw['subtitleDelaySeconds']);
    final position = _numberToDouble(raw['subtitlePositionFactor']);
    final scale = _numberToDouble(raw['subtitleScaleFactor']);
    if (delay == null || position == null || scale == null) return null;
    return PlayerSubtitleAdjustmentRecord(
      key: key,
      title: raw['title']?.toString().trim() ?? '',
      subtitleDelaySeconds: _normalizeSubtitleDelaySeconds(delay),
      subtitlePositionFactor: _normalizeUnitFactor(
        position,
        defaultValue: defaultSubtitlePositionFactor,
      ),
      subtitleScaleFactor: _normalizeUnitFactor(
        scale,
        defaultValue: defaultSubtitleScaleFactor,
      ),
      updatedAtMs: (raw['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  double? _numberToDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void _trimSubtitleAdjustmentRecords(Map<String, Object?> records) {
    const maxRecords = 300;
    if (records.length <= maxRecords) return;
    final entries = records.entries.toList()
      ..sort((left, right) {
        final leftMap = _normalizeRecordMap(left.value);
        final rightMap = _normalizeRecordMap(right.value);
        final leftUpdated = (leftMap['updatedAtMs'] as num?)?.toInt() ?? 0;
        final rightUpdated = (rightMap['updatedAtMs'] as num?)?.toInt() ?? 0;
        return rightUpdated.compareTo(leftUpdated);
      });
    records
      ..clear()
      ..addEntries(entries.take(maxRecords));
  }
}
