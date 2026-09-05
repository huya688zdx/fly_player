import 'dart:io';

import 'package:flutter/services.dart';

/// 封装播放器与系统级媒体会话之间的桥接调用。
class PlayerSystemSessionBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/system');
  static Object? _handlerOwner;

  const PlayerSystemSessionBridge._();

  /// 注册来自系统媒体会话的命令回调。
  static Future<void> registerCommandHandler(
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

  /// 注销此前注册的系统媒体会话命令回调。
  static Future<void> unregisterCommandHandler(Object owner) async {
    if (!identical(_handlerOwner, owner)) {
      return;
    }
    _handlerOwner = null;
    _channel.setMethodCallHandler(null);
  }

  /// 通知平台层开始一个新的媒体会话。
  static Future<void> start(Map<String, Object?> payload) async {
    await _invoke('playerSessionStart', payload);
  }

  /// 向平台层同步当前媒体会话状态。
  static Future<void> update(Map<String, Object?> payload) async {
    await _invoke('playerSessionUpdate', payload);
  }

  /// 通知平台层结束当前媒体会话。
  static Future<void> stop() async {
    await _invoke('playerSessionStop');
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod(method, arguments);
    } on PlatformException {
      // Ignore unavailable session integration on unsupported Android hosts.
    }
  }
}
