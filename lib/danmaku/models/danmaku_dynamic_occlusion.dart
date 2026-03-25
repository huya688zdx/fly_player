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
  final int updatedAtMs;
  final String? maskPath;
  final int maskWidth;
  final int maskHeight;
  final String? framePath;
  final bool cacheHit;
  final DanmakuDynamicOcclusionRect? normalizedRect;

  const DanmakuDynamicOcclusionState({
    required this.enabled,
    required this.available,
    required this.backend,
    required this.updatedAtMs,
    required this.maskPath,
    required this.maskWidth,
    required this.maskHeight,
    required this.framePath,
    required this.cacheHit,
    required this.normalizedRect,
  });

  static const disabled = DanmakuDynamicOcclusionState(
    enabled: false,
    available: false,
    backend: 'disabled',
    updatedAtMs: 0,
    maskPath: null,
    maskWidth: 0,
    maskHeight: 0,
    framePath: null,
    cacheHit: false,
    normalizedRect: null,
  );

  factory DanmakuDynamicOcclusionState.fromMap(Map<Object?, Object?> raw) {
    final rectRaw = raw['normalizedRect'];
    return DanmakuDynamicOcclusionState(
      enabled: raw['enabled'] == true,
      available: raw['available'] == true,
      backend: (raw['backend'] ?? 'disabled').toString().trim(),
      updatedAtMs: switch (raw['updatedAtMs']) {
        final int value => value,
        final num value => value.toInt(),
        final String text => int.tryParse(text) ?? 0,
        _ => 0,
      },
      maskPath: _readText(raw['maskPath']),
      maskWidth: _readInt(raw['maskWidth']),
      maskHeight: _readInt(raw['maskHeight']),
      framePath: _readText(raw['framePath']),
      cacheHit: raw['cacheHit'] == true,
      normalizedRect: rectRaw is Map<Object?, Object?>
          ? DanmakuDynamicOcclusionRect.fromMap(rectRaw)
          : null,
    );
  }

  DanmakuDynamicOcclusionState copyWith({
    bool? enabled,
    bool? available,
    String? backend,
    int? updatedAtMs,
    String? maskPath,
    int? maskWidth,
    int? maskHeight,
    String? framePath,
    bool? cacheHit,
    DanmakuDynamicOcclusionRect? normalizedRect,
    bool clearMaskPath = false,
    bool clearFramePath = false,
    bool clearRect = false,
  }) {
    return DanmakuDynamicOcclusionState(
      enabled: enabled ?? this.enabled,
      available: available ?? this.available,
      backend: backend ?? this.backend,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      maskPath: clearMaskPath ? null : maskPath ?? this.maskPath,
      maskWidth: maskWidth ?? this.maskWidth,
      maskHeight: maskHeight ?? this.maskHeight,
      framePath: clearFramePath ? null : framePath ?? this.framePath,
      cacheHit: cacheHit ?? this.cacheHit,
      normalizedRect: clearRect ? null : normalizedRect ?? this.normalizedRect,
    );
  }

  bool get hasUsableMask =>
      available &&
      (maskPath?.trim().isNotEmpty ?? false) &&
      maskWidth > 0 &&
      maskHeight > 0;

  @override
  bool operator ==(Object other) {
    return other is DanmakuDynamicOcclusionState &&
        other.enabled == enabled &&
        other.available == available &&
        other.backend == backend &&
        other.updatedAtMs == updatedAtMs &&
        other.maskPath == maskPath &&
        other.maskWidth == maskWidth &&
        other.maskHeight == maskHeight &&
        other.framePath == framePath &&
        other.cacheHit == cacheHit &&
        other.normalizedRect == normalizedRect;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    available,
    backend,
    updatedAtMs,
    maskPath,
    maskWidth,
    maskHeight,
    framePath,
    cacheHit,
    normalizedRect,
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
}
