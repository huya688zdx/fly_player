import 'package:flutter/services.dart';

/// 描述当前页面在并行宿主中的承载上下文。
class ParallelHostContext {
  final String surface;
  final String paneSide;
  final String hostRole;
  final String preferredPrimaryPaneSide;

  /// 根据宿主上下文字段构造对象。
  const ParallelHostContext({
    required this.surface,
    required this.paneSide,
    required this.hostRole,
    required this.preferredPrimaryPaneSide,
  });

  /// 从平台层映射恢复宿主上下文。
  factory ParallelHostContext.fromMap(Map<String, dynamic> map) {
    return ParallelHostContext(
      surface: (map['surface'] ?? 'standalone').toString(),
      paneSide: (map['paneSide'] ?? 'fullscreen').toString(),
      hostRole: (map['hostRole'] ?? 'fullscreen').toString(),
      preferredPrimaryPaneSide: (map['preferredPrimaryPaneSide'] ?? 'left')
          .toString(),
    );
  }

  bool get isPrimaryHost => hostRole == 'primary';

  bool get isSecondaryHost => hostRole == 'secondary';

  bool get isFullscreenHost => hostRole == 'fullscreen';
}

/// 封装并行宿主上下文查询相关的平台桥接。
class ParallelHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const ParallelHostBridge._();

  /// 读取当前页面所在的并行宿主上下文。
  static Future<ParallelHostContext> getHostContext() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getParallelHostContext',
      );
      if (result == null) {
        return const ParallelHostContext(
          surface: 'standalone',
          paneSide: 'fullscreen',
          hostRole: 'fullscreen',
          preferredPrimaryPaneSide: 'left',
        );
      }
      return ParallelHostContext.fromMap(_normalizeMap(result));
    } on PlatformException {
      return const ParallelHostContext(
        surface: 'standalone',
        paneSide: 'fullscreen',
        hostRole: 'fullscreen',
        preferredPrimaryPaneSide: 'left',
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
