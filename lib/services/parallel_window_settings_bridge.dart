import 'package:flutter/services.dart';

class ParallelWindowSettings {
  final bool enabled;
  final String preferredPrimaryPaneSide;
  final String preferredPlaybackPrimaryPaneSide;
  final String splitRatioPreset;
  final bool defaultPlaybackFullscreen;
  final bool immersiveStatusBar;

  const ParallelWindowSettings({
    required this.enabled,
    required this.preferredPrimaryPaneSide,
    required this.preferredPlaybackPrimaryPaneSide,
    required this.splitRatioPreset,
    required this.defaultPlaybackFullscreen,
    required this.immersiveStatusBar,
  });

  factory ParallelWindowSettings.fromMap(Map<String, dynamic> map) {
    return ParallelWindowSettings(
      enabled: map['enabled'] == true,
      preferredPrimaryPaneSide: (map['preferredPrimaryPaneSide'] ?? 'left')
          .toString(),
      preferredPlaybackPrimaryPaneSide:
          (map['preferredPlaybackPrimaryPaneSide'] ?? 'right').toString(),
      splitRatioPreset: (map['splitRatioPreset'] ?? 'balanced').toString(),
      defaultPlaybackFullscreen: map['defaultPlaybackFullscreen'] != false,
      immersiveStatusBar: map['immersiveStatusBar'] != false,
    );
  }

  ParallelWindowSettings copyWith({
    bool? enabled,
    String? preferredPrimaryPaneSide,
    String? preferredPlaybackPrimaryPaneSide,
    String? splitRatioPreset,
    bool? defaultPlaybackFullscreen,
    bool? immersiveStatusBar,
  }) {
    return ParallelWindowSettings(
      enabled: enabled ?? this.enabled,
      preferredPrimaryPaneSide:
          preferredPrimaryPaneSide ?? this.preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide:
          preferredPlaybackPrimaryPaneSide ??
          this.preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: splitRatioPreset ?? this.splitRatioPreset,
      defaultPlaybackFullscreen:
          defaultPlaybackFullscreen ?? this.defaultPlaybackFullscreen,
      immersiveStatusBar: immersiveStatusBar ?? this.immersiveStatusBar,
    );
  }
}

class ParallelWindowSettingsBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const ParallelWindowSettingsBridge._();

  static Future<ParallelWindowSettings> load() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getParallelWindowSettings',
      );
      if (result == null) {
        return const ParallelWindowSettings(
          enabled: true,
          preferredPrimaryPaneSide: 'left',
          preferredPlaybackPrimaryPaneSide: 'right',
          splitRatioPreset: 'balanced',
          defaultPlaybackFullscreen: true,
          immersiveStatusBar: true,
        );
      }
      return ParallelWindowSettings.fromMap(_normalizeMap(result));
    } on PlatformException {
      return const ParallelWindowSettings(
        enabled: true,
        preferredPrimaryPaneSide: 'left',
        preferredPlaybackPrimaryPaneSide: 'right',
        splitRatioPreset: 'balanced',
        defaultPlaybackFullscreen: true,
        immersiveStatusBar: true,
      );
    }
  }

  static Future<ParallelWindowSettings> save({
    required bool enabled,
    required String preferredPrimaryPaneSide,
    required String preferredPlaybackPrimaryPaneSide,
    required String splitRatioPreset,
    required bool defaultPlaybackFullscreen,
    required bool immersiveStatusBar,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'updateParallelWindowSettings',
        <String, Object?>{
          'enabled': enabled,
          'preferredPrimaryPaneSide': preferredPrimaryPaneSide,
          'preferredPlaybackPrimaryPaneSide': preferredPlaybackPrimaryPaneSide,
          'splitRatioPreset': splitRatioPreset,
          'defaultPlaybackFullscreen': defaultPlaybackFullscreen,
          'immersiveStatusBar': immersiveStatusBar,
        },
      );
      if (result == null) {
        return ParallelWindowSettings(
          enabled: enabled,
          preferredPrimaryPaneSide: preferredPrimaryPaneSide,
          preferredPlaybackPrimaryPaneSide: preferredPlaybackPrimaryPaneSide,
          splitRatioPreset: splitRatioPreset,
          defaultPlaybackFullscreen: defaultPlaybackFullscreen,
          immersiveStatusBar: immersiveStatusBar,
        );
      }
      return ParallelWindowSettings.fromMap(_normalizeMap(result));
    } on PlatformException {
      return ParallelWindowSettings(
        enabled: enabled,
        preferredPrimaryPaneSide: preferredPrimaryPaneSide,
        preferredPlaybackPrimaryPaneSide: preferredPlaybackPrimaryPaneSide,
        splitRatioPreset: splitRatioPreset,
        defaultPlaybackFullscreen: defaultPlaybackFullscreen,
        immersiveStatusBar: immersiveStatusBar,
      );
    }
  }

  static Map<String, dynamic> _normalizeMap(Map<Object?, Object?> raw) {
    final normalized = <String, dynamic>{};
    raw.forEach((key, value) {
      normalized[key?.toString() ?? ''] = _normalizeValue(value);
    });
    return normalized;
  }

  static dynamic _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }
}
