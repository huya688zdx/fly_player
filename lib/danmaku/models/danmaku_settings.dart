import 'dart:convert';
import 'dart:math' as math;

const List<double> danmakuDisplayAreaPresets = <double>[0.25, 0.50, 0.75, 1.0];

const List<double> danmakuFontThicknessPresets = <double>[0.8, 1.0, 1.2, 1.4];

// speed 现在是"直接倍速"：1.0=正常、0.5=半速、2.0=2 倍，无级连续、跨度大、直观。
const double danmakuSpeedMin = 0.5;
const double danmakuSpeedMax = 2.0;
const int danmakuSpeedDivisions = 6;
const int danmakuRuntimeSpeedNotchOffset = 0;
const double danmakuSpeedStep =
    (danmakuSpeedMax - danmakuSpeedMin) / danmakuSpeedDivisions;

final List<double> danmakuSpeedPresets = List<double>.generate(
  danmakuSpeedDivisions + 1,
  (index) => danmakuSpeedMin + (index * danmakuSpeedStep),
  growable: false,
);

const List<int> danmakuFrameRatePresets = <int>[24, 30, 45, 60, 72, 90, 120];

const double danmakuMotionReferenceShortSideDp = 420.0;
const double danmakuMotionMinDurationScale = 0.90;
const double danmakuMotionMaxDurationScale = 1.40;

double clampDanmakuAreaRatio(double value) {
  return value
      .clamp(danmakuDisplayAreaPresets.first, danmakuDisplayAreaPresets.last)
      .toDouble();
}

double clampDanmakuSpeed(double value) {
  return value.clamp(danmakuSpeedMin, danmakuSpeedMax).toDouble();
}

double nearestDanmakuSpeedPreset(double value) {
  final normalized = clampDanmakuSpeed(value);
  return danmakuSpeedPresets.reduce((best, candidate) {
    return (candidate - normalized).abs() < (best - normalized).abs()
        ? candidate
        : best;
  });
}

double resolveDanmakuRuntimeSpeed(
  double configuredSpeed, {
  int notchOffset = danmakuRuntimeSpeedNotchOffset,
}) {
  final normalized = clampDanmakuSpeed(configuredSpeed);
  if (notchOffset == 0) {
    return normalized;
  }
  return clampDanmakuSpeed(normalized + (danmakuSpeedStep * notchOffset));
}

double resolveDanmakuMotionSpeedFactor(
  double configuredSpeed, {
  int notchOffset = danmakuRuntimeSpeedNotchOffset,
}) {
  // 直接把配置速度当运动倍速（无 notch、无压缩映射）：1.0=正常，0.5=半速(更慢)，
  // 2.0=2 倍(更快)。durationMs = baseMs / 倍速，故倍速越大穿屏越快。
  return resolveDanmakuRuntimeSpeed(configuredSpeed, notchOffset: notchOffset);
}

int normalizeDanmakuFrameRateHz(int value) {
  final normalized = value.clamp(
    danmakuFrameRatePresets.first,
    danmakuFrameRatePresets.last,
  );
  return danmakuFrameRatePresets.reduce((best, candidate) {
    return (candidate - normalized).abs() < (best - normalized).abs()
        ? candidate
        : best;
  });
}

double resolveDanmakuCaptureAreaRatio(double displayAreaRatio) {
  if (displayAreaRatio < danmakuDisplayAreaPresets.first) {
    return danmakuDisplayAreaPresets.first;
  }
  final display = danmakuDisplayAreaPresets.firstWhere(
    (preset) => displayAreaRatio <= preset + 0.0001,
    orElse: () => danmakuDisplayAreaPresets.last,
  );
  for (final preset in danmakuDisplayAreaPresets) {
    if (preset > display + 0.0001) {
      return preset;
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

double resolveDanmakuViewportMotionDurationScale(double shortSideDp) {
  if (shortSideDp <= 0) {
    return 1.0;
  }
  return (shortSideDp / danmakuMotionReferenceShortSideDp)
      .clamp(danmakuMotionMinDurationScale, danmakuMotionMaxDurationScale)
      .toDouble();
}

double resolveDanmakuDensityCapacityScale(double capacityScale) {
  if (capacityScale <= 0) {
    return 0.0;
  }
  return math.sqrt(capacityScale.clamp(0.0, 1.0)).toDouble();
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
  final double fontThickness;
  final double speed;
  final double displayAreaRatio;
  final int targetFrameRateHz;
  final int aiSampleIntervalMs;
  final int aiInputWidth;
  // 弹幕渲染器：false=Flutter 层渲染(texture backend，二级界面顺、但和视频共享 Flutter
  // raster，高码率/120Hz 下视频会挤占弹幕)；true=原生 Canvas 渲染(surface backend，视频
  // 走 SurfaceFlinger 独立硬件层、和弹幕分开，弹幕可 120fps 丝滑，代价是二级界面走 HC
  // 合成可能略卡)。切换需重开播放器生效(PlatformView backend 在会话内锁定，见
  // _handlePlatformViewCreated)。
  final bool useNativeRenderer;

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
    required this.fontThickness,
    required this.speed,
    required this.displayAreaRatio,
    required this.targetFrameRateHz,
    required this.aiSampleIntervalMs,
    required this.aiInputWidth,
    this.useNativeRenderer = true,
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
    fontThickness: 1.0,
    speed: 1.0,
    displayAreaRatio: 0.50,
    targetFrameRateHz: 60,
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
    double? fontThickness,
    double? speed,
    double? displayAreaRatio,
    int? targetFrameRateHz,
    int? aiSampleIntervalMs,
    int? aiInputWidth,
    String? aiPrecisionPreset,
    bool? useNativeRenderer,
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
      fontThickness: (fontThickness ?? this.fontThickness)
          .clamp(0.8, 1.4)
          .toDouble(),
      speed: clampDanmakuSpeed(speed ?? this.speed),
      displayAreaRatio: clampDanmakuAreaRatio(
        displayAreaRatio ?? this.displayAreaRatio,
      ),
      targetFrameRateHz: normalizeDanmakuFrameRateHz(
        targetFrameRateHz ?? this.targetFrameRateHz,
      ),
      aiSampleIntervalMs: aiSampleIntervalMs ?? this.aiSampleIntervalMs,
      aiInputWidth: mappedAiInputWidth.clamp(minAiInputWidth, maxAiInputWidth),
      useNativeRenderer: useNativeRenderer ?? this.useNativeRenderer,
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
      'fontThickness': fontThickness,
      'speed': speed,
      'displayAreaRatio': displayAreaRatio,
      'targetFrameRateHz': targetFrameRateHz,
      'aiSampleIntervalMs': aiSampleIntervalMs,
      'aiInputWidth': aiInputWidth,
      'useNativeRenderer': useNativeRenderer,
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
      fontThickness: _readDouble(json['fontThickness'], defaults.fontThickness),
      speed: _readDouble(json['speed'], defaults.speed),
      displayAreaRatio: _readDouble(
        json['displayAreaRatio'],
        defaults.displayAreaRatio,
      ),
      targetFrameRateHz: normalizeDanmakuFrameRateHz(
        _readInt(json['targetFrameRateHz'], defaults.targetFrameRateHz),
      ),
      aiSampleIntervalMs: _readInt(
        json['aiSampleIntervalMs'],
        defaults.aiSampleIntervalMs,
      ).clamp(minAiSampleIntervalMs, maxAiSampleIntervalMs),
      aiInputWidth: _readAiInputWidth(json),
      useNativeRenderer: json['useNativeRenderer'] is bool
          ? json['useNativeRenderer'] as bool
          : defaults.useNativeRenderer,
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
