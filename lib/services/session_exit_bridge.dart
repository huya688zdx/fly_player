import 'package:flutter/services.dart';

/// 封装注销时对宿主并行界面的清理请求。
class SessionExitBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const SessionExitBridge._();

  /// 请求宿主在注销时重置并行界面状态。
  static Future<void> logoutAndResetParallelUi() async {
    try {
      await _channel.invokeMethod<void>('logoutAndResetParallelUi');
    } on PlatformException {
      // 宿主清理失败不阻断注销。
    } on MissingPluginException {
      // 桌面等没有 Android 分屏宿主的平台无需清理原生窗口。
    }
  }
}
