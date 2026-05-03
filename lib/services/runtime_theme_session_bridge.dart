import 'package:flutter/services.dart';

/// 提供运行时主题会话标识的桥接访问。
class RuntimeThemeSessionBridge {
  RuntimeThemeSessionBridge._();

  static final RuntimeThemeSessionBridge instance =
      RuntimeThemeSessionBridge._();

  static const MethodChannel _channel = MethodChannel('fly_player/system');

  /// 读取当前运行时主题同步会话的唯一标识。
  Future<String> getSessionId() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getRuntimeThemeSessionId',
      );
      return result?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
