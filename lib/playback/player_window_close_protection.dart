import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Complements the player's Flutter route lock on platforms with app windows.
Future<void> setPlayerWindowPreventClose(bool preventClose) async {
  if (kIsWeb) return;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      await windowManager.setPreventClose(preventClose);
    case TargetPlatform.iOS:
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return;
  }
}
