import 'package:flutter/widgets.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/playback/desktop_playback_host.dart';
import '../desktop/playback/desktop_playback_launch_guard.dart';
import '../utils/async_action_guard.dart';
import 'playback_source.dart';
import 'native_playback_host.dart';
import 'playback_host.dart';

/// Windows 和 Linux 复用桌面播放宿主。
PlaybackHost playbackHostFor(BuildContext context) {
  if (DesktopEnvironment.supportsPlayback) {
    return DesktopPlaybackHost(context);
  }
  return NativePlaybackHost(context);
}

/// 已接入的桌面平台在解析前统一防误触；其他平台保留按入口防重。
Future<T?> runPlaybackLaunch<T>(
  BuildContext context, {
  required String title,
  required String actionKey,
  required Future<T?> Function(PlaybackHost host) action,
}) {
  if (!DesktopEnvironment.supportsPlayback) {
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
