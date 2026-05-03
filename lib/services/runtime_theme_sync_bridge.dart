import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 负责将运行时主题状态同步到主宿主进程。
class RuntimeThemeSyncBridge {
  RuntimeThemeSyncBridge._();

  static final RuntimeThemeSyncBridge instance = RuntimeThemeSyncBridge._();

  static const MethodChannel _channel = MethodChannel(
    'fly_player/runtime_theme_sync',
  );

  Object? _handlerOwner;

  /// 注册来自宿主侧的运行时主题回调处理器。
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

  /// 注销当前持有者注册的运行时主题回调。
  Future<void> unregisterHandler(Object owner) async {
    if (!identical(_handlerOwner, owner)) {
      return;
    }
    _handlerOwner = null;
    _channel.setMethodCallHandler(null);
  }

  /// 将指定页面的运行时主题种子推送到主宿主。
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
      if (kDebugMode) {
        debugPrint('[THEME][SYNC] invoke pushRuntimeThemeToMain page=$pageKey');
      }
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

  /// 清除主宿主中指定页面的运行时主题覆盖。
  Future<void> clearRuntimeThemeOnMain(String pageKey) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[THEME][SYNC] invoke clearRuntimeThemeOnMain page=$pageKey',
        );
      }
      await _channel.invokeMethod<void>('clearRuntimeThemeOnMain', {
        'pageKey': pageKey,
      });
    } on PlatformException {
      // Ignore unavailable host synchronization.
    }
  }

  Future<Map<String, dynamic>?> activeRuntimeThemeSnapshot() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getActiveRuntimeTheme',
      );
      return result;
    } on PlatformException {
      return null;
    }
  }
}
