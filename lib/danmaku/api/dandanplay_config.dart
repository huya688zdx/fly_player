import 'dart:io';

import 'package:flutter/services.dart';

class DanDanPlayRuntimeConfig {
  final String appId;
  final List<String> appSecrets;
  final bool configured;
  final String statusMessage;

  const DanDanPlayRuntimeConfig({
    required this.appId,
    required this.appSecrets,
    required this.configured,
    required this.statusMessage,
  });

  const DanDanPlayRuntimeConfig.unconfigured({
    this.statusMessage = DanDanPlayConfig.defaultUnavailableMessage,
  }) : appId = '',
       appSecrets = const <String>[],
       configured = false;

  factory DanDanPlayRuntimeConfig.fromMap(Map<Object?, Object?> raw) {
    final appId = (raw['appId'] ?? '').toString().trim();
    final appSecrets =
        (raw['appSecrets'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final configured =
        raw['configured'] == true && appId.isNotEmpty && appSecrets.isNotEmpty;
    final statusCode = (raw['statusCode'] ?? '').toString().trim();
    final rawStatusMessage = (raw['statusMessage'] ?? '').toString().trim();
    final statusMessage = rawStatusMessage.isNotEmpty
        ? rawStatusMessage
        : DanDanPlayConfig.messageForStatusCode(statusCode);
    return DanDanPlayRuntimeConfig(
      appId: appId,
      appSecrets: appSecrets,
      configured: configured,
      statusMessage: statusMessage,
    );
  }
}

class DanDanPlayConfig {
  static const MethodChannel _channel = MethodChannel(
    'fly_player/secret_store',
  );
  static const String defaultUnavailableMessage = '当前构建未注入 DanDanPlay 凭据';
  static const String _unsupportedAndroidVersion =
      '当前 Android 版本不支持 DanDanPlay 安全存储';
  static const String _unsupportedPlatform = '当前平台不支持 DanDanPlay 安全存储';
  static const String _secureStoreUnavailable = 'DanDanPlay 安全存储不可用';

  static DanDanPlayRuntimeConfig _current =
      const DanDanPlayRuntimeConfig.unconfigured();
  static Future<DanDanPlayRuntimeConfig>? _pendingLoad;
  static bool _loaded = false;

  static String get appId => _current.appId;

  static List<String> get appSecrets => _current.appSecrets;

  static bool get configured => _current.configured;

  static String get unavailableMessage =>
      _current.statusMessage.trim().isNotEmpty
      ? _current.statusMessage
      : defaultUnavailableMessage;

  static String messageForStatusCode(String statusCode) {
    return switch (statusCode.trim()) {
      'unsupported_android_version' => _unsupportedAndroidVersion,
      'missing_build_credentials' => defaultUnavailableMessage,
      _ => defaultUnavailableMessage,
    };
  }

  static Future<bool> ensureConfigured({bool forceRefresh = false}) async {
    final config = await ensureLoaded(forceRefresh: forceRefresh);
    return config.configured;
  }

  static Future<DanDanPlayRuntimeConfig> ensureLoaded({
    bool forceRefresh = false,
  }) {
    if (!Platform.isAndroid) {
      _current = const DanDanPlayRuntimeConfig.unconfigured(
        statusMessage: _unsupportedPlatform,
      );
      _loaded = true;
      return Future<DanDanPlayRuntimeConfig>.value(_current);
    }
    if (!forceRefresh && _loaded) {
      return Future<DanDanPlayRuntimeConfig>.value(_current);
    }
    if (forceRefresh) {
      _pendingLoad = null;
    }
    final pending = _pendingLoad;
    if (pending != null) {
      return pending;
    }
    final future = _loadFromPlatform();
    _pendingLoad = future;
    return future;
  }

  static Future<void> clearCachedConfig() async {
    _current = const DanDanPlayRuntimeConfig.unconfigured();
    _pendingLoad = null;
    _loaded = false;
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clearDanDanPlayConfig');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<DanDanPlayRuntimeConfig> _loadFromPlatform() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDanDanPlayConfig',
      );
      if (raw == null || raw.isEmpty) {
        _current = const DanDanPlayRuntimeConfig.unconfigured();
      } else {
        _current = DanDanPlayRuntimeConfig.fromMap(raw);
      }
      _loaded = true;
    } on MissingPluginException {
      _current = const DanDanPlayRuntimeConfig.unconfigured(
        statusMessage: _unsupportedPlatform,
      );
      _loaded = true;
    } on PlatformException {
      _current = const DanDanPlayRuntimeConfig.unconfigured(
        statusMessage: _secureStoreUnavailable,
      );
      _loaded = true;
    } finally {
      _pendingLoad = null;
    }
    return _current;
  }
}
