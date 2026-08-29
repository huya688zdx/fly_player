import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 桌面运行环境判定（Windows / macOS / Linux）。
///
/// 播放内核尚未选型（需兼顾 Linux，后续可能 macOS / iOS），桌面端当前仅承载
/// 浏览与管理类 UI；所有桌面布局分支都必须先经过 [isDesktopPlatform] 判定，
/// 保证 Android / 窄窗口路径与既有行为完全一致。
abstract final class DesktopEnvironment {
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool get isLinux => !kIsWeb && Platform.isLinux;
}
