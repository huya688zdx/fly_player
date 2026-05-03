class DanmakuDynamicOcclusionRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const DanmakuDynamicOcclusionRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory DanmakuDynamicOcclusionRect.fromMap(Map<Object?, Object?> raw) {
    double readDouble(Object? value) {
      return switch (value) {
        final num number => number.toDouble(),
        final String text => double.tryParse(text) ?? 0,
        _ => 0,
      };
    }

    return DanmakuDynamicOcclusionRect(
      x: readDouble(raw['x']),
      y: readDouble(raw['y']),
      width: readDouble(raw['width']),
      height: readDouble(raw['height']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DanmakuDynamicOcclusionRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class DanmakuDynamicOcclusionState {
  final bool enabled;
  final bool available;
  final String backend;
  final String occlusionMode;
  final int updatedAtMs;
  final String? maskPath;
  final String? maskSignature;
  final int maskWidth;
  final int maskHeight;
  final String? framePath;
  final bool cacheHit;
  final double captureAreaRatio;
  final DanmakuDynamicOcclusionRect? normalizedRect;
  final String? unavailableReason;
  final String captureBackend;
  final String degradationLevel;
  final int effectiveSampleIntervalMs;
  final int effectiveInputWidth;

  const DanmakuDynamicOcclusionState({
    required this.enabled,
    required this.available,
    required this.backend,
    required this.occlusionMode,
    required this.updatedAtMs,
    required this.maskPath,
    required this.maskSignature,
    required this.maskWidth,
    required this.maskHeight,
    required this.framePath,
    required this.cacheHit,
    required this.captureAreaRatio,
    required this.normalizedRect,
    required this.unavailableReason,
    required this.captureBackend,
    required this.degradationLevel,
    required this.effectiveSampleIntervalMs,
    required this.effectiveInputWidth,
  });

  static const disabled = DanmakuDynamicOcclusionState(
    enabled: false,
    available: false,
    backend: 'disabled',
    occlusionMode: 'disabled',
    updatedAtMs: 0,
    maskPath: null,
    maskSignature: null,
    maskWidth: 0,
    maskHeight: 0,
    framePath: null,
    cacheHit: false,
    captureAreaRatio: 1.0,
    normalizedRect: null,
    unavailableReason: null,
    captureBackend: 'none',
    degradationLevel: 'none',
    effectiveSampleIntervalMs: 800,
    effectiveInputWidth: 256,
  );

  factory DanmakuDynamicOcclusionState.fromMap(Map<Object?, Object?> raw) {
    final rectRaw = raw['normalizedRect'];
    return DanmakuDynamicOcclusionState(
      enabled: raw['enabled'] == true,
      available: raw['available'] == true,
      backend: (raw['backend'] ?? 'disabled').toString().trim(),
      occlusionMode: (raw['occlusionMode'] ?? 'disabled').toString().trim(),
      updatedAtMs: switch (raw['updatedAtMs']) {
        final int value => value,
        final num value => value.toInt(),
        final String text => int.tryParse(text) ?? 0,
        _ => 0,
      },
      maskPath: _readText(raw['maskPath']),
      maskSignature: _readText(raw['maskSignature']),
      maskWidth: _readInt(raw['maskWidth']),
      maskHeight: _readInt(raw['maskHeight']),
      framePath: _readText(raw['framePath']),
      cacheHit: raw['cacheHit'] == true,
      captureAreaRatio: _readDouble(raw['captureAreaRatio'], fallback: 1.0),
      normalizedRect: rectRaw is Map<Object?, Object?>
          ? DanmakuDynamicOcclusionRect.fromMap(rectRaw)
          : null,
      unavailableReason: _readText(raw['unavailableReason']),
      captureBackend: _readText(raw['captureBackend']) ?? 'none',
      degradationLevel: _readText(raw['degradationLevel']) ?? 'none',
      effectiveSampleIntervalMs:
          _readInt(raw['effectiveSampleIntervalMs']) <= 0
              ? disabled.effectiveSampleIntervalMs
              : _readInt(raw['effectiveSampleIntervalMs']),
      effectiveInputWidth: _readInt(raw['effectiveInputWidth']) <= 0
          ? disabled.effectiveInputWidth
          : _readInt(raw['effectiveInputWidth']),
    );
  }

  DanmakuDynamicOcclusionState copyWith({
    bool? enabled,
    bool? available,
    String? backend,
    String? occlusionMode,
    int? updatedAtMs,
    String? maskPath,
    String? maskSignature,
    int? maskWidth,
    int? maskHeight,
    String? framePath,
    bool? cacheHit,
    double? captureAreaRatio,
    DanmakuDynamicOcclusionRect? normalizedRect,
    String? unavailableReason,
    String? captureBackend,
    String? degradationLevel,
    int? effectiveSampleIntervalMs,
    int? effectiveInputWidth,
    bool clearMaskPath = false,
    bool clearFramePath = false,
    bool clearRect = false,
    bool clearUnavailableReason = false,
  }) {
    return DanmakuDynamicOcclusionState(
      enabled: enabled ?? this.enabled,
      available: available ?? this.available,
      backend: backend ?? this.backend,
      occlusionMode: occlusionMode ?? this.occlusionMode,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      maskPath: clearMaskPath ? null : maskPath ?? this.maskPath,
      maskSignature: clearMaskPath ? null : maskSignature ?? this.maskSignature,
      maskWidth: maskWidth ?? this.maskWidth,
      maskHeight: maskHeight ?? this.maskHeight,
      framePath: clearFramePath ? null : framePath ?? this.framePath,
      cacheHit: cacheHit ?? this.cacheHit,
      captureAreaRatio: captureAreaRatio ?? this.captureAreaRatio,
      normalizedRect: clearRect ? null : normalizedRect ?? this.normalizedRect,
      unavailableReason: clearUnavailableReason
          ? null
          : unavailableReason ?? this.unavailableReason,
      captureBackend: captureBackend ?? this.captureBackend,
      degradationLevel: degradationLevel ?? this.degradationLevel,
      effectiveSampleIntervalMs:
          effectiveSampleIntervalMs ?? this.effectiveSampleIntervalMs,
      effectiveInputWidth: effectiveInputWidth ?? this.effectiveInputWidth,
    );
  }

  bool get hasUsableMask =>
      available &&
      (maskPath?.trim().isNotEmpty ?? false) &&
      maskWidth > 0 &&
      maskHeight > 0;

  bool get hasUsableRect => available && normalizedRect != null;

  @override
  bool operator ==(Object other) {
    return other is DanmakuDynamicOcclusionState &&
        other.enabled == enabled &&
        other.available == available &&
        other.backend == backend &&
        other.occlusionMode == occlusionMode &&
        other.updatedAtMs == updatedAtMs &&
        other.maskPath == maskPath &&
        other.maskSignature == maskSignature &&
        other.maskWidth == maskWidth &&
        other.maskHeight == maskHeight &&
        other.framePath == framePath &&
        other.cacheHit == cacheHit &&
        other.captureAreaRatio == captureAreaRatio &&
        other.normalizedRect == normalizedRect &&
        other.unavailableReason == unavailableReason &&
        other.captureBackend == captureBackend &&
        other.degradationLevel == degradationLevel &&
        other.effectiveSampleIntervalMs == effectiveSampleIntervalMs &&
        other.effectiveInputWidth == effectiveInputWidth;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    available,
    backend,
    occlusionMode,
    updatedAtMs,
    maskPath,
    maskSignature,
    maskWidth,
    maskHeight,
    framePath,
    cacheHit,
    captureAreaRatio,
    normalizedRect,
    unavailableReason,
    captureBackend,
    degradationLevel,
    effectiveSampleIntervalMs,
    effectiveInputWidth,
  );

  static String? _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _readInt(Object? value) {
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
  }

  static double _readDouble(Object? value, {required double fallback}) {
    final parsed = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    return parsed ?? fallback;
  }
}
