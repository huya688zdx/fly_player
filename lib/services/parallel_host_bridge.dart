import 'package:flutter/services.dart';

/// 描述当前页面在并行宿主中的承载上下文。
class ParallelHostContext {
  final String surface;
  final String paneSide;
  final String hostRole;
  final String preferredPrimaryPaneSide;

  /// 是否处于*分屏播放*布局(一侧视频播放器、一侧 detail 并排同时可见),即原生
  /// `ParallelWindowCoordinator.isSplitPlayerVisible()`。这是唯一会让两个引擎同时
  /// 可见、可能互相改写 prefs 的场景。
  ///
  /// 注意:不要用"detail 引擎是否预热/是否存在"来判断——大屏启动即预热 detail 引擎,
  /// 且从 detail 页进入全屏播放后 DetailActivity 仍残留在返回栈,二者都会让"引擎
  /// 存在/活跃"恒为 true,导致全屏播放时也每 1.5s 跑昂贵的 prefs.reload()(实测平板
  /// CPU profile 头号开销,直接拖累弹幕滚动平滑)。splitPlayerVisible 由 PlayerActivity
  /// 的 layoutMode 驱动(仅 MODE_SPLIT 为 true),全屏单窗口播放恒为 false 且不残留。
  /// Dart 侧据此决定是否需要昂贵的 prefs.reload() 轮询。
  final bool parallelEngineActive;

  /// 根据宿主上下文字段构造对象。
  const ParallelHostContext({
    required this.surface,
    required this.paneSide,
    required this.hostRole,
    required this.preferredPrimaryPaneSide,
    this.parallelEngineActive = false,
  });

  /// 从平台层映射恢复宿主上下文。
  factory ParallelHostContext.fromMap(Map<String, dynamic> map) {
    return ParallelHostContext(
      surface: (map['surface'] ?? 'standalone').toString(),
      paneSide: (map['paneSide'] ?? 'fullscreen').toString(),
      hostRole: (map['hostRole'] ?? 'fullscreen').toString(),
      preferredPrimaryPaneSide: (map['preferredPrimaryPaneSide'] ?? 'left')
          .toString(),
      parallelEngineActive: map['parallelEngineActive'] == true,
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
