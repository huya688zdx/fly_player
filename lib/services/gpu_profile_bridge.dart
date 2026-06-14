import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// GPU 厂商启发式桥接（来自原生 detectDeviceProfile）。
///
/// 用途：Mali 系 GPU 上，Impeller-Vulkan 每帧把整屏视频当纹理合成的开销显著高于
/// Adreno（实测 raster ~2× + gralloc 缓冲格式不匹配导致 QueueBuffer 反复超时），
/// 故 Mali 设备即使用 Flutter 弹幕渲染器也应让视频走 SurfaceView（经 SurfaceFlinger
/// 独立硬件层合成，绕开 Impeller）。见 _preferredVideoOutputBackend。
///
/// 值一次性从原生取回后缓存（GPU 厂商运行期不变）。务必在打开播放器之前调用
/// [ensureLoaded]（在 app 启动时预取），否则首个播放会话可能读到默认值。
class GpuProfileBridge {
  GpuProfileBridge._();

  static const MethodChannel _channel = MethodChannel('fly_player/system');

  static bool _loaded = false;
  static bool _isLikelyMali = false;
  static String _summary = '';
  static Future<void>? _inFlight;

  /// 是否为 Mali 系 GPU。未加载完成前返回 false（保守，沿用默认 texture 路径）。
  static bool get isLikelyMali => _isLikelyMali;

  static bool get isLoaded => _loaded;

  static String get summary => _summary;

  /// 预取并缓存 GPU 画像。重复调用只发一次原生请求。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _inFlight ??= _load();
  }

  static Future<void> _load() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getGpuProfile',
      );
      _isLikelyMali = result?['isLikelyMali'] == true;
      _summary = (result?['summary'] as String?)?.trim() ?? '';
      _loaded = true;
      if (kDebugMode) {
        debugPrint(
          '[GPU][PROFILE] isLikelyMali=$_isLikelyMali summary=$_summary',
        );
      }
    } catch (e) {
      // 取不到（如 channel 尚未注册）保持默认（非 Mali），且**不**标记已加载，
      // 让后续 ensureLoaded 重试。
      _isLikelyMali = false;
      if (kDebugMode) {
        debugPrint('[GPU][PROFILE] load failed (will retry): $e');
      }
    } finally {
      _inFlight = null;
    }
  }
}
