import 'package:flutter/services.dart';

/// 封装主宿主页面与 Flutter 之间的轻量桥接调用。
class MainHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/main_host');

  const MainHostBridge._();

  /// 请求宿主切换主导航页签。
  static Future<bool> switchPrimaryTab(String tabId) async {
    final normalizedTabId = tabId.trim();
    if (normalizedTabId.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'switchPrimaryTab',
            <String, Object?>{'tabId': normalizedTabId},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 桌面端等无宿主实现的环境：视为未处理，交由调用方本地兜底。
      return false;
    }
  }

  /// 请求宿主打开设置页，并可附带目标子路由。
  static Future<bool> openPrimarySettings({String? destinationRoute}) async {
    final normalizedRoute = destinationRoute?.trim() ?? '';
    try {
      return await _channel.invokeMethod<bool>(
            'openPrimarySettings',
            <String, Object?>{
              if (normalizedRoute.isNotEmpty)
                'destinationRoute': normalizedRoute,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 无宿主实现时抛 MissingPluginException（如 Windows），按未处理兜底。
      return false;
    }
  }

  /// 注册来自宿主侧的 MethodChannel 回调处理器。
  static Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) async {
    _channel.setMethodCallHandler(handler);
  }
}
