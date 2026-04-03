import 'package:flutter/services.dart';

class MainHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/main_host');

  const MainHostBridge._();

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
    }
  }

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
    }
  }

  static Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) async {
    _channel.setMethodCallHandler(handler);
  }
}
