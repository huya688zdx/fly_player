import 'package:flutter/services.dart';

class SessionExitBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const SessionExitBridge._();

  static Future<void> logoutAndResetParallelUi() async {
    try {
      await _channel.invokeMethod<void>('logoutAndResetParallelUi');
    } on PlatformException {
      // Ignore platform cleanup failures and allow logout to proceed.
    }
  }
}
