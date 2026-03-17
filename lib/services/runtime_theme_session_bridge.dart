import 'package:flutter/services.dart';

class RuntimeThemeSessionBridge {
  RuntimeThemeSessionBridge._();

  static final RuntimeThemeSessionBridge instance =
      RuntimeThemeSessionBridge._();

  static const MethodChannel _channel = MethodChannel('fly_player/system');

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
