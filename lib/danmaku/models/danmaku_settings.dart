import 'dart:convert';

const List<double> danmakuDisplayAreaPresets = <double>[
  0.10,
  0.25,
  0.50,
  0.75,
  1.0,
];

double clampDanmakuAreaRatio(double value) {
  return value.clamp(0.1, 1.0).toDouble();
}

double resolveDanmakuCaptureAreaRatio(double displayAreaRatio) {
  final normalized = clampDanmakuAreaRatio(displayAreaRatio);
  for (var index = 0; index < danmakuDisplayAreaPresets.length; index += 1) {
    final preset = danmakuDisplayAreaPresets[index];
    if (normalized <= preset + 0.0001) {
      final nextIndex = index + 1 < danmakuDisplayAreaPresets.length
          ? index + 1
          : danmakuDisplayAreaPresets.length - 1;
      return danmakuDisplayAreaPresets[nextIndex];
    }
  }
  return danmakuDisplayAreaPresets.last;
}

double resolveDanmakuMaskSourceCoverageRatio({
  required double displayAreaRatio,
  required double captureAreaRatio,
}) {
  final display = clampDanmakuAreaRatio(displayAreaRatio);
  final capture = clampDanmakuAreaRatio(captureAreaRatio);
  if (capture <= 0) {
    return 1.0;
  }
  return (display / capture).clamp(0.0, 1.0).toDouble();
}

class DanmakuAiPrecisionPreset {
  static const String performance = 'performance';
  static const String balanced = 'balanced';
  static const String quality = 'quality';

  static const List<String> values = <String>[performance, balanced, quality];
}

class DanmakuSettings {
  static const int minAiSampleIntervalMs = 200;
  static const int maxAiSampleIntervalMs = 500;
  static const int minAiInputWidth = 160;
  static const int maxAiInputWidth = 320;

  final bool enabled;
  final bool previewEnabled;
  final bool preferLocalSource;
  final bool scrollEnabled;
  final bool topEnabled;
  final bool bottomEnabled;
  final bool colorEnabled;
  final bool hideDuplicate;
  final bool avoidSubtitleArea;
  final bool avoidCenterArea;
  final double opacity;
  final double density;
  final double fontScale;
  final double speed;
  final double displayAreaRatio;
  final int aiSampleIntervalMs;
  final int aiInputWidth;

  const DanmakuSettings({
    required this.enabled,
    required this.previewEnabled,
    required this.preferLocalSource,
    required this.scrollEnabled,
    required this.topEnabled,
    required this.bottomEnabled,
    required this.colorEnabled,
    required this.hideDuplicate,
    required this.avoidSubtitleArea,
    required this.avoidCenterArea,
    required this.opacity,
    required this.density,
    required this.fontScale,
    required this.speed,
    required this.displayAreaRatio,
    required this.aiSampleIntervalMs,
    required this.aiInputWidth,
  });

  static const DanmakuSettings defaults = DanmakuSettings(
    enabled: false,
    previewEnabled: false,
    preferLocalSource: true,
    scrollEnabled: true,
    topEnabled: true,
    bottomEnabled: false,
    colorEnabled: true,
    hideDuplicate: true,
    avoidSubtitleArea: true,
    avoidCenterArea: true,
    opacity: 0.85,
    density: 1.0,
    fontScale: 1.0,
    speed: 1.0,
    displayAreaRatio: 0.50,
    aiSampleIntervalMs: 500,
    aiInputWidth: 256,
  );

  DanmakuSettings copyWith({
    bool? enabled,
    bool? previewEnabled,
    bool? preferLocalSource,
    bool? scrollEnabled,
    bool? topEnabled,
    bool? bottomEnabled,
    bool? colorEnabled,
    bool? hideDuplicate,
    bool? avoidSubtitleArea,
    bool? avoidCenterArea,
    double? opacity,
    double? density,
    double? fontScale,
    double? speed,
    double? displayAreaRatio,
    int? aiSampleIntervalMs,
    int? aiInputWidth,
    String? aiPrecisionPreset,
  }) {
    final nextAiInputWidth = aiInputWidth ?? this.aiInputWidth;
    final mappedAiInputWidth = aiPrecisionPreset != null
        ? _mapAiPrecisionPresetToWidth(aiPrecisionPreset)
        : nextAiInputWidth;
    return DanmakuSettings(
      enabled: enabled ?? this.enabled,
      previewEnabled: previewEnabled ?? this.previewEnabled,
      preferLocalSource: preferLocalSource ?? this.preferLocalSource,
      scrollEnabled: scrollEnabled ?? this.scrollEnabled,
      topEnabled: topEnabled ?? this.topEnabled,
      bottomEnabled: bottomEnabled ?? this.bottomEnabled,
      colorEnabled: colorEnabled ?? this.colorEnabled,
      hideDuplicate: hideDuplicate ?? this.hideDuplicate,
      avoidSubtitleArea: avoidSubtitleArea ?? this.avoidSubtitleArea,
      avoidCenterArea: avoidCenterArea ?? this.avoidCenterArea,
      opacity: opacity ?? this.opacity,
      density: density ?? this.density,
      fontScale: fontScale ?? this.fontScale,
      speed: speed ?? this.speed,
      displayAreaRatio: displayAreaRatio ?? this.displayAreaRatio,
      aiSampleIntervalMs: aiSampleIntervalMs ?? this.aiSampleIntervalMs,
      aiInputWidth: mappedAiInputWidth.clamp(minAiInputWidth, maxAiInputWidth),
    );
  }

  String get aiPrecisionPreset {
    if (aiInputWidth <= 208) {
      return DanmakuAiPrecisionPreset.performance;
    }
    if (aiInputWidth >= 288) {
      return DanmakuAiPrecisionPreset.quality;
    }
    return DanmakuAiPrecisionPreset.balanced;
  }

  int get aiInputHeight {
    final height = (aiInputWidth * 9 / 16).round();
    return height.isEven ? height : height + 1;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'previewEnabled': previewEnabled,
      'preferLocalSource': preferLocalSource,
      'scrollEnabled': scrollEnabled,
      'topEnabled': topEnabled,
      'bottomEnabled': bottomEnabled,
      'colorEnabled': colorEnabled,
      'hideDuplicate': hideDuplicate,
      'avoidSubtitleArea': avoidSubtitleArea,
      'avoidCenterArea': avoidCenterArea,
      'opacity': opacity,
      'density': density,
      'fontScale': fontScale,
      'speed': speed,
      'displayAreaRatio': displayAreaRatio,
      'aiSampleIntervalMs': aiSampleIntervalMs,
      'aiInputWidth': aiInputWidth,
    };
  }

  String encode() => jsonEncode(toJson());

  static DanmakuSettings decode(String raw) {
    if (raw.trim().isEmpty) return defaults;
    final json = jsonDecode(raw);
    if (json is! Map) return defaults;
    return fromJson(Map<String, dynamic>.from(json));
  }

  static DanmakuSettings fromJson(Map<String, dynamic> json) {
    return defaults.copyWith(
      enabled: json['enabled'] == true,
      previewEnabled: json['previewEnabled'] == true,
      preferLocalSource: json['preferLocalSource'] != false,
      scrollEnabled: json['scrollEnabled'] != false,
      topEnabled: json['topEnabled'] != false,
      bottomEnabled: json['bottomEnabled'] == true,
      colorEnabled: json['colorEnabled'] != false,
      hideDuplicate: json['hideDuplicate'] != false,
      avoidSubtitleArea: json['avoidSubtitleArea'] != false,
      avoidCenterArea: json['avoidCenterArea'] != false,
      opacity: _readDouble(json['opacity'], defaults.opacity),
      density: _readDouble(json['density'], defaults.density),
      fontScale: _readDouble(json['fontScale'], defaults.fontScale),
      speed: _readDouble(json['speed'], defaults.speed),
      displayAreaRatio: _readDouble(
        json['displayAreaRatio'],
        defaults.displayAreaRatio,
      ),
      aiSampleIntervalMs: _readInt(
        json['aiSampleIntervalMs'],
        defaults.aiSampleIntervalMs,
      ).clamp(minAiSampleIntervalMs, maxAiSampleIntervalMs),
      aiInputWidth: _readAiInputWidth(json),
    );
  }

  static double _readDouble(dynamic value, double fallback) {
    final parsed = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    return parsed ?? fallback;
  }

  static int _readInt(dynamic value, int fallback) {
    final parsed = switch (value) {
      final num number => number.toInt(),
      final String text => int.tryParse(text),
      _ => null,
    };
    return parsed ?? fallback;
  }

  static String _readAiPrecisionPreset(dynamic value, String fallback) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null) {
      return fallback;
    }
    if (DanmakuAiPrecisionPreset.values.contains(normalized)) {
      return normalized;
    }
    return fallback;
  }

  static int _readAiInputWidth(Map<String, dynamic> json) {
    final direct = _readInt(json['aiInputWidth'], -1);
    if (direct > 0) {
      return direct.clamp(minAiInputWidth, maxAiInputWidth);
    }
    final legacyPreset = _readAiPrecisionPreset(
      json['aiPrecisionPreset'],
      DanmakuAiPrecisionPreset.balanced,
    );
    return _mapAiPrecisionPresetToWidth(legacyPreset);
  }

  static int _mapAiPrecisionPresetToWidth(String value) {
    return switch (value) {
      DanmakuAiPrecisionPreset.performance => 192,
      DanmakuAiPrecisionPreset.quality => 320,
      _ => 256,
    };
  }
}
