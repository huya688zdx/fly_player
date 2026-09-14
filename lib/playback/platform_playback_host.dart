import 'package:flutter/widgets.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/playback/desktop_playback_host.dart';
import 'native_playback_host.dart';
import 'playback_host.dart';

/// Windows 和 Linux 复用桌面播放宿主。
PlaybackHost playbackHostFor(BuildContext context) {
  if (DesktopEnvironment.supportsPlayback) {
    return DesktopPlaybackHost(context);
  }
  return NativePlaybackHost(context);
}
