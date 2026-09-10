import 'dart:io';

import 'package:flutter/services.dart';

/// 运行时读取到的 DanDanPlay 凭据和状态。
class DanDanPlayRuntimeConfig {
  /// 当前运行时可用的 AppId。
  final String appId;

  /// 当前运行时可用的 AppSecret 列表。
  final List<String> appSecrets;

  /// 是否已经具备完整且可用的配置。
  final bool configured;

  /// 配置状态说明，可直接用于界面展示。
  final String statusMessage;

  /// 使用平台侧返回的完整配置初始化对象。
  const DanDanPlayRuntimeConfig({
    required this.appId,
    required this.appSecrets,
    required this.configured,
    required this.statusMessage,
  });

  /// 构造一个不可用状态的默认配置对象。
  const DanDanPlayRuntimeConfig.unconfigured({
    this.statusMessage = DanDanPlayConfig.defaultUnavailableMessage,
  }) : appId = '',
       appSecrets = const <String>[],
       configured = false;

  /// 根据平台通道返回的原始 map 构造配置对象。
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

/// DanDanPlay 凭据的运行时加载入口。
///
/// 当前凭据来自平台侧安全存储，Flutter 层仅缓存加载结果与状态说明。
class DanDanPlayConfig {
  static const MethodChannel _channel = MethodChannel(
    'fly_player/secret_store',
  );
  static const String defaultUnavailableMessage =
      'DanDanPlay credentials are not injected in this build.';
  static const String _unsupportedAndroidVersion =
      'This Android version does not support DanDanPlay secure storage.';
  static const String _unsupportedPlatform =
      'This platform does not support DanDanPlay secure storage.';
  static const String _windowsConfigUnavailable =
      'DanDanPlay credentials are not configured for this Windows build.';
  static const String _secureStoreUnavailable =
      'DanDanPlay secure storage is unavailable.';
  static const String _windowsAppId = String.fromEnvironment(
    'DANDANPLAY_APP_ID',
    defaultValue: '',
  );
  static const String _windowsAppSecret = String.fromEnvironment(
    'DANDANPLAY_APP_SECRET',
    defaultValue: '',
  );
  static const String _windowsFallbackSecret = String.fromEnvironment(
    'DANDANPLAY_APP_SECRET_FALLBACK',
    defaultValue: '',
  );

  static DanDanPlayRuntimeConfig _current =
      const DanDanPlayRuntimeConfig.unconfigured();
  static Future<DanDanPlayRuntimeConfig>? _pendingLoad;
  static bool _loaded = false;

  /// 当前已加载的 AppId。
  static String get appId => _current.appId;

  /// 当前已加载的 AppSecret 列表。
  static List<String> get appSecrets => _current.appSecrets;

  /// 当前构建是否具备可用的 DanDanPlay 凭据。
  static bool get configured => _current.configured;

  /// 当前不可用时应展示给用户的提示文案。
  static String get unavailableMessage =>
      _current.statusMessage.trim().isNotEmpty
      ? _current.statusMessage
      : defaultUnavailableMessage;

  /// 把平台状态码转成可直接展示的文案。
  static String messageForStatusCode(String statusCode) {
    return switch (statusCode.trim()) {
      'unsupported_android_version' => _unsupportedAndroidVersion,
      'missing_build_credentials' => defaultUnavailableMessage,
      _ => defaultUnavailableMessage,
    };
  }

  /// 确保配置已加载，并只返回是否可用。
  static Future<bool> ensureConfigured({bool forceRefresh = false}) async {
    final config = await ensureLoaded(forceRefresh: forceRefresh);
    return config.configured;
  }

  /// 确保配置已从平台侧加载到 Flutter 层缓存。
  static Future<DanDanPlayRuntimeConfig> ensureLoaded({
    bool forceRefresh = false,
  }) {
    if (Platform.isWindows) {
      if (!forceRefresh && _loaded) {
        return Future<DanDanPlayRuntimeConfig>.value(_current);
      }
      _current = _loadWindowsConfig();
      _loaded = true;
      return Future<DanDanPlayRuntimeConfig>.value(_current);
    }
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

  /// 清理 Flutter 层和平台侧缓存的 DanDanPlay 凭据。
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

  static DanDanPlayRuntimeConfig _loadWindowsConfig() {
    final localProperties = _readWindowsLocalProperties();
    final appId = _firstNonEmpty(<String>[
      _windowsAppId,
      Platform.environment['DANDANPLAY_APP_ID'] ?? '',
      localProperties['DANDANPLAY_APP_ID'] ?? '',
      // 与 Android 构建默认 AppId 保持一致，密钥仍必须显式注入。
      'mgfbs9knmv',
    ]);
    final secrets = <String>{
      _windowsAppSecret.trim(),
      _windowsFallbackSecret.trim(),
      (Platform.environment['DANDANPLAY_APP_SECRET'] ?? '').trim(),
      (Platform.environment['DANDANPLAY_APP_SECRET_FALLBACK'] ?? '').trim(),
      (localProperties['DANDANPLAY_APP_SECRET'] ?? '').trim(),
      (localProperties['DANDANPLAY_APP_SECRET_FALLBACK'] ?? '').trim(),
    }.where((value) => value.isNotEmpty).toList(growable: false);
    if (appId.isEmpty || secrets.isEmpty) {
      return const DanDanPlayRuntimeConfig.unconfigured(
        statusMessage: _windowsConfigUnavailable,
      );
    }
    return DanDanPlayRuntimeConfig(
      appId: appId,
      appSecrets: secrets,
      configured: true,
      statusMessage: '',
    );
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  static Map<String, String> _readWindowsLocalProperties() {
    try {
      var directory = Directory.current;
      for (var depth = 0; depth < 8; depth++) {
        final properties = _readDanDanProperties(
          File(
            '${directory.path}${Platform.pathSeparator}android'
            '${Platform.pathSeparator}local.properties',
          ),
        );
        if (_hasDanDanSecret(properties)) return properties;

        final linkedProperties = _readLinkedMainWorktreeProperties(
          File('${directory.path}${Platform.pathSeparator}.git'),
        );
        if (_hasDanDanSecret(linkedProperties)) {
          return linkedProperties;
        }
        final parent = directory.parent;
        if (parent.path == directory.path) break;
        directory = parent;
      }
    } catch (_) {
      // Windows 开发目录没有本地密钥文件时继续使用显式注入配置。
    }
    return const <String, String>{};
  }

  static Map<String, String> _readDanDanProperties(File file) {
    if (!file.existsSync()) return const <String, String>{};
    final result = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      final normalized = line.trim();
      if (normalized.isEmpty || normalized.startsWith('#')) continue;
      final separator = normalized.indexOf('=');
      if (separator <= 0) continue;
      final key = normalized.substring(0, separator).trim();
      if (!key.startsWith('DANDANPLAY_')) continue;
      result[key] = normalized.substring(separator + 1).trim();
    }
    return result;
  }

  static bool _hasDanDanSecret(Map<String, String> properties) {
    return (properties['DANDANPLAY_APP_SECRET'] ?? '').trim().isNotEmpty ||
        (properties['DANDANPLAY_APP_SECRET_FALLBACK'] ?? '').trim().isNotEmpty;
  }

  static Map<String, String> _readLinkedMainWorktreeProperties(
    File gitPointer,
  ) {
    if (!gitPointer.existsSync()) return const <String, String>{};
    final pointer = gitPointer.readAsStringSync().trim();
    if (!pointer.startsWith('gitdir:')) return const <String, String>{};
    final rawGitDirectory = pointer.substring('gitdir:'.length).trim();
    if (rawGitDirectory.isEmpty) return const <String, String>{};
    final gitDirectory = Directory(rawGitDirectory).absolute;
    final worktreesDirectory = gitDirectory.parent;
    final worktreesName = worktreesDirectory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    if (worktreesName?.toLowerCase() != 'worktrees') {
      return const <String, String>{};
    }
    final mainWorktree = worktreesDirectory.parent.parent;
    return _readDanDanProperties(
      File(
        '${mainWorktree.path}${Platform.pathSeparator}android'
        '${Platform.pathSeparator}local.properties',
      ),
    );
  }
}
