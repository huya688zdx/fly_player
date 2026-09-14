import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 桌面运行环境判定（Windows / macOS / Linux）。
///
/// 所有桌面布局分支都必须先经过 [isDesktopPlatform] 判定，
/// 保证 Android / 窄窗口路径与既有行为完全一致。
abstract final class DesktopEnvironment {
  /// 测试专用钩子：非 null 时强制覆盖 [isDesktopPlatform] 的判定结果。
  ///
  /// 生产代码不得写入；默认 null 时走真实平台判定，既有路径完全不变。
  @visibleForTesting
  static bool? debugOverridePlatform;

  static bool get isDesktopPlatform =>
      debugOverridePlatform ??
      (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 已接入 media_kit 播放宿主的平台；macOS 尚未开放。
  static bool get supportsPlayback => isWindows || isLinux;
}
