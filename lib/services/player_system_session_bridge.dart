import 'dart:io';

import 'package:flutter/services.dart';

class PlayerSystemSessionBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/system');
  static Object? _handlerOwner;

  const PlayerSystemSessionBridge._();

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

  static Future<void> unregisterCommandHandler(Object owner) async {
    if (!identical(_handlerOwner, owner)) {
      return;
    }
    _handlerOwner = null;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> start(Map<String, Object?> payload) async {
    await _invoke('playerSessionStart', payload);
  }

  static Future<void> update(Map<String, Object?> payload) async {
    await _invoke('playerSessionUpdate', payload);
  }

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
