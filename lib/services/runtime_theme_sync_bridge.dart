import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RuntimeThemeSyncBridge {
  RuntimeThemeSyncBridge._();

  static final RuntimeThemeSyncBridge instance = RuntimeThemeSyncBridge._();

  static const MethodChannel _channel = MethodChannel(
    'fly_player/runtime_theme_sync',
  );

  Object? _handlerOwner;

  Future<void> registerHandler(
    Object owner,
    Future<void> Function(MethodCall call) handler,
  ) async {
    _handlerOwner = owner;
    _channel.setMethodCallHandler((call) async {
      if (!identical(_handlerOwner, owner)) {
        return;
      }
      return handler(call);
    });
  }

  Future<void> unregisterHandler(Object owner) async {
    if (!identical(_handlerOwner, owner)) {
      return;
    }
    _handlerOwner = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> pushRuntimeThemeToMain({
    required String pageKey,
    required int backgroundSeed,
    required int accentSeed,
    required int selectionSeed,
    required int linkSeed,
    required bool preferLightSurface,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      debugPrint('[THEME][SYNC] invoke pushRuntimeThemeToMain page=$pageKey');
      await _channel.invokeMethod<void>('pushRuntimeThemeToMain', {
        'pageKey': pageKey,
        'backgroundSeed': backgroundSeed,
        'accentSeed': accentSeed,
        'selectionSeed': selectionSeed,
        'linkSeed': linkSeed,
        'preferLightSurface': preferLightSurface,
      });
    } on PlatformException {
      // Ignore unavailable host synchronization.
    }
  }

  Future<void> clearRuntimeThemeOnMain(String pageKey) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      debugPrint('[THEME][SYNC] invoke clearRuntimeThemeOnMain page=$pageKey');
      await _channel.invokeMethod<void>('clearRuntimeThemeOnMain', {
        'pageKey': pageKey,
      });
    } on PlatformException {
      // Ignore unavailable host synchronization.
    }
  }
}
