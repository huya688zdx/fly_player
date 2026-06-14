import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_player_bridge.dart';

// Re-export the bridge's data classes so callers only need a single import.
export 'native_player_bridge.dart' show NativePlayerLaunchArgs;

/// Clean Dart API for launching the native Android player activity.
///
/// Wraps [NativePlayerBridge] to provide a straightforward call-site for
/// Flutter code that wants to hand off playback to the native player.
class NativePlayerLauncher {
  NativePlayerLauncher._();

  /// Opens the native Android player activity with the supplied [args].
  ///
  /// Sends a launch intent to the native side via [NativePlayerBridge]. The
  /// [context] is available for any pre-launch UI work (e.g. confirming
  /// navigation) and is forwarded to the platform channel.
  ///
  /// Throws [PlatformException] if the native side rejects the launch. Does
  /// nothing on non-Android platforms (the bridge silently ignores
  /// [MissingPluginException]).
  static Future<void> launch(
    BuildContext context,
    NativePlayerLaunchArgs args,
  ) async {
    if (args.url.trim().isEmpty || args.title.trim().isEmpty) {
      debugPrint(
        '[NativePlayerLauncher] launch aborted: url or title is empty',
      );
      return;
    }
    try {
      await NativePlayerBridge.instance.launchPlayer(args);
    } on MissingPluginException {
      debugPrint(
        '[NativePlayerLauncher] native plugin not registered; skipping',
      );
    } catch (error, stackTrace) {
      debugPrint('[NativePlayerLauncher] launch failed: $error\n$stackTrace');
      rethrow;
    }
  }
}
