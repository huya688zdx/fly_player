import 'package:flutter/widgets.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/playback/desktop_playback_host.dart';
import '../desktop/playback/desktop_playback_launch_guard.dart';
import '../utils/async_action_guard.dart';
import 'playback_source.dart';
import 'native_playback_host.dart';
import 'playback_host.dart';

/// 按当前平台选择唯一播放宿主；本轮仅 Windows 启用桌面播放页。
PlaybackHost playbackHostFor(BuildContext context) {
  if (DesktopEnvironment.isWindows) {
    return DesktopPlaybackHost(context);
  }
  return NativePlaybackHost(context);
}

/// Windows 在解析前统一防误触；其他平台保留原来的按入口防重。
Future<T?> runPlaybackLaunch<T>(
  BuildContext context, {
  required String title,
  required String actionKey,
  required Future<T?> Function(PlaybackHost host) action,
}) {
  if (!DesktopEnvironment.isWindows) {
    return AsyncActionGuard.run<T?>(
      actionKey,
      action: () => action(playbackHostFor(context)),
      settleDuration: const Duration(milliseconds: 500),
    );
  }
  return DesktopPlaybackLaunchGuard.run<T>(
    context,
    title: title,
    sourceInUse: DesktopPlaybackHost.sourceInUse,
    action: (request) =>
        action(DesktopPlaybackHost(context, launchRequest: request)),
  );
}

bool playbackLaunchIsCurrent(PlaybackHost host) =>
    host is! DesktopPlaybackHost || host.launchRequest?.isCurrent != false;

void rememberPlaybackLaunchSource(PlaybackHost host, MpvMediaSource source) {
  if (host is DesktopPlaybackHost) host.launchRequest?.pendingSource = source;
}
